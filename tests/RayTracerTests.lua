local RT = require "RayTracer"
local QualityPresets = require "RayTracer.Config.QualityPresets"
local DisplayDenoise = require "RayTracer.Display.DisplayDenoise"
local AOVAtrous = require "RayTracer.Display.AOVAtrous"
local PrimaryAOV = require "RayTracer.Display.PrimaryAOV"

local function assertNear(actual, expected, epsilon, label)
    if math.abs(actual - expected) > epsilon then
        error(string.format("%s: expected %.8f, got %.8f", label, expected, actual))
    end
end

local function assertVectorNear(actual, expected, epsilon, label)
    assertNear(actual.x, expected.x, epsilon, label .. ".x")
    assertNear(actual.y, expected.y, epsilon, label .. ".y")
    assertNear(actual.z, expected.z, epsilon, label .. ".z")
end

local Vec3 = RT.Vec3
local Ray = RT.Ray
local Interval = RT.Interval

local function testVectorMath()
    local a = Vec3.new(1, 2, 3)
    local b = Vec3.new(-2, 4, 1)
    assertVectorNear(a + b, Vec3.new(-1, 6, 4), 1e-8, "addition")
    assertVectorNear(a - b, Vec3.new(3, -2, 2), 1e-8, "subtraction")
    assertNear(a:dot(b), 9, 1e-8, "dot")
    assertVectorNear(a:cross(b), Vec3.new(-10, -7, 8), 1e-8, "cross")
    assertNear(Vec3.new(3, 4, 0):length(), 5, 1e-8, "length")
end

local function testRayAndSphere()
    local sphere = RT.Sphere.new(Vec3.new(0, 0, -1), 0.5)
    local ray = Ray.new(Vec3.new(0, 0, 0), Vec3.new(0, 0, -1))
    local hit = sphere:hit(ray, Interval.new(0.001, math.huge))
    assert(hit ~= nil, "center ray should hit sphere")
    assertNear(hit.t, 0.5, 1e-8, "near sphere root")
    assert(hit.frontFace, "front hit should face ray")
    assertVectorNear(hit.normal, Vec3.new(0, 0, 1), 1e-8, "front normal")

    local insideRay = Ray.new(Vec3.new(0, 0, -1), Vec3.new(0, 0, 1))
    local insideHit = sphere:hit(insideRay, Interval.new(0.001, math.huge))
    assert(insideHit ~= nil, "inside ray should hit sphere")
    assert(not insideHit.frontFace, "inside hit should be back face")
    assertVectorNear(insideHit.normal, Vec3.new(0, 0, -1), 1e-8, "inside normal")
end

local function testDeterministicRng()
    local first = RT.RNG.new(42)
    local second = RT.RNG.new(42)
    for i = 1, 8 do
        assertNear(first:nextFloat(), second:nextFloat(), 0, "rng sample " .. i)
    end
end

local function renderFilm()
    local scene = RT.Scene.new()
    scene:add(RT.Sphere.new(Vec3.new(0, 0, -1), 0.5))
    scene:add(RT.Sphere.new(Vec3.new(0, -100.5, -1), 100))
    local camera = RT.Camera.new {
        aspectRatio = 16 / 9,
        imageWidth = 16,
        verticalFov = 40,
        lookFrom = Vec3.new(0, 0, 0),
        lookAt = Vec3.new(0, 0, -1),
    }
    local renderer = RT.Renderer.new {
        camera = camera,
        scene = scene,
        width = 16,
        height = 9,
        samplesPerPixel = 1,
        tileSize = 4,
        seed = 42,
        integrator = RT.NormalIntegrator.new(),
    }
    renderer:render()
    assert(renderer:isComplete(), "renderer should complete")
    assertNear(renderer:progress(), 1, 0, "renderer progress")
    return renderer.film
end

local function createTestRenderer(options)
    options = options or {}
    local scene = RT.Scene.new()
    scene:add(RT.Sphere.new(Vec3.new(0, 0, -1), 0.5))
    scene:add(RT.Sphere.new(Vec3.new(0, -100.5, -1), 100))
    local camera = RT.Camera.new {
        aspectRatio = 16 / 9,
        imageWidth = options.width or 16,
        verticalFov = 40,
        lookFrom = Vec3.new(0, 0, 0),
        lookAt = Vec3.new(0, 0, -1),
    }
    return RT.Renderer.new {
        camera = camera,
        scene = scene,
        width = options.width or 16,
        height = options.height or 9,
        samplesPerPixel = options.samplesPerPixel or 1,
        tileSize = options.tileSize or 4,
        seed = options.seed or 42,
        presenter = options.presenter,
        integrator = options.integrator or RT.NormalIntegrator.new(),
        timeProvider = options.timeProvider,
    }
end

local function filmsMatch(first, second)
    assert(first.width == second.width and first.height == second.height, "film dimensions should match")
    for y = 0, first.height - 1 do
        for x = 0, first.width - 1 do
            local firstR, firstG, firstB = first:get(x, y)
            local secondR, secondG, secondB = second:get(x, y)
            assertNear(firstR, secondR, 0, "film red channel")
            assertNear(firstG, secondG, 0, "film green channel")
            assertNear(firstB, secondB, 0, "film blue channel")
        end
    end
end

local function assertAOVsMatch(first, second)
    assert(first.width == second.width and first.height == second.height, "AOV dimensions should match")
    for y = 0, first.height - 1 do
        for x = 0, first.width - 1 do
            assertNear(first:getSampleCount(x, y), second:getSampleCount(x, y), 0, "AOV sample count match")
            assertNear(first:getHitCount(x, y), second:getHitCount(x, y), 0, "AOV hit count match")
            assert(
                first:getDenoiseClass(x, y) == second:getDenoiseClass(x, y),
                "AOV denoise class should match"
            )
            local firstHit, firstAlbedo, firstNormal, firstDepth, firstCoverage = first:get(x, y)
            local secondHit, secondAlbedo, secondNormal, secondDepth, secondCoverage = second:get(x, y)
            assert(firstHit == secondHit, "AOV hit presence should match")
            assertVectorNear(firstAlbedo, secondAlbedo, 0, "AOV albedo match")
            assertVectorNear(firstNormal, secondNormal, 0, "AOV normal match")
            assertNear(firstDepth, secondDepth, 0, "AOV depth match")
            assertNear(firstCoverage, secondCoverage, 0, "AOV coverage match")
        end
    end
end

local function testPhaseCRenderer()
    local blocking = createTestRenderer {
        width = 10,
        height = 9,
        tileSize = 4,
        samplesPerPixel = 2,
        seed = 99,
    }
    assertNear(blocking:getStats().totalTiles, 9, 0, "tile count")
    blocking:render()
    local blockingStats = blocking:getStats()
    assert(blockingStats.complete, "blocking renderer should complete")
    assertNear(blockingStats.completedTiles, 9, 0, "completed tile count")
    assertNear(blockingStats.completedPixels, 90, 0, "completed pixel count")
    assertNear(blockingStats.totalSamples, 180, 0, "total sample count")
    assertNear(blockingStats.totalRays, 180, 0, "total ray count")
    assertNear(blockingStats.completedPasses, 2, 0, "completed pass count")
    assertNear(blockingStats.completedSamplePixels, 180, 0, "completed sample pixels")
    assertNear(blockingStats.totalSamplePixels, 180, 0, "total sample pixels")
    assert(blockingStats.elapsedSeconds >= 0, "renderer elapsed time")
    assert(blockingStats.lastStepSeconds >= 0, "renderer step time")
    assert(blockingStats.pixelsPerSecond >= 0, "renderer pixel throughput")
    assert(blockingStats.samplesPerSecond >= 0, "renderer sample throughput")
    if blockingStats.integrator ~= nil then
        assert(blockingStats.integrator.pathCount == 180, "integrator path count")
        assert(blockingStats.integrator.bounceCount >= 180, "integrator bounce count")
    end

    local stepped = createTestRenderer {
        width = 10,
        height = 9,
        tileSize = 4,
        samplesPerPixel = 2,
        seed = 99,
    }
    assertNear(stepped:step(1), 1, 0, "one tile step")
    assertNear(stepped:getStats().completedPixels, 16, 0, "first tile pixels")
    assertNear(stepped:getStats().completedSamplePixels, 16, 0, "first pass sample pixels")
    assert(stepped:progress() < 1, "partial renderer should not be complete")
    stepped:render()
    filmsMatch(blocking.film, stepped.film)
    assertAOVsMatch(blocking.aov, stepped.aov)

    local resetStats = stepped:getStats()
    stepped:reset()
    local afterReset = stepped:getStats()
    assertNear(afterReset.completedTiles, 0, 0, "reset tile count")
    assertNear(afterReset.completedPixels, 0, 0, "reset pixel count")
    assertNear(afterReset.totalSamples, 0, 0, "reset sample count")
    assertNear(afterReset.completedPasses, 0, 0, "reset pass count")
    assertNear(afterReset.completedSamplePixels, 0, 0, "reset sample pixels")
    assert(not afterReset.complete and not afterReset.cancelled, "reset should clear renderer state")
    stepped:render()
    filmsMatch(blocking.film, stepped.film)
    assertAOVsMatch(blocking.aov, stepped.aov)
    assert(resetStats.complete, "pre-reset renderer should have completed")

    local wideBudget = createTestRenderer {
        width = 10,
        height = 9,
        tileSize = 4,
        samplesPerPixel = 2,
        seed = 99,
    }
    wideBudget:render()
    filmsMatch(blocking.film, wideBudget.film)
    assertAOVsMatch(blocking.aov, wideBudget.aov)

    local clock = 0
    local pathRenderer = createTestRenderer {
        width = 4,
        height = 3,
        tileSize = 2,
        samplesPerPixel = 2,
        integrator = RT.PathIntegrator.new {
            maxDepth = 3,
            background = Vec3.new(0.2, 0.3, 0.4),
        },
        timeProvider = function()
            clock = clock + 0.01
            return clock
        end,
    }
    pathRenderer:render()
    local pathStats = pathRenderer:getStats()
    assert(pathStats.elapsedSeconds > 0, "injected clock elapsed time")
    assert(pathStats.pathsPerSecond > 0, "path throughput")
    assert(pathStats.integrator ~= nil, "path integrator stats")
    assert(pathStats.integrator.pathCount == 24, "path renderer count")
    assert(pathStats.integrator.bounceCount >= pathStats.integrator.pathCount, "path bounce count")
    assert(pathStats.integrator.hitCount + pathStats.integrator.missCount == pathStats.integrator.bounceCount, "path hit miss accounting")
    for y = 0, pathRenderer.height - 1 do
        for x = 0, pathRenderer.width - 1 do
            assertNear(pathRenderer.aov:getSampleCount(x, y), 2, 0, "path AOV sample count")
            local hits = pathRenderer.aov:getHitCount(x, y)
            local coverage = pathRenderer.aov:getCoverage(x, y)
            assertNear(coverage, hits / 2, 1e-8, "path AOV coverage")
        end
    end
    pathRenderer:reset()
    local resetPathStats = pathRenderer:getStats()
    assert(resetPathStats.integrator.pathCount == 0, "reset integrator stats")
    assertNear(pathRenderer.aov:getSampleCount(0, 0), 0, 0, "reset path AOV samples")

    local passFilm = RT.Film.new(1, 1)
    passFilm:addSample(0, 0, Vec3.new(0.2, 0.4, 0.6))
    passFilm:addSample(0, 0, Vec3.new(0.6, 0.8, 1.0))
    local passRed, passGreen, passBlue = passFilm:get(0, 0)
    assertNear(passRed, 0.4, 1e-8, "film running red average")
    assertNear(passGreen, 0.6, 1e-8, "film running green average")
    assertNear(passBlue, 0.8, 1e-8, "film running blue average")
    assertNear(passFilm:getSampleCount(0, 0), 2, 0, "film sample count")
    local expectedLuminanceA = 0.2 * 0.2126 + 0.4 * 0.7152 + 0.6 * 0.0722
    local expectedLuminanceB = 0.6 * 0.2126 + 0.8 * 0.7152 + 1.0 * 0.0722
    local expectedLuminanceMean = (expectedLuminanceA + expectedLuminanceB) * 0.5
    local expectedLuminanceVariance = (
        (expectedLuminanceA - expectedLuminanceMean) ^ 2
            + (expectedLuminanceB - expectedLuminanceMean) ^ 2
    )
    local luminanceMean, luminanceVariance, luminanceCount =
        passFilm:getLuminanceMoments(0, 0)
    assertNear(luminanceMean, expectedLuminanceMean, 1e-8, "film luminance mean")
    assertNear(luminanceVariance, expectedLuminanceVariance, 1e-8,
        "film luminance sample variance")
    assertNear(luminanceCount, 2, 0, "film luminance sample count")
    local meanLuminance, meanVariance = passFilm:getMeanLuminanceVariance(0, 0)
    assertNear(meanLuminance, expectedLuminanceMean, 1e-8,
        "film mean luminance moment")
    assertNear(meanVariance, expectedLuminanceVariance / 2, 1e-8,
        "film mean luminance variance")
    passFilm:clear()
    local clearedMean, clearedVariance, clearedCount =
        passFilm:getLuminanceMoments(0, 0)
    assertNear(clearedMean, 0, 0, "cleared film luminance mean")
    assertNear(clearedVariance, 0, 0, "cleared film luminance variance")
    assertNear(clearedCount, 0, 0, "cleared film luminance count")

    local cancelledTiles = 0
    local callback = RT.CallbackPresenter.new {
        onTile = function(_, _, _, _, _, renderer)
            cancelledTiles = cancelledTiles + 1
            renderer:cancel()
        end,
    }
    local cancelled = createTestRenderer { presenter = callback }
    cancelled:step(100)
    local cancelledStats = cancelled:getStats()
    assertNear(cancelledTiles, 1, 0, "cancel callback count")
    assert(cancelledStats.cancelled, "renderer should be cancelled")
    assert(not cancelledStats.complete, "cancelled renderer should not complete")
    assertNear(cancelledStats.completedTiles, 1, 0, "cancelled tile count")
    local completedPixels = cancelledStats.completedPixels
    assertNear(cancelled:step(100), 0, 0, "cancelled step result")
    assertNear(cancelled:getStats().completedPixels, completedPixels, 0, "cancelled renderer should not advance")
end

local function testPresenters()
    local tiles = 0
    local started = false
    local progressCalls = 0
    local completed = false
    local callback = RT.CallbackPresenter.new {
        onStart = function(width, height, renderer)
            started = width == 8 and height == 6 and renderer ~= nil
        end,
        onTile = function(x, y, width, height, pixels, renderer)
            tiles = tiles + 1
            assert(x >= 0 and y >= 0, "callback tile origin")
            assert(width > 0 and height > 0, "callback tile size")
            assert(#pixels == width * height, "callback tile pixel count")
            assert(renderer ~= nil, "callback renderer")
        end,
        onProgress = function(done, total, renderer)
            progressCalls = progressCalls + 1
            assert(done <= total, "callback progress bounds")
            assert(renderer ~= nil, "progress renderer")
        end,
        onComplete = function(film, renderer)
            completed = film.width == 8 and film.height == 6 and renderer ~= nil
        end,
    }
    local renderer = createTestRenderer {
        width = 8,
        height = 6,
        tileSize = 4,
        presenter = callback,
    }
    renderer:render()
    assert(started, "callback start")
    assertNear(tiles, 4, 0, "callback tile count")
    assert(progressCalls > 0, "callback progress")
    assert(completed, "callback complete")

    local ansiOutput = nil
    local ansi = RT.AnsiPresenter.new(function(value)
        ansiOutput = value
    end)
    ansi:onStart(8, 6)
    ansi:onComplete(renderer.film)
    assert(ansiOutput ~= nil and #ansiOutput > 0, "ANSI output should not be empty")
    assert(ansiOutput:find("\27%[48;2;", 1) ~= nil, "ANSI true-color escape")
    assert(ansiOutput:find("\27%[0m", 1) ~= nil, "ANSI reset escape")
end

local function testMaterials()
    local record = {
        point = Vec3.new(0, 0, 0),
        normal = Vec3.new(0, 1, 0),
        frontFace = true,
    }
    local incoming = Ray.new(Vec3.new(0, 1, 0), Vec3.new(0, -1, 0))

    local diffuseColor = Vec3.new(0.7, 0.2, 0.1)
    local diffuse = RT.Lambertian.new(diffuseColor)
    assert(diffuse:denoiseClass(record) == "diffuse", "Lambertian denoise class")
    local diffuseRay, diffuseAttenuation = diffuse:scatter(incoming, record, RT.RNG.new(5))
    assert(diffuseRay ~= nil, "Lambertian should always scatter")
    assertVectorNear(diffuseAttenuation, diffuseColor, 1e-8, "Lambertian attenuation")
    assert(diffuseRay.direction:dot(record.normal) > -1, "Lambertian scatter should be valid")

    local polished = RT.Metal.new(Vec3.new(0.8, 0.8, 0.8), -1)
    assertNear(polished.fuzz, 0, 0, "Metal minimum fuzz")
    assert(polished:denoiseClass(record) == "delta_reflection", "polished Metal denoise class")
    local rough = RT.Metal.new(Vec3.new(0.8, 0.8, 0.8), 2)
    assertNear(rough.fuzz, 1, 0, "Metal maximum fuzz")
    assert(rough:denoiseClass(record) == "glossy", "rough Metal denoise class")
    local metalRay, metalAttenuation = polished:scatter(incoming, record, RT.RNG.new(5))
    assert(metalRay ~= nil, "Metal should reflect front-facing ray")
    assert(metalRay.direction:dot(record.normal) > 0, "Metal reflection should leave surface")
    assertVectorNear(metalAttenuation, Vec3.new(0.8, 0.8, 0.8), 1e-8, "Metal attenuation")

    local glass = RT.Dielectric.new(1.5)
    assert(glass:denoiseClass(record) == "delta_transmission", "Dielectric denoise class")
    local glassRay, glassAttenuation = glass:scatter(incoming, record, RT.RNG.new(5))
    assert(glassRay ~= nil, "Dielectric should scatter")
    assertVectorNear(glassAttenuation, Vec3.new(1, 1, 1), 1e-8, "Dielectric attenuation")
    assertVectorNear(glass:albedoAt(record), Vec3.new(1, 1, 1), 1e-8, "Dielectric AOV albedo")
    assertNear(glassRay.direction:length(), 1, 1e-8, "Dielectric direction length")
end

local function testJ1BSDFContract()
    local record = {
        point = Vec3.new(0, 0, 0),
        normal = Vec3.new(0, 1, 0),
        frontFace = true,
    }
    local incomingRay = Ray.new(Vec3.new(0, 1, 0), Vec3.new(0, -1, 0))
    local outgoingDirection = -incomingRay.direction
    local upperDirection = Vec3.new(0, 1, 0)
    local lowerDirection = Vec3.new(0, -1, 0)

    local diffuseColor = Vec3.new(0.6, 0.3, 0.15)
    local diffuse = RT.Lambertian.new(diffuseColor)
    assert(diffuse:isDelta() == false, "Lambertian must be non-delta")
    assertVectorNear(
        diffuse:evaluate(record, outgoingDirection, upperDirection),
        diffuseColor * (1 / math.pi),
        1e-12,
        "Lambertian evaluate"
    )
    assertNear(
        diffuse:pdf(record, outgoingDirection, upperDirection),
        1 / math.pi,
        1e-12,
        "Lambertian normal-direction PDF"
    )
    assertNear(
        diffuse:pdf(record, outgoingDirection, lowerDirection),
        0,
        0,
        "Lambertian below-surface PDF"
    )
    assertVectorNear(
        diffuse:evaluate(record, outgoingDirection, lowerDirection),
        Vec3.new(0, 0, 0),
        0,
        "Lambertian below-surface evaluate"
    )
    local diffuseLegacyRay, diffuseLegacyAttenuation =
        diffuse:scatter(incomingRay, record, RT.RNG.new(17))
    local diffuseSampleRay, diffuseSampleAttenuation, diffuseSpecular,
        diffuseEvent, diffuseSamplePdf =
        diffuse:sample(incomingRay, record, RT.RNG.new(17))
    assertVectorNear(
        diffuseSampleRay.direction,
        diffuseLegacyRay.direction,
        0,
        "Lambertian sample keeps legacy direction"
    )
    assertVectorNear(
        diffuseSampleAttenuation,
        diffuseLegacyAttenuation,
        0,
        "Lambertian sample keeps legacy attenuation"
    )
    assert(diffuseSpecular == false and diffuseEvent == nil,
        "Lambertian sample event contract")
    assertNear(
        diffuseSamplePdf,
        diffuse:pdf(record, outgoingDirection, diffuseSampleRay.direction),
        0,
        "Lambertian sampled PDF"
    )

    local polished = RT.Metal.new(Vec3.new(0.8, 0.8, 0.8), 0)
    assert(polished:isDelta() == true, "polished Metal must be delta")
    assertNear(polished:pdf(record, outgoingDirection, upperDirection), 0, 0,
        "delta Metal continuous PDF")
    assertVectorNear(
        polished:evaluate(record, outgoingDirection, upperDirection),
        Vec3.new(0, 0, 0),
        0,
        "delta Metal continuous evaluate"
    )
    local polishedLegacyRay = polished:scatter(incomingRay, record, RT.RNG.new(23))
    local polishedSampleRay, _, _, _, polishedSamplePdf =
        polished:sample(incomingRay, record, RT.RNG.new(23))
    assertVectorNear(polishedSampleRay.direction, polishedLegacyRay.direction, 0,
        "delta Metal sample keeps legacy direction")
    assert(polishedSamplePdf == nil,
        "delta Metal must not fake a continuous sampled PDF")

    local rough = RT.Metal.new(Vec3.new(0.8, 0.7, 0.6), 0.25)
    assert(rough:isDelta() == false, "rough Metal must be non-delta")
    assert(rough:evaluate(record, outgoingDirection, upperDirection) == nil,
        "legacy rough Metal evaluate remains unsupported until GGX")
    assert(rough:pdf(record, outgoingDirection, upperDirection) == nil,
        "legacy rough Metal PDF remains unsupported until GGX")

    local glass = RT.Dielectric.new(1.5)
    assert(glass:isDelta() == true, "Dielectric must be delta")
    assertNear(glass:pdf(record, outgoingDirection, upperDirection), 0, 0,
        "Dielectric continuous PDF")
    assertVectorNear(
        glass:evaluate(record, outgoingDirection, upperDirection),
        Vec3.new(0, 0, 0),
        0,
        "Dielectric continuous evaluate"
    )
    local glassLegacyRay, glassLegacyAttenuation, glassLegacySpecular,
        glassLegacyEvent = glass:scatter(incomingRay, record, RT.RNG.new(29))
    local glassSampleRay, glassSampleAttenuation, glassSampleSpecular,
        glassSampleEvent, glassSamplePdf =
        glass:sample(incomingRay, record, RT.RNG.new(29))
    assertVectorNear(glassSampleRay.direction, glassLegacyRay.direction, 0,
        "Dielectric sample keeps legacy direction")
    assertVectorNear(glassSampleAttenuation, glassLegacyAttenuation, 0,
        "Dielectric sample keeps legacy attenuation")
    assert(glassSampleSpecular == glassLegacySpecular
            and glassSampleEvent == glassLegacyEvent,
        "Dielectric sample keeps legacy event")
    assert(glassSamplePdf == nil,
        "Dielectric must not fake a continuous sampled PDF")

    local light = RT.DiffuseLight.new(
        RT.SolidColor.new(Vec3.new(1, 0.9, 0.8)),
        2
    )
    assert(light:isDelta() == false, "area emission is not a delta BSDF")
    assertNear(light:pdf(record, outgoingDirection, upperDirection), 0, 0,
        "emission PDF")
    assertVectorNear(
        light:evaluate(record, outgoingDirection, upperDirection),
        Vec3.new(0, 0, 0),
        0,
        "emission evaluate"
    )
    local lightRay, _, lightSpecular, _, lightPdf =
        light:sample(incomingRay, record, RT.RNG.new(31))
    assert(lightRay == nil and lightSpecular == false and lightPdf == 0,
        "emission must not sample a BSDF direction")
end

local function testPathIntegrator()
    local scene = RT.Scene.new()
    scene:add(RT.Sphere.new(
        Vec3.new(0, 0, -1),
        0.5,
        RT.Lambertian.new(Vec3.new(0.7, 0.3, 0.3))
    ))
    local integrator = RT.PathIntegrator.new {
        maxDepth = 8,
        background = Vec3.new(0.5, 0.7, 1.0),
    }
    local ray = Ray.new(Vec3.new(0, 0, 0), Vec3.new(0, 0, -1))
    local color = integrator:trace(ray, scene, RT.RNG.new(42))
    assert(color ~= nil, "Path integrator should return a color")
    assert(color.x == color.x and color.y == color.y and color.z == color.z, "Path color must not be NaN")
    assert(color.x >= 0 and color.y >= 0 and color.z >= 0, "Path color must be non-negative")
end

local function testDirectLightMaterialBoundary()
    local function traceMaterial(material, onPrimaryHit)
        local hitCalls = 0
        local primaryRecord = {
            point = Vec3.new(0, 0, 0),
            normal = Vec3.new(0, 1, 0),
            t = 1,
            frontFace = true,
            material = material,
        }
        local light = {
            material = {
                emitted = function()
                    return Vec3.new(2, 2, 2)
                end,
            },
            sampleSurface = function()
                return Vec3.new(0, 1, 0), Vec3.new(0, -1, 0), 1
            end,
        }
        local scene = {
            lights = { light },
            hit = function()
                hitCalls = hitCalls + 1
                if hitCalls == 1 then
                    return primaryRecord
                end
                return nil
            end,
        }
        local integrator = RT.PathIntegrator.new {
            maxDepth = 1,
            background = Vec3.new(0, 0, 0),
            roulette = false,
        }
        local color = integrator:trace(
            Ray.new(Vec3.new(0, 1, 0), Vec3.new(0, -1, 0)),
            scene,
            RT.RNG.new(42),
            onPrimaryHit
        )
        return color, hitCalls
    end

    local diffuse = RT.Lambertian.new(Vec3.new(0.5, 0.5, 0.5))
    assert(type(diffuse.directLightAlbedo) == "function", "Lambertian direct-light interface")
    local diffuseColor, diffuseHitCalls = traceMaterial(diffuse)
    assert(diffuseColor.x > 0 and diffuseColor.y > 0 and diffuseColor.z > 0,
        "Lambertian should receive direct lighting")
    assertNear(diffuseHitCalls, 2, 0, "Lambertian should cast one shadow ray")

    local glass = RT.Dielectric.new(1.333)
    assert(glass.albedoAt ~= nil, "Dielectric should retain AOV albedo")
    assert(glass.directLightAlbedo == nil, "Dielectric must reject Lambertian direct lighting")
    local glassColor, glassHitCalls = traceMaterial(glass)
    assertVectorNear(glassColor, Vec3.new(0, 0, 0), 0,
        "Dielectric must not receive Lambertian direct lighting")
    assertNear(glassHitCalls, 1, 0, "Dielectric should not cast a diffuse shadow ray")

    local withoutAOV = traceMaterial(diffuse)
    local callbackRecord = nil
    local withAOV = traceMaterial(diffuse, function(record)
        callbackRecord = record
        if record ~= nil and record.material ~= nil then
            record.material:albedoAt(record)
        end
    end)
    assert(callbackRecord ~= nil, "AOV callback should receive primary hit")
    assertVectorNear(withAOV, withoutAOV, 0,
        "AOV collection must not change Beauty radiance")
end

local function testAOVCorrect5TransmissionDiagnostics()
    local glass = RT.Dielectric.new(1.5)
    local record = {
        point = Vec3.new(0, 0, 0),
        normal = Vec3.new(0, 1, 0),
        frontFace = true,
    }
    local incoming = Ray.new(
        Vec3.new(0, 1, 0),
        Vec3.new(0, -1, 0)
    )
    local function fixedRng(value)
        return {
            nextFloat = function()
                return value
            end,
        }
    end

    local reflected, reflectedAttenuation, reflectedSpecular, reflectedEvent =
        glass:scatter(incoming, record, fixedRng(0))
    assert(reflectedEvent == "reflection",
        "Dielectric should report Fresnel reflection")
    assert(reflectedSpecular == true,
        "Dielectric reflection remains specular")
    assertVectorNear(reflectedAttenuation, Vec3.new(1, 1, 1), 0,
        "Dielectric reflection attenuation")
    assertVectorNear(reflected.direction, Vec3.new(0, 1, 0), 1e-12,
        "Dielectric reflection direction")

    local transmitted, transmittedAttenuation, transmittedSpecular, transmittedEvent =
        glass:scatter(incoming, record, fixedRng(1))
    assert(transmittedEvent == "transmission",
        "Dielectric should report refraction")
    assert(transmittedSpecular == true,
        "Dielectric refraction remains specular")
    assertVectorNear(transmittedAttenuation, Vec3.new(1, 1, 1), 0,
        "Dielectric refraction attenuation")
    assertVectorNear(transmitted.direction, Vec3.new(0, -1, 0), 1e-12,
        "Dielectric refraction direction")

    local primaryRecord = {
        point = record.point,
        normal = record.normal,
        frontFace = record.frontFace,
        material = glass,
    }
    local diffuseStop = {
        denoiseClass = function()
            return "diffuse"
        end,
        emitted = function()
            return Vec3.new(0, 0, 0)
        end,
        scatter = function()
            return nil
        end,
    }
    local diffuseRecord = {
        point = Vec3.new(0, -1, 0),
        normal = Vec3.new(0, 1, 0),
        frontFace = true,
        material = diffuseStop,
    }
    local diffuseCalls = 0
    local diffuseScene = {
        hit = function()
            diffuseCalls = diffuseCalls + 1
            if diffuseCalls == 1 then
                return primaryRecord
            elseif diffuseCalls == 2 then
                return diffuseRecord
            end
            return nil
        end,
    }
    local diffuseIntegrator = RT.PathIntegrator.new {
        maxDepth = 3,
        background = Vec3.new(0.2, 0.3, 0.4),
        roulette = false,
    }
    diffuseIntegrator:trace(incoming, diffuseScene, fixedRng(1))
    local diffuseStats = diffuseIntegrator:getStats()
    assertNear(diffuseStats.primaryTransmissionCount, 1, 0,
        "primary transmission path count")
    assertNear(diffuseStats.primaryTransmissionReflectionCount, 0, 0,
        "primary transmission reflection count")
    assertNear(diffuseStats.primaryTransmissionRefractionCount, 1, 0,
        "primary transmission refraction count")
    assertNear(diffuseStats.primaryTransmissionFirstDiffuseCount, 1, 0,
        "first diffuse target count")
    assertNear(diffuseCalls, 2, 0,
        "transmission diagnostics must not add scene hits")
    assertNear(
        diffuseStats.primaryTransmissionFirstDiffuseCount
            + diffuseStats.primaryTransmissionFirstGlossyCount
            + diffuseStats.primaryTransmissionFirstEmissionCount
            + diffuseStats.primaryTransmissionFirstOtherCount
            + diffuseStats.primaryTransmissionSkyCount
            + diffuseStats.primaryTransmissionRouletteCount
            + diffuseStats.primaryTransmissionScatterStopCount
            + diffuseStats.primaryTransmissionDepthLimitCount,
        diffuseStats.primaryTransmissionCount,
        0,
        "diffuse transmission destination accounting"
    )

    local skyCalls = 0
    local skyScene = {
        hit = function()
            skyCalls = skyCalls + 1
            if skyCalls == 1 then
                return primaryRecord
            end
            return nil
        end,
    }
    local skyIntegrator = RT.PathIntegrator.new {
        maxDepth = 3,
        background = Vec3.new(0.2, 0.3, 0.4),
        roulette = false,
    }
    skyIntegrator:trace(incoming, skyScene, fixedRng(0))
    local skyStats = skyIntegrator:getStats()
    assertNear(skyStats.primaryTransmissionReflectionCount, 1, 0,
        "primary Fresnel reflection count")
    assertNear(skyStats.primaryTransmissionSkyCount, 1, 0,
        "primary transmission sky termination count")
    assertNear(skyCalls, 2, 0,
        "sky diagnostics must not add scene hits")
    assertNear(
        skyStats.primaryTransmissionReflectionCount
            + skyStats.primaryTransmissionRefractionCount,
        skyStats.primaryTransmissionCount,
        0,
        "primary transmission branch accounting"
    )

    local depthCalls = 0
    local depthScene = {
        hit = function()
            depthCalls = depthCalls + 1
            return primaryRecord
        end,
    }
    local depthIntegrator = RT.PathIntegrator.new {
        maxDepth = 1,
        background = Vec3.new(0.2, 0.3, 0.4),
        roulette = false,
    }
    depthIntegrator:trace(incoming, depthScene, fixedRng(1))
    local depthStats = depthIntegrator:getStats()
    assertNear(depthStats.primaryTransmissionDepthLimitCount, 1, 0,
        "primary transmission depth-limit count")

    local stoppingGlass = {
        denoiseClass = function()
            return "delta_transmission"
        end,
        emitted = function()
            return Vec3.new(0, 0, 0)
        end,
        scatter = function()
            return nil, nil, true, "transmission"
        end,
    }
    local stopCalls = 0
    local stopScene = {
        hit = function()
            stopCalls = stopCalls + 1
            if stopCalls == 1 then
                return {
                    point = record.point,
                    normal = record.normal,
                    frontFace = record.frontFace,
                    material = stoppingGlass,
                }
            end
            return nil
        end,
    }
    local stopIntegrator = RT.PathIntegrator.new {
        maxDepth = 3,
        background = Vec3.new(0.2, 0.3, 0.4),
        roulette = false,
    }
    stopIntegrator:trace(incoming, stopScene, fixedRng(1))
    local stopStats = stopIntegrator:getStats()
    assertNear(stopStats.primaryTransmissionScatterStopCount, 1, 0,
        "primary transmission scatter-stop count")
    assertNear(stopCalls, 1, 0,
        "scatter-stop diagnostics must not add scene hits")

    local legacyGlass = {
        denoiseClass = function(_, hitRecord)
            return glass:denoiseClass(hitRecord)
        end,
        emitted = function(_, hitRecord)
            return glass:emitted(hitRecord)
        end,
        scatter = function(_, sourceRay, hitRecord, rng)
            local scatteredRay, attenuation, isSpecular =
                glass:scatter(sourceRay, hitRecord, rng)
            return scatteredRay, attenuation, isSpecular
        end,
    }
    local function traceSky(material)
        local calls = 0
        local scene = {
            hit = function()
                calls = calls + 1
                if calls == 1 then
                    return {
                        point = record.point,
                        normal = record.normal,
                        frontFace = record.frontFace,
                        material = material,
                    }
                end
                return nil
            end,
        }
        local integrator = RT.PathIntegrator.new {
            maxDepth = 3,
            background = Vec3.new(0.2, 0.3, 0.4),
            roulette = false,
        }
        return integrator:trace(incoming, scene, fixedRng(1))
    end
    local diagnosticBeauty = traceSky(glass)
    local legacyBeauty = traceSky(legacyGlass)
    assertVectorNear(diagnosticBeauty, legacyBeauty, 0,
        "transmission diagnostics must not change Beauty")
end

local function testAcceleration()
    local unitBox = RT.AABB.new(Vec3.new(-1, -1, -1), Vec3.new(1, 1, 1))
    local interval = Interval.new(0.001, math.huge)
    assert(unitBox:hit(Ray.new(Vec3.new(0, 0, -3), Vec3.new(0, 0, 1)), interval), "AABB front hit")
    assert(unitBox:hit(Ray.new(Vec3.new(0, 0, 0), Vec3.new(1, 0, 0)), interval), "AABB inside hit")
    assert(unitBox:hit(Ray.new(Vec3.new(0, 0, -3), Vec3.new(0, 0, 1)), interval), "AABB parallel in slab")
    assert(not unitBox:hit(Ray.new(Vec3.new(2, 0, -3), Vec3.new(0, 0, 1)), interval), "AABB parallel outside slab")

    local triangle = RT.Triangle.new(
        Vec3.new(-1, -1, -2),
        Vec3.new(1, -1, -2),
        Vec3.new(0, 1, -2)
    )
    local triangleHit = triangle:hit(
        Ray.new(Vec3.new(0, 0, 0), Vec3.new(0, 0, -1)),
        interval
    )
    assert(triangleHit ~= nil, "center ray should hit triangle")
    assertNear(triangleHit.t, 2, 1e-8, "triangle distance")
    assert(triangleHit.u >= 0 and triangleHit.v >= 0 and triangleHit.u + triangleHit.v <= 1, "triangle barycentric coordinates")
    assert(triangle:hit(Ray.new(Vec3.new(2, 2, 0), Vec3.new(0, 0, -1)), interval) == nil, "ray should miss triangle")
    assert(triangle:hit(Ray.new(Vec3.new(0, 0, -2), Vec3.new(1, 0, 0)), interval) == nil, "parallel ray should miss triangle")

    local scene = RT.Scene.new()
    for z = 1, 8 do
        for x = 1, 8 do
            scene:add(RT.Sphere.new(Vec3.new(x * 2, 0, z * 2), 0.45))
        end
    end
    scene:add(triangle)
    local bvh = scene:buildBVH()
    assert(scene:getAccelerator() == bvh, "Scene should cache built BVH")
    local rays = {
        Ray.new(Vec3.new(0, 0, 0), Vec3.new(0, 0, -1)),
        Ray.new(Vec3.new(2, 0, 0), Vec3.new(0, 0, 1)),
        Ray.new(Vec3.new(8, 0, 0), Vec3.new(0, 0, 1)),
        Ray.new(Vec3.new(20, 5, 0), Vec3.new(0, 0, 1)),
    }
    for index = 1, #rays do
        local bruteHit = scene:hitBruteForce(rays[index], interval)
        bvh:resetStats()
        local acceleratedHit = scene:hit(rays[index], interval)
        local traversalStats = bvh:getStats()
        assert(traversalStats.boxTests > 0, "Scene should route hit through BVH " .. index)
        assert((bruteHit == nil) == (acceleratedHit == nil), "BVH hit presence " .. index)
        if bruteHit ~= nil then
            assertNear(acceleratedHit.t, bruteHit.t, 1e-8, "BVH hit distance " .. index)
            assertVectorNear(acceleratedHit.normal, bruteHit.normal, 1e-8, "BVH hit normal " .. index)
        end
    end

    bvh:resetStats()
    local measuredRay = Ray.new(Vec3.new(2, 0, 0), Vec3.new(0, 0, 1))
    bvh:hit(measuredRay, interval)
    local stats = bvh:getStats()
    assert(stats.nodeCount > 1 and stats.leafCount > 1, "BVH build stats")
    assert(stats.boxTests > 0, "BVH box tests")
    assert(stats.primitiveTests < #scene.objects, "BVH should reduce primitive tests")

    local closerScene = RT.Scene.new()
    closerScene:add(RT.Sphere.new(Vec3.new(0, 0, -4), 1))
    closerScene:buildBVH()
    closerScene:add(RT.Sphere.new(Vec3.new(0, 0, -1), 0.25))
    local invalidatedHit = closerScene:hit(
        Ray.new(Vec3.new(0, 0, 0), Vec3.new(0, 0, -1)),
        interval
    )
    assertNear(invalidatedHit.t, 0.75, 1e-8, "Scene add should invalidate BVH")

    closerScene:clear()
    assert(closerScene:getAccelerator() == nil, "Scene clear should invalidate BVH")
    assert(
        closerScene:hit(Ray.new(Vec3.new(0, 0, 0), Vec3.new(0, 0, -1)), interval) == nil,
        "cleared Scene should miss"
    )
end

local function testLightingAndTextures()
    local red = RT.SolidColor.new(Vec3.new(0.8, 0.1, 0.05))
    local blue = RT.SolidColor.new(Vec3.new(0.05, 0.1, 0.8))
    local checker = RT.Checker.new(1.0, red, blue)
    local evenRecord = { point = Vec3.new(0.1, 0.1, 0.1) }
    local oddRecord = { point = Vec3.new(1.1, 0.1, 0.1) }
    assertVectorNear(checker:value(evenRecord), Vec3.new(0.8, 0.1, 0.05), 1e-8, "checker even")
    assertVectorNear(checker:value(oddRecord), Vec3.new(0.05, 0.1, 0.8), 1e-8, "checker odd")

    local image = RT.ImageTexture.fromPPM([[P3
2 2
255
255 0 0   0 255 0
0 0 255   255 255 255
]])
    assertNear(image.width, 2, 0, "image texture width")
    assertNear(image.height, 2, 0, "image texture height")
    assertVectorNear(
        image:value({ u = 0.1, v = 0.1 }),
        Vec3.new(0, 0, 1),
        1e-8,
        "image texture bottom-left"
    )
    assertVectorNear(
        image:value({ u = 0.9, v = 0.1 }),
        Vec3.new(1, 1, 1),
        1e-8,
        "image texture bottom-right"
    )
    assertVectorNear(
        image:value({ u = 0.1, v = 0.9 }),
        Vec3.new(1, 0, 0),
        1e-8,
        "image texture top-left"
    )
    assertVectorNear(
        image:value({ u = 0.9, v = 0.9 }),
        Vec3.new(0, 1, 0),
        1e-8,
        "image texture top-right"
    )

    local texturedLambertian = RT.Lambertian.new(image)
    local _, texturedAlbedo = texturedLambertian:scatter(
        Ray.new(Vec3.new(0, 0, 1), Vec3.new(0, 0, -1)),
        { point = Vec3.new(0, 0, 0), normal = Vec3.new(0, 0, 1), u = 0.9, v = 0.9 },
        RT.RNG.new(17)
    )
    assertVectorNear(texturedAlbedo, Vec3.new(0, 1, 0), 1e-8, "textured Lambertian albedo")

    local light = RT.DiffuseLight.new(red, 3.0)
    local lightRecord = { point = Vec3.new(0, 0, 0), frontFace = true }
    assert(light:denoiseClass(lightRecord) == "emission", "DiffuseLight denoise class")
    assertVectorNear(light:albedoAt(lightRecord), Vec3.new(0.8, 0.1, 0.05), 1e-8, "light AOV albedo")
    assertVectorNear(light:emitted(lightRecord), Vec3.new(2.4, 0.3, 0.15), 1e-8, "emitted color")
    lightRecord.frontFace = false
    assertVectorNear(light:emitted(lightRecord), Vec3.new(0, 0, 0), 1e-8, "back face emission")

    local lightSphere = RT.Sphere.new(Vec3.new(0, 2, 0), 1, light)
    local point, normal, pdf = lightSphere:sampleSurface(RT.RNG.new(7))
    assertNear((point - lightSphere.center):length(), 1, 1e-8, "sampled light surface")
    assertNear(normal:length(), 1, 1e-8, "sampled light normal")
    assertNear(pdf, 1 / (4 * math.pi), 1e-8, "sphere area pdf")

    local litScene = RT.Scene.new()
    litScene:add(RT.Sphere.new(Vec3.new(0, 0, -1), 0.5, RT.Lambertian.new(red)))
    litScene:add(RT.Sphere.new(Vec3.new(0, 2, -1), 0.5, light))
    assertNear(#litScene.lights, 1, 0, "scene light registry")
    local integrator = RT.PathIntegrator.new {
        maxDepth = 4,
        background = Vec3.new(0, 0, 0),
    }
    local color = integrator:trace(
        Ray.new(Vec3.new(0, 0, 0), Vec3.new(0, 0, -1)),
        litScene,
        RT.RNG.new(11)
    )
    assert(color.x >= 0 and color.y >= 0 and color.z >= 0, "direct lighting color")
end

local function testQuadAndRussianRoulette()
    local quad = RT.Quad.new(
        Vec3.new(-1, -1, -2),
        Vec3.new(2, 0, 0),
        Vec3.new(0, 2, 0),
        RT.Lambertian.new(Vec3.new(0.5, 0.5, 0.5))
    )
    local hit = quad:hit(
        Ray.new(Vec3.new(0, 0, 0), Vec3.new(0, 0, -1)),
        Interval.new(0.001, math.huge)
    )
    assert(hit ~= nil, "center ray should hit quad")
    assertNear(hit.t, 2, 1e-8, "quad hit distance")
    assertNear(hit.u, 0.5, 1e-8, "quad u")
    assertNear(hit.v, 0.5, 1e-8, "quad v")
    assert(quad:hit(Ray.new(Vec3.new(2, 0, 0), Vec3.new(0, 0, -1)), Interval.new(0.001, math.huge)) == nil, "ray should miss quad")

    local point, normal, pdf = quad:sampleSurface(RT.RNG.new(5))
    assertNear(point.z, -2, 1e-8, "quad sample plane")
    assertNear(normal:length(), 1, 1e-8, "quad sample normal")
    assertNear(pdf, 0.25, 1e-8, "quad area pdf")

    local roulette = RT.RussianRoulette.new {
        minimumDepth = 3,
        survivalProbability = 0.5,
    }
    local attenuation = Vec3.new(0.4, 0.3, 0.2)
    local beforeMinimum, continued = roulette:continuePath(2, attenuation, RT.RNG.new(1))
    assert(continued, "roulette should continue before minimum depth")
    assertVectorNear(beforeMinimum, attenuation, 1e-8, "roulette pre-minimum attenuation")

    local survivalRng = { nextFloat = function() return 0.25 end }
    local survived, didSurvive = roulette:continuePath(3, attenuation, survivalRng)
    assert(didSurvive, "roulette survival")
    assertVectorNear(survived, attenuation / 0.5, 1e-8, "roulette unbiased weight")

    local terminationRng = { nextFloat = function() return 0.75 end }
    local _, terminated = roulette:continuePath(3, attenuation, terminationRng)
    assert(not terminated, "roulette termination")
end

local function testCornellBoxSceneGeometry()
    local white = RT.Lambertian.new(Vec3.new(0.73, 0.73, 0.73))
    local red = RT.Lambertian.new(Vec3.new(0.65, 0.05, 0.05))
    local green = RT.Lambertian.new(Vec3.new(0.12, 0.45, 0.15))
    local light = RT.DiffuseLight.new(
        RT.SolidColor.new(Vec3.new(1, 1, 1)),
        8
    )
    local scene = RT.Scene.new()

    scene:add(RT.Quad.new(
        Vec3.new(-3, 0, 4), Vec3.new(6, 0, 0), Vec3.new(0, 5, 0), white
    ))
    scene:add(RT.Quad.new(
        Vec3.new(-3, 0, -1), Vec3.new(0, 0, 5), Vec3.new(6, 0, 0), white
    ))
    scene:add(RT.Quad.new(
        Vec3.new(-3, 5, -1), Vec3.new(6, 0, 0), Vec3.new(0, 0, 5), white
    ))
    scene:add(RT.Quad.new(
        Vec3.new(-3, 0, -1), Vec3.new(0, 5, 0), Vec3.new(0, 0, 5), red
    ))
    scene:add(RT.Quad.new(
        Vec3.new(3, 0, 4), Vec3.new(0, 0, -5), Vec3.new(0, 5, 0), green
    ))
    scene:add(RT.Quad.new(
        Vec3.new(-1, 4.98, 1), Vec3.new(2, 0, 0), Vec3.new(0, 0, 1.5), light
    ))

    assertNear(#scene.objects, 6, 0, "Cornell Box room primitive count")
    assertNear(#scene.lights, 1, 0, "Cornell Box light count")
    local box = scene:boundingBox()
    assertNear(box.minimum.x, -3, 1e-3, "Cornell Box bounds min x")
    assertNear(box.minimum.y, 0, 1e-3, "Cornell Box bounds min y")
    assertNear(box.minimum.z, -1, 1e-3, "Cornell Box bounds min z")
    assertNear(box.maximum.x, 3, 1e-3, "Cornell Box bounds max x")
    assertNear(box.maximum.y, 5, 1e-3, "Cornell Box bounds max y")
    assertNear(box.maximum.z, 4, 1e-3, "Cornell Box bounds max z")
end

local function testQualityPresets()
    local preview = QualityPresets.get("preview")
    assertNear(preview.width, 256, 0, "preview width")
    assertNear(preview.height, 144, 0, "preview height")
    assertNear(preview.samplesPerPixel, 32, 0, "preview spp")
    assertNear(preview.maxDepth, 6, 0, "preview max depth")

    local square = QualityPresets.get("quality-square")
    assertNear(square.width, 256, 0, "square width")
    assertNear(square.height, 256, 0, "square height")
    assertNear(square.samplesPerPixel, 64, 0, "square spp")

    local offline = QualityPresets.get("offline")
    assertNear(offline.width, 512, 0, "offline width")
    assertNear(offline.height, 512, 0, "offline height")
    assertNear(offline.samplesPerPixel, 64, 0, "offline spp")

    local ok = pcall(QualityPresets.get, "missing")
    assert(not ok, "unknown quality preset should fail")
end

local function testDisplayDenoise()
    local film = RT.Film.new(3, 3)
    for y = 0, 2 do
        for x = 0, 2 do
            if x == 1 and y == 1 then
                film:addSample(x, y, Vec3.new(1.0, 0.0, 0.0))
            else
                film:addSample(x, y, Vec3.new(0.2, 0.2, 0.2))
            end
        end
    end

    local red, green, blue = DisplayDenoise.filterPixel(film, 1, 1, 3, 3)
    assert(red > 0.8, "denoise should preserve center highlight")
    assert(green < 0.2 and blue < 0.2, "denoise should preserve highlight color")

    local edgeFilm = RT.Film.new(3, 3)
    for y = 0, 2 do
        for x = 0, 1 do
            edgeFilm:addSample(x, y, Vec3.new(0.1, 0.1, 0.1))
        end
        edgeFilm:addSample(2, y, Vec3.new(0.9, 0.9, 0.9))
    end
    local edgeRed = DisplayDenoise.filterPixel(edgeFilm, 1, 1, 3, 3)
    assert(edgeRed > 0.1 and edgeRed < 0.9, "denoise edge should remain bounded")
end

local function testPrimaryAOVAccumulation()
    local aov = PrimaryAOV.new(2, 1)
    aov:set(0, 0, {
        hit = true,
        albedo = Vec3.new(0.2, 0.4, 0.6),
        normal = Vec3.new(0, 1, 0),
        depth = 2,
    })
    aov:set(0, 0, nil)
    aov:set(0, 0, {
        hit = true,
        albedo = Vec3.new(0.6, 0.8, 1.0),
        normal = Vec3.new(0, 1, 0),
        depth = 4,
    })

    local hit, albedo, normal, depth, coverage = aov:get(0, 0)
    assert(hit, "accumulated AOV should report a hit")
    assertVectorNear(albedo, Vec3.new(0.4, 0.6, 0.8), 1e-8, "AOV albedo average")
    assertVectorNear(normal, Vec3.new(0, 1, 0), 1e-8, "AOV normalized normal")
    assertNear(depth, 3, 1e-8, "AOV valid-hit depth average")
    assertNear(coverage, 2 / 3, 1e-8, "AOV hit coverage")
    assertNear(aov:getSampleCount(0, 0), 3, 0, "AOV sample count")
    assertNear(aov:getHitCount(0, 0), 2, 0, "AOV hit count")
    assert(aov:getDenoiseClass(0, 0) == "unknown", "AOV default denoise class")

    aov:set(1, 0, {
        hit = true,
        class = "diffuse",
        albedo = Vec3.new(0.5, 0.5, 0.5),
        normal = Vec3.new(0, 1, 0),
        depth = 2,
    })
    assert(aov:getDenoiseClass(1, 0) == "diffuse", "AOV explicit denoise class")
    aov:set(1, 0, {
        hit = true,
        class = "delta_transmission",
        albedo = Vec3.new(1, 1, 1),
        normal = Vec3.new(0, 1, 0),
        depth = 2,
    })
    assert(aov:getDenoiseClass(1, 0) == "mixed", "AOV mixed denoise class")

    aov:clear()
    local miss, _, _, missDepth, missCoverage = aov:get(1, 0)
    assert(not miss, "untouched AOV pixel should miss")
    assertNear(missDepth, 0, 0, "untouched AOV depth")
    assertNear(missCoverage, 0, 0, "untouched AOV coverage")

    aov:clear()
    assertNear(aov:getSampleCount(0, 0), 0, 0, "cleared AOV sample count")
    assertNear(aov:getHitCount(0, 0), 0, 0, "cleared AOV hit count")
    assertNear(aov:getCoverage(0, 0), 0, 0, "cleared AOV coverage")
end

local function testAOVClassFiltering()
    local protectedClasses = {
        "delta_reflection",
        "delta_transmission",
        "emission",
        "mixed",
        "unknown",
    }
    for classIndex = 1, #protectedClasses do
        local protectedClass = protectedClasses[classIndex]
        local film = RT.Film.new(3, 1)
        film:addSample(0, 0, Vec3.new(0.1, 0.1, 0.1))
        film:addSample(1, 0, Vec3.new(8.0, 6.0, 4.0))
        film:addSample(2, 0, Vec3.new(0.1, 0.1, 0.1))

        local aov = PrimaryAOV.new(3, 1)
        local classes = { "diffuse", protectedClass, "diffuse" }
        for x = 0, 2 do
            aov:set(x, 0, {
                hit = true,
                class = classes[x + 1],
                albedo = Vec3.new(1, 1, 1),
                normal = Vec3.new(0, 1, 0),
                depth = 1,
            })
        end

        local filtered = AOVAtrous.filter(film, aov, 3)
        local protectedR, protectedG, protectedB = filtered:get(1, 0)
        assertNear(protectedR, 8.0, 0, protectedClass .. " red should pass through")
        assertNear(protectedG, 6.0, 0, protectedClass .. " green should pass through")
        assertNear(protectedB, 4.0, 0, protectedClass .. " blue should pass through")
        local diffuseR, diffuseG, diffuseB = filtered:get(0, 0)
        assertNear(diffuseR, 0.1, 1e-12, protectedClass .. " must not leak into diffuse red")
        assertNear(diffuseG, 0.1, 1e-12, protectedClass .. " must not leak into diffuse green")
        assertNear(diffuseB, 0.1, 1e-12, protectedClass .. " must not leak into diffuse blue")
    end

    local material = RT.Dielectric.new(1.33)
    local camera = {
        imageWidth = 1,
        imageHeight = 1,
        getRay = function()
            return Ray.new(Vec3.new(0, 0, 0), Vec3.new(0, 0, -1))
        end,
    }
    local integrator = {
        resetStats = function()
        end,
        trace = function(_, _, _, _, onPrimaryHit)
            onPrimaryHit({
                point = Vec3.new(0, 0, -1),
                normal = Vec3.new(0, 1, 0),
                t = 1,
                frontFace = true,
                material = material,
            })
            return Vec3.new(0.25, 0.5, 0.75)
        end,
    }
    local renderer = RT.Renderer.new {
        camera = camera,
        scene = {},
        integrator = integrator,
        width = 1,
        height = 1,
        samplesPerPixel = 1,
    }
    renderer:render()
    assert(
        renderer.aov:getDenoiseClass(0, 0) == "delta_transmission",
        "Renderer should propagate primary material denoise class"
    )
end

local function testAOVCorrect3EdgeStopping()
    local function makeFilm(values)
        local film = RT.Film.new(#values, 1)
        for x = 0, #values - 1 do
            local value = values[x + 1]
            film:addSample(x, 0, Vec3.new(value, value, value))
        end
        return film
    end

    local function makeAOV(normals, depths, coverages)
        local aov = PrimaryAOV.new(#normals, 1)
        for x = 0, #normals - 1 do
            local sampleCount = 8
            local hitCount = math.floor((coverages[x + 1] or 1) * sampleCount + 0.5)
            for sample = 1, sampleCount do
                if sample <= hitCount then
                    aov:set(x, 0, {
                        hit = true,
                        class = "diffuse",
                        albedo = Vec3.new(0.5, 0.5, 0.5),
                        normal = normals[x + 1],
                        depth = depths[x + 1],
                    })
                else
                    aov:set(x, 0, nil)
                end
            end
        end
        return aov
    end

    local values = { 0.1, 0.1, 1.0 }
    local upward = Vec3.new(0, 1, 0)
    local forward = Vec3.new(0, 0, 1)
    local normalFilm = makeFilm(values)
    local normalFiltered = AOVAtrous.filter(normalFilm, makeAOV(
        { upward, upward, forward },
        { 1, 1, 1 },
        { 1, 1, 1 }
    ), 1)
    local normalEdge = normalFiltered:get(1, 0)
    assertNear(normalEdge, 0.1, 1e-12,
        "orthogonal normal must contribute zero weight")

    local depthFilm = makeFilm(values)
    local depthFiltered = AOVAtrous.filter(depthFilm, makeAOV(
        { upward, upward, upward },
        { 1, 1, 2 },
        { 1, 1, 1 }
    ), 1)
    local depthEdge = depthFiltered:get(1, 0)
    assertNear(depthEdge, 0.1, 1e-12,
        "large depth discontinuity must contribute zero weight")

    local coverageFilm = makeFilm(values)
    local coverageFiltered = AOVAtrous.filter(coverageFilm, makeAOV(
        { upward, upward, upward },
        { 1, 1, 1 },
        { 1, 1, 0.5 }
    ), 1)
    local coverageEdge = coverageFiltered:get(1, 0)
    assertNear(coverageEdge, 0.1, 1e-12,
        "coverage discontinuity must contribute zero weight")

    local hdrFilm = makeFilm({ 0.1, 0.1, 50.0 })
    local beforeR, beforeG, beforeB = hdrFilm:get(2, 0)
    local hdrFiltered = AOVAtrous.filter(hdrFilm, makeAOV(
        { upward, upward, upward },
        { 1, 1, 1 },
        { 1, 1, 1 }
    ), 1)
    local hdrCenter = hdrFiltered:get(1, 0)
    assert(hdrCenter < 0.2,
        "HDR outlier must not spread into a large bright region")
    local afterR, afterG, afterB = hdrFilm:get(2, 0)
    assertNear(afterR, beforeR, 0, "filter must not change Film red")
    assertNear(afterG, beforeG, 0, "filter must not change Film green")
    assertNear(afterB, beforeB, 0, "filter must not change Film blue")
end

local function testAOVCorrect31DirectionalDepth()
    local function makeGrid(depthAt)
        local width = 9
        local height = 9
        local film = RT.Film.new(width, height)
        local aov = PrimaryAOV.new(width, height)
        local normal = Vec3.new(0, 1, 0)

        for y = 0, height - 1 do
            for x = 0, width - 1 do
                local value = 0.2 + ((x + y) % 2) * 0.02
                film:addSample(x, y, Vec3.new(value, value, value))
                aov:set(x, y, {
                    hit = true,
                    class = "diffuse",
                    albedo = Vec3.new(0.5, 0.5, 0.5),
                    normal = normal,
                    depth = depthAt(x, y),
                })
            end
        end

        return film, aov
    end

    local flatFilm, flatAOV = makeGrid(function()
        return 2
    end)
    local flatFiltered = AOVAtrous.filter(flatFilm, flatAOV, 3)
    local flatCenter = flatFiltered:get(4, 4)

    local horizontalFilm, horizontalAOV = makeGrid(function(x)
        return 2 + x * 0.02
    end)
    local horizontalFiltered = AOVAtrous.filter(
        horizontalFilm, horizontalAOV, 3)
    local horizontalCenter = horizontalFiltered:get(4, 4)
    assertNear(
        horizontalCenter,
        flatCenter,
        1e-12,
        "horizontal planar depth gradient must not create vertical bands"
    )

    local verticalFilm, verticalAOV = makeGrid(function(_, y)
        return 2 + y * 0.02
    end)
    local verticalFiltered = AOVAtrous.filter(
        verticalFilm, verticalAOV, 3)
    local verticalCenter = verticalFiltered:get(4, 4)
    assertNear(
        verticalCenter,
        flatCenter,
        1e-12,
        "vertical planar depth gradient must not create horizontal bands"
    )
end

local function testAOVCorrect4Kernels()
    local kernel3 = AOVAtrous.getKernelInfo("3x3")
    local kernel5 = AOVAtrous.getKernelInfo("5x5")
    assert(kernel3 ~= nil, "3x3 kernel info")
    assert(kernel5 ~= nil, "5x5 kernel info")
    assertNear(kernel3.taps, 9, 0, "3x3 kernel taps")
    assertNear(kernel3.weightSum, 16, 0, "3x3 kernel weight sum")
    assertNear(kernel5.taps, 25, 0, "5x5 kernel taps")
    assertNear(kernel5.weightSum, 256, 0, "5x5 B3-spline weight sum")
    assert(AOVAtrous.getKernelInfo("missing") == nil,
        "unknown kernel info should be nil")

    local width = 7
    local height = 7
    local film = RT.Film.new(width, height)
    local aov = PrimaryAOV.new(width, height)
    for y = 0, height - 1 do
        for x = 0, width - 1 do
            film:addSample(x, y, Vec3.new(0.25, 0.25, 0.25))
            aov:set(x, y, {
                hit = true,
                class = "diffuse",
                albedo = Vec3.new(0.5, 0.5, 0.5),
                normal = Vec3.new(0, 1, 0),
                depth = 2,
            })
        end
    end

    local filtered3 = AOVAtrous.filter(film, aov, {
        iterations = 1,
        kernel = "3x3",
    })
    local filtered5 = AOVAtrous.filter(film, aov, {
        iterations = 1,
        kernel = "5x5",
    })
    assertNear(filtered3.stats.taps, 9, 0, "3x3 result taps")
    assertNear(filtered5.stats.taps, 25, 0, "5x5 result taps")
    assertNear(filtered3.stats.candidateVisits, 361, 0,
        "3x3 candidate visits")
    assertNear(filtered5.stats.candidateVisits, 841, 0,
        "5x5 candidate visits")
    assert(filtered5.stats.candidateVisits
            > filtered3.stats.candidateVisits,
        "5x5 must visit more neighbors")

    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local r3, g3, b3 = filtered3:get(x, y)
            local r5, g5, b5 = filtered5:get(x, y)
            assertNear(r3, 0.25, 1e-12, "3x3 constant red")
            assertNear(g3, 0.25, 1e-12, "3x3 constant green")
            assertNear(b3, 0.25, 1e-12, "3x3 constant blue")
            assertNear(r5, 0.25, 1e-12, "5x5 constant red")
            assertNear(g5, 0.25, 1e-12, "5x5 constant green")
            assertNear(b5, 0.25, 1e-12, "5x5 constant blue")
        end
    end

    local repeat5 = AOVAtrous.filter(film, aov, {
        iterations = 1,
        kernel = "5x5",
    })
    local firstR, firstG, firstB = filtered5:get(3, 3)
    local repeatR, repeatG, repeatB = repeat5:get(3, 3)
    assertNear(repeatR, firstR, 0, "5x5 deterministic red")
    assertNear(repeatG, firstG, 0, "5x5 deterministic green")
    assertNear(repeatB, firstB, 0, "5x5 deterministic blue")

    local protectedFilm = RT.Film.new(5, 1)
    local protectedAOV = PrimaryAOV.new(5, 1)
    for x = 0, 4 do
        local value = x == 2 and 8 or 0.1
        protectedFilm:addSample(x, 0, Vec3.new(value, value, value))
        protectedAOV:set(x, 0, {
            hit = true,
            class = x == 2 and "delta_transmission" or "diffuse",
            albedo = Vec3.new(1, 1, 1),
            normal = Vec3.new(0, 1, 0),
            depth = 1,
        })
    end
    local protected5 = AOVAtrous.filter(protectedFilm, protectedAOV, {
        iterations = 3,
        kernel = "5x5",
    })
    local protectedCenter = protected5:get(2, 0)
    local protectedNeighbor = protected5:get(1, 0)
    assertNear(protectedCenter, 8, 0,
        "5x5 protected class must pass through")
    assertNear(protectedNeighbor, 0.1, 1e-12,
        "5x5 protected class must not leak")

    local ok = pcall(AOVAtrous.filter, film, aov, {
        iterations = 1,
        kernel = "missing",
    })
    assert(not ok, "unknown filter kernel should fail")
end

local function testOutput()
    local film = renderFilm()
    local ppm = {}
    local writer = RT.PPMWriter.new(function(chunk)
        ppm[#ppm + 1] = chunk
    end)
    writer:onStart(film.width, film.height)
    writer:onComplete(film)
    local output = table.concat(ppm)
    assert(output:sub(1, 3) == "P3\n", "PPM magic header")
    assert(output:find("16 9", 1, true) ~= nil, "PPM dimensions")

    local asciiOutput = nil
    local presenter = RT.AsciiPresenter.new(function(value)
        asciiOutput = value
    end)
    presenter:onStart(film.width, film.height)
    presenter:onComplete(film)
    assert(asciiOutput ~= nil and #asciiOutput > 0, "ASCII output should not be empty")
end

testVectorMath()
testRayAndSphere()
testDeterministicRng()
testMaterials()
testJ1BSDFContract()
testPathIntegrator()
testDirectLightMaterialBoundary()
testAOVCorrect5TransmissionDiagnostics()
testAcceleration()
testLightingAndTextures()
testQuadAndRussianRoulette()
testCornellBoxSceneGeometry()
testQualityPresets()
testDisplayDenoise()
testPrimaryAOVAccumulation()
testAOVClassFiltering()
testAOVCorrect3EdgeStopping()
testAOVCorrect31DirectionalDepth()
testAOVCorrect4Kernels()
testPhaseCRenderer()
testPresenters()
testOutput()
print("[RayTracerTests] all tests passed")
