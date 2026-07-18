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

function Material:scatter(ray, record, rng)
    return nil, nil
end

return Material
