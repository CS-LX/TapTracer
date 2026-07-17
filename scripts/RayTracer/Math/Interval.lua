local Interval = {}
Interval.__index = Interval

function Interval.new(minimum, maximum)
    return setmetatable({ min = minimum, max = maximum }, Interval)
end

function Interval:contains(value)
    return self.min <= value and value <= self.max
end

function Interval:surrounds(value)
    return self.min < value and value < self.max
end

function Interval:size()
    return self.max - self.min
end

function Interval:clamp(value)
    if value < self.min then
        return self.min
    end
    if value > self.max then
        return self.max
    end
    return value
end

Interval.EMPTY = Interval.new(math.huge, -math.huge)
Interval.UNIVERSE = Interval.new(-math.huge, math.huge)

return Interval
