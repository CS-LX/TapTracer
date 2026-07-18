local AOVAtrous = {}

local FILTERABLE_CLASSES = {
    diffuse = true,
    glossy = true,
}

local KERNEL_3X3 = {
    { -1, -1, 1 }, { 0, -1, 2 }, { 1, -1, 1 },
    { -1, 0, 2 }, { 0, 0, 4 }, { 1, 0, 2 },
    { -1, 1, 1 }, { 0, 1, 2 }, { 1, 1, 1 },
}

local function buildSeparableKernel(weights)
    local kernel = {}
    local radius = math.floor(#weights * 0.5)
    for y = -radius, radius do
        for x = -radius, radius do
            kernel[#kernel + 1] = {
                x,
                y,
                weights[x + radius + 1]
                    * weights[y + radius + 1],
            }
        end
    end
    return kernel
end

local KERNEL_5X5 = buildSeparableKernel({ 1, 4, 6, 4, 1 })
local KERNELS = {
    ["3x3"] = KERNEL_3X3,
    ["5x5"] = KERNEL_5X5,
}
local DEFAULT_KERNEL = "3x3"

local COVERAGE_THRESHOLD = 0.125
local NORMAL_CUTOFF = 0.7
local NORMAL_POWER = 8
local DEPTH_BASE_SCALE = 0.002
local DEPTH_GRADIENT_RELATIVE_LIMIT = 0.05
local DEPTH_HARD_STOP_SIGMA = 4
local VARIANCE_FLOOR = 0.02
local HDR_SIGMA_LIMIT = 3.0

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function luminance(r, g, b)
    return r * 0.2126 + g * 0.7152 + b * 0.0722
end

local function pixelIndex(width, x, y)
    return y * width + x + 1
end

local function compatibleDepth(guides, width, height, x, y, center)
    if x < 0 or x >= width or y < 0 or y >= height then
        return nil
    end
    local sample = guides[pixelIndex(width, x, y)]
    if not sample.hit
            or sample.class ~= center.class
            or math.abs(sample.coverage - center.coverage)
                > COVERAGE_THRESHOLD then
        return nil
    end
    return sample.depth
end

local function axisDepthGradient(negativeDepth, centerDepth, positiveDepth)
    if negativeDepth ~= nil and positiveDepth ~= nil then
        return (positiveDepth - negativeDepth) * 0.5
    end
    if positiveDepth ~= nil then
        return positiveDepth - centerDepth
    end
    if negativeDepth ~= nil then
        return centerDepth - negativeDepth
    end
    return 0
end

local function buildBuffers(film, aov)
    local width = film.width
    local height = film.height
    local pixels = {}
    local guides = {}

    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local index = pixelIndex(width, x, y)
            local r, g, b = film:get(x, y)
            local hit, albedo, normal, depth, coverage = aov:get(x, y)
            local meanLuminance, meanVariance = film:getMeanLuminanceVariance(x, y)
            pixels[index] = { r = r, g = g, b = b }
            guides[index] = {
                hit = hit,
                albedo = albedo,
                normal = normal,
                depth = depth,
                coverage = coverage,
                class = aov:getDenoiseClass(x, y),
                meanLuminance = meanLuminance,
                meanVariance = meanVariance,
                depthGradientX = 0,
                depthGradientY = 0,
            }
        end
    end

    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local index = pixelIndex(width, x, y)
            local center = guides[index]
            if center.hit and FILTERABLE_CLASSES[center.class] then
                local negativeX = compatibleDepth(
                    guides, width, height, x - 1, y, center)
                local positiveX = compatibleDepth(
                    guides, width, height, x + 1, y, center)
                local negativeY = compatibleDepth(
                    guides, width, height, x, y - 1, center)
                local positiveY = compatibleDepth(
                    guides, width, height, x, y + 1, center)
                local gradientLimit = math.max(
                    0.001,
                    math.abs(center.depth)
                        * DEPTH_GRADIENT_RELATIVE_LIMIT
                )
                center.depthGradientX = clamp(
                    axisDepthGradient(negativeX, center.depth, positiveX),
                    -gradientLimit,
                    gradientLimit
                )
                center.depthGradientY = clamp(
                    axisDepthGradient(negativeY, center.depth, positiveY),
                    -gradientLimit,
                    gradientLimit
                )
            end
        end
    end

    return pixels, guides
end

local function normalWeight(centerNormal, sampleNormal)
    local cosine = clamp(
        centerNormal.x * sampleNormal.x
            + centerNormal.y * sampleNormal.y
            + centerNormal.z * sampleNormal.z,
        0,
        1
    )
    if cosine <= NORMAL_CUTOFF then
        return 0
    end
    local normalized = (cosine - NORMAL_CUTOFF) / (1 - NORMAL_CUTOFF)
    return normalized ^ NORMAL_POWER
end

local function depthWeight(center, sample, offsetX, offsetY)
    local actualDelta = sample.depth - center.depth
    local gradientX = (center.depthGradientX + sample.depthGradientX) * 0.5
    local gradientY = (center.depthGradientY + sample.depthGradientY) * 0.5
    local predictedDelta = gradientX * offsetX + gradientY * offsetY
    local residual = math.abs(actualDelta - predictedDelta)
    local spatialDistance = math.sqrt(offsetX * offsetX + offsetY * offsetY)
    local baseTolerance = math.max(
        0.001,
        math.abs(center.depth) * DEPTH_BASE_SCALE
    ) * math.max(1, spatialDistance)
    local tolerance = baseTolerance + math.abs(predictedDelta) * 0.1
    local normalizedResidual = residual / math.max(tolerance, 1e-8)
    if normalizedResidual >= DEPTH_HARD_STOP_SIGMA then
        return 0
    end
    return math.exp(-normalizedResidual * normalizedResidual * 0.5)
end

local function varianceColorWeight(centerPixel, samplePixel, centerGuide, sampleGuide)
    local centerLuminance = luminance(centerPixel.r, centerPixel.g, centerPixel.b)
    local sampleLuminance = luminance(samplePixel.r, samplePixel.g, samplePixel.b)
    local sigma = math.sqrt(math.max(
        0,
        centerGuide.meanVariance + sampleGuide.meanVariance
    )) + VARIANCE_FLOOR * (1 + centerGuide.meanLuminance)
    local luminanceDifference = math.abs(centerLuminance - sampleLuminance)
    local normalizedLuminance = luminanceDifference / math.max(sigma, 1e-6)
    local colorScale = 0.1 + math.max(centerLuminance, sampleLuminance)
    local colorDifference = (
        math.abs(centerPixel.r - samplePixel.r)
            + math.abs(centerPixel.g - samplePixel.g)
            + math.abs(centerPixel.b - samplePixel.b)
    ) / colorScale
    return 1 / (
        1
            + normalizedLuminance * normalizedLuminance
            + colorDifference * colorDifference
    ), centerLuminance, sampleLuminance, sigma
end

local function robustHDRWeight(centerLuminance, sampleLuminance, sigma)
    local excess = sampleLuminance - centerLuminance
    local limit = HDR_SIGMA_LIMIT * sigma
        + VARIANCE_FLOOR * (1 + centerLuminance)
    if excess <= limit then
        return 1
    end
    return clamp(limit / math.max(excess, 1e-8), 0, 1)
end

local function guidedWeight(centerPixel, samplePixel, centerGuide, sampleGuide,
        spatialWeight, offsetX, offsetY)
    if not sampleGuide.hit
            or sampleGuide.class ~= centerGuide.class
            or math.abs(sampleGuide.coverage - centerGuide.coverage)
                > COVERAGE_THRESHOLD then
        return 0
    end

    local normal = normalWeight(centerGuide.normal, sampleGuide.normal)
    if normal <= 0 then
        return 0
    end

    local depth = depthWeight(centerGuide, sampleGuide, offsetX, offsetY)
    if depth <= 0 then
        return 0
    end

    local albedoDifference = math.abs(centerGuide.albedo.x - sampleGuide.albedo.x)
        + math.abs(centerGuide.albedo.y - sampleGuide.albedo.y)
        + math.abs(centerGuide.albedo.z - sampleGuide.albedo.z)
    local albedo = 1 / (1 + albedoDifference * 8)
    local color, centerLuminance, sampleLuminance, sigma = varianceColorWeight(
        centerPixel,
        samplePixel,
        centerGuide,
        sampleGuide
    )
    local robust = robustHDRWeight(centerLuminance, sampleLuminance, sigma)
    return spatialWeight * normal * depth * albedo * color * robust
end

local function resolveOptions(options)
    if type(options) == "number" or options == nil then
        return math.max(1, math.floor(options or 2)), DEFAULT_KERNEL
    end
    local passes = math.max(1, math.floor(options.iterations or 2))
    local kernelName = options.kernel or DEFAULT_KERNEL
    if KERNELS[kernelName] == nil then
        error("Unknown A-Trous kernel: " .. tostring(kernelName))
    end
    return passes, kernelName
end

function AOVAtrous.getKernelInfo(name)
    local kernelName = name or DEFAULT_KERNEL
    local kernel = KERNELS[kernelName]
    if kernel == nil then
        return nil
    end
    local weightSum = 0
    for index = 1, #kernel do
        weightSum = weightSum + kernel[index][3]
    end
    return {
        name = kernelName,
        taps = #kernel,
        weightSum = weightSum,
    }
end

function AOVAtrous.filter(film, aov, options)
    local width = film.width
    local height = film.height
    local source, guides = buildBuffers(film, aov)
    local passes, kernelName = resolveOptions(options)
    local kernel = KERNELS[kernelName]
    local candidateVisits = 0
    local acceptedVisits = 0

    for pass = 1, passes do
        local step = 2 ^ (pass - 1)
        local target = {}
        for y = 0, height - 1 do
            for x = 0, width - 1 do
                local centerIndex = pixelIndex(width, x, y)
                local centerPixel = source[centerIndex]
                local centerGuide = guides[centerIndex]
                if not centerGuide.hit
                        or not FILTERABLE_CLASSES[centerGuide.class] then
                    target[centerIndex] = centerPixel
                else
                    local red = 0
                    local green = 0
                    local blue = 0
                    local totalWeight = 0
                    for kernelIndex = 1, #kernel do
                        local kernelTap = kernel[kernelIndex]
                        local sampleX = x + kernelTap[1] * step
                        local sampleY = y + kernelTap[2] * step
                        if sampleX >= 0 and sampleX < width
                                and sampleY >= 0 and sampleY < height then
                            local sampleIndex = pixelIndex(width, sampleX, sampleY)
                            local samplePixel = source[sampleIndex]
                            candidateVisits = candidateVisits + 1
                            local offsetX = kernelTap[1] * step
                            local offsetY = kernelTap[2] * step
                            local weight = guidedWeight(
                                centerPixel,
                                samplePixel,
                                centerGuide,
                                guides[sampleIndex],
                                kernelTap[3],
                                offsetX,
                                offsetY
                            )
                            if weight > 0 then
                                acceptedVisits = acceptedVisits + 1
                            end
                            red = red + samplePixel.r * weight
                            green = green + samplePixel.g * weight
                            blue = blue + samplePixel.b * weight
                            totalWeight = totalWeight + weight
                        end
                    end
                    if totalWeight > 0 then
                        target[centerIndex] = {
                            r = math.max(0, red / totalWeight),
                            g = math.max(0, green / totalWeight),
                            b = math.max(0, blue / totalWeight),
                        }
                    else
                        target[centerIndex] = centerPixel
                    end
                end
            end
        end
        source = target
    end

    return {
        width = width,
        height = height,
        pixels = source,
        stats = {
            kernel = kernelName,
            taps = #kernel,
            passes = passes,
            candidateVisits = candidateVisits,
            acceptedVisits = acceptedVisits,
        },
        get = function(self, x, y)
            local pixel = self.pixels[pixelIndex(self.width, x, y)]
            return pixel.r, pixel.g, pixel.b
        end,
    }
end

return AOVAtrous
