local Vec3 = require "RayTracer.Math.Vec3"
local Ray = require "RayTracer.Math.Ray"
local SolidColor = require "RayTracer.Texture.SolidColor"

---@class LambertianVec3
---@field x number
---@field y number
---@field z number
---@field lengthSquared fun(self: LambertianVec3): number
---@class Lambertian
---@field albedo LambertianVec3
local Lambertian = {}
Lambertian.__index = Lambertian

function Lambertian.new(albedo)
    local texture = albedo
    if texture == nil or type(texture.value) ~= "function" then
        texture = SolidColor.new(albedo)
    end
    return setmetatable({ albedo = albedo, texture = texture }, Lambertian)
end

function Lambertian:emitted(_)
    return Vec3.new(0, 0, 0)
end

function Lambertian:denoiseClass(_)
    return "diffuse"
end

function Lambertian:albedoAt(record)
    return self.texture:value(record)
end

function Lambertian:directLightAlbedo(record)
    return self:albedoAt(record)
end

function Lambertian:isDelta()
    return false
end

function Lambertian:sample(ray, record, rng)
    local scattered, attenuation, isSpecular, event = self:scatter(ray, record, rng)
    local samplePdf = scattered ~= nil
        and self:pdf(record, -ray.direction, scattered.direction) or 0
    return scattered, attenuation, isSpecular, event, samplePdf
end

function Lambertian:evaluate(record, outgoingDirection, incomingDirection)
    local normal = record.normal
    local outgoingCosine = normal:dot(outgoingDirection:unit())
    local incomingCosine = normal:dot(incomingDirection:unit())
    if outgoingCosine <= 0 or incomingCosine <= 0 then
        return Vec3.new(0, 0, 0)
    end
    return self:albedoAt(record) * (1 / math.pi)
end

function Lambertian:pdf(record, _, incomingDirection)
    return math.max(0, record.normal:dot(incomingDirection:unit())) / math.pi
end

function Lambertian:scatter(ray, record, rng)
    local normal = record.normal
    local randomDirection = Vec3.randomUnitVector(rng)
    local nx = rawget(normal, "x")
    local ny = rawget(normal, "y")
    local nz = rawget(normal, "z")
    local rx = rawget(randomDirection, "x")
    local ry = rawget(randomDirection, "y")
    local rz = rawget(randomDirection, "z")
    local direction = Vec3.new(nx + rx, ny + ry, nz + rz)
    local directionLengthSquared = rawget(direction, "x") ^ 2
        + rawget(direction, "y") ^ 2
        + rawget(direction, "z") ^ 2
    if directionLengthSquared < 1e-16 then
        direction = normal
    end
    local material = self
    local albedo = material:albedoAt(record)
    return Ray.new(record.point, direction), albedo, false
end

return Lambertian
