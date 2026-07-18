local Film = {}
Film.__index = Film

local function luminance(r, g, b)
    return r * 0.2126 + g * 0.7152 + b * 0.0722
end

function Film.new(width, height)
    assert(width >= 1 and height >= 1, "Film dimensions must be positive")
    local pixels = {}
    local sampleCounts = {}
    local luminanceMean = {}
    local luminanceM2 = {}
    for i = 1, width * height do
        pixels[i] = { r = 0, g = 0, b = 0 }
        sampleCounts[i] = 0
        luminanceMean[i] = 0
        luminanceM2[i] = 0
    end
    return setmetatable({
        width = width,
        height = height,
        pixels = pixels,
        sampleCounts = sampleCounts,
        luminanceMean = luminanceMean,
        luminanceM2 = luminanceM2,
    }, Film)
end

function Film:clear()
    for i = 1, #self.pixels do
        self.pixels[i] = { r = 0, g = 0, b = 0 }
        self.sampleCounts[i] = 0
        self.luminanceMean[i] = 0
        self.luminanceM2[i] = 0
    end
end

function Film:index(x, y)
    return y * self.width + x + 1
end

function Film:set(x, y, color)
    local index = self:index(x, y)
    self.pixels[index] = { r = color.x, g = color.y, b = color.z }
    self.sampleCounts[index] = 1
    self.luminanceMean[index] = luminance(color.x, color.y, color.z)
    self.luminanceM2[index] = 0
end

function Film:addSample(x, y, color)
    local index = self:index(x, y)
    local pixel = self.pixels[index]
    local previousCount = self.sampleCounts[index]
    local count = previousCount + 1
    local weight = 1 / count
    pixel.r = pixel.r + (color.x - pixel.r) * weight
    pixel.g = pixel.g + (color.y - pixel.g) * weight
    pixel.b = pixel.b + (color.z - pixel.b) * weight

    local sampleLuminance = luminance(color.x, color.y, color.z)
    local previousMean = self.luminanceMean[index]
    local delta = sampleLuminance - previousMean
    local mean = previousMean + delta * weight
    self.luminanceMean[index] = mean
    self.luminanceM2[index] = self.luminanceM2[index]
        + delta * (sampleLuminance - mean)
    self.sampleCounts[index] = count
end

function Film:getSampleCount(x, y)
    return self.sampleCounts[self:index(x, y)]
end

function Film:getLuminanceMoments(x, y)
    local index = self:index(x, y)
    local count = self.sampleCounts[index]
    local mean = self.luminanceMean[index]
    local variance = count > 1 and self.luminanceM2[index] / (count - 1) or 0
    return mean, math.max(0, variance), count
end

function Film:getMeanLuminanceVariance(x, y)
    local mean, variance, count = self:getLuminanceMoments(x, y)
    return mean, count > 0 and variance / count or 0
end

function Film:get(x, y)
    local pixel = self.pixels[self:index(x, y)]
    return pixel.r, pixel.g, pixel.b
end

function Film:forEachPixel(callback)
    for y = 0, self.height - 1 do
        for x = 0, self.width - 1 do
            local r, g, b = self:get(x, y)
            callback(x, y, r, g, b)
        end
    end
end

return Film
