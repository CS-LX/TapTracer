local RNG = {}
RNG.__index = RNG

local UINT32 = 4294967296
local MULTIPLIER = 1664525
local INCREMENT = 1013904223

function RNG.new(seed)
    local normalized = math.floor(seed or 1) % UINT32
    if normalized == 0 then
        normalized = 1
    end
    return setmetatable({ state = normalized }, RNG)
end

function RNG:nextUint32()
    self.state = (MULTIPLIER * self.state + INCREMENT) % UINT32
    return self.state
end

function RNG:nextFloat()
    return self:nextUint32() / UINT32
end

function RNG:range(minimum, maximum)
    return minimum + (maximum - minimum) * self:nextFloat()
end

return RNG
