local Interval = require "RayTracer.Math.Interval"

local Sphere = {}
Sphere.__index = Sphere

function Sphere.new(center, radius)
    assert(radius > 0, "Sphere radius must be positive")
    return setmetatable({ center = center, radius = radius }, Sphere)
end

function Sphere:hit(ray, rayInterval)
    local offset = ray.origin - self.center
    local a = ray.direction:lengthSquared()
    local halfB = offset:dot(ray.direction)
    local c = offset:lengthSquared() - self.radius * self.radius
    local discriminant = halfB * halfB - a * c

    if discriminant < 0 then
        return nil
    end

    local root = math.sqrt(discriminant)
    local firstRoot = (-halfB - root) / a
    local secondRoot = (-halfB + root) / a
    local t = firstRoot

    if not rayInterval:surrounds(t) then
        t = secondRoot
        if not rayInterval:surrounds(t) then
            return nil
        end
    end

    local record = {
        point = ray:at(t),
        normal = nil,
        t = t,
        frontFace = true,
        object = self,
    }
    local outwardNormal = (record.point - self.center) / self.radius
    record.frontFace = ray.direction:dot(outwardNormal) < 0
    record.normal = record.frontFace and outwardNormal or -outwardNormal
    return record
end

function Sphere:boundingBox()
    local radius = self.radius
    local delta = require "RayTracer.Math.Vec3".new(radius, radius, radius)
    return self.center - delta, self.center + delta
end

return Sphere
