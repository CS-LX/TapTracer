local QualityPresets = {}

local PRESETS = {
    preview = {
        width = 256,
        height = 144,
        samplesPerPixel = 32,
        maxDepth = 6,
        progressiveChunkWidth = 64,
        progressiveChunkHeight = 4,
        maxTilesPerStep = 1,
        seed = 42,
        exposure = 1.0,
        useMIS = true,
        denoise = true,
        transmissionDenoise = true,
        denoiseIterations = 3,
        denoiseKernel = "3x3",
    },
    ["quality-square"] = {
        width = 256,
        height = 256,
        samplesPerPixel = 64,
        maxDepth = 6,
        progressiveChunkWidth = 64,
        progressiveChunkHeight = 4,
        maxTilesPerStep = 1,
        seed = 42,
        exposure = 1.0,
        useMIS = true,
        denoise = true,
        transmissionDenoise = true,
        denoiseIterations = 3,
        denoiseKernel = "3x3",
    },
    offline = {
        width = 512,
        height = 512,
        samplesPerPixel = 64,
        maxDepth = 8,
        progressiveChunkWidth = 64,
        progressiveChunkHeight = 4,
        maxTilesPerStep = 1,
        seed = 42,
        exposure = 1.0,
        useMIS = true,
        denoise = true,
        transmissionDenoise = true,
        denoiseIterations = 3,
        denoiseKernel = "5x5",
    },
}

local function copy(source)
    local result = {}
    for key, value in pairs(source) do
        result[key] = value
    end
    return result
end

function QualityPresets.get(name)
    local preset = PRESETS[name]
    assert(preset ~= nil, "Unknown quality preset: " .. tostring(name))
    local result = copy(preset)
    result.quality = name
    return result
end

return QualityPresets
