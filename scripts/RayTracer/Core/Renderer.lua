local Renderer = {}
Renderer.__index = Renderer

local Vec3 = require "RayTracer.Math.Vec3"
local Film = require "RayTracer.Core.Film"
local RNG = require "RayTracer.Math.RNG"

function Renderer.new(options)
    options = options or {}
    assert(options.camera ~= nil, "Renderer requires a camera")
    assert(options.scene ~= nil, "Renderer requires a scene")
    assert(options.integrator ~= nil, "Renderer requires an integrator")

    local width = options.width or options.camera.imageWidth
    local height = options.height or options.camera.imageHeight
    local samplesPerPixel = options.samplesPerPixel or 1
    local tileSize = options.tileSize or 8
    local presenter = options.presenter

    return setmetatable({
        camera = options.camera,
        scene = options.scene,
        integrator = options.integrator,
        film = options.film or Film.new(width, height),
        width = width,
        height = height,
        samplesPerPixel = samplesPerPixel,
        tileSize = tileSize,
        seed = options.seed or 1,
        presenter = presenter,
        nextPixel = 0,
        totalPixels = width * height,
        completedPixels = 0,
        complete = false,
        cancelled = false,
        started = false,
        reportedComplete = false,
    }, Renderer)
end

function Renderer:reset()
    self.nextPixel = 0
    self.completedPixels = 0
    self.complete = false
    self.cancelled = false
    self.started = false
    self.reportedComplete = false
end

function Renderer:cancel()
    self.cancelled = true
end

function Renderer:isComplete()
    return self.complete
end

function Renderer:progress()
    return self.totalPixels == 0 and 1 or self.completedPixels / self.totalPixels
end

function Renderer:step(pixelBudget)
    if self.complete or self.cancelled then
        return 0
    end

    local budget = pixelBudget or self.tileSize * self.tileSize
    local processed = 0

    if not self.started then
        self.started = true
        if self.presenter and self.presenter.onStart then
            self.presenter:onStart(self.width, self.height)
        end
    end

    while processed < budget and self.nextPixel < self.totalPixels and not self.cancelled do
        local pixelIndex = self.nextPixel
        local x = pixelIndex % self.width
        local y = math.floor(pixelIndex / self.width)
        local accumulated = Vec3.new(0, 0, 0)

        for sample = 1, self.samplesPerPixel do
            local rng = RNG.new(self.seed + pixelIndex * 977 + sample * 131)
            local ray = self.camera:getRay(x, y, rng)
            accumulated = accumulated + self.integrator:trace(ray, self.scene, rng)
        end

        self.film:set(x, y, accumulated / self.samplesPerPixel)
        self.nextPixel = self.nextPixel + 1
        self.completedPixels = self.completedPixels + 1
        processed = processed + 1
    end

    if self.nextPixel >= self.totalPixels then
        self.complete = true
    end

    if self.presenter and self.presenter.onProgress then
        self.presenter:onProgress(self.completedPixels, self.totalPixels, self)
    end
    if self.complete and not self.reportedComplete and self.presenter and self.presenter.onComplete then
        self.reportedComplete = true
        self.presenter:onComplete(self.film, self)
    end

    return processed
end

function Renderer:render()
    while not self.complete and not self.cancelled do
        self:step(self.tileSize * self.tileSize)
    end
    return self.film
end

return Renderer
