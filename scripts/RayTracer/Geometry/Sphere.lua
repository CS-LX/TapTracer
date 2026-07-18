local Interval = require "RayTracer.Math.Interval"
local Vec3 = require "RayTracer.Math.Vec3"

local Sphere = {}
Sphere.__index = Sphere

function Sphere.new(center, radius, material)
    assert(radius > 0, "Sphere radius must be positive")
    return setmetatable({
        center = center,
        radius = radius,
        material = material,
    }, Sphere)
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
        material = self.material,
    }
    local outwardNormal = (record.point - self.center) / self.radius
    record.frontFace = ray.direction:dot(outwardNormal) < 0
    record.normal = record.frontFace and outwardNormal or -outwardNormal
    return record
end

function Sphere:sampleSurface(rng)
    local direction = Vec3.randomUnitVector(rng)
    local point = self.center + direction * self.radius
    local normal = direction
    return point, normal, 1 / (4 * math.pi * self.radius * self.radius)
end

function Sphere:pdfSurface(origin, point)
    local toLight = point - origin
    local distanceSquared = toLight:lengthSquared()
    if distanceSquared <= 1e-12 then
        return 0
    end
    local direction = toLight / math.sqrt(distanceSquared)
    local outwardNormal = (point - self.center) / self.radius
    local lightCosine = outwardNormal:dot(-direction)
    if lightCosine <= 0 then
        return 0
    end
    return distanceSquared / (lightCosine * 4 * math.pi * self.radius * self.radius)
end

function Sphere:boundingBox()
    local radius = self.radius
    local delta = Vec3.new(radius, radius, radius)
    local AABB = require "RayTracer.Acceleration.AABB"
    return AABB.new(self.center - delta, self.center + delta)
end

return Sphere
