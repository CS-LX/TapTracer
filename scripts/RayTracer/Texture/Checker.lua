local Checker = {}
Checker.__index = Checker

function Checker.new(scale, evenTexture, oddTexture)
    assert(scale > 0, "Checker scale must be positive")
    assert(evenTexture ~= nil and oddTexture ~= nil, "Checker requires two textures")
    return setmetatable({
        inverseScale = 1 / scale,
        evenTexture = evenTexture,
        oddTexture = oddTexture,
    }, Checker)
end

function Checker:value(record)
    local point = record.point
    local x = math.floor(point.x * self.inverseScale)
    local y = math.floor(point.y * self.inverseScale)
    local z = math.floor(point.z * self.inverseScale)
    local texture = (x + y + z) % 2 == 0 and self.evenTexture or self.oddTexture
    return texture:value(record)
end

return Checker
