local AsciiPresenter = {}
AsciiPresenter.__index = AsciiPresenter

function AsciiPresenter.new(sink)
    return setmetatable({ sink = sink or print, lines = {} }, AsciiPresenter)
end

function AsciiPresenter:onStart(width, height)
    self.width = width
    self.height = height
    self.lines = {}
end

function AsciiPresenter:onComplete(film)
    local ramp = " .:-=+*#%@"
    for y = 0, film.height - 1 do
        local line = {}
        for x = 0, film.width - 1 do
            local r, g, b = film:get(x, y)
            local luminance = math.max(0, math.min(1, 0.2126 * r + 0.7152 * g + 0.0722 * b))
            local index = math.floor(luminance * (#ramp - 1)) + 1
            line[#line + 1] = ramp:sub(index, index)
        end
        self.lines[#self.lines + 1] = table.concat(line)
    end
    self.sink(table.concat(self.lines, "\n"))
end

return AsciiPresenter
