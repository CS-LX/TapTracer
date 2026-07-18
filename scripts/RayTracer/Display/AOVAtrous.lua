local AOVAtrous = {}

local KERNEL = {
    { -1, -1, 1 }, { 0, -1, 2 }, { 1, -1, 1 },
    { -1, 0, 2 }, { 0, 0, 4 }, { 1, 0, 2 },
    { -1, 1, 1 }, { 0, 1, 2 }, { 1, 1, 1 },
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function luminance(r, g, b)
    return r * 0.2126 + g * 0.7152 + b * 0.0722
end

local function pixelIndex(width, x, y)
    return y * width + x + 1
end

local function copyFilm(film)
    local buffer = {}
    for y = 0, film.height - 1 do
        for x = 0, film.width - 1 do
            local r, g, b = film:get(x, y)
            buffer[pixelIndex(film.width, x, y)] = { r = r, g = g, b = b }
        end
    end
    return buffer
end

local function sampleBuffer(buffer, width, x, y)
    local pixel = buffer[pixelIndex(width, x, y)]
    return pixel.r, pixel.g, pixel.b
end

local function guidedWeight(center, sample, centerAlbedo, sampleAlbedo,
        centerNormal, sampleNormal, centerDepth, sampleDepth, spatialWeight)
    local centerLuminance = luminance(center.r, center.g, center.b)
    local sampleLuminance = luminance(sample.r, sample.g, sample.b)
    local colorDifference = math.abs(center.r - sample.r)
        + math.abs(center.g - sample.g)
        + math.abs(center.b - sample.b)
    local albedoDifference = math.abs(centerAlbedo.x - sampleAlbedo.x)
        + math.abs(centerAlbedo.y - sampleAlbedo.y)
        + math.abs(centerAlbedo.z - sampleAlbedo.z)
    local normalCosine = centerNormal.x * sampleNormal.x
        + centerNormal.y * sampleNormal.y
        + centerNormal.z * sampleNormal.z
    local normalWeight = clamp((normalCosine - 0.55) / 0.4, 0, 1)
    local relativeDepth = math.abs(centerDepth - sampleDepth)
        / math.max(0.001, math.abs(centerDepth))
    local depthWeight = 1 / (1 + relativeDepth * 12)
    local colorWeight = 1 / (1 + colorDifference * 5 + math.abs(centerLuminance - sampleLuminance) * 8)
    local albedoWeight = 1 / (1 + albedoDifference * 8)
    return spatialWeight * colorWeight * albedoWeight
        * (0.15 + 0.85 * normalWeight) * depthWeight
end

function AOVAtrous.filter(film, aov, iterations)
    local width = film.width
    local height = film.height
    local source = copyFilm(film)
    local passes = math.max(1, math.floor(iterations or 2))

    for pass = 1, passes do
        local step = 2 ^ (pass - 1)
        local target = {}
        for y = 0, height - 1 do
            for x = 0, width - 1 do
                local centerIndex = pixelIndex(width, x, y)
                local center = source[centerIndex]
                local centerHit, centerAlbedo, centerNormal, centerDepth = aov:get(x, y)
                if not centerHit then
                    target[centerIndex] = center
                else
                    local red = 0
                    local green = 0
                    local blue = 0
                    local totalWeight = 0
                    for index = 1, #KERNEL do
                        local kernel = KERNEL[index]
                        local sampleX = x + kernel[1] * step
                        local sampleY = y + kernel[2] * step
                        if sampleX >= 0 and sampleX < width
                                and sampleY >= 0 and sampleY < height then
                            local sampleIndex = pixelIndex(width, sampleX, sampleY)
                            local sampleHit, sampleAlbedo, sampleNormal, sampleDepth = aov:get(sampleX, sampleY)
                            if sampleHit then
                                local sample = source[sampleIndex]
                                local weight = guidedWeight(
                                    center,
                                    sample,
                                    centerAlbedo,
                                    sampleAlbedo,
                                    centerNormal,
                                    sampleNormal,
                                    centerDepth,
                                    sampleDepth,
                                    kernel[3]
                                )
                                red = red + sample.r * weight
                                green = green + sample.g * weight
                                blue = blue + sample.b * weight
                                totalWeight = totalWeight + weight
                            end
                        end
                    end
                    if totalWeight > 0 then
                        target[centerIndex] = {
                            r = clamp(red / totalWeight, 0, math.huge),
                            g = clamp(green / totalWeight, 0, math.huge),
                            b = clamp(blue / totalWeight, 0, math.huge),
                        }
                    else
                        target[centerIndex] = center
                    end
                end
            end
        end
        source = target
    end

    return {
        width = width,
        height = height,
        pixels = source,
        get = function(self, x, y)
            local pixel = self.pixels[pixelIndex(self.width, x, y)]
            return pixel.r, pixel.g, pixel.b
        end,
    }
end

return AOVAtrous
