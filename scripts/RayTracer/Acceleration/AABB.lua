local Vec3 = require "RayTracer.Math.Vec3"

local AABB = {}
AABB.__index = AABB

function AABB.new(first, second)
    assert(first ~= nil and second ~= nil, "AABB requires two corners")
    local minimum = Vec3.new(
        math.min(first.x, second.x),
        math.min(first.y, second.y),
        math.min(first.z, second.z)
    )
    local maximum = Vec3.new(
        math.max(first.x, second.x),
        math.max(first.y, second.y),
        math.max(first.z, second.z)
    )
    local padding = 0.0001

    if maximum.x - minimum.x < padding then
        local center = (minimum.x + maximum.x) * 0.5
        minimum.x = center - padding * 0.5
        maximum.x = center + padding * 0.5
    end
    if maximum.y - minimum.y < padding then
        local center = (minimum.y + maximum.y) * 0.5
        minimum.y = center - padding * 0.5
        maximum.y = center + padding * 0.5
    end
    if maximum.z - minimum.z < padding then
        local center = (minimum.z + maximum.z) * 0.5
        minimum.z = center - padding * 0.5
        maximum.z = center + padding * 0.5
    end

    return setmetatable({ minimum = minimum, maximum = maximum }, AABB)
end

function AABB.fromBoxes(first, second)
    return AABB.new(
        Vec3.new(
            math.min(first.minimum.x, second.minimum.x),
            math.min(first.minimum.y, second.minimum.y),
            math.min(first.minimum.z, second.minimum.z)
        ),
        Vec3.new(
            math.max(first.maximum.x, second.maximum.x),
            math.max(first.maximum.y, second.maximum.y),
            math.max(first.maximum.z, second.maximum.z)
        )
    )
end

function AABB:axisInterval(axis)
    if axis == 1 then
        return self.minimum.y, self.maximum.y
    end
    if axis == 2 then
        return self.minimum.z, self.maximum.z
    end
    return self.minimum.x, self.maximum.x
end

function AABB:longestAxis()
    local sizeX = self.maximum.x - self.minimum.x
    local sizeY = self.maximum.y - self.minimum.y
    local sizeZ = self.maximum.z - self.minimum.z
    if sizeY > sizeX and sizeY >= sizeZ then
        return 1
    end
    if sizeZ > sizeX and sizeZ > sizeY then
        return 2
    end
    return 0
end

function AABB:hit(ray, rayInterval)
    local origin = ray.origin
    local direction = ray.direction
    local minimum = rayInterval.min
    local maximum = rayInterval.max

    for axis = 0, 2 do
        local originValue
        local directionValue
        local lower
        local upper
        if axis == 0 then
            originValue = origin.x
            directionValue = direction.x
            lower = self.minimum.x
            upper = self.maximum.x
        elseif axis == 1 then
            originValue = origin.y
            directionValue = direction.y
            lower = self.minimum.y
            upper = self.maximum.y
        else
            originValue = origin.z
            directionValue = direction.z
            lower = self.minimum.z
            upper = self.maximum.z
        end

        if math.abs(directionValue) < 1e-15 then
            if originValue < lower or originValue > upper then
                return false
            end
        else
            local inverse = 1.0 / directionValue
            local near = (lower - originValue) * inverse
            local far = (upper - originValue) * inverse
            if near > far then
                near, far = far, near
            end
            minimum = math.max(minimum, near)
            maximum = math.min(maximum, far)
            if maximum <= minimum then
                return false
            end
        end
    end

    return true
end

return AABB
