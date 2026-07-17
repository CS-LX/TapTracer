local Vec3 = require "RayTracer.Math.Vec3"
local Ray = require "RayTracer.Math.Ray"

---@class LambertianVec3
---@field x number
---@field y number
---@field z number
---@field lengthSquared fun(self: LambertianVec3): number
---@class Lambertian
---@field albedo LambertianVec3
local Lambertian = {}
Lambertian.__index = Lambertian

function Lambertian.new(albedo)
    return setmetatable({ albedo = albedo }, Lambertian)
end

function Lambertian:scatter(ray, record, rng)
    local normal = record.normal
    local randomDirection = Vec3.randomUnitVector(rng)
    local nx = rawget(normal, "x")
    local ny = rawget(normal, "y")
    local nz = rawget(normal, "z")
    local rx = rawget(randomDirection, "x")
    local ry = rawget(randomDirection, "y")
    local rz = rawget(randomDirection, "z")
    local direction = Vec3.new(nx + rx, ny + ry, nz + rz)
    local directionLengthSquared = rawget(direction, "x") ^ 2
        + rawget(direction, "y") ^ 2
        + rawget(direction, "z") ^ 2
    if directionLengthSquared < 1e-16 then
        direction = normal
    end
    local material = self
    local albedo = rawget(material, "albedo")
    return Ray.new(record.point, direction), albedo
end

return Lambertian
