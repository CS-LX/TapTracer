local Film = {}
Film.__index = Film

function Film.new(width, height)
    assert(width >= 1 and height >= 1, "Film dimensions must be positive")
    local pixels = {}
    for i = 1, width * height do
        pixels[i] = { r = 0, g = 0, b = 0 }
    end
    return setmetatable({ width = width, height = height, pixels = pixels }, Film)
end

function Film:clear()
    for i = 1, #self.pixels do
        self.pixels[i] = { r = 0, g = 0, b = 0 }
    end
end

function Film:index(x, y)
    return y * self.width + x + 1
end

function Film:set(x, y, color)
    self.pixels[self:index(x, y)] = { r = color.x, g = color.y, b = color.z }
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
