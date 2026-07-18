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
---@field completedPasses number
---@field currentPass number
---@field completedPassPixels number
---@field completedSamplePixels number
---@field totalSamplePixels number
---@field seed number
---@field presenter table|nil
---@field timeProvider function|nil
---@field renderStartTime number
---@field renderEndTime number
---@field elapsedSeconds number
---@field lastStepSeconds number
---@field pixelsPerSecond number
---@field samplesPerSecond number
---@field pathsPerSecond number
---@field nextPixel number
---@field totalPixels number
---@field completedPixels number
---@field totalSamples number
---@field totalRays number
---@field lastTile table|nil
---@field complete boolean
---@field cancelled boolean
---@field started boolean
---@field reportedComplete boolean
local Renderer = {}
Renderer.__index = Renderer

local Vec3 = require "RayTracer.Math.Vec3"
local Film = require "RayTracer.Core.Film"
local Interval = require "RayTracer.Math.Interval"
local PrimaryAOV = require "RayTracer.Display.PrimaryAOV"
local RNG = require "RayTracer.Math.RNG"

local function deriveSampleSeed(baseSeed, pixelIndex, sampleIndex)
    local value = (baseSeed
        ~ (pixelIndex * 0x9E3779B9)
        ~ (sampleIndex * 0x85EBCA6B)) & 0xFFFFFFFF
    value = ((value ~ (value >> 16)) * 0x7FEB352D) & 0xFFFFFFFF
    value = ((value ~ (value >> 15)) * 0x846CA68B) & 0xFFFFFFFF
    return (value ~ (value >> 16)) & 0xFFFFFFFF
end

local function updatePerformanceStats(renderer, computeSeconds, endTime)
    renderer.lastStepSeconds = math.max(0, computeSeconds)
    renderer.elapsedSeconds = renderer.elapsedSeconds + renderer.lastStepSeconds

    if renderer.complete and renderer.renderEndTime == 0 then
        renderer.renderEndTime = endTime
    end

    if renderer.elapsedSeconds > 0 then
        renderer.pixelsPerSecond = renderer.completedSamplePixels / renderer.elapsedSeconds
        renderer.samplesPerSecond = renderer.totalSamples / renderer.elapsedSeconds
        local pathCount = renderer.totalSamples
        if renderer.integrator.getStats then
            local integratorStats = renderer.integrator:getStats()
            if integratorStats and integratorStats.pathCount then
                pathCount = integratorStats.pathCount
            end
        end
        renderer.pathsPerSecond = pathCount / renderer.elapsedSeconds
    end
end

function Renderer.new(options)
    options = options or {}
    assert(options.camera ~= nil, "Renderer requires a camera")
    assert(options.scene ~= nil, "Renderer requires a scene")
    assert(options.integrator ~= nil, "Renderer requires an integrator")

    local width = options.width or options.camera.imageWidth
    local height = options.height or options.camera.imageHeight
    local samplesPerPixel = math.max(1, math.floor(options.samplesPerPixel or 1))
    local tileSize = options.tileSize or 8
    local tileWidth = options.tileWidth or tileSize
    local tileHeight = options.tileHeight or tileSize
    local presenter = options.presenter
    local timeProvider = options.timeProvider or function()
        return 0
    end
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
        aov = options.aov or PrimaryAOV.new(width, height),
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
        completedPasses = 0,
        currentPass = 1,
        completedPassPixels = 0,
        completedSamplePixels = 0,
        totalSamplePixels = width * height * samplesPerPixel,
        seed = options.seed or 1,
        presenter = presenter,
        timeProvider = timeProvider,
        renderStartTime = 0,
        renderEndTime = 0,
        elapsedSeconds = 0,
        lastStepSeconds = 0,
        pixelsPerSecond = 0,
        samplesPerSecond = 0,
        pathsPerSecond = 0,
        nextPixel = 0,
        totalPixels = width * height,
        completedPixels = 0,
        totalSamples = 0,
        totalRays = 0,
        lastTile = nil,
        complete = false,
        cancelled = false,
        started = false,
        reportedComplete = false,
    }, Renderer)
end

function Renderer:reset()
    self.film:clear()
    self.aov:clear()
    self.nextTile = 1
    self.completedTiles = 0
    self.completedPasses = 0
    self.currentPass = 1
    self.completedPassPixels = 0
    self.completedSamplePixels = 0
    self.nextPixel = 0
    self.completedPixels = 0
    self.totalSamples = 0
    self.totalRays = 0
    self.lastTile = nil
    self.renderStartTime = 0
    self.renderEndTime = 0
    self.elapsedSeconds = 0
    self.lastStepSeconds = 0
    self.pixelsPerSecond = 0
    self.samplesPerSecond = 0
    self.pathsPerSecond = 0
    self.complete = false
    self.cancelled = false
    self.started = false
    self.reportedComplete = false
    if self.integrator.resetStats then
        self.integrator:resetStats()
    end
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
    if self.totalSamplePixels == 0 then
        return 1
    end
    return (self.completedPasses * self.totalPixels + self.completedPassPixels)
        / self.totalSamplePixels
end

function Renderer:getStats()
    local integratorStats = nil
    if self.integrator.getStats then
        integratorStats = self.integrator:getStats()
    end

    return {
        width = self.width,
        height = self.height,
        samplesPerPixel = self.samplesPerPixel,
        currentPass = self.currentPass,
        completedPasses = self.completedPasses,
        completedPassPixels = self.completedPassPixels,
        completedSamplePixels = self.completedSamplePixels,
        totalSamplePixels = self.totalSamplePixels,
        tileSize = self.tileSize,
        tileWidth = self.tileWidth,
        tileHeight = self.tileHeight,
        totalTiles = self.totalTiles,
        completedTiles = self.completedTiles,
        totalPixels = self.totalPixels,
        completedPixels = self.completedPixels,
        totalSamples = self.totalSamples,
        totalRays = self.totalRays,
        elapsedSeconds = self.elapsedSeconds,
        lastStepSeconds = self.lastStepSeconds,
        pixelsPerSecond = self.pixelsPerSecond,
        samplesPerSecond = self.samplesPerSecond,
        pathsPerSecond = self.pathsPerSecond,
        integrator = integratorStats,
        progress = self:progress(),
        complete = self.complete,
        cancelled = self.cancelled,
    }
end

local function getPrimaryDenoiseClass(material, record)
    if material ~= nil and type(material.denoiseClass) == "function" then
        return material:denoiseClass(record)
    end
    return "unknown"
end

local function getPrimaryAlbedo(material, record)
    if material ~= nil and type(material.albedoAt) == "function" then
        return material:albedoAt(record)
    end
    return Vec3.new(1, 1, 1)
end

function Renderer:renderPixel(pixelIndex, sampleIndex)
    local x = pixelIndex % self.width
    local y = math.floor(pixelIndex / self.width)
    local rng = RNG.new(deriveSampleSeed(self.seed, pixelIndex, sampleIndex))
    local ray = self.camera:getRay(x, y, rng)
    local color = self.integrator:trace(ray, self.scene, rng, function(primaryRecord)
        if primaryRecord ~= nil and primaryRecord.material ~= nil then
            self.aov:set(x, y, {
                hit = true,
                class = getPrimaryDenoiseClass(primaryRecord.material, primaryRecord),
                albedo = getPrimaryAlbedo(primaryRecord.material, primaryRecord),
                normal = primaryRecord.normal,
                depth = primaryRecord.t,
            })
        else
            self.aov:set(x, y, nil)
        end
    end)
    self.film:addSample(x, y, color)
    self.totalSamples = self.totalSamples + 1
    self.totalRays = self.totalRays + 1
end

function Renderer:step(tileBudget)
    if self.complete or self.cancelled then
        return 0
    end

    local stepStartTime = self.timeProvider()
    local budget = math.max(1, math.floor(tileBudget or 1))
    local processedTiles = 0
    self.lastTile = nil

    if not self.started then
        self.started = true
        self.renderStartTime = stepStartTime
        self.currentPass = 1
        if self.integrator.resetStats then
            self.integrator:resetStats()
        end
        if self.presenter and self.presenter.onStart then
            self.presenter:onStart(self.width, self.height, self)
        end
    end

    while processedTiles < budget and self.nextTile <= self.totalTiles and not self.cancelled do
        local tile = self.tiles[self.nextTile]
        local firstPixel = tile.y * self.width + tile.x

        for row = 0, tile.height - 1 do
            for column = 0, tile.width - 1 do
                self:renderPixel(firstPixel + row * self.width + column, self.currentPass)
                self.completedPassPixels = self.completedPassPixels + 1
                self.completedSamplePixels = self.completedSamplePixels + 1
            end
        end

        self.nextTile = self.nextTile + 1
        self.completedTiles = self.completedTiles + 1
        self.completedPixels = self.completedPassPixels
        self.nextPixel = self.completedPassPixels
        self.lastTile = tile
        processedTiles = processedTiles + 1

        if self.presenter and self.presenter.onTile then
            self.presenter:onTile(tile.x, tile.y, tile.width, tile.height, self.film, self)
        end

        if self.nextTile > self.totalTiles then
            self.completedPasses = self.completedPasses + 1
            if self.completedPasses >= self.samplesPerPixel then
                self.complete = true
                self.completedPixels = self.totalPixels
                self.completedPassPixels = 0
            else
                self.currentPass = self.completedPasses + 1
                self.nextTile = 1
                self.completedTiles = 0
                self.completedPassPixels = 0
                self.completedPixels = 0
                self.nextPixel = 0
            end
        end
    end

    local stepEndTime = self.timeProvider()
    updatePerformanceStats(self, stepEndTime - stepStartTime, stepEndTime)

    if self.presenter and self.presenter.onProgress then
        self.presenter:onProgress(
            self.completedPasses * self.totalPixels + self.completedPassPixels,
            self.totalSamplePixels,
            self
        )
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
