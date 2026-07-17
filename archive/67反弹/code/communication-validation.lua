local UI = require("urhox-libs/UI")

local CONFIG = {
    TITLE = "67反弹 · 最小通信验证",
    ENDPOINT = "http://127.0.0.1:8767/v1/frame",
    POLL_HZ = 30,
    REQUEST_TIMEOUT_MS = 800,
    CONNECTION_TIMEOUT_SEC = 1.2,
    FRAME_RESET_TIMEOUT_SEC = 2.0,
    MIN_CONFIDENCE = 0.01,
}

---@type Widget?
local uiRoot_ = nil
---@type Panel?
local arena_ = nil
---@type Panel?
local connectionBadge_ = nil
---@type Label?
local connectionLabel_ = nil
---@type Label?
local frameLabel_ = nil
---@type Label?
local rateLabel_ = nil
---@type Label?
local latencyLabel_ = nil
---@type Label?
local sourceLabel_ = nil
---@type table<integer, Panel?>
local handPanels_ = {}
---@type table<integer, Label?>
local handLabels_ = {}
---@type HttpClient?
local currentRequest_ = nil

local requestInFlight_ = false
local pollAccumulator_ = 0.0
local uiAccumulator_ = 0.0
local lastSuccessTime_ = -1000.0
local lastFrameId_ = -1
---@type number
local latestLatencyMs_ = 0.0
local receivedFrameCount_ = 0
---@type number
local receiveRate_ = 0.0
local rateWindowElapsed_ = 0.0
local lastErrorLogTime_ = -1000.0
local latestSourceText_ = "等待外部程序数据"
local latestMirrored_ = false
local acceptedHands_ = 0
local requestErrorCount_ = 0
local latestRequestError_ = "尚未收到 HTTP 响应"

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function Percent(value)
    return string.format("%.3f%%", value * 100.0)
end

local function IsFiniteNumber(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function SetHandVisible(index, visible)
    local panel = handPanels_[index]
    if panel then
        panel:SetVisible(visible)
    end
end

local function HideAllHands()
    for i = 1, #handPanels_ do
        SetHandVisible(i, false)
    end
    acceptedHands_ = 0
end

local function ApplyHand(index, hand)
    local panel = handPanels_[index]
    local label = handLabels_[index]
    if not panel or not label or type(hand) ~= "table" then
        SetHandVisible(index, false)
        return false
    end

    local x = hand.x
    local y = hand.y
    local width = hand.width
    local height = hand.height
    local confidence = hand.confidence
    if not IsFiniteNumber(x) or not IsFiniteNumber(y)
        or not IsFiniteNumber(width) or not IsFiniteNumber(height)
        or not IsFiniteNumber(confidence) or confidence < CONFIG.MIN_CONFIDENCE then
        SetHandVisible(index, false)
        return false
    end

    x = Clamp(x, 0.0, 1.0)
    y = Clamp(y, 0.0, 1.0)
    width = Clamp(width, 0.0, 1.0 - x)
    height = Clamp(height, 0.0, 1.0 - y)
    if width <= 0.001 or height <= 0.001 then
        SetHandVisible(index, false)
        return false
    end

    panel:SetStyle({
        left = Percent(x),
        top = Percent(y),
        width = Percent(width),
        height = Percent(height),
    })
    panel:SetVisible(true)
    label:SetText(string.format("轨迹 %s  ·  %.0f%%", tostring(hand.trackId or index), confidence * 100.0))
    return true
end

local function ApplyFrame(data)
    if type(data) ~= "table" or data.version ~= 1 or not IsFiniteNumber(data.frameId) then
        return false, "协议版本或 frameId 无效"
    end

    local now = time:GetElapsedTime()
    local frameId = math.floor(data.frameId)
    local connectionWasStale = now - lastSuccessTime_ >= CONFIG.FRAME_RESET_TIMEOUT_SEC
    if frameId <= lastFrameId_ and not connectionWasStale then
        return false, "过期或乱序帧"
    end

    if type(data.hands) ~= "table" then
        return false, "hands 必须是数组"
    end

    lastFrameId_ = frameId
    lastSuccessTime_ = now
    receivedFrameCount_ = receivedFrameCount_ + 1
    latestMirrored_ = data.mirrored == true

    if IsFiniteNumber(data.captureTimestampMs) then
        latestLatencyMs_ = math.max(0, time:GetTimeSinceEpochMs() - data.captureTimestampMs)
    else
        latestLatencyMs_ = 0
    end

    local sourceWidth = IsFiniteNumber(data.sourceWidth) and math.floor(data.sourceWidth) or 0
    local sourceHeight = IsFiniteNumber(data.sourceHeight) and math.floor(data.sourceHeight) or 0
    local adoptedHands = 0
    for i = 1, 2 do
        if ApplyHand(i, data.hands[i]) then
            adoptedHands = adoptedHands + 1
        end
    end
    acceptedHands_ = adoptedHands
    latestSourceText_ = string.format(
        "输入源  %d × %d  ·  镜像标记 %s  ·  已采用 %d 只手",
        sourceWidth,
        sourceHeight,
        latestMirrored_ and "是" or "否",
        acceptedHands_
    )
    return true
end

local function LogRequestError(message)
    latestRequestError_ = message
    requestErrorCount_ = requestErrorCount_ + 1

    local now = time:GetElapsedTime()
    if now - lastErrorLogTime_ >= 2.0 then
        print("[通信验证] " .. message)
        lastErrorLogTime_ = now
    end
end

local function RequestNextFrame()
    if requestInFlight_ then
        return
    end

    requestInFlight_ = true
    currentRequest_ = http:Create()
    currentRequest_:SetUrl(CONFIG.ENDPOINT)
        :SetMethod(HTTP_GET)
        :SetTimeout(CONFIG.REQUEST_TIMEOUT_MS)
        :AddHeader("Accept", "application/json")
        :OnSuccess(function(client, response)
            requestInFlight_ = false
            currentRequest_ = nil

            local body = response:GetDataAsString()
            local ok, decoded = pcall(cjson.decode, body)
            if not ok then
                LogRequestError("JSON 解析失败: " .. tostring(decoded))
                return
            end

            local accepted, reason = ApplyFrame(decoded)
            if accepted then
                latestRequestError_ = ""
                requestErrorCount_ = 0
            elseif reason ~= "过期或乱序帧" then
                LogRequestError("数据帧被拒绝: " .. tostring(reason))
            end
        end)
        :OnError(function(client, statusCode, errorMessage)
            requestInFlight_ = false
            currentRequest_ = nil
            LogRequestError(string.format("请求失败 (%d): %s", statusCode, errorMessage))
        end)
    currentRequest_:Send()
end

local function CreateStatCard(title, id, initialText, accentColor)
    return UI.Panel {
        flexGrow = 1,
        flexBasis = 0,
        flexShrink = 1,
        minWidth = 128,
        padding = 12,
        gap = 4,
        backgroundColor = { 18, 27, 43, 235 },
        borderRadius = 10,
        borderWidth = 1,
        borderColor = { accentColor[1], accentColor[2], accentColor[3], 95 },
        children = {
            UI.Label {
                text = title,
                fontSize = 10,
                fontColor = { 137, 157, 184, 255 },
                letterSpacing = 0.7,
            },
            UI.Label {
                id = id,
                text = initialText,
                fontSize = 18,
                fontWeight = "bold",
                fontColor = accentColor,
            },
        },
    }
end

local function CreateHandPanel(index, color)
    local label = UI.Label {
        text = "轨迹 -  ·  0%",
        fontSize = 11,
        fontWeight = "bold",
        fontColor = { 255, 255, 255, 255 },
        textStroke = { width = 1, color = { 0, 0, 0, 210 } },
        position = "absolute",
        top = 5,
        left = 7,
        right = 5,
    }

    local panel = UI.Panel {
        id = "hand" .. index,
        visible = false,
        position = "absolute",
        left = "10%",
        top = "20%",
        width = "18%",
        height = "28%",
        minWidth = 36,
        minHeight = 36,
        backgroundColor = { color[1], color[2], color[3], 68 },
        borderColor = { color[1], color[2], color[3], 255 },
        borderWidth = 3,
        borderRadius = 12,
        boxShadow = {
            { x = 0, y = 0, blur = 18, spread = 2, color = { color[1], color[2], color[3], 70 } },
        },
        transition = "opacity 0.15s easeOut",
        children = { label },
    }

    handPanels_[index] = panel
    handLabels_[index] = label
    return panel
end

local function CreateUI()
    connectionLabel_ = UI.Label {
        text = "等待连接",
        fontSize = 12,
        fontWeight = "bold",
        fontColor = { 255, 198, 92, 255 },
    }
    connectionBadge_ = UI.Panel {
        paddingHorizontal = 12,
        paddingVertical = 7,
        backgroundColor = { 111, 76, 20, 220 },
        borderColor = { 255, 190, 72, 150 },
        borderWidth = 1,
        borderRadius = 18,
        children = { connectionLabel_ },
    }

    local frameCard = CreateStatCard("最新帧", "frameValue", "--", { 118, 201, 255, 255 })
    local rateCard = CreateStatCard("接收帧率", "rateValue", "0.0 FPS", { 114, 242, 245, 255 })
    local latencyCard = CreateStatCard("采集延迟", "latencyValue", "-- ms", { 239, 121, 255, 255 })
    frameLabel_ = frameCard:FindById("frameValue")
    rateLabel_ = rateCard:FindById("rateValue")
    latencyLabel_ = latencyCard:FindById("latencyValue")

    sourceLabel_ = UI.Label {
        text = latestSourceText_,
        fontSize = 11,
        fontColor = { 151, 169, 194, 255 },
        maxLines = 1,
    }

    arena_ = UI.Panel {
        id = "trackingArena",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        minHeight = 240,
        overflow = "hidden",
        backgroundGradient = {
            type = "linear",
            direction = "to-bottom-right",
            from = { 9, 17, 31, 255 },
            to = { 17, 31, 48, 255 },
        },
        borderRadius = 16,
        borderWidth = 1,
        borderColor = { 67, 91, 120, 180 },
        children = {
            UI.Panel {
                position = "absolute",
                left = "50%",
                top = 0,
                bottom = 0,
                width = 1,
                backgroundColor = { 93, 123, 158, 48 },
            },
            UI.Panel {
                position = "absolute",
                left = 0,
                right = 0,
                top = "50%",
                height = 1,
                backgroundColor = { 93, 123, 158, 48 },
            },
            UI.Label {
                text = "归一化输入区域  0—1",
                position = "absolute",
                left = 14,
                bottom = 12,
                fontSize = 10,
                fontColor = { 120, 145, 173, 150 },
            },
            CreateHandPanel(1, { 48, 213, 200 }),
            CreateHandPanel(2, { 255, 102, 153 }),
        },
    }

    uiRoot_ = UI.Panel {
        width = "100%",
        height = "100%",
        padding = 20,
        gap = 14,
        backgroundGradient = {
            type = "linear",
            direction = "to-bottom",
            from = { 7, 12, 23, 255 },
            to = { 12, 22, 36, 255 },
        },
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                gap = 12,
                children = {
                    UI.Panel {
                        flexShrink = 1,
                        gap = 2,
                        children = {
                            UI.Label {
                                text = CONFIG.TITLE,
                                fontSize = 22,
                                fontWeight = "bold",
                                fontColor = { 240, 247, 255, 255 },
                            },
                            UI.Label {
                                text = "阶段一 / Loopback Input Monitor",
                                fontSize = 10,
                                fontColor = { 103, 211, 255, 220 },
                                letterSpacing = 1.0,
                            },
                        },
                    },
                    connectionBadge_,
                },
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                gap = 10,
                children = { frameCard, rateCard, latencyCard },
            },
            arena_,
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                gap = 12,
                children = {
                    sourceLabel_,
                    UI.Label {
                        text = "GET 127.0.0.1:8767/v1/frame  ·  30 Hz",
                        fontSize = 10,
                        fontColor = { 95, 121, 153, 210 },
                    },
                },
            },
        },
    }

    UI.SetRoot(uiRoot_)
end

local function RefreshStatusUI()
    if not connectionLabel_ or not connectionBadge_ or not frameLabel_
        or not rateLabel_ or not latencyLabel_ or not sourceLabel_ then
        return
    end

    local now = time:GetElapsedTime()
    local connected = now - lastSuccessTime_ < CONFIG.CONNECTION_TIMEOUT_SEC

    if connected then
        connectionLabel_:SetText(string.format("已连接 · %d 手", acceptedHands_))
        connectionLabel_:SetFontColor({ 144, 255, 185, 255 })
        connectionBadge_:SetStyle({
            backgroundColor = { 17, 83, 60, 225 },
            borderColor = { 68, 224, 153, 170 },
        })
    else
        if requestErrorCount_ > 0 then
            connectionLabel_:SetText("HTTP 请求被阻止")
            connectionLabel_:SetFontColor({ 255, 148, 148, 255 })
            connectionBadge_:SetStyle({
                backgroundColor = { 102, 31, 42, 225 },
                borderColor = { 255, 100, 119, 170 },
            })
        else
            connectionLabel_:SetText("等待外部程序")
            connectionLabel_:SetFontColor({ 255, 198, 92, 255 })
            connectionBadge_:SetStyle({
                backgroundColor = { 111, 76, 20, 220 },
                borderColor = { 255, 190, 72, 150 },
            })
        end
        HideAllHands()
    end

    frameLabel_:SetText(lastFrameId_ >= 0 and tostring(lastFrameId_) or "--")
    rateLabel_:SetText(string.format("%.1f FPS", receiveRate_))
    latencyLabel_:SetText(lastFrameId_ >= 0 and string.format("%d ms", latestLatencyMs_) or "-- ms")
    if connected then
        sourceLabel_:SetText(latestSourceText_)
    elseif requestErrorCount_ > 0 then
        sourceLabel_:SetText(string.format("%s · 请检查 CORS/PNA 响应头", latestRequestError_))
    else
        sourceLabel_:SetText("请启动 C# 外部测试程序")
    end
end

function Start()
    graphics.windowTitle = CONFIG.TITLE
    input.mouseMode = MM_ABSOLUTE

    UI.Init({
        theme = "default-dark",
        fonts = {
            {
                family = "sans",
                weights = {
                    normal = "Fonts/MiSans-Regular.ttf",
                    bold = "Fonts/MiSans-Regular.ttf",
                },
            },
        },
        scale = UI.Scale.DEFAULT,
    })
    CreateUI()

    SubscribeToEvent("Update", "HandleUpdate")
    print("[通信验证] 内部程序启动")
    print("[通信验证] 正在轮询 " .. CONFIG.ENDPOINT)
end

function Stop()
    if currentRequest_ then
        currentRequest_:Cancel()
        currentRequest_ = nil
    end
    requestInFlight_ = false
    UI.Shutdown()
    print("[通信验证] 内部程序已停止")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local timeStep = eventData:GetFloat("TimeStep")

    pollAccumulator_ = pollAccumulator_ + timeStep
    local pollInterval = 1.0 / CONFIG.POLL_HZ
    if pollAccumulator_ >= pollInterval then
        pollAccumulator_ = pollAccumulator_ % pollInterval
        RequestNextFrame()
    end

    rateWindowElapsed_ = rateWindowElapsed_ + timeStep
    if rateWindowElapsed_ >= 1.0 then
        receiveRate_ = receivedFrameCount_ / rateWindowElapsed_
        receivedFrameCount_ = 0
        rateWindowElapsed_ = 0.0
        if time:GetElapsedTime() - lastSuccessTime_ < CONFIG.CONNECTION_TIMEOUT_SEC then
            print(string.format(
                "[通信验证] frame=%d rate=%.1f latency=%dms hands=%d mirrored=%s",
                lastFrameId_, receiveRate_, latestLatencyMs_, acceptedHands_, tostring(latestMirrored_)
            ))
        end
    end

    uiAccumulator_ = uiAccumulator_ + timeStep
    if uiAccumulator_ >= 0.1 then
        uiAccumulator_ = 0.0
        RefreshStatusUI()
    end
end
