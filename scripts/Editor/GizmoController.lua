local GizmoController = {}
GizmoController.__index = GizmoController

local AXES = {
    x = { vector = Vector3.RIGHT, index = 1 },
    y = { vector = Vector3.UP, index = 2 },
    z = { vector = Vector3.FORWARD, index = 3 },
}

local function copyVector(value)
    return { value[1], value[2], value[3] }
end

local function objectCenter(object)
    if object.type == "sphere" then
        return copyVector(object.center)
    elseif object.type == "box" then
        return {
            (object.minimum[1] + object.maximum[1]) * 0.5,
            (object.minimum[2] + object.maximum[2]) * 0.5,
            (object.minimum[3] + object.maximum[3]) * 0.5,
        }
    end
    return {
        object.origin[1] + (object.edgeU[1] + object.edgeV[1]) * 0.5,
        object.origin[2] + (object.edgeU[2] + object.edgeV[2]) * 0.5,
        object.origin[3] + (object.edgeU[3] + object.edgeV[3]) * 0.5,
    }
end

local function distanceToSegment(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local lengthSquared = dx * dx + dy * dy
    if lengthSquared <= 0.0001 then
        return math.sqrt((px - ax) ^ 2 + (py - ay) ^ 2)
    end
    local t = ((px - ax) * dx + (py - ay) * dy) / lengthSquared
    t = math.max(0, math.min(1, t))
    local x, y = ax + dx * t, ay + dy * t
    return math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
end

function GizmoController.new(document, adapter)
    return setmetatable({
        document = document,
        adapter = adapter,
        tool = "move",
        selectedId = nil,
        drag = nil,
        axisLength = 2,
    }, GizmoController)
end

function GizmoController:setTool(tool)
    assert(tool == "move" or tool == "scale")
    self.tool = tool
    self.drag = nil
end

function GizmoController:setSelected(id)
    self.selectedId = id
    self.drag = nil
end

function GizmoController:hitAxis(mouseX, mouseY, viewportRect)
    local object = self.document:findObject(self.selectedId)
    local camera = self.adapter:getCamera()
    if object == nil or camera == nil then
        return nil
    end
    local center = objectCenter(object)
    local worldCenter = Vector3(center[1], center[2], center[3])
    local screenCenter = camera:WorldToScreenPoint(worldCenter)
    local centerX = viewportRect.left + screenCenter.x * viewportRect.width
    local centerY = viewportRect.top + screenCenter.y * viewportRect.height
    local bestAxis, bestDistance = nil, 10
    for name, axis in pairs(AXES) do
        local endpoint = camera:WorldToScreenPoint(
            worldCenter + axis.vector * self.axisLength
        )
        local endpointX = viewportRect.left + endpoint.x * viewportRect.width
        local endpointY = viewportRect.top + endpoint.y * viewportRect.height
        local distance = distanceToSegment(
            mouseX, mouseY, centerX, centerY, endpointX, endpointY
        )
        if distance < bestDistance then
            bestAxis, bestDistance = name, distance
        end
    end
    return bestAxis
end

function GizmoController:beginDrag(axisName, mouseX, mouseY)
    local object = self.document:findObject(self.selectedId)
    local axis = AXES[axisName]
    if object == nil or axis == nil then
        return false
    end
    self.drag = {
        axis = axisName,
        startX = mouseX,
        startY = mouseY,
        object = {
            minimum = object.minimum and copyVector(object.minimum),
            maximum = object.maximum and copyVector(object.maximum),
            center = object.center and copyVector(object.center),
            radius = object.radius,
            origin = object.origin and copyVector(object.origin),
            edgeU = object.edgeU and copyVector(object.edgeU),
            edgeV = object.edgeV and copyVector(object.edgeV),
        },
    }
    return true
end

function GizmoController:updateDrag(mouseX, mouseY)
    local drag = self.drag
    local object = self.document:findObject(self.selectedId)
    if drag == nil or object == nil then
        return false
    end
    local delta = ((mouseX - drag.startX) - (mouseY - drag.startY)) * 0.025
    local axis = AXES[drag.axis]
    local index = axis.index

    if self.tool == "move" then
        if object.type == "sphere" then
            object.center = copyVector(drag.object.center)
            object.center[index] = object.center[index] + delta
        elseif object.type == "box" then
            object.minimum = copyVector(drag.object.minimum)
            object.maximum = copyVector(drag.object.maximum)
            object.minimum[index] = object.minimum[index] + delta
            object.maximum[index] = object.maximum[index] + delta
        else
            object.origin = copyVector(drag.object.origin)
            object.origin[index] = object.origin[index] + delta
        end
    elseif object.type == "sphere" then
        object.radius = math.max(0.05, drag.object.radius + delta)
    elseif object.type == "box" then
        local center = {
            (drag.object.minimum[index] + drag.object.maximum[index]) * 0.5
        }
        local halfSize = math.max(0.025,
            (drag.object.maximum[index] - drag.object.minimum[index]) * 0.5 + delta)
        object.minimum = copyVector(drag.object.minimum)
        object.maximum = copyVector(drag.object.maximum)
        object.minimum[index] = center[1] - halfSize
        object.maximum[index] = center[1] + halfSize
    else
        object.edgeU = copyVector(drag.object.edgeU)
        object.edgeV = copyVector(drag.object.edgeV)
        local target = math.abs(object.edgeU[index]) > math.abs(object.edgeV[index])
            and object.edgeU or object.edgeV
        local sign = target[index] < 0 and -1 or 1
        target[index] = sign * math.max(0.05, math.abs(target[index]) + delta)
    end

    self.document:markDirty()
    self.adapter:updateObject(self.selectedId)
    return true
end

function GizmoController:endDrag()
    self.drag = nil
end

function GizmoController:isDragging()
    return self.drag ~= nil
end

return GizmoController
