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

function DiffuseLight:denoiseClass(_)
    return "emission"
end

function DiffuseLight:albedoAt(record)
    return self.emitTexture:value(record)
end

function DiffuseLight:emitted(record)
    if record.frontFace == false then
        return Vec3.new(0, 0, 0)
    end
    local color = self.emitTexture:value(record)
    return color * self.intensity
end

function DiffuseLight:isDelta()
    return false
end

function DiffuseLight:sample(_, _, _)
    return nil, nil, false, nil, 0
end

function DiffuseLight:evaluate(_, _, _)
    return Vec3.new(0, 0, 0)
end

function DiffuseLight:pdf(_, _, _)
    return 0
end

function DiffuseLight:scatter(_, record)
    return nil, nil
end

return DiffuseLight
