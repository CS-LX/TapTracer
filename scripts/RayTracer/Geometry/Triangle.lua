local AABB = require "RayTracer.Acceleration.AABB"
local Vec3 = require "RayTracer.Math.Vec3"

local Triangle = {}
Triangle.__index = Triangle

function Triangle.new(first, second, third, material)
    local edge1 = second - first
    local edge2 = third - first
    local normal = edge1:cross(edge2)
    assert(normal:lengthSquared() > 1e-16, "Triangle vertices must not be collinear")

    return setmetatable({
        first = first,
        second = second,
        third = third,
        edge1 = edge1,
        edge2 = edge2,
        normal = normal:unit(),
        material = material,
        box = AABB.new(
            Vec3.new(
                math.min(first.x, second.x, third.x),
                math.min(first.y, second.y, third.y),
                math.min(first.z, second.z, third.z)
            ),
            Vec3.new(
                math.max(first.x, second.x, third.x),
                math.max(first.y, second.y, third.y),
                math.max(first.z, second.z, third.z)
            )
        ),
    }, Triangle)
end

function Triangle:sampleSurface(rng)
    local u = math.sqrt(rng:nextFloat())
    local v = rng:nextFloat()
    local firstWeight = 1 - u
    local secondWeight = u * (1 - v)
    local thirdWeight = u * v
    local point = self.first * firstWeight
        + self.second * secondWeight
        + self.third * thirdWeight
    return point, self.normal, 1 / self:area()
end

function Triangle:area()
    return 0.5 * self.edge1:cross(self.edge2):length()
end

function Triangle:boundingBox()
    return self.box
end

function Triangle:hit(ray, rayInterval)
    local cross = ray.direction:cross(self.edge2)
    local determinant = self.edge1:dot(cross)
    if math.abs(determinant) < 1e-10 then
        return nil
    end

    local inverse = 1.0 / determinant
    local offset = ray.origin - self.first
    local u = offset:dot(cross) * inverse
    if u < 0 or u > 1 then
        return nil
    end

    local q = offset:cross(self.edge1)
    local v = ray.direction:dot(q) * inverse
    if v < 0 or u + v > 1 then
        return nil
    end

    local t = self.edge2:dot(q) * inverse
    if not rayInterval:surrounds(t) then
        return nil
    end

    local outwardNormal = self.normal
    local frontFace = ray.direction:dot(outwardNormal) < 0
    return {
        point = ray:at(t),
        normal = frontFace and outwardNormal or -outwardNormal,
        t = t,
        frontFace = frontFace,
        object = self,
        material = self.material,
        u = u,
        v = v,
    }
end

return Triangle
