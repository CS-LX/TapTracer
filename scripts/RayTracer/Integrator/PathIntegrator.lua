local Vec3 = require "RayTracer.Math.Vec3"
local Interval = require "RayTracer.Math.Interval"

---@class PathIntegratorVec3
---@field x number
---@field y number
---@field z number
---@class PathIntegrator
---@field background PathIntegratorVec3
---@field maxDepth number
local PathIntegrator = {}
PathIntegrator.__index = PathIntegrator

---@param options table|nil
---@return PathIntegrator
function PathIntegrator.new(options)
    options = options or {}
    return setmetatable({
        background = options.background,
        maxDepth = options.maxDepth or 8,
    }, PathIntegrator)
end

---@param ray table
---@param scene table
---@param rng table
---@return table|nil
function PathIntegrator:trace(ray, scene, rng)
    local integrator = self
    local currentRay = ray
    local radiance = Vec3.new(0, 0, 0)
    local background = rawget(integrator, "background") or Vec3.new(0.5, 0.7, 1.0)
    local maxDepth = rawget(integrator, "maxDepth") or 8
    local attenuationR = 1.0
    local attenuationG = 1.0
    local attenuationB = 1.0
    local radianceR = 0.0
    local radianceG = 0.0
    local radianceB = 0.0

    for _ = 1, maxDepth do
        local record = scene:hit(currentRay, Interval.new(0.001, math.huge))
        if record == nil then
            local unitDirection = currentRay.direction:unit()
            local blend = 0.5 * (unitDirection.y + 1)
            local skyX = 1 * (1 - blend) + background.x * blend
            local skyY = 1 * (1 - blend) + background.y * blend
            local skyZ = 1 * (1 - blend) + background.z * blend
            radiance = Vec3.new(
                radianceR + attenuationR * skyX,
                radianceG + attenuationG * skyY,
                radianceB + attenuationB * skyZ
            )
            return radiance
        end

        if record.material == nil then
            return radiance
        end

        local scattered, albedo = record.material:scatter(currentRay, record, rng)
        if scattered == nil then
            return radiance
        end

        local albedoR = albedo.x
        local albedoG = albedo.y
        local albedoB = albedo.z
        attenuationR = attenuationR * albedoR
        attenuationG = attenuationG * albedoG
        attenuationB = attenuationB * albedoB
        currentRay = scattered
    end

    return radiance
end

return PathIntegrator
