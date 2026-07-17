local function encode(value)
    local clamped = math.max(0, math.min(0.999, value))
    return math.floor(256 * math.sqrt(clamped))
end

local PPMWriter = {}
PPMWriter.__index = PPMWriter

function PPMWriter.new(sink)
    assert(type(sink) == "function", "PPMWriter requires a sink function")
    return setmetatable({ sink = sink }, PPMWriter)
end

function PPMWriter:onStart(width, height)
    self.sink(string.format("P3\n%d %d\n255\n", width, height))
end

function PPMWriter:onComplete(film)
    film:forEachPixel(function(_, _, r, g, b)
        self.sink(string.format("%d %d %d\n", encode(r), encode(g), encode(b)))
    end)
end

return PPMWriter
