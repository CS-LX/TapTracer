---@class Renderer
---@field camera table
---@field scene table
---@field integrator table
---@field film table
---@field width number
---@field height number
---@field samplesPerPixel number
---@field tileSize number
---@field tileWidth number
---@field tileHeight number
---@field tiles table
---@field nextTile number
---@field totalTiles number
---@field completedTiles number
---@field seed number
---@field presenter table|nil
---@field nextPixel number
---@field totalPixels number
---@field completedPixels number
---@field totalSamples number
---@field totalRays number
---@field complete boolean
---@field cancelled boolean
---@field started boolean
---@field reportedComplete boolean
local Renderer = {}
Renderer.__index = Renderer

local Vec3 = require "RayTracer.Math.Vec3"
local Film = require "RayTracer.Core.Film"
local RNG = require "RayTracer.Math.RNG"

local function deriveSampleSeed(baseSeed, pixelIndex, sampleIndex)
    local value = (baseSeed
        ~ (pixelIndex * 0x9E3779B9)
        ~ (sampleIndex * 0x85EBCA6B)) & 0xFFFFFFFF
    value = ((value ~ (value >> 16)) * 0x7FEB352D) & 0xFFFFFFFF
    value = ((value ~ (value >> 15)) * 0x846CA68B) & 0xFFFFFFFF
    return (value ~ (value >> 16)) & 0xFFFFFFFF
end

function Renderer.new(options)
    options = options or {}
    assert(options.camera ~= nil, "Renderer requires a camera")
    assert(options.scene ~= nil, "Renderer requires a scene")
    assert(options.integrator ~= nil, "Renderer requires an integrator")

    local width = options.width or options.camera.imageWidth
    local height = options.height or options.camera.imageHeight
    local samplesPerPixel = options.samplesPerPixel or 1
    local tileSize = options.tileSize or 8
    local tileWidth = options.tileWidth or tileSize
    local tileHeight = options.tileHeight or tileSize
    local presenter = options.presenter
    local tiles = {}

    for top = 0, height - 1, tileHeight do
        for left = 0, width - 1, tileWidth do
            tiles[#tiles + 1] = {
                x = left,
                y = top,
                width = math.min(tileWidth, width - left),
                height = math.min(tileHeight, height - top),
            }
        end
    end

    return setmetatable({
        camera = options.camera,
        scene = options.scene,
        integrator = options.integrator,
        film = options.film or Film.new(width, height),
        width = width,
        height = height,
        samplesPerPixel = samplesPerPixel,
        tileSize = tileSize,
        tileWidth = tileWidth,
        tileHeight = tileHeight,
        tiles = tiles,
        nextTile = 1,
        totalTiles = #tiles,
        completedTiles = 0,
        seed = options.seed or 1,
        presenter = presenter,
        nextPixel = 0,
        totalPixels = width * height,
        completedPixels = 0,
        totalSamples = 0,
        totalRays = 0,
        complete = false,
        cancelled = false,
        started = false,
        reportedComplete = false,
    }, Renderer)
end

function Renderer:reset()
    self.film:clear()
    self.nextTile = 1
    self.completedTiles = 0
    self.nextPixel = 0
    self.completedPixels = 0
    self.totalSamples = 0
    self.totalRays = 0
    self.complete = false
    self.cancelled = false
    self.started = false
    self.reportedComplete = false
end

function Renderer:cancel()
    self.cancelled = true
end

function Renderer:isCancelled()
    return self.cancelled
end

function Renderer:isComplete()
    return self.complete
end

function Renderer:progress()
    return self.totalPixels == 0 and 1 or self.completedPixels / self.totalPixels
end

function Renderer:getStats()
    return {
        width = self.width,
        height = self.height,
        samplesPerPixel = self.samplesPerPixel,
        tileSize = self.tileSize,
        tileWidth = self.tileWidth,
        tileHeight = self.tileHeight,
        totalTiles = self.totalTiles,
        completedTiles = self.completedTiles,
        totalPixels = self.totalPixels,
        completedPixels = self.completedPixels,
        totalSamples = self.totalSamples,
        totalRays = self.totalRays,
        progress = self:progress(),
        complete = self.complete,
        cancelled = self.cancelled,
    }
end

function Renderer:renderPixel(pixelIndex)
    local x = pixelIndex % self.width
    local y = math.floor(pixelIndex / self.width)
    local accumulated = Vec3.new(0, 0, 0)

    for sample = 1, self.samplesPerPixel do
        local rng = RNG.new(deriveSampleSeed(self.seed, pixelIndex, sample))
        local ray = self.camera:getRay(x, y, rng)
        accumulated = accumulated + self.integrator:trace(ray, self.scene, rng)
        self.totalSamples = self.totalSamples + 1
        self.totalRays = self.totalRays + 1
    end

    self.film:set(x, y, accumulated / self.samplesPerPixel)
end

function Renderer:step(tileBudget)
    if self.complete or self.cancelled then
        return 0
    end

    local budget = math.max(1, math.floor(tileBudget or 1))
    local processedTiles = 0

    if not self.started then
        self.started = true
        if self.presenter and self.presenter.onStart then
            self.presenter:onStart(self.width, self.height, self)
        end
    end

    while processedTiles < budget and self.nextTile <= self.totalTiles and not self.cancelled do
        local tile = self.tiles[self.nextTile]
        local firstPixel = tile.y * self.width + tile.x

        for row = 0, tile.height - 1 do
            for column = 0, tile.width - 1 do
                self:renderPixel(firstPixel + row * self.width + column)
                self.completedPixels = self.completedPixels + 1
                self.nextPixel = self.nextPixel + 1
            end
        end

        self.nextTile = self.nextTile + 1
        self.completedTiles = self.completedTiles + 1
        processedTiles = processedTiles + 1

        if self.presenter and self.presenter.onTile then
            self.presenter:onTile(tile.x, tile.y, tile.width, tile.height, self.film, self)
        end
    end

    if self.nextTile > self.totalTiles and not self.cancelled then
        self.complete = true
    end

    if self.presenter and self.presenter.onProgress then
        self.presenter:onProgress(self.completedPixels, self.totalPixels, self)
    end
    if self.complete and not self.reportedComplete and self.presenter and self.presenter.onComplete then
        self.reportedComplete = true
        self.presenter:onComplete(self.film, self)
    end

    return processedTiles
end

function Renderer:render()
    while not self.complete and not self.cancelled do
        self:step(1)
    end
    return self.film
end

return Renderer
