local AABB = require "RayTracer.Acceleration.AABB"
local Interval = require "RayTracer.Math.Interval"

local BVH = {}
BVH.__index = BVH

local function axisMinimum(object, axis)
    local minimum = object:boundingBox().minimum
    if axis == 1 then
        return minimum.y
    end
    if axis == 2 then
        return minimum.z
    end
    return minimum.x
end

local function sortRange(objects, first, last, axis)
    for index = first + 1, last do
        local value = objects[index]
        local valueMinimum = axisMinimum(value, axis)
        local position = index - 1
        while position >= first and axisMinimum(objects[position], axis) > valueMinimum do
            objects[position + 1] = objects[position]
            position = position - 1
        end
        objects[position + 1] = value
    end
end

local function build(objects, first, last, stats, depth)
    local count = last - first + 1
    local box = objects[first]:boundingBox()
    for index = first + 1, last do
        box = AABB.fromBoxes(box, objects[index]:boundingBox())
    end

    stats.nodeCount = stats.nodeCount + 1
    stats.maxDepth = math.max(stats.maxDepth, depth)

    if count <= 2 then
        stats.leafCount = stats.leafCount + 1
        return {
            box = box,
            first = objects[first],
            second = count == 2 and objects[last] or nil,
        }
    end

    local axis = box:longestAxis()
    sortRange(objects, first, last, axis)

    local middle = first + math.floor(count / 2) - 1
    return {
        box = box,
        left = build(objects, first, middle, stats, depth + 1),
        right = build(objects, middle + 1, last, stats, depth + 1),
    }
end

function BVH.new(source)
    local sourceObjects = source.objects or source
    assert(type(sourceObjects) == "table" and #sourceObjects > 0, "BVH requires objects")
    local objects = {}
    for index = 1, #sourceObjects do
        assert(type(sourceObjects[index].boundingBox) == "function", "BVH object requires boundingBox")
        objects[index] = sourceObjects[index]
    end

    local stats = { nodeCount = 0, leafCount = 0, maxDepth = 0, boxTests = 0, primitiveTests = 0 }
    local root = build(objects, 1, #objects, stats, 1)
    return setmetatable({ root = root, stats = stats }, BVH)
end

function BVH:resetStats()
    self.stats.boxTests = 0
    self.stats.primitiveTests = 0
end

function BVH:getStats()
    return {
        nodeCount = self.stats.nodeCount,
        leafCount = self.stats.leafCount,
        maxDepth = self.stats.maxDepth,
        boxTests = self.stats.boxTests,
        primitiveTests = self.stats.primitiveTests,
    }
end

function BVH:boundingBox()
    return self.root.box
end

function BVH:hit(ray, rayInterval)
    local stack = { self.root }
    local stackSize = 1
    local closest = rayInterval.max
    local closestRecord = nil

    while stackSize > 0 do
        local node = stack[stackSize]
        stack[stackSize] = nil
        stackSize = stackSize - 1
        self.stats.boxTests = self.stats.boxTests + 1

        if node.box:hit(ray, Interval.new(rayInterval.min, closest)) then
            if node.first then
                self.stats.primitiveTests = self.stats.primitiveTests + 1
                local record = node.first:hit(ray, Interval.new(rayInterval.min, closest))
                if record ~= nil then
                    closest = record.t
                    closestRecord = record
                end
                if node.second then
                    self.stats.primitiveTests = self.stats.primitiveTests + 1
                    record = node.second:hit(ray, Interval.new(rayInterval.min, closest))
                    if record ~= nil then
                        closest = record.t
                        closestRecord = record
                    end
                end
            else
                stackSize = stackSize + 1
                stack[stackSize] = node.right
                stackSize = stackSize + 1
                stack[stackSize] = node.left
            end
        end
    end

    return closestRecord
end

return BVH
