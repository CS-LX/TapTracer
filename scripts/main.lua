local RayTracer = require "RayTracer"
local UI = require("urhox-libs/UI")

local CONFIG = {
    title = "CPU Ray Tracer · 第一轮法线图",
    width = 64,
    height = 36,
    samplesPerPixel = 1,
    maxPixelsPerStep = 32,
}

---@type table|nil
local camera_ = nil
---@type table|nil
local scene_ = nil
---@type table|nil
local renderer_ = nil
---@type table|nil
local frame_ = nil
---@type NVGContextWrapper|nil
local vg_ = nil
---@type Label|nil
local statusLabel_ = nil
---@type ProgressBar|nil
local progressBar_ = nil
---@type Panel|nil
local uiRoot_ = nil
local reportedComplete_ = false

local function buildScene()
    local Vec3 = RayTracer.Vec3
    scene_ = RayTracer.Scene.new()
    scene_:add(RayTracer.Sphere.new(Vec3.new(0, 0, -1), 0.5))
    scene_:add(RayTracer.Sphere.new(Vec3.new(0, -100.5, -1), 100))

    camera_ = RayTracer.Camera.new {
        aspectRatio = CONFIG.width / CONFIG.height,
        imageWidth = CONFIG.width,
        verticalFov = 40,
        lookFrom = Vec3.new(0, 0, 0),
        lookAt = Vec3.new(0, 0, -1),
        up = Vec3.new(0, 1, 0),
    }
end

local function buildRenderer()
    renderer_ = RayTracer.Renderer.new {
        camera = camera_,
        scene = scene_,
        width = CONFIG.width,
        height = CONFIG.height,
        samplesPerPixel = CONFIG.samplesPerPixel,
        tileSize = 8,
        seed = 42,
        integrator = RayTracer.NormalIntegrator.new(),
    }
end

local function buildUI()
    UI.Init {
        theme = "default-dark",
        fonts = {
            { name = "sans", path = "Fonts/NotoSansSC-Black.ttf" },
        },
        scale = UI.Scale.DEFAULT,
    }

    statusLabel_ = UI.Label {
        id = "render-status",
        position = "absolute",
        left = 0,
        width = "100%",
        bottom = 54,
        height = 28,
        text = "初始化中",
        fontSize = 14,
        fontColor = { 206, 224, 244, 255 },
        textAlign = "center",
        verticalAlign = "middle",
        textStroke = { width = 2, color = { 8, 12, 20, 255 } },
    }

    progressBar_ = UI.ProgressBar {
        id = "render-progress",
        position = "absolute",
        left = 24,
        width = "94%",
        bottom = 34,
        height = 10,
        value = 0,
        max = 1,
        fillGradient = {
            direction = "to-right",
            from = { 80, 190, 255, 255 },
            to = { 90, 230, 160, 255 },
        },
        backgroundColor = { 22, 32, 48, 240 },
        borderColor = { 100, 145, 180, 255 },
        borderWidth = 1,
        borderRadius = 5,
    }

    local titleLabel = UI.Label {
        id = "title",
        position = "absolute",
        left = 0,
        width = "100%",
        top = 10,
        height = 32,
        text = CONFIG.title,
        fontSize = 18,
        fontColor = { 235, 242, 255, 255 },
        textAlign = "center",
        verticalAlign = "middle",
        textStroke = { width = 2, color = { 8, 12, 20, 255 } },
    }

    local footerLabel = UI.Label {
        id = "footer",
        position = "absolute",
        left = 0,
        width = "100%",
        bottom = 8,
        height = 18,
        text = "纯 Lua 5.4 · CPU-only · 无图形 API 参与计算",
        fontSize = 10,
        fontColor = { 138, 169, 202, 255 },
        textAlign = "center",
        verticalAlign = "middle",
        textStroke = { width = 1, color = { 8, 12, 20, 255 } },
    }

    uiRoot_ = UI.Panel {
        width = "100%",
        height = "100%",
        position = "relative",
        pointerEvents = "box-none",
        children = {
            titleLabel,
            statusLabel_,
            progressBar_,
            footerLabel,
        },
    }
    UI.SetRoot(uiRoot_)
end

local function colorToRgba(r, g, b)
    local red = math.floor(math.max(0, math.min(1, r)) * 255)
    local green = math.floor(math.max(0, math.min(1, g)) * 255)
    local blue = math.floor(math.max(0, math.min(1, b)) * 255)
    return nvgRGBA(red, green, blue, 255)
end

local function drawPixelImage(ctx, left, top, width, height)
    if frame_ == nil then
        return
    end

    local cellW = width / frame_.width
    local cellH = height / frame_.height
    for y = 0, frame_.height - 1 do
        for x = 0, frame_.width - 1 do
            local r, g, b = frame_:get(x, y)
            nvgBeginPath(ctx)
            nvgRect(ctx, left + x * cellW, top + y * cellH, cellW + 0.5, cellH + 0.5)
            nvgFillColor(ctx, colorToRgba(r, g, b))
            nvgFill(ctx)
        end
    end
end

function Start()
    graphics.windowTitle = CONFIG.title
    input.mouseMode = MM_ABSOLUTE

    vg_ = nvgCreate(1)
    if vg_ == nil then
        print("[RayTracer] ERROR: NanoVG context creation failed")
        return
    end

    buildUI()
    buildScene()
    buildRenderer()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent(vg_, "NanoVGRender", "HandleRender")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")
    print(string.format("[RayTracer] started: %dx%d", CONFIG.width, CONFIG.height))
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local renderer = renderer_
    local statusLabel = statusLabel_
    local progressBar = progressBar_
    if renderer == nil or statusLabel == nil or progressBar == nil then
        return
    end

    if not renderer:isComplete() then
        renderer:step(CONFIG.maxPixelsPerStep)
        frame_ = renderer.film
        local progress = renderer:progress()
        statusLabel:SetText(string.format("渲染中 %.1f%%", progress * 100))
        progressBar:SetValue(progress)
    elseif not reportedComplete_ then
        statusLabel:SetText("渲染完成 · 法线积分器")
        progressBar:SetValue(1)
        reportedComplete_ = true
        print("[RayTracer] render complete")
    end
end

---@param eventType string
---@param eventData ScreenModeEventData
function HandleScreenMode(eventType, eventData)
    UI.MarkLayoutDirty()
end

---@param eventType string
---@param eventData NanoVGRenderEventData
function HandleRender(eventType, eventData)
    local vg = vg_
    if vg == nil then
        return
    end

    local physicalW = graphics:GetWidth()
    local physicalH = graphics:GetHeight()
    local dpr = graphics:GetDPR()
    if dpr <= 0 then
        dpr = 1
    end
    local logicalW = physicalW / dpr
    local logicalH = physicalH / dpr

    nvgBeginFrame(vg, logicalW, logicalH, dpr)

    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, logicalW, logicalH)
    nvgFillColor(vg, nvgRGBA(8, 12, 20, 255))
    nvgFill(vg)

    local imageWidth = math.min(logicalW - 48, logicalH * 1.65)
    local imageHeight = imageWidth * CONFIG.height / CONFIG.width
    local imageLeft = (logicalW - imageWidth) * 0.5
    local imageTop = math.max(56, (logicalH - imageHeight) * 0.5)
    drawPixelImage(vg, imageLeft, imageTop, imageWidth, imageHeight)

    nvgEndFrame(vg)
end

function Stop()
    if UI.GetRoot() ~= nil then
        UI.Shutdown()
        uiRoot_ = nil
        statusLabel_ = nil
        progressBar_ = nil
    end
    if vg_ ~= nil then
        nvgDelete(vg_)
        vg_ = nil
        print("[RayTracer] NanoVG context deleted")
    end
end
