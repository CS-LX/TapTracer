local RayTracer = require "RayTracer"
local UI = require("urhox-libs/UI")

local CONFIG = {
    title = "CPU Ray Tracer · Cornell Box",
    width = 128,
    height = 72,
    samplesPerPixel = 16,
    maxTilesPerStep = 2,
    maxDepth = 8,
    denoise = false,
    rawDisplayWidth = 112,
    denoisedDisplayWidth = 96,
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

local function addBox(scene, minimum, maximum, material)
    local Vec3 = RayTracer.Vec3
    local minX = minimum.x
    local minY = minimum.y
    local minZ = minimum.z
    local maxX = maximum.x
    local maxY = maximum.y
    local maxZ = maximum.z

    scene:add(RayTracer.Quad.new(
        Vec3.new(minX, minY, minZ),
        Vec3.new(maxX - minX, 0, 0),
        Vec3.new(0, maxY - minY, 0),
        material
    ))
    scene:add(RayTracer.Quad.new(
        Vec3.new(minX, minY, maxZ),
        Vec3.new(maxX - minX, 0, 0),
        Vec3.new(0, maxY - minY, 0),
        material
    ))
    scene:add(RayTracer.Quad.new(
        Vec3.new(minX, minY, minZ),
        Vec3.new(0, maxY - minY, 0),
        Vec3.new(0, 0, maxZ - minZ),
        material
    ))
    scene:add(RayTracer.Quad.new(
        Vec3.new(maxX, minY, maxZ),
        Vec3.new(0, maxY - minY, 0),
        Vec3.new(0, 0, minZ - maxZ),
        material
    ))
    scene:add(RayTracer.Quad.new(
        Vec3.new(minX, minY, minZ),
        Vec3.new(0, 0, maxZ - minZ),
        Vec3.new(maxX - minX, 0, 0),
        material
    ))
    scene:add(RayTracer.Quad.new(
        Vec3.new(minX, maxY, minZ),
        Vec3.new(maxX - minX, 0, 0),
        Vec3.new(0, 0, maxZ - minZ),
        material
    ))
end

local function buildScene()
    local Vec3 = RayTracer.Vec3
    local red = RayTracer.Lambertian.new(Vec3.new(0.65, 0.05, 0.05))
    local green = RayTracer.Lambertian.new(Vec3.new(0.12, 0.45, 0.15))
    local white = RayTracer.Lambertian.new(Vec3.new(0.73, 0.73, 0.73))
    local imageTexture = RayTracer.ImageTexture.fromPPM([[P3
2 2
255
220 40 40   40 210 70
40 90 220   235 235 235
]])
    local texturedWhite = RayTracer.Lambertian.new(imageTexture)
    local light = RayTracer.DiffuseLight.new(
        RayTracer.SolidColor.new(Vec3.new(1.0, 1.0, 1.0)),
        8.0
    )

    scene_ = RayTracer.Scene.new()

    -- Cornell Box: camera faces +Z toward the back wall at z = 4.
    scene_:add(RayTracer.Quad.new(
        Vec3.new(-3, 0, 4),
        Vec3.new(6, 0, 0),
        Vec3.new(0, 5, 0),
        white
    ))
    scene_:add(RayTracer.Quad.new(
        Vec3.new(-3, 0, -1),
        Vec3.new(0, 0, 5),
        Vec3.new(6, 0, 0),
        white
    ))
    scene_:add(RayTracer.Quad.new(
        Vec3.new(-3, 5, -1),
        Vec3.new(6, 0, 0),
        Vec3.new(0, 0, 5),
        white
    ))
    scene_:add(RayTracer.Quad.new(
        Vec3.new(-3, 0, -1),
        Vec3.new(0, 5, 0),
        Vec3.new(0, 0, 5),
        red
    ))
    scene_:add(RayTracer.Quad.new(
        Vec3.new(3, 0, 4),
        Vec3.new(0, 0, -5),
        Vec3.new(0, 5, 0),
        green
    ))
    scene_:add(RayTracer.Quad.new(
        Vec3.new(-1.0, 4.98, 1.0),
        Vec3.new(2.0, 0, 0),
        Vec3.new(0, 0, 1.5),
        light
    ))
    addBox(
        scene_,
        Vec3.new(-2.15, 0, 1.2),
        Vec3.new(-0.45, 2.15, 2.55),
        white
    )
    addBox(
        scene_,
        Vec3.new(0.35, 0, 0.15),
        Vec3.new(2.15, 3.35, 1.75),
        texturedWhite
    )

    camera_ = RayTracer.Camera.new {
        aspectRatio = CONFIG.width / CONFIG.height,
        imageWidth = CONFIG.width,
        verticalFov = 40,
        lookFrom = Vec3.new(0, 2.5, -6.5),
        lookAt = Vec3.new(0, 2.5, 1.5),
        up = Vec3.new(0, 1, 0),
        defocusAngle = 0,
    }
end

local function buildRenderer()
    renderer_ = RayTracer.Renderer.new {
        camera = camera_,
        scene = scene_,
        width = CONFIG.width,
        height = CONFIG.height,
        samplesPerPixel = CONFIG.samplesPerPixel,
        maxDepth = CONFIG.maxDepth,
        tileSize = 8,
        seed = 42,
        integrator = RayTracer.PathIntegrator.new {
            maxDepth = CONFIG.maxDepth,
            background = RayTracer.Vec3.new(0, 0, 0),
        },
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
        height = 36,
        text = "初始化中 · Cornell Box",
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
    local function encode(value)
        return math.floor(
            math.max(0, math.min(1, value)) * 255
        )
    end

    return nvgRGBA(encode(r), encode(g), encode(b), 255)
end

local function drawRawPixelImage(ctx, left, top, width, height)
    local displayWidth = math.min(frame_.width, CONFIG.rawDisplayWidth)
    local displayHeight = math.floor(displayWidth * frame_.height / frame_.width)
    local cellW = width / displayWidth
    local cellH = height / displayHeight

    for y = 0, displayHeight - 1 do
        local sourceY = math.min(
            frame_.height - 1,
            math.floor(y * frame_.height / displayHeight)
        )
        for x = 0, displayWidth - 1 do
            local sourceX = math.min(
                frame_.width - 1,
                math.floor(x * frame_.width / displayWidth)
            )
            local r, g, b = frame_:get(sourceX, sourceY)
            nvgBeginPath(ctx)
            nvgRect(ctx, left + x * cellW, top + y * cellH, cellW + 0.5, cellH + 0.5)
            nvgFillColor(ctx, colorToRgba(r, g, b))
            nvgFill(ctx)
        end
    end
end

local function drawPixelImage(ctx, left, top, width, height)
    if frame_ == nil then
        return
    end

    if not CONFIG.denoise then
        drawRawPixelImage(ctx, left, top, width, height)
        return
    end

    local displayWidth = math.min(frame_.width, CONFIG.denoisedDisplayWidth)
    local displayHeight = math.floor(displayWidth * frame_.height / frame_.width)
    local cellW = width / displayWidth
    local cellH = height / displayHeight

    for y = 0, displayHeight - 1 do
        local sourceTop = math.floor(y * frame_.height / displayHeight)
        local sourceBottom = math.max(
            sourceTop,
            math.ceil((y + 1) * frame_.height / displayHeight) - 1
        )
        for x = 0, displayWidth - 1 do
            local sourceLeft = math.floor(x * frame_.width / displayWidth)
            local sourceRight = math.max(
                sourceLeft,
                math.ceil((x + 1) * frame_.width / displayWidth) - 1
            )
            local red = 0.0
            local green = 0.0
            local blue = 0.0
            local count = 0

            for sourceY = sourceTop, sourceBottom do
                for sourceX = sourceLeft, sourceRight do
                    local r, g, b = frame_:get(sourceX, sourceY)
                    red = red + r
                    green = green + g
                    blue = blue + b
                    count = count + 1
                end
            end

            nvgBeginPath(ctx)
            nvgRect(ctx, left + x * cellW, top + y * cellH, cellW + 0.5, cellH + 0.5)
            nvgFillColor(ctx, colorToRgba(red / count, green / count, blue / count))
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
        renderer:step(CONFIG.maxTilesPerStep)
        frame_ = renderer.film
        local progress = renderer:progress()
        statusLabel:SetText(string.format("渲染中 %.1f%%", progress * 100))
        progressBar:SetValue(progress)
    elseif not reportedComplete_ then
        statusLabel:SetText("渲染完成 · Cornell Box")
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
