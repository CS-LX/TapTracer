local RayTracer = require "RayTracer"

local CONFIG = {
    title = "CPU Ray Tracer · 第一轮法线图",
    width = 64,
    height = 36,
    samplesPerPixel = 1,
    maxPixelsPerStep = 128,
}

local camera_ = nil
local scene_ = nil
local renderer_ = nil
local frame_ = nil
local vg_ = nil
local logicalW_ = 0
local logicalH_ = 0
local dpr_ = 1
local fontId_ = -1
local hasFont_ = false
local statusText_ = "初始化中"
local lastProgress_ = -1

local function updateViewportSize()
    local physicalW = graphics:GetWidth()
    local physicalH = graphics:GetHeight()
    dpr_ = graphics:GetDPR()
    if dpr_ <= 0 then
        dpr_ = 1
    end
    logicalW_ = physicalW / dpr_
    logicalH_ = physicalH / dpr_
end

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
    statusText_ = "开始渲染"
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

local function drawText(ctx, x, y, size, text, color, align)
    if not hasFont_ then
        return
    end
    nvgFontFaceId(ctx, fontId_)
    nvgFontSize(ctx, size)
    nvgTextAlign(ctx, align or NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    nvgFillColor(ctx, color)
    nvgText(ctx, x, y, text, nil)
end

function Start()
    graphics.windowTitle = CONFIG.title
    input.mouseMode = MM_ABSOLUTE
    updateViewportSize()

    vg_ = nvgCreate(1)
    if vg_ == nil then
        print("[RayTracer] ERROR: NanoVG context creation failed")
        return
    end

    fontId_ = nvgCreateFont(vg_, "sans", "Fonts/NotoSansSC-Black.ttf")
    if fontId_ == -1 then
        print("[RayTracer] WARNING: Font unavailable; continuing without text overlay")
        hasFont_ = false
    else
        hasFont_ = true
    end

    buildScene()
    buildRenderer()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent(vg_, "NanoVGRender", "HandleRender")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")
    print(string.format("[RayTracer] started: %dx%d, DPR %.2f", CONFIG.width, CONFIG.height, dpr_))
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    if renderer_ == nil then
        return
    end

    if not renderer_:isComplete() then
        renderer_:step(CONFIG.maxPixelsPerStep)
        frame_ = renderer_.film
        local progress = renderer_:progress()
        if progress ~= lastProgress_ then
            lastProgress_ = progress
            statusText_ = string.format("渲染中 %.1f%%", progress * 100)
        end
    else
        statusText_ = "渲染完成 · 法线积分器"
    end
end

---@param eventType string
---@param eventData ScreenModeEventData
function HandleScreenMode(eventType, eventData)
    updateViewportSize()
end

---@param eventType string
---@param eventData NanoVGRenderEventData
function HandleRender(eventType, eventData)
    if vg_ == nil then
        return
    end

    updateViewportSize()
    nvgBeginFrame(vg_, logicalW_, logicalH_, dpr_)

    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, logicalW_, logicalH_)
    nvgFillColor(vg_, nvgRGBA(8, 12, 20, 255))
    nvgFill(vg_)

    local imageWidth = math.min(logicalW_ - 48, logicalH_ * 1.65)
    local imageHeight = imageWidth * CONFIG.height / CONFIG.width
    local imageLeft = (logicalW_ - imageWidth) * 0.5
    local imageTop = math.max(56, (logicalH_ - imageHeight) * 0.5)
    drawPixelImage(vg_, imageLeft, imageTop, imageWidth, imageHeight)

    drawText(vg_, logicalW_ * 0.5, 18, 18, CONFIG.title, nvgRGBA(235, 242, 255, 255), NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    drawText(vg_, logicalW_ * 0.5, imageTop + imageHeight + 14, 13, statusText_, nvgRGBA(166, 190, 215, 255), NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    drawText(vg_, 16, logicalH_ - 20, 11, "纯 Lua 5.4 · CPU-only · 无图形 API 参与计算", nvgRGBA(112, 145, 175, 255), NVG_ALIGN_LEFT + NVG_ALIGN_BASELINE)

    nvgEndFrame(vg_)
end

function Stop()
    if vg_ ~= nil then
        nvgDelete(vg_)
        vg_ = nil
        print("[RayTracer] NanoVG context deleted")
    end
end
