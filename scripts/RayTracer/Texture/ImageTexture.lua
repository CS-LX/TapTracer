local Vec3 = require "RayTracer.Math.Vec3"

local ImageTexture = {}
ImageTexture.__index = ImageTexture

local function clamp01(value)
    return math.max(0, math.min(1, value))
end

local function parsePPM(text)
    assert(type(text) == "string", "ImageTexture PPM source must be a string")
    local tokens = {}
    for line in text:gmatch("[^\n\r]*") do
        local content = line:gsub("#.*", "")
        for token in content:gmatch("%S+") do
            tokens[#tokens + 1] = token
        end
    end

    assert(tokens[1] == "P3", "ImageTexture supports ASCII P3 PPM only")
    local width = tonumber(tokens[2])
    local height = tonumber(tokens[3])
    local maxValue = tonumber(tokens[4])
    assert(width and height and maxValue and width >= 1 and height >= 1 and maxValue > 0,
        "ImageTexture PPM header is invalid")

    local pixels = {}
    local tokenIndex = 5
    for index = 1, width * height do
        local red = tonumber(tokens[tokenIndex])
        local green = tonumber(tokens[tokenIndex + 1])
        local blue = tonumber(tokens[tokenIndex + 2])
        assert(red and green and blue, "ImageTexture PPM pixel data is incomplete")
        pixels[index] = Vec3.new(
            clamp01(red / maxValue),
            clamp01(green / maxValue),
            clamp01(blue / maxValue)
        )
        tokenIndex = tokenIndex + 3
    end

    return width, height, pixels
end

function ImageTexture.new(width, height, pixels)
    assert(width >= 1 and height >= 1, "ImageTexture dimensions must be positive")
    assert(type(pixels) == "table" and #pixels == width * height,
        "ImageTexture pixels must match dimensions")
    return setmetatable({
        width = width,
        height = height,
        pixels = pixels,
    }, ImageTexture)
end

function ImageTexture.fromPPM(text)
    local width, height, pixels = parsePPM(text)
    return ImageTexture.new(width, height, pixels)
end

function ImageTexture:value(record)
    local u = clamp01(record.u or 0)
    local v = 1 - clamp01(record.v or 0)
    local x = math.min(self.width - 1, math.floor(u * self.width))
    local y = math.min(self.height - 1, math.floor(v * self.height))
    return self.pixels[y * self.width + x + 1]
end

return ImageTexture
