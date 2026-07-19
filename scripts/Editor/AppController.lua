local UI = require "urhox-libs/UI"
local SceneDocument = require "Editor.SceneDocument"
local RealtimeSceneAdapter = require "Editor.RealtimeSceneAdapter"
local EditorCameraController = require "Editor.EditorCameraController"
local GizmoController = require "Editor.GizmoController"
local EditorWorkspace = require "Editor.UI.EditorWorkspace"
local JsonSceneLoader = require "SceneFormat.JsonSceneLoader"
local RenderMode = require "render_legacy"

local EditorApp = {}
EditorApp.__index = EditorApp

local function vectorTable(value)
    return { value.x, value.y, value.z }
end

function EditorApp.new()
    return setmetatable({
        document = nil,
        adapter = nil,
        cameraController = nil,
        gizmo = nil,
        workspace = nil,
        viewportRect = { left = 0, top = 0, width = 1, height = 1 },
        viewportHovered = false,
        selectedId = nil,
        mode = "editor",
    }, EditorApp)
end

function EditorApp:start()
    graphics.windowTitle = "CPU Ray Tracer · Scene Editor"
    input.mouseMode = MM_ABSOLUTE
    self.document = SceneDocument.load(
        "Scenes/MaterialShowcase.json",
        "scene-editor/MaterialShowcase.json"
    )
    self:startEditorWorkspace()
end

function EditorApp:buildEditorPreview()
    self.adapter = RealtimeSceneAdapter.new(self.document)
    self.adapter:build()
    self.cameraController = EditorCameraController.new(
        self.adapter:getCameraNode()
    )
    self.gizmo = GizmoController.new(self.document, self.adapter)
end

function EditorApp:enterRenderMode()
    if self.mode == "render" then
        return
    end
    local provider = JsonSceneLoader.compileDocument(
        self.document:snapshot(),
        "SceneEditorMemory"
    )
    self.mode = "render"
    self.adapter:dispose()
    self.adapter = nil
    self.cameraController = nil
    self.gizmo = nil
    self.workspace = nil
    UI.Shutdown()
    RenderMode.start {
        sceneProvider = provider,
        onBack = function()
            self:returnToEditor()
        end,
    }
end

function EditorApp:returnToEditor()
    if self.mode ~= "render" then
        return
    end
    RenderMode.stop()
    UI.Shutdown()
    self.mode = "editor"
    self:startEditorWorkspace()
end

function EditorApp:startEditorWorkspace()
    UI.Init {
        theme = "default-taptap",
        fonts = {
            {
                family = "sans",
                weights = {
                    normal = "Fonts/NotoSansSC-Black.ttf",
                    bold = "Fonts/NotoSansSC-Black.ttf",
                },
            },
        },
        scale = UI.Scale.DEFAULT,
    }
    self:buildEditorPreview()

    self.workspace = EditorWorkspace.build(UI, {
        document = self.document,
        onAddObject = function(objectType)
            local object = self.document:addObject(objectType)
            self.adapter:createObject(object)
            self.workspace.refreshHierarchy()
            self.workspace.setStatus("已添加 " .. object.name)
            return object.id
        end,
        onSelectObject = function(id)
            self.selectedId = id
            self.adapter:select(id)
            self.gizmo:setSelected(id)
        end,
        onObjectChanged = function(id)
            self.adapter:updateObject(id)
        end,
        onObjectRemoved = function(id)
            self.adapter:removeObject(id)
            self.selectedId = nil
            self.gizmo:setSelected(nil)
        end,
        onMaterialChanged = function(name)
            self.adapter:refreshMaterial(name)
        end,
        onMaterialRemoved = function(name)
            self.adapter.materialFactory:invalidate(name)
            self.adapter:rebuildObjects()
        end,
        onToolChanged = function(tool)
            self.gizmo:setTool(tool)
            self.workspace.setStatus("变换工具 · " .. string.upper(tool))
        end,
        onUseRenderCamera = function()
            self.cameraController:useRenderCamera(
                self.document:getData().camera
            )
        end,
        onCaptureRenderCamera = function()
            local camera = self.adapter:getCameraNode()
            local cameraData = self.document:getData().camera
            cameraData.lookFrom = vectorTable(camera.position)
            cameraData.lookAt = vectorTable(
                camera.position + camera.direction * 10
            )
            cameraData.up = { 0, 1, 0 }
            self.document:markDirty()
            self.workspace.setStatus("已将当前视角写入渲染摄像机")
        end,
        onRestoreBuiltIn = function()
            self.document:restoreBuiltIn()
            self.adapter.materialFactory:clear()
            self.adapter:rebuildObjects()
            self.selectedId = nil
            self.adapter:select(nil)
            self.gizmo:setSelected(nil)
        end,
        onRenderRequested = function()
            self:enterRenderMode()
        end,
    })
    UI.SetRoot(self.workspace.root)
    UI.MarkLayoutDirty()
    self:updateViewportRect()

    print(string.format(
        "[Editor] started: source=%s objects=%d",
        self.document.sourcePath,
        #self.document:getObjects()
    ))
end

function EditorApp:stop()
    if self.mode == "render" then
        RenderMode.stop()
    elseif self.adapter ~= nil then
        self.adapter:dispose()
        self.adapter = nil
    end
    if UI.GetRoot() ~= nil then
        UI.Shutdown()
    end
end

function EditorApp:updateViewportRect()
    if self.mode == "render" then
        RenderMode.screenMode()
        return
    end
    if self.workspace == nil or self.adapter == nil then
        return
    end
    UI.Layout()
    local bounds = self.workspace.viewport:GetAbsoluteLayout()
    local scale = UI.GetScale()
    local left = math.floor(bounds.x * scale + 0.5)
    local top = math.floor(bounds.y * scale + 0.5)
    local width = math.max(1, math.floor(bounds.w * scale + 0.5))
    local height = math.max(1, math.floor(bounds.h * scale + 0.5))
    self.viewportRect = {
        left = left,
        top = top,
        width = width,
        height = height,
    }
    self.adapter:setViewportRect(IntRect(left, top, left + width, top + height))
end

function EditorApp:isMouseInViewport(mouse)
    local rect = self.viewportRect
    return mouse.x >= rect.left
        and mouse.y >= rect.top
        and mouse.x < rect.left + rect.width
        and mouse.y < rect.top + rect.height
end

function EditorApp:normalizedMouse(mouse)
    local rect = self.viewportRect
    return (mouse.x - rect.left) / rect.width,
        (mouse.y - rect.top) / rect.height
end

function EditorApp:handlePointer()
    local mouse = input:GetMousePosition()
    self.viewportHovered = self:isMouseInViewport(mouse)
    if not self.viewportHovered or input:GetMouseButtonDown(MOUSEB_RIGHT) then
        return
    end

    if input:GetMouseButtonPress(MOUSEB_LEFT) then
        local axis = self.gizmo:hitAxis(
            mouse.x,
            mouse.y,
            self.viewportRect
        )
        if axis ~= nil and self.selectedId ~= nil then
            self.gizmo:beginDrag(axis, mouse.x, mouse.y)
            return
        end
        local x, y = self:normalizedMouse(mouse)
        local id = self.adapter:pick(x, y)
        self.workspace.selectObject(id)
    elseif self.gizmo:isDragging()
            and input:GetMouseButtonDown(MOUSEB_LEFT) then
        if self.gizmo:updateDrag(mouse.x, mouse.y) then
            self.workspace.refreshInspector()
        end
    end

    if input:GetMouseButtonRelease(MOUSEB_LEFT) then
        self.gizmo:endDrag()
    end
end

function EditorApp:update(timeStep)
    if self.mode == "render" then
        RenderMode.update(timeStep)
        return
    end
    self:updateViewportRect()
    self:handlePointer()
    self.cameraController:update(timeStep, self.viewportHovered, false)

    if input:GetKeyPress(KEY_F) and self.selectedId ~= nil then
        self.cameraController:focus(
            self.adapter:getObjectCenter(self.selectedId),
            8
        )
    end
end

function EditorApp:postRenderUpdate()
    if self.mode == "editor" and self.adapter ~= nil then
        self.adapter:drawDebug(self.gizmo.tool)
    end
end

return EditorApp
