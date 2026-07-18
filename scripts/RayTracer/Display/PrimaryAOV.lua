local Vec3 = require "RayTracer.Math.Vec3"

local PrimaryAOV = {}
PrimaryAOV.__index = PrimaryAOV

local function zeroVector()
    return Vec3.new(0, 0, 0)
end

function PrimaryAOV.new(width, height)
    local size = width * height
    local albedo = {}
    local normal = {}
    local depth = {}
    local hit = {}
    for index = 1, size do
        albedo[index] = zeroVector()
        normal[index] = zeroVector()
        depth[index] = 0
        hit[index] = false
    end
    return setmetatable({
        width = width,
        height = height,
        albedo = albedo,
        normal = normal,
        depth = depth,
        hit = hit,
    }, PrimaryAOV)
end

function PrimaryAOV:index(x, y)
    return y * self.width + x + 1
end

function PrimaryAOV:clear()
    for index = 1, #self.hit do
        self.albedo[index] = zeroVector()
        self.normal[index] = zeroVector()
        self.depth[index] = 0
        self.hit[index] = false
    end
end

function PrimaryAOV:set(x, y, sample)
    local index = self:index(x, y)
    if sample == nil or sample.hit ~= true then
        self.hit[index] = false
        return
    end
    self.hit[index] = true
    self.albedo[index] = sample.albedo or zeroVector()
    self.normal[index] = sample.normal or zeroVector()
    self.depth[index] = sample.depth or 0
end

function PrimaryAOV:get(x, y)
    local index = self:index(x, y)
    return self.hit[index], self.albedo[index], self.normal[index], self.depth[index]
end

function PrimaryAOV:getHit(x, y)
    return self.hit[self:index(x, y)]
end

return PrimaryAOV
