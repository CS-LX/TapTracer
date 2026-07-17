local Vec3 = require "RayTracer.Math.Vec3"
local Interval = require "RayTracer.Math.Interval"

local NormalIntegrator = {}
NormalIntegrator.__index = NormalIntegrator

function NormalIntegrator.new(background)
    return setmetatable({
        background = background or Vec3.new(0.7, 0.8, 1.0),
    }, NormalIntegrator)
end

function NormalIntegrator:resetStats()
end

function NormalIntegrator:getStats()
    return nil
end

function NormalIntegrator:trace(ray, scene)
    local record = scene:hit(ray, Interval.new(0.001, math.huge))
    if record ~= nil then
        return (record.normal + Vec3.new(1, 1, 1)) * 0.5
    end

    local unitDirection = ray.direction:unit()
    local blend = 0.5 * (unitDirection.y + 1.0)
    return Vec3.new(1, 1, 1) * (1 - blend) + self.background * blend
end

return NormalIntegrator
