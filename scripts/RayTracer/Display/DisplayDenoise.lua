local DisplayDenoise = {}

local OFFSETS = {
    { -1, -1, 0.50 }, { 0, -1, 0.75 }, { 1, -1, 0.50 },
    { -1, 0, 0.75 }, { 0, 0, 1.00 }, { 1, 0, 0.75 },
    { -1, 1, 0.50 }, { 0, 1, 0.75 }, { 1, 1, 0.50 },
}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function luminance(r, g, b)
    return r * 0.2126 + g * 0.7152 + b * 0.0722
end

function DisplayDenoise.filterPixel(film, x, y, width, height)
    local centerR, centerG, centerB = film:get(x, y)
    local centerLuminance = luminance(centerR, centerG, centerB)
    local red = 0
    local green = 0
    local blue = 0
    local totalWeight = 0

    for index = 1, #OFFSETS do
        local offset = OFFSETS[index]
        local sampleX = x + offset[1]
        local sampleY = y + offset[2]
        if sampleX >= 0 and sampleX < width and sampleY >= 0 and sampleY < height then
            local sampleCount = film.getSampleCount and film:getSampleCount(sampleX, sampleY) or 1
            if sampleCount > 0 then
                local sampleR, sampleG, sampleB = film:get(sampleX, sampleY)
                local sampleLuminance = luminance(sampleR, sampleG, sampleB)
                local luminanceDifference = math.abs(sampleLuminance - centerLuminance)
                local colorDifference = math.abs(sampleR - centerR)
                    + math.abs(sampleG - centerG)
                    + math.abs(sampleB - centerB)
                local edgeWeight = 1 / (1 + luminanceDifference * 10 + colorDifference * 16)
                local weight = offset[3] * edgeWeight

                red = red + sampleR * weight
                green = green + sampleG * weight
                blue = blue + sampleB * weight
                totalWeight = totalWeight + weight
            end
        end
    end

    if totalWeight <= 0 then
        return centerR, centerG, centerB
    end

    return clamp(red / totalWeight, 0, math.huge),
        clamp(green / totalWeight, 0, math.huge),
        clamp(blue / totalWeight, 0, math.huge)
end

return DisplayDenoise
