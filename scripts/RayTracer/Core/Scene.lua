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

function Scene:boundingBox()
    assert(#self.objects > 0, "Scene requires at least one object")
    local box = self.objects[1]:boundingBox()
    local AABB = require "RayTracer.Acceleration.AABB"
    for index = 2, #self.objects do
        box = AABB.fromBoxes(box, self.objects[index]:boundingBox())
    end
    return box
end

function Scene:buildBVH()
    local BVH = require "RayTracer.Acceleration.BVH"
    return BVH.new(self.objects)
end

return Scene
