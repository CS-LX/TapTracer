local PathIntegrator = require "RayTracer.Integrator.PathIntegrator"
local PrimaryAOV = require "RayTracer.Display.PrimaryAOV"
local Vec3 = require "RayTracer.Math.Vec3"
local Ray = require "RayTracer.Math.Ray"

local function assertNear(actual, expected, epsilon, label)
    if math.abs(actual - expected) > epsilon then
        error(string.format(
            "%s: expected %.8f, got %.8f",
            label,
            expected,
            actual
        ))
    end
end

local function makeMaterial(class, event)
    return {
        denoiseClass = function()
            return class
        end,
        emitted = function()
            return Vec3.new(0, 0, 0)
        end,
        scatter = function(_, _, record)
            if event == nil then
                return nil, nil
            end
            return Ray.new(record.point, Vec3.new(0, 0, 1)),
                Vec3.new(1, 1, 1), true, event
        end,
        isDelta = function()
            return class == "delta_transmission"
                or class == "delta_reflection"
        end,
    }
end

local function makeRecord(material, t)
    return {
        point = Vec3.new(0, 0, t),
        normal = Vec3.new(0, 1, 0),
        t = t,
        frontFace = true,
        material = material,
    }
end

local function runPath(firstEvent)
    local diffuse = makeMaterial("diffuse", nil)
    local reflectionRay = Ray.new(Vec3.new(0, 0, 1), Vec3.new(-1, 0, 0))
    local transmissionRay = firstEvent == "transmission"
        and Ray.new(Vec3.new(0, 0, 1), Vec3.new(1, 0, 0)) or nil
    local glass = makeMaterial("delta_transmission", firstEvent)
    glass.buildLobes = function()
        return {
            attenuation = Vec3.new(1, 1, 1),
            fresnel = transmissionRay ~= nil and 0.25 or 1,
            reflectionRay = reflectionRay,
            transmissionRay = transmissionRay,
            totalInternalReflection = transmissionRay == nil,
        }
    end
    local primaryRecord = makeRecord(glass, 1)
    local targetRecord = makeRecord(diffuse, 2)
    local hitCalls = 0
    local scene = {
        lights = {},
        hit = function(_, ray)
            hitCalls = hitCalls + 1
            if hitCalls == 1 then
                return primaryRecord
            end
            if ray.direction.x ~= 0 then
                return targetRecord
            end
            return nil
        end,
    }
    local guide = nil
    local integrator = PathIntegrator.new {
        maxDepth = 2,
        background = Vec3.new(0, 0, 0),
        roulette = false,
        useMIS = false,
    }
    integrator:trace(
        Ray.new(Vec3.new(0, 0, 0), Vec3.new(0, 0, 1)),
        scene,
        { nextFloat = function() return 1 end },
        nil,
        function(record, class, depth)
            guide = { record = record, class = class, depth = depth }
        end,
        function()
            return { reflectionSeed = 123, transmissionSeed = 456 }
        end
    )
    return guide, hitCalls
end

local function runChecks()
    local transmissionGuide, transmissionHits = runPath("transmission")
    assert(transmissionGuide ~= nil,
        "transmission branch must record a guide")
    assert(transmissionGuide.class == "diffuse",
        "guide must use first non-delta class")
    assertNear(transmissionGuide.depth, 3, 1e-12,
        "guide must store cumulative path depth")
    assert(transmissionHits == 3,
        "dual continuation must reuse primary hit and trace each branch once")

    local reflectionGuide, reflectionHits = runPath("reflection")
    assert(reflectionGuide == nil,
        "reflection branch must not record transmission guide")
    assert(reflectionHits == 2,
        "TIR fallback must keep one primary and one continuation hit")

    local aov = PrimaryAOV.new(1, 1)
    aov:set(0, 0, {
        hit = true,
        class = transmissionGuide.class,
        albedo = Vec3.new(0.4, 0.5, 0.6),
        normal = transmissionGuide.record.normal,
        depth = transmissionGuide.depth,
    })
    aov:set(0, 0, nil)
    assert(aov:getSampleCount(0, 0) == 2,
        "coverage must count hit and miss samples")
    assert(aov:getHitCount(0, 0) == 1,
        "coverage must count one valid guide")
    assertNear(aov:getCoverage(0, 0), 0.5, 1e-12,
        "coverage must be hit/sample")

    aov:clear()
    assert(aov:getSampleCount(0, 0) == 0,
        "clear must reset sample count")
    assert(aov:getHitCount(0, 0) == 0,
        "clear must reset hit count")
    assertNear(aov:getCoverage(0, 0), 0, 0,
        "clear must reset coverage")
end

function Start()
    local ok, errorMessage = pcall(runChecks)
    if ok then
        print("[J4SemanticCheck] passed")
    else
        log:Write(LOG_ERROR, "[J4SemanticCheck] " .. tostring(errorMessage))
    end
    engine:Exit()
end
