local AABB = require "RayTracer.Acceleration.AABB"
local Vec3 = require "RayTracer.Math.Vec3"

local Quad = {}
Quad.__index = Quad

function Quad.new(origin, edgeU, edgeV, material)
    local cross = edgeU:cross(edgeV)
    local area = cross:length()
    assert(area > 1e-12, "Quad edges must not be parallel")
    local normal = cross / area
    local edgeMin = Vec3.new(
        math.min(origin.x, origin.x + edgeU.x, origin.x + edgeV.x, origin.x + edgeU.x + edgeV.x),
        math.min(origin.y, origin.y + edgeU.y, origin.y + edgeV.y, origin.y + edgeU.y + edgeV.y),
        math.min(origin.z, origin.z + edgeU.z, origin.z + edgeV.z, origin.z + edgeU.z + edgeV.z)
    )
    local edgeMax = Vec3.new(
        math.max(origin.x, origin.x + edgeU.x, origin.x + edgeV.x, origin.x + edgeU.x + edgeV.x),
        math.max(origin.y, origin.y + edgeU.y, origin.y + edgeV.y, origin.y + edgeU.y + edgeV.y),
        math.max(origin.z, origin.z + edgeU.z, origin.z + edgeV.z, origin.z + edgeU.z + edgeV.z)
    )

    return setmetatable({
        origin = origin,
        edgeU = edgeU,
        edgeV = edgeV,
        normal = normal,
        area = area,
        material = material,
        box = AABB.new(edgeMin, edgeMax),
    }, Quad)
end

function Quad:boundingBox()
    return self.box
end

function Quad:sampleSurface(rng)
    local u = rng:nextFloat()
    local v = rng:nextFloat()
    return self.origin + self.edgeU * u + self.edgeV * v,
        self.normal,
        1 / self.area
end

function Quad:hit(ray, rayInterval)
    local denominator = self.normal:dot(ray.direction)
    if math.abs(denominator) < 1e-10 then
        return nil
    end

    local t = self.normal:dot(self.origin - ray.origin) / denominator
    if not rayInterval:surrounds(t) then
        return nil
    end

    local point = ray:at(t)
    local offset = point - self.origin
    local uu = self.edgeU:dot(self.edgeU)
    local uv = self.edgeU:dot(self.edgeV)
    local vv = self.edgeV:dot(self.edgeV)
    local wu = offset:dot(self.edgeU)
    local wv = offset:dot(self.edgeV)
    local determinant = uu * vv - uv * uv
    local u = (wu * vv - wv * uv) / determinant
    local v = (wv * uu - wu * uv) / determinant
    if u < 0 or u > 1 or v < 0 or v > 1 then
        return nil
    end

    local frontFace = ray.direction:dot(self.normal) < 0
    return {
        point = point,
        normal = frontFace and self.normal or -self.normal,
        t = t,
        frontFace = frontFace,
        object = self,
        material = self.material,
        u = u,
        v = v,
    }
end

return Quad
