local Vec3 = require "RayTracer.Math.Vec3"

local Material = {}
Material.__index = Material

function Material.new()
    return setmetatable({}, Material)
end

function Material:denoiseClass(_)
    return "unknown"
end

function Material:albedoAt(_)
    return Vec3.new(1, 1, 1)
end

function Material:isDelta()
    return false
end

function Material:sample(ray, record, rng)
    return self:scatter(ray, record, rng)
end

function Material:evaluate(_, _, _)
    return Vec3.new(0, 0, 0)
end

function Material:pdf(_, _, _)
    return 0
end

function Material:scatter(ray, record, rng)
    return nil, nil
end

return Material
