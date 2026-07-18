local RayTracer = require "RayTracer"
local QualityPresets = require "RayTracer.Config.QualityPresets"
local DisplayDenoise = require "RayTracer.Display.DisplayDenoise"
local PrimaryAOV = require "RayTracer.Display.PrimaryAOV"
local AOVAtrous = require "RayTracer.Display.AOVAtrous"
local RenderController = require "RayTracer.Runtime.RenderController"
local InspectorUI = require "RayTracer.UI.InspectorUI"
local SceneCatalog = require "RayTracer.Scenes.SceneCatalog"
local MaterialShowcase = SceneCatalog.active
local UI = require("urhox-libs/UI")

local ACTIVE_QUALITY = "preview"
local ACTIVE_PRESET = QualityPresets.get(ACTIVE_QUALITY)

local CONFIG = {
    title = MaterialShowcase.title,
    quality = ACTIVE_QUALITY,
    width = ACTIVE_PRESET.width,
    height = ACTIVE_PRESET.height,
    samplesPerPixel = ACTIVE_PRESET.samplesPerPixel,
    progressiveChunkWidth = ACTIVE_PRESET.progressiveChunkWidth,
    progressiveChunkHeight = ACTIVE_PRESET.progressiveChunkHeight,
    maxTilesPerStep = ACTIVE_PRESET.maxTilesPerStep,
    maxDepth = ACTIVE_PRESET.maxDepth or 8,
    denoise = true,
    transmissionDenoise = true,
    denoiseIterations = 3,
    denoiseKernel = "3x3",
}

local function copyConfig(config)
    local result = {}
    for key, value in pairs(config) do
        result[key] = value
    end
    return result
end

---@type table|nil
local camera_ = nil
---@type table|nil
local scene_ = nil
---@type table|nil
local renderer_ = nil
---@type table|nil
local renderController_ = nil
local displayFrame_ = nil
local displayFramePass_ = 0
local renderConfig_ = copyConfig(CONFIG)
---@type NVGContextWrapper|nil
local vg_ = nil
---@type Label|nil
local statusLabel_ = nil
---@type ProgressBar|nil
local progressBar_ = nil
---@type Panel|nil
local uiRoot_ = nil
---@type Image|nil
local displayImage_ = nil
---@type Texture2D|nil
local displayTexture_ = nil
---@type BorderImage|nil
local displayCanvas_ = nil
local displayedPixels_ = 0
local displayUploadSeconds_ = 0
local displayUploadCount_ = 0
local displayFilterSeconds_ = 0
local displayFilterPixels_ = 0
local displayAOVFilterSeconds_ = 0
local displayAOVFilterCount_ = 0
local displayAOVCandidateVisits_ = 0
local displayAOVAcceptedVisits_ = 0
local lastAOVFilterSeconds_ = 0
local lastAOVFilterStats_ = nil
local pendingDisplayUpload_ = false
local reportedComplete_ = false
local INSPECTOR_RESERVED_WIDTH = 278
local DISPLAY_MARGIN = 24
local J6_SEED = 42
local J6_EXPOSURE = 1.0

local function buildCamera(config)
    camera_ = MaterialShowcase.buildCamera(config)
end

local function buildScene()
    scene_ = MaterialShowcase.build()
    local bvh = scene_:buildBVH()
    local bvhStats = bvh:getStats()
    print(string.format(
        "[RayTracer] BVH: %d objects, %d nodes, %d leaves, depth %d",
        #scene_.objects,
        bvhStats.nodeCount,
        bvhStats.leafCount,
        bvhStats.maxDepth
    ))
end

local function buildRenderer(config)
    renderer_ = RayTracer.Renderer.new {
        camera = camera_,
        scene = scene_,
        width = config.width,
        height = config.height,
        samplesPerPixel = config.samplesPerPixel,
        maxDepth = config.maxDepth,
        tileSize = 8,
        tileWidth = config.progressiveChunkWidth,
        tileHeight = config.progressiveChunkHeight,
        seed = J6_SEED,
        timeProvider = function()
            return GetTime():GetElapsedTime()
        end,
        integrator = RayTracer.PathIntegrator.new {
            maxDepth = config.maxDepth,
            background = MaterialShowcase.background,
            useMIS = true,
        },
    }
    return renderer_
end

local function encodeDisplayChannel(value)
    return math.max(0, math.min(1, value))
end

local function setConfig(config)
    local snapshot = copyConfig(config)
    for key in pairs(renderConfig_) do
        renderConfig_[key] = nil
    end
    for key, value in pairs(snapshot) do
        renderConfig_[key] = value
    end
    CONFIG.quality = renderConfig_.quality
    CONFIG.width = renderConfig_.width
    CONFIG.height = renderConfig_.height
    CONFIG.samplesPerPixel = renderConfig_.samplesPerPixel
    CONFIG.progressiveChunkWidth = renderConfig_.progressiveChunkWidth
    CONFIG.progressiveChunkHeight = renderConfig_.progressiveChunkHeight
    CONFIG.maxTilesPerStep = renderConfig_.maxTilesPerStep
    CONFIG.maxDepth = renderConfig_.maxDepth
    CONFIG.denoise = renderConfig_.denoise
    CONFIG.transmissionDenoise = renderConfig_.transmissionDenoise ~= false
    CONFIG.denoiseIterations = renderConfig_.denoiseIterations or 3
    CONFIG.denoiseKernel = renderConfig_.denoiseKernel or "3x3"
end

local function applyPreset(name)
    local preset = QualityPresets.get(name)
    local config = copyConfig(CONFIG)
    for key, value in pairs(preset) do
        config[key] = value
    end
    config.quality = name
    setConfig(config)
end

local function updateDisplayFromFrame(frame, iterations)
    if frame == nil or displayImage_ == nil or renderer_ == nil then
        return
    end
    local displayFrame = frame
    local filterStart = GetTime():GetElapsedTime()
    if CONFIG.denoise then
        local aovStart = GetTime():GetElapsedTime()
        displayFrame = AOVAtrous.filter(frame, renderer_.aov, {
            iterations = iterations,
            kernel = CONFIG.denoiseKernel,
        })
        local filteredTransmission = nil
        if CONFIG.transmissionDenoise then
            filteredTransmission = AOVAtrous.filter(
                renderer_.transmissionFilm,
                renderer_.transmissionAov,
                {
                    iterations = iterations,
                    kernel = CONFIG.denoiseKernel,
                }
            )
        end
        local filteredBeauty = displayFrame
        displayFrame = {
            width = frame.width,
            height = frame.height,
            stats = filteredBeauty.stats,
            get = function(_, column, row)
                local beautyR, beautyG, beautyB = frame:get(column, row)
                local rawR, rawG, rawB = renderer_.transmissionFilm:get(column, row)
                local primaryClass = renderer_.aov:getDenoiseClass(column, row)
                if primaryClass ~= "delta_transmission"
                        or filteredTransmission == nil then
                    return filteredBeauty:get(column, row)
                end
                local filteredR, filteredG, filteredB =
                    filteredTransmission:get(column, row)
                return beautyR - rawR + filteredR,
                    beautyG - rawG + filteredG,
                    beautyB - rawB + filteredB
            end,
        }
        local aovSeconds = math.max(
            0,
            GetTime():GetElapsedTime() - aovStart
        )
        local aovStats = displayFrame.stats or {}
        lastAOVFilterSeconds_ = aovSeconds
        lastAOVFilterStats_ = aovStats
        displayAOVFilterSeconds_ = displayAOVFilterSeconds_ + aovSeconds
        displayAOVFilterCount_ = displayAOVFilterCount_ + 1
        displayAOVCandidateVisits_ = displayAOVCandidateVisits_
            + (aovStats.candidateVisits or 0)
        displayAOVAcceptedVisits_ = displayAOVAcceptedVisits_
            + (aovStats.acceptedVisits or 0)
    end
    local width = CONFIG.width
    local height = CONFIG.height
    for row = 0, height - 1 do
        for column = 0, width - 1 do
            local r, g, b = displayFrame:get(column, row)
            displayImage_:SetPixel(column, row, Color(
                encodeDisplayChannel(r),
                encodeDisplayChannel(g),
                encodeDisplayChannel(b),
                1.0
            ))
        end
    end
    if CONFIG.denoise then
        displayFilterSeconds_ = displayFilterSeconds_
            + math.max(0, GetTime():GetElapsedTime() - filterStart)
        displayFilterPixels_ = displayFilterPixels_ + width * height
    end
    pendingDisplayUpload_ = true
end

local function buildDisplayTexture()
    displayImage_ = Image:new()
    displayImage_:SetSize(CONFIG.width, CONFIG.height, 4)
    displayImage_:Clear(Color(0.02, 0.03, 0.05, 1.0))

    displayTexture_ = Texture2D:new()
    displayTexture_:SetSRGB(false)
    displayTexture_:SetNumLevels(1)
    displayTexture_:SetFilterMode(FILTER_NEAREST)
    displayTexture_:SetData(displayImage_, false)

    displayCanvas_ = BorderImage:new()
    displayCanvas_:SetTexture(displayTexture_)
    displayCanvas_:SetImageRect(IntRect(0, 0, CONFIG.width, CONFIG.height))
    displayCanvas_:SetPriority(-1000000)
    displayCanvas_:SetBringToBack(true)
    ui.root:InsertChild(0, displayCanvas_)
    displayedPixels_ = 0
    displayUploadSeconds_ = 0
    displayUploadCount_ = 0
    displayFilterSeconds_ = 0
    displayFilterPixels_ = 0
    displayAOVFilterSeconds_ = 0
    displayAOVFilterCount_ = 0
    displayAOVCandidateVisits_ = 0
    displayAOVAcceptedVisits_ = 0
    lastAOVFilterSeconds_ = 0
    lastAOVFilterStats_ = nil
    pendingDisplayUpload_ = false
    print(string.format(
        "[RayTracer] live display texture ready: %dx%d",
        CONFIG.width,
        CONFIG.height
    ))
end

local function resetDisplayTexture()
    if displayImage_ == nil or displayTexture_ == nil or displayCanvas_ == nil then
        return
    end
    displayImage_:SetSize(CONFIG.width, CONFIG.height, 4)
    displayImage_:Clear(Color(0.02, 0.03, 0.05, 1.0))
    displayTexture_:SetData(displayImage_, false)
    displayCanvas_:SetTexture(displayTexture_)
    displayCanvas_:SetImageRect(IntRect(0, 0, CONFIG.width, CONFIG.height))
    displayedPixels_ = 0
    displayFrame_ = nil
    displayFramePass_ = 0
    pendingDisplayUpload_ = false
end

local function uploadDisplayTexture()
    local texture = displayTexture_
    local image = displayImage_
    if texture == nil or image == nil then
        return
    end

    local uploadStart = GetTime():GetElapsedTime()
    texture:SetData(image, false)
    pendingDisplayUpload_ = false
    displayUploadSeconds_ = displayUploadSeconds_
        + math.max(0, GetTime():GetElapsedTime() - uploadStart)
    displayUploadCount_ = displayUploadCount_ + 1
end

local function updateDisplayTile(tile)
    local image = displayImage_
    local frame = displayFrame_
    if image == nil or frame == nil or tile == nil then
        return
    end

    local displayFrame = frame
    if CONFIG.denoise then
        displayFrame = {
            get = function(_, column, row)
                return DisplayDenoise.filterPixel(frame, column, row, CONFIG.width, CONFIG.height)
            end,
        }
    end

    local startX = tile.x
    local startY = tile.y
    local endX = tile.x + tile.width - 1
    local endY = tile.y + tile.height - 1
    if CONFIG.denoise then
        startX = math.max(0, startX - 1)
        startY = math.max(0, startY - 1)
        endX = math.min(CONFIG.width - 1, endX + 1)
        endY = math.min(CONFIG.height - 1, endY + 1)
    end

    local filterStart = CONFIG.denoise and GetTime():GetElapsedTime() or 0
    local filteredPixels = 0
    for row = startY, endY do
        for column = startX, endX do
            local r, g, b = displayFrame:get(column, row)
            image:SetPixel(column, row, Color(
                encodeDisplayChannel(r),
                encodeDisplayChannel(g),
                encodeDisplayChannel(b),
                1.0
            ))
            filteredPixels = filteredPixels + 1
        end
    end
    if CONFIG.denoise then
        displayFilterSeconds_ = displayFilterSeconds_
            + math.max(0, GetTime():GetElapsedTime() - filterStart)
        displayFilterPixels_ = displayFilterPixels_ + filteredPixels
    end

    pendingDisplayUpload_ = true
end

local function layoutDisplayCanvas()
    local canvas = displayCanvas_
    if canvas == nil then
        return
    end

    local physicalW = graphics:GetWidth()
    local physicalH = graphics:GetHeight()
    local dpr = math.max(1, graphics:GetDPR())
    local logicalW = physicalW / dpr
    local logicalH = physicalH / dpr
    local availableWidth = math.max(160, logicalW - INSPECTOR_RESERVED_WIDTH - DISPLAY_MARGIN * 2)
    local availableHeight = math.max(90, logicalH - 150)
    local imageWidth = math.min(availableWidth, availableHeight * CONFIG.width / CONFIG.height)
    local imageHeight = imageWidth * CONFIG.height / CONFIG.width
    local imageLeft = DISPLAY_MARGIN + (availableWidth - imageWidth) * 0.5
    local imageTop = math.max(56, (logicalH - imageHeight) * 0.5)

    canvas:SetPosition(
        math.floor(imageLeft * dpr),
        math.floor(imageTop * dpr)
    )
    canvas:SetSize(
        math.floor(imageWidth * dpr),
        math.floor(imageHeight * dpr)
    )
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
        text = "初始化中 · " .. MaterialShowcase.statusName,
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
        text = string.format("%s · %s", CONFIG.title, CONFIG.quality),
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

local function collectJ6GlassBounds(renderer)
    local primaryAov = renderer.aov
    local minX = renderer.width
    local minY = renderer.height
    local maxX = -1
    local maxY = -1
    local pixelCount = 0
    for y = 0, renderer.height - 1 do
        for x = 0, renderer.width - 1 do
            if primaryAov:getDenoiseClass(x, y) == "delta_transmission" then
                minX = math.min(minX, x)
                minY = math.min(minY, y)
                maxX = math.max(maxX, x)
                maxY = math.max(maxY, y)
                pixelCount = pixelCount + 1
            end
        end
    end
    return minX, minY, maxX, maxY, pixelCount
end

local function makeJ6GlassROIs(minX, minY, maxX, maxY)
    local width = maxX - minX + 1
    local height = maxY - minY + 1
    local insetX = math.max(2, math.floor(width * 0.18))
    local insetY = math.max(2, math.floor(height * 0.10))
    local innerMinX = minX + insetX
    local innerMaxX = maxX - insetX
    local innerMinY = minY + insetY
    local innerMaxY = maxY - insetY
    local innerHeight = innerMaxY - innerMinY + 1
    local upperEndY = innerMinY + math.max(0, math.floor(innerHeight * 0.35) - 1)
    local coreStartY = innerMinY + math.floor(innerHeight * 0.45)
    return {
        {
            name = "glassUpper",
            x0 = innerMinX,
            y0 = innerMinY,
            x1 = innerMaxX,
            y1 = upperEndY,
        },
        {
            name = "glassCore",
            x0 = innerMinX,
            y0 = coreStartY,
            x1 = innerMaxX,
            y1 = innerMaxY,
        },
    }
end

local function collectJ6ROIStats(renderer, roi)
    local film = renderer.film
    local transmissionFilm = renderer.transmissionFilm
    local primaryAov = renderer.aov
    local transmissionAov = renderer.transmissionAov
    local pixelCount = 0
    local beautyMeanSum = 0
    local beautyVarianceSum = 0
    local beautyMeanVarianceSum = 0
    local transmissionVarianceSum = 0
    local transmissionMeanVarianceSum = 0
    local transmissionGuideHits = 0
    local primaryGlassSamples = 0

    for y = roi.y0, roi.y1 do
        for x = roi.x0, roi.x1 do
            if primaryAov:getDenoiseClass(x, y) == "delta_transmission" then
                local beautyMean, beautyVariance, beautySamples =
                    film:getLuminanceMoments(x, y)
                local _, transmissionVariance, transmissionSamples =
                    transmissionFilm:getLuminanceMoments(x, y)
                pixelCount = pixelCount + 1
                beautyMeanSum = beautyMeanSum + beautyMean
                beautyVarianceSum = beautyVarianceSum + beautyVariance
                beautyMeanVarianceSum = beautyMeanVarianceSum
                    + (beautySamples > 0 and beautyVariance / beautySamples or 0)
                transmissionVarianceSum = transmissionVarianceSum + transmissionVariance
                transmissionMeanVarianceSum = transmissionMeanVarianceSum
                    + (transmissionSamples > 0
                        and transmissionVariance / transmissionSamples or 0)
                transmissionGuideHits = transmissionGuideHits
                    + transmissionAov:getHitCount(x, y)
                primaryGlassSamples = primaryGlassSamples
                    + primaryAov:getSampleCount(x, y)
            end
        end
    end

    local inversePixels = pixelCount > 0 and 1 / pixelCount or 0
    return {
        pixelCount = pixelCount,
        beautyMean = beautyMeanSum * inversePixels,
        beautySampleVariance = beautyVarianceSum * inversePixels,
        beautyMeanVariance = beautyMeanVarianceSum * inversePixels,
        transmissionSampleVariance = transmissionVarianceSum * inversePixels,
        transmissionMeanVariance = transmissionMeanVarianceSum * inversePixels,
        guideCoverage = primaryGlassSamples > 0
            and transmissionGuideHits / primaryGlassSamples or 0,
    }
end

local function printRenderStats(renderer)
    local stats = renderer:getStats()
    local integrator = stats.integrator or {}
    local accelerator = scene_ and scene_:getAccelerator()
    local bvh = accelerator and accelerator:getStats() or {}
    print(string.format(
        "[RayTracer][F] compute=%.3fs pixels/s=%.1f samples/s=%.1f paths/s=%.1f",
        stats.elapsedSeconds,
        stats.pixelsPerSecond,
        stats.samplesPerSecond,
        stats.pathsPerSecond
    ))
    print(string.format(
        "[RayTracer][F] paths=%d bounces=%d avgDepth=%.3f hits=%d misses=%d shadows=%d",
        integrator.pathCount or 0,
        integrator.bounceCount or 0,
        integrator.averagePathDepth or 0,
        integrator.hitCount or 0,
        integrator.missCount or 0,
        integrator.shadowRayCount or 0
    ))
    print(string.format(
        "[RayTracer][F] BVH boxes=%d primitives=%d displayUploads=%d upload=%.3fs",
        bvh.boxTests or 0,
        bvh.primitiveTests or 0,
        displayUploadCount_,
        displayUploadSeconds_
    ))
    print(string.format(
        "[RayTracer][H4] denoise=%s kernel=%s iterations=%d displayFilter=%.3fs filteredPixels=%d",
        tostring(CONFIG.denoise),
        CONFIG.denoiseKernel,
        CONFIG.denoiseIterations,
        displayFilterSeconds_,
        displayFilterPixels_
    ))
    local lastStats = lastAOVFilterStats_ or {}
    print(string.format(
        "[RayTracer][H4] AOV last=%.3fs taps=%d candidates=%d accepted=%d calls=%d total=%.3fs totalCandidates=%d totalAccepted=%d",
        lastAOVFilterSeconds_,
        lastStats.taps or 0,
        lastStats.candidateVisits or 0,
        lastStats.acceptedVisits or 0,
        displayAOVFilterCount_,
        displayAOVFilterSeconds_,
        displayAOVCandidateVisits_,
        displayAOVAcceptedVisits_
    ))
    local transmissionCount = integrator.primaryTransmissionCount or 0
    local fresnelSum = integrator.primaryTransmissionFresnelSum or 0
    local reflectionCount = integrator.primaryTransmissionReflectionCount or 0
    local refractionCount = integrator.primaryTransmissionRefractionCount or 0
    local guideCount = integrator.primaryTransmissionGuideCount or 0
    local guideDiffuseCount = integrator.primaryTransmissionGuideDiffuseCount or 0
    local guideGlossyCount = integrator.primaryTransmissionGuideGlossyCount or 0
    local guideEmissionCount = integrator.primaryTransmissionGuideEmissionCount or 0
    local guideOtherCount = integrator.primaryTransmissionGuideOtherCount or 0
    local firstDiffuseCount = integrator.primaryTransmissionFirstDiffuseCount or 0
    local firstGlossyCount = integrator.primaryTransmissionFirstGlossyCount or 0
    local firstEmissionCount = integrator.primaryTransmissionFirstEmissionCount or 0
    local firstOtherCount = integrator.primaryTransmissionFirstOtherCount or 0
    local skyCount = integrator.primaryTransmissionSkyCount or 0
    local rouletteCount = integrator.primaryTransmissionRouletteCount or 0
    local scatterStopCount = integrator.primaryTransmissionScatterStopCount or 0
    local depthLimitCount = integrator.primaryTransmissionDepthLimitCount or 0
    local classifiedCount = firstDiffuseCount
        + firstGlossyCount
        + firstEmissionCount
        + firstOtherCount
        + skyCount
        + rouletteCount
        + scatterStopCount
        + depthLimitCount
    print(string.format(
        "[RayTracer][H5] primaryTransmission=%d reflection=%d refraction=%d unclassifiedBranch=%d",
        transmissionCount,
        reflectionCount,
        refractionCount,
        math.max(0, transmissionCount - reflectionCount - refractionCount)
    ))
    print(string.format(
        "[RayTracer][H5] firstDiffuse=%d firstGlossy=%d firstEmission=%d firstOther=%d sky=%d roulette=%d scatterStop=%d depthLimit=%d unresolved=%d",
        firstDiffuseCount,
        firstGlossyCount,
        firstEmissionCount,
        firstOtherCount,
        skyCount,
        rouletteCount,
        scatterStopCount,
        depthLimitCount,
        math.max(0, transmissionCount - classifiedCount)
    ))
    print(string.format(
        "[RayTracer][J6.1] compute=%.3fs primaryGlass=%d dualSplit=%d reflectionContinuations=%d transmissionContinuations=%d expectedExtraSceneHits=%.3f reflectionSceneHits=%d transmissionSceneHits=%d tirFallback=%d unavailableFallback=%d",
        stats.elapsedSeconds,
        transmissionCount,
        integrator.j61DualSplitCount or 0,
        integrator.j61ReflectionLaunchCount or 0,
        integrator.j61TransmissionLaunchCount or 0,
        integrator.j61ExpectedExtraHitCount or 0,
        integrator.j61ReflectionSceneHitCalls or 0,
        integrator.j61TransmissionSceneHitCalls or 0,
        integrator.j61TirCount or 0,
        integrator.j61UnavailableCount or 0
    ))
    print(string.format(
        "[RayTracer][J6.0] config=%dx%d spp=%d maxDepth=%d seed=%d exposure=%.3f",
        CONFIG.width,
        CONFIG.height,
        CONFIG.samplesPerPixel,
        CONFIG.maxDepth,
        J6_SEED,
        J6_EXPOSURE
    ))
    print(string.format(
        "[RayTracer][J6.0] primaryGlass=%d avgFresnel=%.6f reflectionEffective=%d transmissionEffective=%d guideEffective=%d guideCoverage=%.6f",
        transmissionCount,
        transmissionCount > 0 and fresnelSum / transmissionCount or 0,
        reflectionCount,
        refractionCount,
        guideCount,
        refractionCount > 0 and guideCount / refractionCount or 0
    ))
    print(string.format(
        "[RayTracer][J6.0] transmissionTargets diffuse=%d(%.3f%%) glossy=%d(%.3f%%) emission=%d(%.3f%%) other=%d(%.3f%%)",
        guideDiffuseCount,
        guideCount > 0 and guideDiffuseCount * 100 / guideCount or 0,
        guideGlossyCount,
        guideCount > 0 and guideGlossyCount * 100 / guideCount or 0,
        guideEmissionCount,
        guideCount > 0 and guideEmissionCount * 100 / guideCount or 0,
        guideOtherCount,
        guideCount > 0 and guideOtherCount * 100 / guideCount or 0
    ))
    print("[RayTracer][J6.0] roiMetric=Film coordinates with top-left origin; primary-delta-transmission pixels only; sampleVariance=unbiased luminance M2/(n-1); meanVariance=sampleVariance/n; ROI value=arithmetic mean across included pixels")
    local glassMinX, glassMinY, glassMaxX, glassMaxY, glassPixels =
        collectJ6GlassBounds(renderer)
    print(string.format(
        "[RayTracer][J6.0] glassBounds=%d,%d-%d,%d pixels=%d",
        glassMinX,
        glassMinY,
        glassMaxX,
        glassMaxY,
        glassPixels
    ))
    local glassROIs = makeJ6GlassROIs(
        glassMinX,
        glassMinY,
        glassMaxX,
        glassMaxY
    )
    for i = 1, #glassROIs do
        local roi = glassROIs[i]
        local roiStats = collectJ6ROIStats(renderer, roi)
        print(string.format(
            "[RayTracer][J6.0] roi=%s bounds=%d,%d-%d,%d pixels=%d beautyMean=%.8f beautySampleVariance=%.8f beautyMeanVariance=%.8f transmissionSampleVariance=%.8f transmissionMeanVariance=%.8f guideCoverage=%.6f",
            roi.name,
            roi.x0,
            roi.y0,
            roi.x1,
            roi.y1,
            roiStats.pixelCount,
            roiStats.beautyMean,
            roiStats.beautySampleVariance,
            roiStats.beautyMeanVariance,
            roiStats.transmissionSampleVariance,
            roiStats.transmissionMeanVariance,
            roiStats.guideCoverage
        ))
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

    applyPreset(ACTIVE_QUALITY)
    buildUI()
    buildDisplayTexture()
    layoutDisplayCanvas()
    buildScene()
    buildCamera(renderConfig_)
    renderController_ = RenderController.new {
        config = renderConfig_,
        createRenderer = function(config)
            return buildRenderer(config)
        end,
    }
    local inspectorPanel = InspectorUI.build(UI, {
        state = renderConfig_,
        getPreset = function(name)
            return QualityPresets.get(name)
        end,
        onConfigChanged = function(config)
            local previousWidth = CONFIG.width
            local previousHeight = CONFIG.height
            setConfig(config)
            buildCamera(renderConfig_)
            if previousWidth ~= CONFIG.width or previousHeight ~= CONFIG.height then
                resetDisplayTexture()
            end
            layoutDisplayCanvas()
            if statusLabel_ ~= nil then
                statusLabel_:SetText(string.format(
                    "待机 · %s · %dx%d · %d spp · %s/%d轮",
                    CONFIG.quality,
                    CONFIG.width,
                    CONFIG.height,
                    CONFIG.samplesPerPixel,
                    CONFIG.denoiseKernel,
                    CONFIG.denoiseIterations
                ))
            end
        end,
        onStart = function(status)
            if renderController_:start() then
                displayFilterSeconds_ = 0
                displayFilterPixels_ = 0
                displayAOVFilterSeconds_ = 0
                displayAOVFilterCount_ = 0
                displayAOVCandidateVisits_ = 0
                displayAOVAcceptedVisits_ = 0
                lastAOVFilterSeconds_ = 0
                lastAOVFilterStats_ = nil
                renderer_ = renderController_:getRenderer()
                reportedComplete_ = false
                displayFrame_ = nil
                displayFramePass_ = 0
                status:SetText("已开始绘制")
            else
                status:SetText("绘制正在进行")
            end
        end,
        onStop = function(status)
            renderController_:stop()
            status:SetText("已终止绘制")
        end,
    })
    uiRoot_:AddChild(inspectorPanel)
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent(vg_, "NanoVGRender", "HandleRender")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")
    print(string.format(
        "[RayTracer] started: preset=%s resolution=%dx%d spp=%d",
        CONFIG.quality,
        CONFIG.width,
        CONFIG.height,
        CONFIG.samplesPerPixel
    ))
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local controller = renderController_
    local statusLabel = statusLabel_
    local progressBar = progressBar_
    if controller == nil or statusLabel == nil or progressBar == nil then
        return
    end

    if controller:isRunning() then
        local renderer = controller:update(CONFIG.maxTilesPerStep)
        renderer_ = renderer
        if renderer ~= nil then
            displayFrame_ = renderer.film
            local stats = renderer:getStats()
            local progress = stats.progress
            local pass = math.min(CONFIG.samplesPerPixel, stats.currentPass)
            local passProgress = stats.totalPixels > 0
                and stats.completedPassPixels / stats.totalPixels or 0
            statusLabel:SetText(string.format(
                "逐轮累积中 · 第 %d/%d 轮 · 当前轮 %.1f%% · 总进度 %.1f%%",
                pass,
                CONFIG.samplesPerPixel,
                passProgress * 100,
                progress * 100
            ))
            progressBar:SetValue(progress)

            if displayFramePass_ ~= stats.completedPasses then
                displayFramePass_ = stats.completedPasses
                updateDisplayFromFrame(displayFrame_, CONFIG.denoiseIterations)
            end
            if pendingDisplayUpload_ then
                uploadDisplayTexture()
            end
        end
    elseif renderer_ ~= nil and renderer_:isComplete() and not reportedComplete_ then
        displayFrame_ = renderer_.film
        updateDisplayFromFrame(displayFrame_, CONFIG.denoiseIterations)
        if pendingDisplayUpload_ then
            uploadDisplayTexture()
        end
        statusLabel:SetText("渲染完成 · " .. MaterialShowcase.statusName)
        progressBar:SetValue(1)
        reportedComplete_ = true
        printRenderStats(renderer_)
        print("[RayTracer] render complete")
    end
end

---@param eventType string
---@param eventData ScreenModeEventData
function HandleScreenMode(eventType, eventData)
    UI.MarkLayoutDirty()
    layoutDisplayCanvas()
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
