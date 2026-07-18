local Vec3 = require "RayTracer.Math.Vec3"
local Ray = require "RayTracer.Math.Ray"

---@class Metal
---@field albedo table
---@field fuzz number
local Metal = {}
Metal.__index = Metal

local DELTA_THRESHOLD = 1e-6
local MIN_ALPHA = 1e-4

local function ggxAlpha(roughness)
    return math.max(MIN_ALPHA, roughness * roughness)
end

local function tangentFrame(normal)
    local seed = math.abs(normal.x) > 0.9
        and Vec3.new(0, 1, 0)
        or Vec3.new(1, 0, 0)
    local tangent = seed:cross(normal):unit()
    return tangent, normal:cross(tangent)
end

local function sampleGGXNormal(normal, alpha, rng)
    local u1 = rng:nextFloat()
    local u2 = rng:nextFloat()
    local phi = 2 * math.pi * u1
    local alphaSquared = alpha * alpha
    local cosine = math.sqrt(
        math.max(0, (1 - u2) / (1 + (alphaSquared - 1) * u2))
    )
    local sine = math.sqrt(math.max(0, 1 - cosine * cosine))
    local tangent, bitangent = tangentFrame(normal)
    return (
        tangent * (sine * math.cos(phi))
        + bitangent * (sine * math.sin(phi))
        + normal * cosine
    ):unit()
end

local function distributionGGX(normalCosine, alpha)
    if normalCosine <= 0 then
        return 0
    end
    local alphaSquared = alpha * alpha
    local denominator = normalCosine * normalCosine * (alphaSquared - 1) + 1
    return alphaSquared / (math.pi * denominator * denominator)
end

local function smithG1(normalCosine, alpha)
    if normalCosine <= 0 then
        return 0
    end
    local alphaSquared = alpha * alpha
    local root = math.sqrt(
        alphaSquared + (1 - alphaSquared) * normalCosine * normalCosine
    )
    return 2 * normalCosine / (normalCosine + root)
end

local function fresnelSchlick(cosine, f0)
    local factor = (1 - math.max(0, math.min(1, cosine))) ^ 5
    return f0 + (Vec3.new(1, 1, 1) - f0) * factor
end

function Metal.new(albedo, fuzz)
    return setmetatable({
        albedo = albedo,
        fuzz = math.max(0, math.min(1, fuzz or 0)),
    }, Metal)
end

function Metal:emitted(_)
    return Vec3.new(0, 0, 0)
end

function Metal:denoiseClass(_)
    if self:isDelta() then
        return "delta_reflection"
    end
    return "glossy"
end

function Metal:albedoAt(_)
    return self.albedo
end

function Metal:isDelta()
    return self.fuzz <= DELTA_THRESHOLD
end

function Metal:sample(ray, record, rng)
    local outgoing = -ray.direction:unit()
    if self:isDelta() then
        local direction = ray.direction:unit():reflect(record.normal)
        if direction:dot(record.normal) <= 0 then
            return nil, nil, true, "reflection", nil
        end
        return Ray.new(record.point, direction), self.albedo,
            true, "reflection", nil
    end

    local halfVector = sampleGGXNormal(
        record.normal,
        ggxAlpha(self.fuzz),
        rng
    )
    if outgoing:dot(halfVector) <= 0 then
        return nil, nil, false, nil, 0
    end

    local incoming = (-outgoing):reflect(halfVector):unit()
    local incomingCosine = record.normal:dot(incoming)
    if incomingCosine <= 0 then
        return nil, nil, false, nil, 0
    end

    local samplePdf = self:pdf(record, outgoing, incoming)
    if samplePdf <= 0 then
        return nil, nil, false, nil, 0
    end
    local bsdf = self:evaluate(record, outgoing, incoming)
    local throughput = bsdf * (incomingCosine / samplePdf)
    return Ray.new(record.point, incoming), throughput,
        false, nil, samplePdf
end

function Metal:evaluate(record, outgoingDirection, incomingDirection)
    if self:isDelta() then
        return Vec3.new(0, 0, 0)
    end

    local normal = record.normal
    local outgoing = outgoingDirection:unit()
    local incoming = incomingDirection:unit()
    local outgoingCosine = normal:dot(outgoing)
    local incomingCosine = normal:dot(incoming)
    if outgoingCosine <= 0 or incomingCosine <= 0 then
        return Vec3.new(0, 0, 0)
    end

    local halfVector = (outgoing + incoming):unit()
    if halfVector:nearZero() then
        return Vec3.new(0, 0, 0)
    end
    local normalHalf = math.max(0, normal:dot(halfVector))
    local outgoingHalf = math.max(0, outgoing:dot(halfVector))
    if normalHalf <= 0 or outgoingHalf <= 0 then
        return Vec3.new(0, 0, 0)
    end

    local alpha = ggxAlpha(self.fuzz)
    local distribution = distributionGGX(normalHalf, alpha)
    local geometry = smithG1(outgoingCosine, alpha)
        * smithG1(incomingCosine, alpha)
    local fresnel = fresnelSchlick(outgoingHalf, self.albedo)
    return fresnel * (
        distribution * geometry / (4 * outgoingCosine * incomingCosine)
    )
end

function Metal:pdf(record, outgoingDirection, incomingDirection)
    if self:isDelta() then
        return 0
    end

    local normal = record.normal
    local outgoing = outgoingDirection:unit()
    local incoming = incomingDirection:unit()
    if normal:dot(outgoing) <= 0 or normal:dot(incoming) <= 0 then
        return 0
    end

    local halfVector = (outgoing + incoming):unit()
    if halfVector:nearZero() then
        return 0
    end
    local normalHalf = math.max(0, normal:dot(halfVector))
    local outgoingHalf = math.abs(outgoing:dot(halfVector))
    if normalHalf <= 0 or outgoingHalf <= 1e-12 then
        return 0
    end

    local halfPdf = distributionGGX(
        normalHalf,
        ggxAlpha(self.fuzz)
    ) * normalHalf
    return halfPdf / (4 * outgoingHalf)
end

function Metal:scatter(ray, record, rng)
    local scattered, attenuation, isSpecular, event =
        self:sample(ray, record, rng)
    return scattered, attenuation, isSpecular, event
end

return Metal
