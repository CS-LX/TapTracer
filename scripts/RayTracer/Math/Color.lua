local Vec3 = require "RayTracer.Math.Vec3"
local Color = {}

function Color.new(r, g, b)
    return Vec3.new(r, g, b)
end

function Color.black()
    return Vec3.new(0, 0, 0)
end

function Color.white()
    return Vec3.new(1, 1, 1)
end

return Color
