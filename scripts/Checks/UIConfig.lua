local QualityPresets = require "RayTracer.Config.QualityPresets"
local RenderController = require "RayTracer.Runtime.RenderController"

local REQUIRED_FIELDS = {
    "quality",
    "width",
    "height",
    "samplesPerPixel",
    "maxDepth",
    "progressiveChunkWidth",
    "progressiveChunkHeight",
    "maxTilesPerStep",
    "seed",
    "exposure",
    "useMIS",
    "denoise",
    "transmissionDenoise",
    "denoiseIterations",
    "denoiseKernel",
}

local function validatePreset(name)
    local preset = QualityPresets.get(name)
    for i = 1, #REQUIRED_FIELDS do
        local key = REQUIRED_FIELDS[i]
        assert(preset[key] ~= nil, name .. " missing field " .. key)
    end
    return preset
end

local function runChecks()
    local preview = validatePreset("preview")
    validatePreset("quality-square")
    validatePreset("offline")

    preview.width = 999
    assert(QualityPresets.get("preview").width == 256,
        "preset callers must receive independent copies")

    local createCount = 0
    local controller = RenderController.new {
        config = { marker = 1 },
        createRenderer = function(config)
            createCount = createCount + 1
            return {
                marker = config.marker,
                isComplete = function() return false end,
                isCancelled = function() return false end,
                cancel = function() end,
            }
        end,
    }
    assert(controller:start(), "controller starts")
    assert(controller:getRenderer().marker == 1, "initial config used")
    controller:configure({ marker = 2 })
    assert(controller:getRenderer() == nil, "configure discards stale renderer")
    assert(controller:start(), "controller restarts after configure")
    assert(controller:getRenderer().marker == 2, "updated config used")
    assert(createCount == 2, "renderer recreated once per start")
end

function Start()
    local ok, errorMessage = pcall(runChecks)
    if ok then
        print("[UIConfigCheck] passed")
    else
        log:Write(LOG_ERROR, "[UIConfigCheck] " .. tostring(errorMessage))
    end
    engine:Exit()
end
