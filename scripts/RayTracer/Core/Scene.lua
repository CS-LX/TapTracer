local Interval = require "RayTracer.Math.Interval"

local Scene = {}
Scene.__index = Scene

function Scene.new()
    return setmetatable({ objects = {} }, Scene)
end

function Scene:add(object)
    self.objects[#self.objects + 1] = object
    return object
end

function Scene:clear()
    self.objects = {}
end

function Scene:hit(ray, rayInterval)
    local closest = rayInterval.max
    local closestRecord = nil

    for i = 1, #self.objects do
        local record = self.objects[i]:hit(ray, Interval.new(rayInterval.min, closest))
        if record ~= nil then
            closest = record.t
            closestRecord = record
        end
    end

    return closestRecord
end

return Scene
