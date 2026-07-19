local EditorApp = require "Editor.AppController"

---@type table|nil
local app_ = nil

function Start()
    app_ = EditorApp.new()
    app_:start()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PostRenderUpdate", "HandlePostRenderUpdate")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    if app_ ~= nil then
        app_:update(eventData:GetFloat("TimeStep"))
    end
end

---@param eventType string
---@param eventData PostRenderUpdateEventData
function HandlePostRenderUpdate(eventType, eventData)
    if app_ ~= nil then
        app_:postRenderUpdate()
    end
end

---@param eventType string
---@param eventData ScreenModeEventData
function HandleScreenMode(eventType, eventData)
    if app_ ~= nil then
        app_:updateViewportRect()
    end
end

function Stop()
    if app_ ~= nil then
        app_:stop()
        app_ = nil
    end
end
