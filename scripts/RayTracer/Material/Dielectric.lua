local Vec3 = require "RayTracer.Math.Vec3"
local Ray = require "RayTracer.Math.Ray"

---@class Dielectric
---@field refractionIndex number
local Dielectric = {}
Dielectric.__index = Dielectric

local function reflectance(cosine, refractionRatio)
    local r0 = (1 - refractionRatio) / (1 + refractionRatio)
    r0 = r0 * r0
    return r0 + (1 - r0) * (1 - cosine) ^ 5
end

function Dielectric.new(refractionIndex)
    assert(refractionIndex > 0, "Dielectric refraction index must be positive")
    return setmetatable({ refractionIndex = refractionIndex }, Dielectric)
end

function Dielectric:emitted(_)
    return Vec3.new(0, 0, 0)
end

function Dielectric:denoiseClass(_)
    return "delta_transmission"
end

function Dielectric:albedoAt(_)
    return Vec3.new(1, 1, 1)
end

function Dielectric:isDelta()
    return true
end

function Dielectric:sample(ray, record, rng)
    local scattered, attenuation, isSpecular, event, fresnel =
        self:scatter(ray, record, rng)
    return scattered, attenuation, isSpecular, event, nil, fresnel
end

function Dielectric:evaluate(_, _, _)
    return Vec3.new(0, 0, 0)
end

function Dielectric:pdf(_, _, _)
    return 0
end

function Dielectric:buildLobes(ray, record)
    local attenuation = Vec3.new(1, 1, 1)
    local ratio = record.frontFace and (1 / self.refractionIndex) or self.refractionIndex
    local unitDirection = ray.direction:unit()
    local directionDotNormal = unitDirection.x * record.normal.x
        + unitDirection.y * record.normal.y
        + unitDirection.z * record.normal.z
    local cosTheta = math.min(-directionDotNormal, 1.0)
    local sinTheta = math.sqrt(math.max(0.0, 1.0 - cosTheta * cosTheta))
    local totalInternalReflection = ratio * sinTheta > 1
    local fresnel = totalInternalReflection and 1.0
        or reflectance(cosTheta, ratio)
    local reflectionRay = Ray.new(
        record.point,
        unitDirection:reflect(record.normal)
    )
    local transmissionRay = nil
    if not totalInternalReflection then
        transmissionRay = Ray.new(
            record.point,
            unitDirection:refract(record.normal, ratio)
        )
    end
    return {
        attenuation = attenuation,
        fresnel = fresnel,
        reflectionRay = reflectionRay,
        transmissionRay = transmissionRay,
        totalInternalReflection = totalInternalReflection,
    }
end

function Dielectric:scatter(ray, record, rng)
    local lobes = self:buildLobes(ray, record)
    if lobes.totalInternalReflection or lobes.fresnel > rng:nextFloat() then
        return lobes.reflectionRay, lobes.attenuation, true,
            "reflection", lobes.fresnel
    end
    return lobes.transmissionRay, lobes.attenuation, true,
        "transmission", lobes.fresnel
end

return Dielectric
