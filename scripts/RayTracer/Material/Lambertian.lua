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

local function cosineSampleDirection(normal, rng)
    local radius = math.sqrt(rng:nextFloat())
    local angle = 2 * math.pi * rng:nextFloat()
    local tangentSeed = math.abs(normal.x) > 0.9
        and Vec3.new(0, 1, 0)
        or Vec3.new(1, 0, 0)
    local tangent = tangentSeed:cross(normal):unit()
    local bitangent = normal:cross(tangent)
    local localZ = math.sqrt(math.max(0, 1 - radius * radius))
    return tangent * (radius * math.cos(angle))
        + bitangent * (radius * math.sin(angle))
        + normal * localZ
end

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
    local direction = cosineSampleDirection(record.normal, rng)
    local scattered = Ray.new(record.point, direction)
    local attenuation = self:albedoAt(record)
    local samplePdf = self:pdf(record, -ray.direction, direction)
    return scattered, attenuation, false, nil, samplePdf
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
