local Vec3 = require "RayTracer.Math.Vec3"

local DiffuseLight = {}
DiffuseLight.__index = DiffuseLight

function DiffuseLight.new(emitTexture, intensity)
    assert(emitTexture ~= nil, "DiffuseLight requires an emission texture")
    return setmetatable({
        emitTexture = emitTexture,
        intensity = intensity or 1.0,
        isLight = true,
    }, DiffuseLight)
end

function DiffuseLight:emitted(record)
    if record.frontFace == false then
        return Vec3.new(0, 0, 0)
    end
    local color = self.emitTexture:value(record)
    return color * self.intensity
end

function DiffuseLight:scatter(_, record)
    return nil, nil
end

return DiffuseLight
