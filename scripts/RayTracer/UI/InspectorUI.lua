local InspectorUI = {}

local function numberText(value)
    return string.format("%.0f", value)
end

function InspectorUI.build(UI, options)
    local state = options.state
    local onConfigChanged = options.onConfigChanged
    local onStart = options.onStart
    local onStop = options.onStop

    local status = UI.Label {
        id = "inspector-status",
        text = "待机：请选择参数后点击开始",
        fontSize = 12,
        fontColor = { 190, 214, 232, 255 },
        height = 28,
    }

    local function setValue(key, value)
        state[key] = value
        onConfigChanged(state)
    end

    local function choosePreset(name)
        local preset = options.getPreset(name)
        for key, value in pairs(preset) do
            state[key] = value
        end
        state.quality = name
        onConfigChanged(state)
    end

    local presetButtons = UI.Panel {
        gap = 4,
        children = {
            UI.Button {
                text = "Preview",
                width = 96,
                height = 32,
                onClick = function()
                    choosePreset("preview")
                end,
            },
            UI.Button {
                text = "Square",
                width = 96,
                height = 32,
                onClick = function()
                    choosePreset("quality-square")
                end,
            },
            UI.Button {
                text = "Offline",
                width = 96,
                height = 32,
                onClick = function()
                    choosePreset("offline")
                end,
            },
        },
    }

    local settings = UI.Panel {
        gap = 4,
        children = {
            UI.Label { text = "分辨率", fontSize = 11, fontColor = { 170, 190, 210, 255 } },
            UI.Label {
                id = "inspector-resolution",
                text = numberText(state.width) .. " × " .. numberText(state.height),
                fontSize = 12,
                height = 24,
            },
            UI.Label { text = "采样轮数", fontSize = 11, fontColor = { 170, 190, 210, 255 } },
            UI.Slider {
                id = "inspector-spp",
                value = state.samplesPerPixel,
                min = 1,
                max = 128,
                step = 1,
                height = 24,
                onChange = function(_, value)
                    setValue("samplesPerPixel", math.floor(value + 0.5))
                end,
            },
            UI.Label { text = "最大路径深度", fontSize = 11, fontColor = { 170, 190, 210, 255 } },
            UI.Slider {
                id = "inspector-depth",
                value = state.maxDepth,
                min = 1,
                max = 16,
                step = 1,
                height = 24,
                onChange = function(_, value)
                    setValue("maxDepth", math.floor(value + 0.5))
                end,
            },
            UI.Label { text = "降噪", fontSize = 11, fontColor = { 170, 190, 210, 255 } },
            UI.Toggle {
                id = "inspector-denoise",
                checked = state.denoise,
                onChange = function(_, checked)
                    setValue("denoise", checked)
                end,
            },
        },
    }

    local startButton = UI.Button {
        text = "开始绘制",
        variant = "success",
        height = 36,
        onClick = function()
            onStart(status)
        end,
    }
    local stopButton = UI.Button {
        text = "终止绘制",
        variant = "danger",
        height = 36,
        onClick = function()
            onStop(status)
        end,
    }

    local panel = UI.Panel {
        position = "absolute",
        right = 16,
        top = 54,
        width = 230,
        padding = 12,
        gap = 8,
        backgroundColor = { 12, 24, 38, 238 },
        borderColor = { 72, 124, 164, 255 },
        borderWidth = 1,
        borderRadius = 10,
        children = {
            UI.Label {
                text = "Ray Tracer Inspector",
                fontSize = 15,
                height = 28,
                fontColor = { 235, 242, 255, 255 },
            },
            presetButtons,
            settings,
            startButton,
            stopButton,
            status,
        },
    }

    return panel
end

return InspectorUI
