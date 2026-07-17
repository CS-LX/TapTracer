local Interval = require "RayTracer.Math.Interval"

local Scene = {}
Scene.__index = Scene

function Scene.new()
    return setmetatable({ objects = {}, lights = {}, accelerator = nil }, Scene)
end

function Scene:add(object)
    self.objects[#self.objects + 1] = object
    self.accelerator = nil
    if object.material and object.material.isLight and object.sampleSurface then
        self.lights[#self.lights + 1] = object
    end
    return object
end

function Scene:clear()
    self.objects = {}
    self.lights = {}
    self.accelerator = nil
end

function Scene:hitBruteForce(ray, rayInterval)
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

function Scene:hit(ray, rayInterval)
    if self.accelerator ~= nil then
        return self.accelerator:hit(ray, rayInterval)
    end

    return self:hitBruteForce(ray, rayInterval)
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

function Scene:setAccelerator(accelerator)
    self.accelerator = accelerator
    return accelerator
end

function Scene:getAccelerator()
    return self.accelerator
end

function Scene:buildBVH()
    local BVH = require "RayTracer.Acceleration.BVH"
    return self:setAccelerator(BVH.new(self.objects))
end

return Scene
