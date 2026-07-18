local PathIntegrator = require "RayTracer.Integrator.PathIntegrator"
local Vec3 = require "RayTracer.Math.Vec3"
local Ray = require "RayTracer.Math.Ray"

local function assertNear(actual, expected, epsilon, label)
    if math.abs(actual - expected) > epsilon then
        error(string.format("%s: expected %.8f, got %.8f", label, expected, actual))
    end
end

local function assertVec3(actual, expected, label)
    assertNear(actual.x, expected.x, 1e-12, label .. ".x")
    assertNear(actual.y, expected.y, 1e-12, label .. ".y")
    assertNear(actual.z, expected.z, 1e-12, label .. ".z")
end

local function makeRecord(material, point, normal, t)
    return {
        point = point,
        normal = normal,
        t = t,
        frontFace = true,
        material = material,
    }
end

local function makeTerminal(class, emitted)
    return {
        denoiseClass = function() return class end,
        emitted = function() return emitted end,
        scatter = function() return nil, nil end,
        isDelta = function() return false end,
    }
end

local function makeGlass(fresnel, totalInternalReflection)
    local reflectionRay = Ray.new(Vec3.new(0, 0, 1), Vec3.new(-1, 0, 0))
    local transmissionRay = totalInternalReflection and nil
        or Ray.new(Vec3.new(0, 0, 1), Vec3.new(1, 0, 0))
    return {
        denoiseClass = function() return "delta_transmission" end,
        emitted = function() return Vec3.new(0, 0, 0) end,
        isDelta = function() return true end,
        buildLobes = function()
            return {
                attenuation = Vec3.new(1, 1, 1),
                fresnel = fresnel,
                reflectionRay = reflectionRay,
                transmissionRay = transmissionRay,
                totalInternalReflection = totalInternalReflection,
            }
        end,
        scatter = function()
            return reflectionRay, Vec3.new(1, 1, 1), true, "reflection", fresnel
        end,
    }
end

local function runDualLobe()
    local glass = makeGlass(0.25, false)
    local reflectionTarget = makeTerminal("emission", Vec3.new(4, 0, 0))
    local transmissionTarget = makeTerminal("diffuse", Vec3.new(0, 0, 2))
    local primary = makeRecord(glass, Vec3.new(0, 0, 1), Vec3.new(0, 0, -1), 1)
    local reflected = makeRecord(reflectionTarget, Vec3.new(-2, 0, 1), Vec3.new(1, 0, 0), 2)
    local transmitted = makeRecord(transmissionTarget, Vec3.new(2, 0, 1), Vec3.new(-1, 0, 0), 2)
    local hitCalls = 0
    local scene = {
        lights = {},
        hit = function(_, ray)
            hitCalls = hitCalls + 1
            if hitCalls == 1 then
                return primary
            end
            return ray.direction.x < 0 and reflected or transmitted
        end,
    }
    local primaryCallbacks = 0
    local transmissionCallbacks = 0
    local guideClass = nil
    local guideDepth = 0
    local integrator = PathIntegrator.new {
        maxDepth = 2,
        background = Vec3.new(0, 0, 0),
        roulette = false,
        useMIS = false,
    }
    local color, transmission = integrator:trace(
        Ray.new(Vec3.new(0, 0, 0), Vec3.new(0, 0, 1)),
        scene,
        { nextFloat = function() return 0.5 end },
        function() primaryCallbacks = primaryCallbacks + 1 end,
        function(_, class, depth)
            transmissionCallbacks = transmissionCallbacks + 1
            guideClass = class
            guideDepth = depth
        end,
        function()
            return { reflectionSeed = 123, transmissionSeed = 456 }
        end
    )
    assertVec3(color, Vec3.new(1, 0, 1.5), "Fresnel weighted beauty")
    assertVec3(transmission, Vec3.new(0, 0, 1.5), "weighted transmission AOV")
    assert(primaryCallbacks == 1, "primary callback must run exactly once")
    assert(transmissionCallbacks == 1, "transmission guide must run exactly once")
    assert(guideClass == "diffuse", "guide must come from transmission branch")
    assertNear(guideDepth, 3, 1e-12, "guide cumulative depth")
    assert(hitCalls == 3, "primary hit must be reused by both continuations")

    local stats = integrator:getStats()
    assert(stats.j61DualSplitCount == 1, "dual split must be counted")
    assert(stats.j61ReflectionLaunchCount == 1, "reflection launch must be counted")
    assert(stats.j61TransmissionLaunchCount == 1, "transmission launch must be counted")
    assert(stats.j61ReflectionSceneHitCalls == 1, "reflection scene hit count")
    assert(stats.j61TransmissionSceneHitCalls == 1, "transmission scene hit count")
    assertNear(stats.j61ExpectedExtraHitCount, 1, 1e-12,
        "expected additional scene hit count")
end

local function runPrimaryMiss()
    local hitCalls = 0
    local scene = {
        lights = {},
        hit = function()
            hitCalls = hitCalls + 1
            return nil
        end,
    }
    local integrator = PathIntegrator.new {
        maxDepth = 2,
        background = Vec3.new(0.2, 0.4, 0.6),
        roulette = false,
        useMIS = false,
    }
    local color = integrator:trace(
        Ray.new(Vec3.new(0, 0, 0), Vec3.new(0, 1, 0)),
        scene,
        { nextFloat = function() return 0.5 end }
    )
    assert(hitCalls == 1, "primary miss must not repeat scene hit")
    assertVec3(color, Vec3.new(0.2, 0.4, 0.6), "primary miss sky")
end

local function runNonGlass()
    local terminal = makeTerminal("diffuse", Vec3.new(0.2, 0.3, 0.4))
    local record = makeRecord(terminal, Vec3.new(0, 0, 1), Vec3.new(0, 0, -1), 1)
    local hitCalls = 0
    local branchSeedCalls = 0
    local scene = {
        lights = {},
        hit = function()
            hitCalls = hitCalls + 1
            return record
        end,
    }
    local integrator = PathIntegrator.new {
        maxDepth = 1,
        roulette = false,
        useMIS = false,
    }
    local color = integrator:trace(
        Ray.new(Vec3.new(0, 0, 0), Vec3.new(0, 0, 1)),
        scene,
        { nextFloat = function() error("non-glass path must not draw RNG") end },
        nil,
        nil,
        function()
            branchSeedCalls = branchSeedCalls + 1
            return { reflectionSeed = 1, transmissionSeed = 2 }
        end
    )
    assert(hitCalls == 1, "non-glass primary hit must be reused")
    assert(branchSeedCalls == 0, "non-glass path must not request branch seeds")
    assertVec3(color, Vec3.new(0.2, 0.3, 0.4), "non-glass output")
end

local function runChecks()
    runDualLobe()
    runPrimaryMiss()
    runNonGlass()
end

function Start()
    local ok, errorMessage = pcall(runChecks)
    if ok then
        print("[J61SemanticCheck] passed")
    else
        log:Write(LOG_ERROR, "[J61SemanticCheck] " .. tostring(errorMessage))
    end
    engine:Exit()
end
