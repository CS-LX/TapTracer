local Vec3 = require "RayTracer.Math.Vec3"
local Ray = require "RayTracer.Math.Ray"

---@class Metal
---@field albedo table
---@field fuzz number
local Metal = {}
Metal.__index = Metal

function Metal.new(albedo, fuzz)
    return setmetatable({
        albedo = albedo,
        fuzz = math.max(0, math.min(1, fuzz or 0)),
    }, Metal)
end

function Metal:emitted(_)
    return Vec3.new(0, 0, 0)
end

function Metal:denoiseClass(_)
    if self.fuzz <= 1e-6 then
        return "delta_reflection"
    end
    return "glossy"
end

function Metal:albedoAt(_)
    return self.albedo
end

function Metal:isDelta()
    return self.fuzz <= 1e-6
end

function Metal:sample(ray, record, rng)
    local scattered, attenuation, isSpecular, event = self:scatter(ray, record, rng)
    return scattered, attenuation, isSpecular, event, nil
end

function Metal:evaluate(_, _, _)
    if self:isDelta() then
        return Vec3.new(0, 0, 0)
    end
    return nil
end

function Metal:pdf(_, _, _)
    if self:isDelta() then
        return 0
    end
    return nil
end

function Metal:scatter(ray, record, rng)
    local reflected = ray.direction:unit():reflect(record.normal)
    reflected = reflected + Vec3.randomUnitVector(rng) * self.fuzz
    local directionDotNormal = reflected.x * record.normal.x
        + reflected.y * record.normal.y
        + reflected.z * record.normal.z
    if directionDotNormal <= 0 then
        return nil, nil
    end
    return Ray.new(record.point, reflected), self.albedo, true
end

return Metal
