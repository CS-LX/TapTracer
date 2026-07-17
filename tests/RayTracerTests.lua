local RT = require "RayTracer"

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
        integrator = RT.NormalIntegrator.new(),
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

    local stepped = createTestRenderer {
        width = 10,
        height = 9,
        tileSize = 4,
        samplesPerPixel = 2,
        seed = 99,
    }
    assertNear(stepped:step(1), 1, 0, "one tile step")
    assertNear(stepped:getStats().completedPixels, 16, 0, "first tile pixels")
    assert(stepped:progress() < 1, "partial renderer should not be complete")
    stepped:render()
    filmsMatch(blocking.film, stepped.film)

    local resetStats = stepped:getStats()
    stepped:reset()
    local afterReset = stepped:getStats()
    assertNear(afterReset.completedTiles, 0, 0, "reset tile count")
    assertNear(afterReset.completedPixels, 0, 0, "reset pixel count")
    assertNear(afterReset.totalSamples, 0, 0, "reset sample count")
    assert(not afterReset.complete and not afterReset.cancelled, "reset should clear renderer state")
    stepped:render()
    filmsMatch(blocking.film, stepped.film)
    assert(resetStats.complete, "pre-reset renderer should have completed")

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
    local diffuseRay, diffuseAttenuation = diffuse:scatter(incoming, record, RT.RNG.new(5))
    assert(diffuseRay ~= nil, "Lambertian should always scatter")
    assertVectorNear(diffuseAttenuation, diffuseColor, 1e-8, "Lambertian attenuation")
    assert(diffuseRay.direction:dot(record.normal) > -1, "Lambertian scatter should be valid")

    local polished = RT.Metal.new(Vec3.new(0.8, 0.8, 0.8), -1)
    assertNear(polished.fuzz, 0, 0, "Metal minimum fuzz")
    local rough = RT.Metal.new(Vec3.new(0.8, 0.8, 0.8), 2)
    assertNear(rough.fuzz, 1, 0, "Metal maximum fuzz")
    local metalRay, metalAttenuation = polished:scatter(incoming, record, RT.RNG.new(5))
    assert(metalRay ~= nil, "Metal should reflect front-facing ray")
    assert(metalRay.direction:dot(record.normal) > 0, "Metal reflection should leave surface")
    assertVectorNear(metalAttenuation, Vec3.new(0.8, 0.8, 0.8), 1e-8, "Metal attenuation")

    local glass = RT.Dielectric.new(1.5)
    local glassRay, glassAttenuation = glass:scatter(incoming, record, RT.RNG.new(5))
    assert(glassRay ~= nil, "Dielectric should scatter")
    assertVectorNear(glassAttenuation, Vec3.new(1, 1, 1), 1e-8, "Dielectric attenuation")
    assertNear(glassRay.direction:length(), 1, 1e-8, "Dielectric direction length")
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
testPathIntegrator()
testAcceleration()
testLightingAndTextures()
testQuadAndRussianRoulette()
testCornellBoxSceneGeometry()
testPhaseCRenderer()
testPresenters()
testOutput()
print("[RayTracerTests] all tests passed")
