local AnsiPresenter = {}
AnsiPresenter.__index = AnsiPresenter

function AnsiPresenter.new(sink)
    return setmetatable({ sink = sink or print }, AnsiPresenter)
end

function AnsiPresenter:onStart(width, height)
    self.width = width
    self.height = height
end

function AnsiPresenter:onComplete(film)
    local lines = {}
    for y = 0, film.height - 1 do
        local line = {}
        for x = 0, film.width - 1 do
            local r, g, b = film:get(x, y)
            local red = math.floor(math.max(0, math.min(1, r)) * 255)
            local green = math.floor(math.max(0, math.min(1, g)) * 255)
            local blue = math.floor(math.max(0, math.min(1, b)) * 255)
            line[#line + 1] = string.format("\27[48;2;%d;%d;%dm ", red, green, blue)
        end
        line[#line + 1] = "\27[0m"
        lines[#lines + 1] = table.concat(line)
    end
    self.sink(table.concat(lines, "\n") .. "\27[0m")
end

return AnsiPresenter
