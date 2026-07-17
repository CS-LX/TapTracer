local Vec3 = require "RayTracer.Math.Vec3"

local RussianRoulette = {}
RussianRoulette.__index = RussianRoulette

function RussianRoulette.new(options)
    options = options or {}
    local minimumDepth = options.minimumDepth or 3
    local survivalProbability = options.survivalProbability or 0.8
    assert(minimumDepth >= 1, "RussianRoulette minimumDepth must be positive")
    assert(survivalProbability > 0 and survivalProbability <= 1, "RussianRoulette survivalProbability must be in (0, 1]")
    return setmetatable({
        minimumDepth = minimumDepth,
        survivalProbability = survivalProbability,
    }, RussianRoulette)
end

function RussianRoulette:continuePath(depth, attenuation, rng)
    if depth < self.minimumDepth then
        return attenuation, true
    end
    if rng:nextFloat() <= self.survivalProbability then
        return attenuation / self.survivalProbability, true
    end
    return Vec3.new(0, 0, 0), false
end

return RussianRoulette
