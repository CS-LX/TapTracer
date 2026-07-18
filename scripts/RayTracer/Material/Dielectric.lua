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

function Dielectric:albedoAt(_)
    return Vec3.new(1, 1, 1)
end

function Dielectric:scatter(ray, record, rng)
    local attenuation = Vec3.new(1, 1, 1)
    local ratio = record.frontFace and (1 / self.refractionIndex) or self.refractionIndex
    local unitDirection = ray.direction:unit()
    local directionDotNormal = unitDirection.x * record.normal.x
        + unitDirection.y * record.normal.y
        + unitDirection.z * record.normal.z
    local cosTheta = math.min(-directionDotNormal, 1.0)
    local sinTheta = math.sqrt(math.max(0.0, 1.0 - cosTheta * cosTheta))
    local cannotRefract = ratio * sinTheta > 1
    local direction

    if cannotRefract or reflectance(cosTheta, ratio) > rng:nextFloat() then
        direction = unitDirection:reflect(record.normal)
    else
        direction = unitDirection:refract(record.normal, ratio)
    end

    return Ray.new(record.point, direction), attenuation, true
end

return Dielectric
