local EditorCameraController = {}
EditorCameraController.__index = EditorCameraController

local function syncAngles(controller)
    local rotation = controller.node.rotation
    controller.yaw = rotation:YawAngle()
    controller.pitch = rotation:PitchAngle()
end

function EditorCameraController.new(cameraNode)
    local controller = setmetatable({
        node = cameraNode,
        yaw = 0,
        pitch = 0,
        speed = 12,
        sensitivity = 0.12,
    }, EditorCameraController)
    syncAngles(controller)
    return controller
end

function EditorCameraController:applyLookDelta(deltaX, deltaY)
    self.yaw = self.yaw + deltaX * self.sensitivity
    self.pitch = Clamp(
        self.pitch + deltaY * self.sensitivity,
        -89,
        89
    )
    self.node.rotation = Quaternion(self.pitch, self.yaw, 0)
end

function EditorCameraController:update(timeStep, viewportHovered, inputBlocked)
    if inputBlocked or not viewportHovered then
        return
    end

    if input:GetMouseButtonDown(MOUSEB_RIGHT) then
        self:applyLookDelta(input.mouseMoveX, input.mouseMoveY)

        local speed = self.speed * timeStep
        if input:GetKeyDown(KEY_SHIFT) then
            speed = speed * 3
        end
        if input:GetKeyDown(KEY_W) then
            self.node:Translate(Vector3.FORWARD * speed)
        end
        if input:GetKeyDown(KEY_S) then
            self.node:Translate(-Vector3.FORWARD * speed)
        end
        if input:GetKeyDown(KEY_A) then
            self.node:Translate(-Vector3.RIGHT * speed)
        end
        if input:GetKeyDown(KEY_D) then
            self.node:Translate(Vector3.RIGHT * speed)
        end
        if input:GetKeyDown(KEY_SPACE) then
            self.node:Translate(Vector3.UP * speed, TS_WORLD)
        end
        if input:GetKeyDown(KEY_C) then
            self.node:Translate(-Vector3.UP * speed, TS_WORLD)
        end
    end
end

function EditorCameraController:focus(point, distance)
    if point == nil then
        return
    end
    local direction = self.node.direction
    self.node.position = point - direction * (distance or 8)
    self.node:LookAt(point, Vector3.UP, TS_WORLD)
    syncAngles(self)
end

function EditorCameraController:useRenderCamera(cameraData)
    self.node.position = Vector3(
        cameraData.lookFrom[1],
        cameraData.lookFrom[2],
        cameraData.lookFrom[3]
    )
    self.node:LookAt(Vector3(
        cameraData.lookAt[1],
        cameraData.lookAt[2],
        cameraData.lookAt[3]
    ), Vector3(
        cameraData.up[1],
        cameraData.up[2],
        cameraData.up[3]
    ), TS_WORLD)
    syncAngles(self)
end

return EditorCameraController
