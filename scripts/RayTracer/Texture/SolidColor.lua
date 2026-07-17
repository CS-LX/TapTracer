local SolidColor = {}
SolidColor.__index = SolidColor

function SolidColor.new(color)
    assert(color ~= nil, "SolidColor requires a color")
    return setmetatable({ color = color }, SolidColor)
end

function SolidColor:value(_)
    return self.color
end

return SolidColor
