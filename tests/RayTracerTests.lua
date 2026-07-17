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
testOutput()
print("[RayTracerTests] all tests passed")
