local Vec3 = require "RayTracer.Math.Vec3"
local Ray = require "RayTracer.Math.Ray"
local Interval = require "RayTracer.Math.Interval"
local RussianRoulette = require "RayTracer.Integrator.RussianRoulette"

---@class PathIntegratorVec3
---@field x number
---@field y number
---@field z number
---@class PathIntegrator
---@field background PathIntegratorVec3
---@field maxDepth number
local function sampleDirectLight(scene, record, material, rng, stats)
    local lights = scene.lights
    if lights == nil or #lights == 0
            or material == nil
            or type(material.directLightAlbedo) ~= "function" then
        return Vec3.new(0, 0, 0)
    end

    local lightIndex = math.min(#lights, math.floor(rng:nextFloat() * #lights) + 1)
    local light = lights[lightIndex]
    local lightPoint, lightNormal, areaPdf = light:sampleSurface(rng)
    local toLight = lightPoint - record.point
    local distanceSquared = toLight:lengthSquared()
    if distanceSquared <= 1e-12 then
        return Vec3.new(0, 0, 0)
    end

    local distance = math.sqrt(distanceSquared)
    local direction = toLight / distance
    local surfaceCosine = math.max(0, record.normal:dot(direction))
    local lightCosine = math.max(0, lightNormal:dot(-direction))
    if surfaceCosine <= 0 or lightCosine <= 0 then
        return Vec3.new(0, 0, 0)
    end

    local shadowRay = Ray.new(record.point, direction)
    stats.shadowRayCount = stats.shadowRayCount + 1
    local blocker = scene:hit(shadowRay, Interval.new(0.001, distance - 0.001))
    if blocker ~= nil then
        return Vec3.new(0, 0, 0)
    end

    local lightRecord = {
        point = lightPoint,
        normal = lightNormal,
        frontFace = true,
        object = light,
        material = light.material,
    }
    local emitted = light.material:emitted(lightRecord)
    local albedo = material:directLightAlbedo(record)
    local geometry = surfaceCosine * lightCosine / distanceSquared
    local weight = #lights * geometry / (math.pi * areaPdf)
    return albedo * emitted * weight
end

local PathIntegrator = {}
PathIntegrator.__index = PathIntegrator

local function newStats()
    return {
        pathCount = 0,
        bounceCount = 0,
        shadowRayCount = 0,
        hitCount = 0,
        missCount = 0,
        primaryTransmissionCount = 0,
        primaryTransmissionReflectionCount = 0,
        primaryTransmissionRefractionCount = 0,
        primaryTransmissionFirstDiffuseCount = 0,
        primaryTransmissionFirstGlossyCount = 0,
        primaryTransmissionFirstEmissionCount = 0,
        primaryTransmissionFirstOtherCount = 0,
        primaryTransmissionSkyCount = 0,
        primaryTransmissionRouletteCount = 0,
        primaryTransmissionScatterStopCount = 0,
        primaryTransmissionDepthLimitCount = 0,
    }
end

---@param options table|nil
---@return PathIntegrator
function PathIntegrator.new(options)
    options = options or {}
    local roulette = nil
    if options.roulette ~= false then
        roulette = RussianRoulette.new(options.roulette)
    end
    return setmetatable({
        background = options.background,
        maxDepth = options.maxDepth or 8,
        roulette = roulette,
        stats = newStats(),
    }, PathIntegrator)
end

function PathIntegrator:resetStats()
    self.stats = newStats()
end

function PathIntegrator:getStats()
    local stats = self.stats
    return {
        pathCount = stats.pathCount,
        bounceCount = stats.bounceCount,
        shadowRayCount = stats.shadowRayCount,
        hitCount = stats.hitCount,
        missCount = stats.missCount,
        primaryTransmissionCount = stats.primaryTransmissionCount,
        primaryTransmissionReflectionCount = stats.primaryTransmissionReflectionCount,
        primaryTransmissionRefractionCount = stats.primaryTransmissionRefractionCount,
        primaryTransmissionFirstDiffuseCount = stats.primaryTransmissionFirstDiffuseCount,
        primaryTransmissionFirstGlossyCount = stats.primaryTransmissionFirstGlossyCount,
        primaryTransmissionFirstEmissionCount = stats.primaryTransmissionFirstEmissionCount,
        primaryTransmissionFirstOtherCount = stats.primaryTransmissionFirstOtherCount,
        primaryTransmissionSkyCount = stats.primaryTransmissionSkyCount,
        primaryTransmissionRouletteCount = stats.primaryTransmissionRouletteCount,
        primaryTransmissionScatterStopCount = stats.primaryTransmissionScatterStopCount,
        primaryTransmissionDepthLimitCount = stats.primaryTransmissionDepthLimitCount,
        averagePathDepth = stats.pathCount > 0 and stats.bounceCount / stats.pathCount or 0,
    }
end

local function denoiseClass(material, record)
    if material ~= nil and type(material.denoiseClass) == "function" then
        return material:denoiseClass(record)
    end
    return "unknown"
end

local function recordFirstTransmissionTarget(stats, class)
    if class == "diffuse" then
        stats.primaryTransmissionFirstDiffuseCount =
            stats.primaryTransmissionFirstDiffuseCount + 1
    elseif class == "glossy" then
        stats.primaryTransmissionFirstGlossyCount =
            stats.primaryTransmissionFirstGlossyCount + 1
    elseif class == "emission" then
        stats.primaryTransmissionFirstEmissionCount =
            stats.primaryTransmissionFirstEmissionCount + 1
    else
        stats.primaryTransmissionFirstOtherCount =
            stats.primaryTransmissionFirstOtherCount + 1
    end
end

---@param ray table
---@param scene table
---@param rng table
---@return table|nil
function PathIntegrator:trace(ray, scene, rng, onPrimaryHit)
    local integrator = self
    local stats = integrator.stats
    stats.pathCount = stats.pathCount + 1
    local currentRay = ray
    local background = rawget(integrator, "background") or Vec3.new(0.5, 0.7, 1.0)
    local maxDepth = rawget(integrator, "maxDepth") or 8
    local attenuationR = 1.0
    local attenuationG = 1.0
    local attenuationB = 1.0
    local radianceR = 0.0
    local radianceG = 0.0
    local radianceB = 0.0
    local previousSpecular = true
    local primaryTransmission = false
    local pendingTransmissionTarget = false

    for depth = 1, maxDepth do
        stats.bounceCount = stats.bounceCount + 1
        local record = scene:hit(currentRay, Interval.new(0.001, math.huge))
        if depth == 1 and onPrimaryHit ~= nil then
            onPrimaryHit(record)
        end
        if record == nil then
            stats.missCount = stats.missCount + 1
            if primaryTransmission and pendingTransmissionTarget then
                stats.primaryTransmissionSkyCount =
                    stats.primaryTransmissionSkyCount + 1
                pendingTransmissionTarget = false
            end
            local unitDirection = currentRay.direction:unit()
            local blend = 0.5 * (unitDirection.y + 1)
            local skyX = 1 * (1 - blend) + background.x * blend
            local skyY = 1 * (1 - blend) + background.y * blend
            local skyZ = 1 * (1 - blend) + background.z * blend
            return Vec3.new(
                radianceR + attenuationR * skyX,
                radianceG + attenuationG * skyY,
                radianceB + attenuationB * skyZ
            )
        end

        stats.hitCount = stats.hitCount + 1

        if record.material == nil then
            if primaryTransmission and pendingTransmissionTarget then
                recordFirstTransmissionTarget(stats, "unknown")
                pendingTransmissionTarget = false
            end
            return Vec3.new(radianceR, radianceG, radianceB)
        end

        local materialClass = denoiseClass(record.material, record)
        if primaryTransmission and pendingTransmissionTarget
                and materialClass ~= "delta_transmission"
                and materialClass ~= "delta_reflection" then
            recordFirstTransmissionTarget(stats, materialClass)
            pendingTransmissionTarget = false
        end

        local emitted = Vec3.new(0, 0, 0)
        if record.material.emitted then
            emitted = record.material:emitted(record)
        end

        local emittedR = emitted.x
        local emittedG = emitted.y
        local emittedB = emitted.z
        if previousSpecular then
            radianceR = radianceR + attenuationR * emittedR
            radianceG = radianceG + attenuationG * emittedG
            radianceB = radianceB + attenuationB * emittedB
        end

        local direct = sampleDirectLight(scene, record, record.material, rng, stats)
        radianceR = radianceR + attenuationR * direct.x
        radianceG = radianceG + attenuationG * direct.y
        radianceB = radianceB + attenuationB * direct.z

        local scattered, albedo, isSpecular, scatterEvent =
            record.material:scatter(currentRay, record, rng)
        if depth == 1 and materialClass == "delta_transmission" then
            primaryTransmission = true
            pendingTransmissionTarget = true
            stats.primaryTransmissionCount =
                stats.primaryTransmissionCount + 1
            if scatterEvent == "reflection" then
                stats.primaryTransmissionReflectionCount =
                    stats.primaryTransmissionReflectionCount + 1
            elseif scatterEvent == "transmission" then
                stats.primaryTransmissionRefractionCount =
                    stats.primaryTransmissionRefractionCount + 1
            end
        end
        if scattered == nil then
            if primaryTransmission and pendingTransmissionTarget then
                stats.primaryTransmissionScatterStopCount =
                    stats.primaryTransmissionScatterStopCount + 1
                pendingTransmissionTarget = false
            end
            return Vec3.new(radianceR, radianceG, radianceB)
        end

        local albedoR = albedo.x
        local albedoG = albedo.y
        local albedoB = albedo.z
        attenuationR = attenuationR * albedoR
        attenuationG = attenuationG * albedoG
        attenuationB = attenuationB * albedoB

        if integrator.roulette then
            local attenuation = Vec3.new(attenuationR, attenuationG, attenuationB)
            local adjusted, survived = integrator.roulette:continuePath(depth, attenuation, rng)
            if not survived then
                if primaryTransmission and pendingTransmissionTarget then
                    stats.primaryTransmissionRouletteCount =
                        stats.primaryTransmissionRouletteCount + 1
                    pendingTransmissionTarget = false
                end
                return Vec3.new(radianceR, radianceG, radianceB)
            end
            attenuationR = adjusted.x
            attenuationG = adjusted.y
            attenuationB = adjusted.z
        end

        currentRay = scattered
        previousSpecular = isSpecular == true
    end

    if primaryTransmission and pendingTransmissionTarget then
        stats.primaryTransmissionDepthLimitCount =
            stats.primaryTransmissionDepthLimitCount + 1
    end
    return Vec3.new(radianceR, radianceG, radianceB)
end

return PathIntegrator
