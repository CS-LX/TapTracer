local InspectorUI = {}

local COLORS = {
    text = { 239, 246, 255, 255 },
    muted = { 154, 174, 196, 255 },
    accent = { 56, 189, 248, 255 },
    surface = { 13, 24, 38, 214 },
    field = { 24, 39, 56, 220 },
    border = { 90, 122, 150, 128 },
}

local function rounded(value)
    return math.floor(value + 0.5)
end

local function formatNumber(value, decimals)
    return string.format("%." .. tostring(decimals or 0) .. "f", value)
end

function InspectorUI.build(UI, options)
    local state = options.state
    local syncing = false
    local controls = {}
    local valueLabels = {}

    local status = UI.Label {
        id = "inspector-status",
        text = "待机 · 调整参数后开始绘制",
        fontSize = 11,
        fontColor = COLORS.muted,
        minHeight = 34,
        whiteSpace = "normal",
    }
    local presetLabel = UI.Label {
        text = "当前预设 · " .. tostring(state.quality),
        fontSize = 10,
        fontColor = COLORS.accent,
        height = 20,
    }

    local function commit(key, value)
        if syncing then
            return
        end
        state[key] = value
        state.quality = "custom"
        presetLabel:SetText("当前预设 · custom")
        options.onConfigChanged(state)
    end

    local function sectionTitle(text)
        return UI.Label {
            text = text,
            fontSize = 11,
            fontWeight = "bold",
            fontColor = COLORS.text,
            height = 24,
            marginTop = 4,
        }
    end

    local function numericControl(key, label, minimum, maximum, step, decimals)
        local valueLabel = UI.Label {
            text = formatNumber(state[key], decimals),
            fontSize = 10,
            fontColor = COLORS.accent,
            textAlign = "right",
            width = 72,
            height = 20,
        }
        local slider = UI.Slider {
            value = state[key],
            min = minimum,
            max = maximum,
            step = step,
            height = 24,
            onChange = function(_, value)
                valueLabel:SetText(formatNumber(value, decimals))
            end,
            onChangeEnd = function(_, value)
                value = decimals == 0 and rounded(value) or value
                valueLabel:SetText(formatNumber(value, decimals))
                commit(key, value)
            end,
        }
        controls[key] = slider
        valueLabels[key] = valueLabel
        return UI.Panel {
            gap = 2,
            children = {
                UI.Panel {
                    height = 20,
                    flexDirection = "row",
                    justifyContent = "space-between",
                    children = {
                        UI.Label {
                            text = label,
                            fontSize = 10,
                            fontColor = COLORS.muted,
                            flexGrow = 1,
                            flexShrink = 1,
                        },
                        valueLabel,
                    },
                },
                slider,
            },
        }
    end

    local function toggleControl(key, label)
        local toggle = UI.Toggle {
            value = state[key] == true,
            onChange = function(_, enabled)
                commit(key, enabled)
            end,
        }
        controls[key] = toggle
        return UI.Panel {
            height = 30,
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "space-between",
            children = {
                UI.Label {
                    text = label,
                    fontSize = 10,
                    fontColor = COLORS.muted,
                    flexGrow = 1,
                    flexShrink = 1,
                },
                toggle,
            },
        }
    end

    local kernelToggle = UI.Toggle {
        value = state.denoiseKernel == "5x5",
        onChange = function(_, enabled)
            commit("denoiseKernel", enabled and "5x5" or "3x3")
        end,
    }
    controls.denoiseKernel = kernelToggle

    local function syncControls(config)
        syncing = true
        for key, control in pairs(controls) do
            if key == "denoiseKernel" then
                control:SetValue(config.denoiseKernel == "5x5")
            elseif type(config[key]) == "boolean" then
                control:SetValue(config[key])
            elseif config[key] ~= nil then
                control:SetValue(config[key])
            end
        end
        for key, label in pairs(valueLabels) do
            local decimals = key == "exposure" and 2 or 0
            label:SetText(formatNumber(config[key], decimals))
        end
        presetLabel:SetText("当前预设 · " .. tostring(config.quality))
        syncing = false
    end

    local function choosePreset(name)
        local preset = options.getPreset(name)
        for key in pairs(state) do
            if key ~= "title" then
                state[key] = nil
            end
        end
        for key, value in pairs(preset) do
            state[key] = value
        end
        syncControls(state)
        options.onConfigChanged(state)
    end

    local presetButtons = UI.Panel {
        id = "preset-actions",
        height = 34,
        flexDirection = "row",
        gap = 2,
        children = {
            UI.Button {
                text = "Preview",
                flexGrow = 1,
                flexBasis = 0,
                flexShrink = 1,
                height = 32,
                fontSize = 10,
                paddingHorizontal = 4,
                borderRadius = 3,
                onClick = function() choosePreset("preview") end,
            },
            UI.Button {
                text = "Square",
                flexGrow = 1,
                flexBasis = 0,
                flexShrink = 1,
                height = 32,
                fontSize = 10,
                paddingHorizontal = 4,
                borderRadius = 3,
                onClick = function() choosePreset("quality-square") end,
            },
            UI.Button {
                text = "Offline",
                flexGrow = 1,
                flexBasis = 0,
                flexShrink = 1,
                height = 32,
                fontSize = 10,
                paddingHorizontal = 4,
                borderRadius = 3,
                onClick = function() choosePreset("offline") end,
            },
        },
    }

    local settings = UI.Panel {
        width = "100%",
        gap = 5,
        children = {
            sectionTitle("OUTPUT"),
            numericControl("width", "宽度", 64, 1024, 16, 0),
            numericControl("height", "高度", 64, 1024, 16, 0),
            numericControl("samplesPerPixel", "每像素采样", 1, 256, 1, 0),
            numericControl("maxDepth", "最大路径深度", 1, 16, 1, 0),
            numericControl("seed", "随机种子", 1, 999, 1, 0),
            numericControl("exposure", "显示曝光", 0.25, 4.0, 0.05, 2),

            sectionTitle("SCHEDULER"),
            numericControl("progressiveChunkWidth", "Tile 宽度", 8, 256, 8, 0),
            numericControl("progressiveChunkHeight", "Tile 高度", 1, 64, 1, 0),
            numericControl("maxTilesPerStep", "每帧 Tile 数", 1, 16, 1, 0),

            sectionTitle("INTEGRATION"),
            toggleControl("useMIS", "多重重要性采样"),

            sectionTitle("DISPLAY FILTER"),
            toggleControl("denoise", "Beauty 降噪"),
            toggleControl("transmissionDenoise", "玻璃透射降噪"),
            numericControl("denoiseIterations", "A-Trous 轮数", 1, 3, 1, 0),
            UI.Panel {
                height = 30,
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                children = {
                    UI.Label {
                        text = "5×5 B3-spline Kernel",
                        fontSize = 10,
                        fontColor = COLORS.muted,
                        flexGrow = 1,
                        flexShrink = 1,
                    },
                    kernelToggle,
                },
            },
        },
    }

    local startButton = UI.Button {
        text = "开始绘制",
        height = 38,
        borderRadius = 3,
        backgroundColor = { 14, 165, 145, 255 },
        hoverBackgroundColor = { 20, 184, 166, 255 },
        pressedBackgroundColor = { 13, 148, 136, 255 },
        onClick = function() options.onStart(status) end,
    }
    local stopButton = UI.Button {
        text = "终止",
        height = 38,
        borderRadius = 3,
        backgroundColor = { 51, 65, 85, 255 },
        hoverBackgroundColor = { 71, 85, 105, 255 },
        pressedBackgroundColor = { 30, 41, 59, 255 },
        onClick = function() options.onStop(status) end,
    }

    local panel = UI.Panel {
        id = "inspector-sidebar",
        width = options.width or 304,
        minWidth = 280,
        maxWidth = 360,
        height = "100%",
        flexShrink = 0,
        padding = 14,
        gap = 8,
        backgroundColor = COLORS.surface,
        borderLeftWidth = 1,
        borderLeftColor = COLORS.border,
        children = {
            UI.Panel {
                height = 48,
                children = {
                    UI.Label {
                        text = "INSPECTOR",
                        fontSize = 15,
                        fontWeight = "bold",
                        fontColor = COLORS.text,
                        height = 22,
                        letterSpacing = 1.5,
                    },
                    presetLabel,
                },
            },
            presetButtons,
            UI.Divider.Horizontal { color = COLORS.border, spacing = 2 },
            UI.ScrollView {
                id = "inspector-scroll",
                width = "100%",
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                showScrollbar = true,
                bounces = false,
                children = { settings },
            },
            UI.Panel {
                id = "render-actions",
                width = "100%",
                flexDirection = "row",
                gap = 6,
                children = {
                    UI.Panel {
                        flexGrow = 1,
                        flexBasis = 0,
                        flexShrink = 1,
                        children = { startButton },
                    },
                    UI.Panel {
                        width = 72,
                        flexShrink = 1,
                        children = { stopButton },
                    },
                },
            },
            status,
        },
    }

    panel.SyncConfig = syncControls
    return panel
end

return InspectorUI
