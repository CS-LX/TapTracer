local Ray = {}
Ray.__index = Ray

function Ray.new(origin, direction)
    return setmetatable({ origin = origin, direction = direction }, Ray)
end

function Ray:at(t)
    return self.origin + self.direction * t
end

return Ray
