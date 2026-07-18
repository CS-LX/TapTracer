local Vec3 = require "RayTracer.Math.Vec3"
local Ray = require "RayTracer.Math.Ray"
local Interval = require "RayTracer.Math.Interval"
local RNG = require "RayTracer.Math.RNG"
local RussianRoulette = require "RayTracer.Integrator.RussianRoulette"

local function powerHeuristic(firstPdf, secondPdf)
    local firstSquared = firstPdf * firstPdf
    local secondSquared = secondPdf * secondPdf
    local denominator = firstSquared + secondSquared
    return denominator <= 1e-24 and 0 or firstSquared / denominator
end

local function lightIndexForObject(lights, object)
    for index = 1, #lights do
        if lights[index] == object then
            return index
        end
    end
    return nil
end

local function lightPdfForHit(scene, origin, record)
    local lights = scene.lights
    if lights == nil or #lights == 0 or origin == nil or record == nil
            or record.object == nil or type(record.object.pdfSurface) ~= "function"
            or lightIndexForObject(lights, record.object) == nil then
        return 0
    end
    local surfacePdf = record.object:pdfSurface(origin, record.point)
    return surfacePdf > 0 and surfacePdf / #lights or 0
end

local function sampleDirectLight(scene, record, material, outgoingDirection, rng, stats, useMIS, hitScene)
    local lights = scene.lights
    if lights == nil or #lights == 0 or material == nil then
        return Vec3.new(0, 0, 0)
    end
    local canEvaluate = useMIS and type(material.evaluate) == "function"
    local canUseLegacy = type(material.directLightAlbedo) == "function"
    if not canEvaluate and not canUseLegacy then
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

    stats.shadowRayCount = stats.shadowRayCount + 1
    if hitScene(Ray.new(record.point, direction), Interval.new(0.001, distance - 0.001)) ~= nil then
        return Vec3.new(0, 0, 0)
    end
    local emitted = light.material:emitted {
        point = lightPoint, normal = lightNormal, frontFace = true,
        object = light, material = light.material,
    }
    local lightPdf = areaPdf * distanceSquared / (lightCosine * #lights)
    local contribution
    if canEvaluate then
        contribution = material:evaluate(record, outgoingDirection, direction)
            * emitted * (surfaceCosine / lightPdf)
    else
        contribution = material:directLightAlbedo(record) * emitted
            * (#lights * surfaceCosine * lightCosine
                / (math.pi * areaPdf * distanceSquared))
    end
    if canEvaluate and type(material.pdf) == "function" then
        local bsdfPdf = material:pdf(record, outgoingDirection, direction)
        if type(bsdfPdf) == "number" and bsdfPdf > 0 then
            contribution = contribution * powerHeuristic(lightPdf, bsdfPdf)
            stats.misLightSamples = stats.misLightSamples + 1
        end
    end
    return contribution
end

local PathIntegrator = {}
PathIntegrator.__index = PathIntegrator

local function newStats()
    return {
        pathCount = 0, bounceCount = 0, shadowRayCount = 0,
        hitCount = 0, missCount = 0,
        primaryTransmissionCount = 0, primaryTransmissionFresnelSum = 0,
        primaryTransmissionReflectionCount = 0,
        primaryTransmissionRefractionCount = 0,
        primaryTransmissionGuideCount = 0,
        primaryTransmissionGuideDiffuseCount = 0,
        primaryTransmissionGuideGlossyCount = 0,
        primaryTransmissionGuideEmissionCount = 0,
        primaryTransmissionGuideOtherCount = 0,
        primaryTransmissionFirstDiffuseCount = 0,
        primaryTransmissionFirstGlossyCount = 0,
        primaryTransmissionFirstEmissionCount = 0,
        primaryTransmissionFirstOtherCount = 0,
        primaryTransmissionSkyCount = 0,
        primaryTransmissionRouletteCount = 0,
        primaryTransmissionScatterStopCount = 0,
        primaryTransmissionDepthLimitCount = 0,
        misLightSamples = 0, misBsdfSamples = 0, misEmissionSamples = 0,
        j61DualSplitCount = 0, j61ReflectionLaunchCount = 0,
        j61TransmissionLaunchCount = 0, j61ReflectionSceneHitCalls = 0,
        j61TransmissionSceneHitCalls = 0, j61ExpectedExtraHitCount = 0,
        j61TirCount = 0, j61UnavailableCount = 0,
    }
end

function PathIntegrator.new(options)
    options = options or {}
    return setmetatable({
        background = options.background,
        maxDepth = options.maxDepth or 8,
        roulette = options.roulette == false and nil or RussianRoulette.new(options.roulette),
        useMIS = options.useMIS == true,
        stats = newStats(),
    }, PathIntegrator)
end

function PathIntegrator:resetStats()
    self.stats = newStats()
end

function PathIntegrator:getStats()
    local result = {}
    for key, value in pairs(self.stats) do
        result[key] = value
    end
    result.averagePathDepth = result.pathCount > 0
        and result.bounceCount / result.pathCount or 0
    return result
end

local function denoiseClass(material, record)
    if material ~= nil and type(material.denoiseClass) == "function" then
        return material:denoiseClass(record)
    end
    return "unknown"
end

local function recordFirstTransmissionTarget(stats, class)
    local names = {
        diffuse = "primaryTransmissionFirstDiffuseCount",
        glossy = "primaryTransmissionFirstGlossyCount",
        emission = "primaryTransmissionFirstEmissionCount",
    }
    local name = names[class] or "primaryTransmissionFirstOtherCount"
    stats[name] = stats[name] + 1
end

local function recordTransmissionGuide(stats, class)
    stats.primaryTransmissionGuideCount = stats.primaryTransmissionGuideCount + 1
    local names = {
        diffuse = "primaryTransmissionGuideDiffuseCount",
        glossy = "primaryTransmissionGuideGlossyCount",
        emission = "primaryTransmissionGuideEmissionCount",
    }
    local name = names[class] or "primaryTransmissionGuideOtherCount"
    stats[name] = stats[name] + 1
end

local function skyRadiance(ray, background)
    local direction = ray.direction:unit()
    local blend = 0.5 * (direction.y + 1)
    return Vec3.new(
        1 * (1 - blend) + background.x * blend,
        1 * (1 - blend) + background.y * blend,
        1 * (1 - blend) + background.z * blend
    )
end

-- Starts at initialDepth. firstRecord is an already-computed primary hit when non-nil.
local function traceContinuation(integrator, currentRay, scene, rng, initialDepth,
        firstRecord, trackTransmission, onTransmissionHit, branchName,
        initialTraveledDistance)
    local stats = integrator.stats
    local background = rawget(integrator, "background") or Vec3.new(0.5, 0.7, 1.0)
    local maxDepth = rawget(integrator, "maxDepth") or 8
    local attenuationR, attenuationG, attenuationB = 1, 1, 1
    local radianceR, radianceG, radianceB = 0, 0, 0
    local previousSpecular, previousBsdfPdf, previousBsdfOrigin = true, 0, nil
    local pendingTransmissionTarget = trackTransmission
    local traveledDistance = initialTraveledDistance or 0

    local function hitScene(ray, interval)
        if branchName == "reflection" then
            stats.j61ReflectionSceneHitCalls = stats.j61ReflectionSceneHitCalls + 1
        elseif branchName == "transmission" then
            stats.j61TransmissionSceneHitCalls = stats.j61TransmissionSceneHitCalls + 1
        end
        return scene:hit(ray, interval or Interval.new(0.001, math.huge))
    end

    for depth = initialDepth, maxDepth do
        stats.bounceCount = stats.bounceCount + 1
        local record = firstRecord
        firstRecord = nil
        if record == nil then
            record = hitScene(currentRay)
        end
        if record == nil then
            stats.missCount = stats.missCount + 1
            if pendingTransmissionTarget then
                stats.primaryTransmissionSkyCount = stats.primaryTransmissionSkyCount + 1
            end
            local sky = skyRadiance(currentRay, background)
            return Vec3.new(radianceR + attenuationR * sky.x,
                radianceG + attenuationG * sky.y, radianceB + attenuationB * sky.z)
        end
        stats.hitCount = stats.hitCount + 1
        traveledDistance = traveledDistance + record.t * currentRay.direction:length()
        if record.material == nil then
            if pendingTransmissionTarget then
                recordFirstTransmissionTarget(stats, "unknown")
            end
            return Vec3.new(radianceR, radianceG, radianceB)
        end

        local material = record.material
        local materialClass = denoiseClass(material, record)
        if pendingTransmissionTarget and materialClass ~= "delta_transmission"
                and materialClass ~= "delta_reflection" then
            recordFirstTransmissionTarget(stats, materialClass)
            if onTransmissionHit ~= nil then
                recordTransmissionGuide(stats, materialClass)
                onTransmissionHit(record, materialClass, traveledDistance)
            end
            pendingTransmissionTarget = false
        end

        local emitted = material.emitted and material:emitted(record) or Vec3.new(0, 0, 0)
        if integrator.useMIS and material.isLight then
            local lightPdf = lightPdfForHit(scene, previousBsdfOrigin, record)
            local weight = previousBsdfPdf > 0 and lightPdf > 0
                and powerHeuristic(previousBsdfPdf, lightPdf) or 1
            if previousBsdfPdf > 0 then
                stats.misEmissionSamples = stats.misEmissionSamples + 1
            end
            radianceR = radianceR + attenuationR * emitted.x * weight
            radianceG = radianceG + attenuationG * emitted.y * weight
            radianceB = radianceB + attenuationB * emitted.z * weight
        elseif previousSpecular then
            radianceR = radianceR + attenuationR * emitted.x
            radianceG = radianceG + attenuationG * emitted.y
            radianceB = radianceB + attenuationB * emitted.z
        end

        local direct = sampleDirectLight(scene, record, material,
            -currentRay.direction:unit(), rng, stats, integrator.useMIS, hitScene)
        radianceR = radianceR + attenuationR * direct.x
        radianceG = radianceG + attenuationG * direct.y
        radianceB = radianceB + attenuationB * direct.z

        local scattered, albedo, isSpecular, scatterEvent, scatterFresnel
        local supportsContinuousMIS = integrator.useMIS
            and type(material.sample) == "function" and type(material.pdf) == "function"
            and type(material.isDelta) == "function" and not material:isDelta()
        if supportsContinuousMIS then
            local samplePdf
            scattered, albedo, isSpecular, scatterEvent, samplePdf, scatterFresnel =
                material:sample(currentRay, record, rng)
            previousBsdfPdf, previousBsdfOrigin = samplePdf or 0, record.point
            stats.misBsdfSamples = stats.misBsdfSamples + 1
        else
            scattered, albedo, isSpecular, scatterEvent, scatterFresnel =
                material:scatter(currentRay, record, rng)
            previousBsdfPdf, previousBsdfOrigin = 0, nil
        end
        if scattered == nil then
            if pendingTransmissionTarget then
                stats.primaryTransmissionScatterStopCount = stats.primaryTransmissionScatterStopCount + 1
            end
            return Vec3.new(radianceR, radianceG, radianceB)
        end

        attenuationR, attenuationG, attenuationB = attenuationR * albedo.x,
            attenuationG * albedo.y, attenuationB * albedo.z
        if integrator.roulette then
            local adjusted, survived = integrator.roulette:continuePath(depth,
                Vec3.new(attenuationR, attenuationG, attenuationB), rng)
            if not survived then
                if pendingTransmissionTarget then
                    stats.primaryTransmissionRouletteCount = stats.primaryTransmissionRouletteCount + 1
                end
                return Vec3.new(radianceR, radianceG, radianceB)
            end
            attenuationR, attenuationG, attenuationB = adjusted.x, adjusted.y, adjusted.z
        end
        currentRay, previousSpecular = scattered, isSpecular == true
    end
    if pendingTransmissionTarget then
        stats.primaryTransmissionDepthLimitCount = stats.primaryTransmissionDepthLimitCount + 1
    end
    return Vec3.new(radianceR, radianceG, radianceB)
end

function PathIntegrator:trace(ray, scene, rng, onPrimaryHit, onTransmissionHit, getBranchSeeds)
    local stats = self.stats
    stats.pathCount = stats.pathCount + 1
    local primaryRecord = scene:hit(ray, Interval.new(0.001, math.huge))
    if onPrimaryHit ~= nil then
        onPrimaryHit(primaryRecord)
    end
    if primaryRecord == nil then
        stats.bounceCount = stats.bounceCount + 1
        stats.missCount = stats.missCount + 1
        return skyRadiance(ray,
            rawget(self, "background") or Vec3.new(0.5, 0.7, 1.0)), nil
    end

    local material = primaryRecord.material
    local materialClass = material and denoiseClass(material, primaryRecord) or "unknown"
    if materialClass ~= "delta_transmission" then
        return traceContinuation(self, ray, scene, rng, 1, primaryRecord, false, nil, nil), nil
    end
    if type(material.buildLobes) ~= "function" then
        stats.j61UnavailableCount = stats.j61UnavailableCount + 1
        return traceContinuation(self, ray, scene, rng, 1, primaryRecord, false, nil, nil), nil
    end

    local lobes = material:buildLobes(ray, primaryRecord)
    if lobes == nil or lobes.reflectionRay == nil or lobes.attenuation == nil then
        stats.j61UnavailableCount = stats.j61UnavailableCount + 1
        return traceContinuation(self, ray, scene, rng, 1, primaryRecord, false, nil, nil), nil
    end
    if lobes.totalInternalReflection or lobes.transmissionRay == nil then
        stats.j61TirCount = stats.j61TirCount + 1
        return traceContinuation(self, ray, scene, rng, 1, primaryRecord, false, nil, nil), nil
    end

    if type(getBranchSeeds) ~= "function" then
        stats.j61UnavailableCount = stats.j61UnavailableCount + 1
        return traceContinuation(self, ray, scene, rng, 1, primaryRecord, false, nil, nil), nil
    end
    local branchSeeds = getBranchSeeds()
    if branchSeeds == nil or branchSeeds.reflectionSeed == nil
            or branchSeeds.transmissionSeed == nil then
        stats.j61UnavailableCount = stats.j61UnavailableCount + 1
        return traceContinuation(self, ray, scene, rng, 1, primaryRecord, false, nil, nil), nil
    end

    stats.bounceCount = stats.bounceCount + 1
    stats.primaryTransmissionCount = stats.primaryTransmissionCount + 1
    stats.primaryTransmissionFresnelSum = stats.primaryTransmissionFresnelSum + lobes.fresnel
    stats.primaryTransmissionReflectionCount = stats.primaryTransmissionReflectionCount + 1
    stats.j61ReflectionLaunchCount = stats.j61ReflectionLaunchCount + 1

    stats.j61DualSplitCount = stats.j61DualSplitCount + 1
    stats.primaryTransmissionRefractionCount = stats.primaryTransmissionRefractionCount + 1
    stats.j61TransmissionLaunchCount = stats.j61TransmissionLaunchCount + 1
    local reflectionRng = RNG.new(branchSeeds.reflectionSeed)
    local reflectionHitsBefore = stats.j61ReflectionSceneHitCalls
    local reflection = traceContinuation(self, lobes.reflectionRay, scene, reflectionRng,
        2, nil, false, nil, "reflection",
        primaryRecord.t * ray.direction:length())
    local reflectionHitCalls = stats.j61ReflectionSceneHitCalls
        - reflectionHitsBefore
    local transmissionRng = RNG.new(branchSeeds.transmissionSeed)
    local transmissionHitsBefore = stats.j61TransmissionSceneHitCalls
    local transmission = traceContinuation(self, lobes.transmissionRay, scene, transmissionRng,
        2, nil, true, onTransmissionHit, "transmission",
        primaryRecord.t * ray.direction:length())
    local transmissionHitCalls = stats.j61TransmissionSceneHitCalls
        - transmissionHitsBefore
    local fresnel = lobes.fresnel
    stats.j61ExpectedExtraHitCount = stats.j61ExpectedExtraHitCount
        + (1 - fresnel) * reflectionHitCalls
        + fresnel * transmissionHitCalls
    local transmissionWeight = 1 - fresnel
    local color = reflection * fresnel + transmission * transmissionWeight
    return color, transmission * transmissionWeight
end

return PathIntegrator
