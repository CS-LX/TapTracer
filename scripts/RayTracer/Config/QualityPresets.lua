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
    },
    ["quality-square"] = {
        width = 256,
        height = 256,
        samplesPerPixel = 64,
        progressiveChunkWidth = 64,
        progressiveChunkHeight = 4,
        maxTilesPerStep = 1,
    },
    offline = {
        width = 512,
        height = 512,
        samplesPerPixel = 64,
        progressiveChunkWidth = 64,
        progressiveChunkHeight = 4,
        maxTilesPerStep = 1,
    },
}

function QualityPresets.get(name)
    local preset = PRESETS[name]
    assert(preset ~= nil, "Unknown quality preset: " .. tostring(name))
    return preset
end

return QualityPresets
