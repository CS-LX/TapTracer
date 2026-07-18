local Vec3 = require "RayTracer.Math.Vec3"

local PrimaryAOV = {}
PrimaryAOV.__index = PrimaryAOV

local function zeroVector()
    return Vec3.new(0, 0, 0)
end

function PrimaryAOV.new(width, height)
    local size = width * height
    local albedo = {}
    local normalSum = {}
    local normal = {}
    local normalDirty = {}
    local depth = {}
    local sampleCount = {}
    local hitCount = {}
    local denoiseClass = {}
    for index = 1, size do
        albedo[index] = zeroVector()
        normalSum[index] = zeroVector()
        normal[index] = zeroVector()
        normalDirty[index] = false
        depth[index] = 0
        sampleCount[index] = 0
        hitCount[index] = 0
        denoiseClass[index] = "miss"
    end
    return setmetatable({
        width = width,
        height = height,
        albedo = albedo,
        normalSum = normalSum,
        normal = normal,
        normalDirty = normalDirty,
        depth = depth,
        sampleCount = sampleCount,
        hitCount = hitCount,
        denoiseClass = denoiseClass,
    }, PrimaryAOV)
end

function PrimaryAOV:index(x, y)
    return y * self.width + x + 1
end

function PrimaryAOV:clear()
    for index = 1, #self.hitCount do
        self.albedo[index] = zeroVector()
        self.normalSum[index] = zeroVector()
        self.normal[index] = zeroVector()
        self.normalDirty[index] = false
        self.depth[index] = 0
        self.sampleCount[index] = 0
        self.hitCount[index] = 0
        self.denoiseClass[index] = "miss"
    end
end

function PrimaryAOV:set(x, y, sample)
    local index = self:index(x, y)
    self.sampleCount[index] = self.sampleCount[index] + 1
    if sample == nil or sample.hit ~= true then
        return
    end

    local hits = self.hitCount[index] + 1
    local inverseHits = 1 / hits
    local sampleClass = sample.class or "unknown"
    if hits == 1 then
        self.denoiseClass[index] = sampleClass
    elseif self.denoiseClass[index] ~= sampleClass then
        self.denoiseClass[index] = "mixed"
    end

    local albedo = sample.albedo or zeroVector()
    local albedoAverage = self.albedo[index]
    albedoAverage.x = albedoAverage.x + (albedo.x - albedoAverage.x) * inverseHits
    albedoAverage.y = albedoAverage.y + (albedo.y - albedoAverage.y) * inverseHits
    albedoAverage.z = albedoAverage.z + (albedo.z - albedoAverage.z) * inverseHits

    local normal = sample.normal or zeroVector()
    local normalSum = self.normalSum[index]
    normalSum.x = normalSum.x + normal.x
    normalSum.y = normalSum.y + normal.y
    normalSum.z = normalSum.z + normal.z
    self.normalDirty[index] = true

    local depth = sample.depth or 0
    self.depth[index] = self.depth[index] + (depth - self.depth[index]) * inverseHits
    self.hitCount[index] = hits
end

function PrimaryAOV:get(x, y)
    local index = self:index(x, y)
    local hits = self.hitCount[index]
    if hits == 0 then
        return false, self.albedo[index], self.normal[index], 0, 0
    end

    if self.normalDirty[index] then
        local sum = self.normalSum[index]
        local resolved = self.normal[index]
        local lengthSquared = sum.x * sum.x + sum.y * sum.y + sum.z * sum.z
        if lengthSquared > 1e-16 then
            local inverseLength = 1 / math.sqrt(lengthSquared)
            resolved.x = sum.x * inverseLength
            resolved.y = sum.y * inverseLength
            resolved.z = sum.z * inverseLength
        else
            resolved.x = 0
            resolved.y = 0
            resolved.z = 0
        end
        self.normalDirty[index] = false
    end

    local samples = self.sampleCount[index]
    local coverage = samples > 0 and hits / samples or 0
    return true, self.albedo[index], self.normal[index], self.depth[index], coverage
end

function PrimaryAOV:getDenoiseClass(x, y)
    return self.denoiseClass[self:index(x, y)]
end

function PrimaryAOV:getHit(x, y)
    return self.hitCount[self:index(x, y)] > 0
end

function PrimaryAOV:getSampleCount(x, y)
    return self.sampleCount[self:index(x, y)]
end

function PrimaryAOV:getHitCount(x, y)
    return self.hitCount[self:index(x, y)]
end

function PrimaryAOV:getCoverage(x, y)
    local index = self:index(x, y)
    local samples = self.sampleCount[index]
    return samples > 0 and self.hitCount[index] / samples or 0
end

return PrimaryAOV
