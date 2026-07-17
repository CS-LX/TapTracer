local Vec3 = require "RayTracer.Math.Vec3"
local Ray = require "RayTracer.Math.Ray"
local SolidColor = require "RayTracer.Texture.SolidColor"

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
    local texture = albedo
    if texture == nil or type(texture.value) ~= "function" then
        texture = SolidColor.new(albedo)
    end
    return setmetatable({ albedo = albedo, texture = texture }, Lambertian)
end

function Lambertian:emitted(_)
    return Vec3.new(0, 0, 0)
end

function Lambertian:albedoAt(record)
    return self.texture:value(record)
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
    local albedo = material:albedoAt(record)
    return Ray.new(record.point, direction), albedo, false
end

return Lambertian
