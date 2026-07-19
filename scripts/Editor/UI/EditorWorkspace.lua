local EditorWorkspace = {}

local PANEL = { 13, 22, 32, 238 }
local PANEL_ALT = { 18, 30, 43, 245 }
local BORDER = { 64, 84, 103, 150 }
local TEXT = { 226, 236, 245, 255 }
local MUTED = { 135, 157, 177, 255 }
local ACCENT = { 45, 212, 191, 255 }

local function sectionTitle(UI, text)
    return UI.Label {
        text = text,
        height = 24,
        fontSize = 11,
        fontWeight = "bold",
        fontColor = MUTED,
        letterSpacing = 1.1,
        verticalAlign = "middle",
    }
end

local function compactButton(UI, text, onClick, variant)
    return UI.Button {
        text = text,
        variant = variant or "secondary",
        height = 30,
        fontSize = 10,
        paddingHorizontal = 8,
        flexGrow = 1,
        flexShrink = 1,
        onClick = onClick,
    }
end

local function numericField(UI, label, value, onChange)
    local field = UI.TextField {
        value = string.format("%.3f", value),
        height = 28,
        fontSize = 10,
        flexGrow = 1,
        flexShrink = 1,
        onSubmit = function(self, text)
            local number = tonumber(text)
            if number ~= nil then
                onChange(number)
            else
                self:SetValue(string.format("%.3f", value))
            end
        end,
    }
    return UI.Panel {
        height = 30,
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        children = {
            UI.Label {
                text = label,
                width = 66,
                fontSize = 9,
                fontColor = MUTED,
                verticalAlign = "middle",
            },
            field,
        },
    }
end

local function vectorFields(UI, title, value, onChange)
    local children = { sectionTitle(UI, title) }
    local labels = { "X", "Y", "Z" }
    for index = 1, 3 do
        children[#children + 1] = numericField(UI, labels[index], value[index], function(number)
            local nextValue = { value[1], value[2], value[3] }
            nextValue[index] = number
            onChange(nextValue)
        end)
    end
    return UI.Panel { gap = 3, children = children }
end

local function materialOptions(document)
    local options = {}
    for name in pairs(document:getMaterials()) do
        options[#options + 1] = { value = name, label = name }
    end
    table.sort(options, function(a, b) return a.label < b.label end)
    return options
end

function EditorWorkspace.build(UI, options)
    local document = options.document
    local state = {
        selectedObjectId = nil,
        selectedMaterial = nil,
        inspectorMode = "scene",
    }

    local hierarchyList = UI.Panel { gap = 3 }
    local materialList = UI.Panel { gap = 3 }
    local inspectorContent = UI.Panel { gap = 7 }
    local statusLabel = UI.Label {
        text = "编辑模式 · 实时预览",
        fontSize = 10,
        fontColor = MUTED,
        flexGrow = 1,
        flexShrink = 1,
        verticalAlign = "middle",
    }

    local function setStatus(text)
        statusLabel:SetText(text)
        if options.onStatus ~= nil then
            options.onStatus(text)
        end
    end

    local refreshInspector
    local refreshHierarchy
    local refreshMaterials

    local function selectObject(id)
        state.selectedObjectId = id
        state.selectedMaterial = nil
        state.inspectorMode = "object"
        options.onSelectObject(id)
        refreshHierarchy()
        refreshInspector()
    end

    local function selectMaterial(name)
        state.selectedObjectId = nil
        state.selectedMaterial = name
        state.inspectorMode = "material"
        options.onSelectObject(nil)
        refreshHierarchy()
        refreshMaterials()
        refreshInspector()
    end

    refreshHierarchy = function()
        hierarchyList:ClearChildren()
        for _, object in ipairs(document:getObjects()) do
            local selected = object.id == state.selectedObjectId
            hierarchyList:AddChild(UI.Button {
                text = string.format("%s  ·  %s", object.name, object.type),
                height = 28,
                fontSize = 9,
                textAlign = "left",
                backgroundColor = selected and { 32, 91, 102, 255 } or PANEL_ALT,
                textColor = selected and { 210, 255, 248, 255 } or TEXT,
                onClick = function() selectObject(object.id) end,
            })
        end
    end

    refreshMaterials = function()
        materialList:ClearChildren()
        local names = {}
        for name in pairs(document:getMaterials()) do
            names[#names + 1] = name
        end
        table.sort(names)
        for _, name in ipairs(names) do
            local descriptor = document:getMaterials()[name]
            local selected = name == state.selectedMaterial
            materialList:AddChild(UI.Button {
                text = string.format("%s  ·  %s  ·  %d", name, descriptor.type,
                    document:materialUsage(name)),
                height = 28,
                fontSize = 9,
                textAlign = "left",
                backgroundColor = selected and { 32, 91, 102, 255 } or PANEL_ALT,
                textColor = selected and { 210, 255, 248, 255 } or TEXT,
                onClick = function() selectMaterial(name) end,
            })
        end
    end

    local function refreshObjectInspector(object)
        inspectorContent:AddChild(UI.Label {
            text = object.name,
            fontSize = 15,
            fontWeight = "bold",
            fontColor = TEXT,
            height = 28,
        })
        inspectorContent:AddChild(UI.Label {
            text = string.upper(object.type) .. "  /  " .. object.id,
            fontSize = 9,
            fontColor = ACCENT,
            height = 20,
        })
        inspectorContent:AddChild(UI.Dropdown {
            value = object.material,
            options = materialOptions(document),
            height = 32,
            onChange = function(_, value)
                document:updateObject(object.id, { material = value })
                options.onObjectChanged(object.id)
                setStatus("已更换材质 · " .. value)
            end,
        })

        if object.type == "sphere" then
            inspectorContent:AddChild(vectorFields(UI, "POSITION", object.center, function(value)
                document:updateObject(object.id, { center = value })
                options.onObjectChanged(object.id)
                refreshInspector()
            end))
            inspectorContent:AddChild(numericField(UI, "Radius", object.radius, function(value)
                document:updateObject(object.id, { radius = math.max(0.05, value) })
                options.onObjectChanged(object.id)
                refreshInspector()
            end))
        elseif object.type == "box" then
            local center = {
                (object.minimum[1] + object.maximum[1]) * 0.5,
                (object.minimum[2] + object.maximum[2]) * 0.5,
                (object.minimum[3] + object.maximum[3]) * 0.5,
            }
            local size = {
                object.maximum[1] - object.minimum[1],
                object.maximum[2] - object.minimum[2],
                object.maximum[3] - object.minimum[3],
            }
            inspectorContent:AddChild(vectorFields(UI, "POSITION", center, function(value)
                local half = { size[1] * 0.5, size[2] * 0.5, size[3] * 0.5 }
                document:updateObject(object.id, {
                    minimum = { value[1] - half[1], value[2] - half[2], value[3] - half[3] },
                    maximum = { value[1] + half[1], value[2] + half[2], value[3] + half[3] },
                })
                options.onObjectChanged(object.id)
                refreshInspector()
            end))
            inspectorContent:AddChild(vectorFields(UI, "SIZE", size, function(value)
                local half = {
                    math.max(0.05, value[1]) * 0.5,
                    math.max(0.05, value[2]) * 0.5,
                    math.max(0.05, value[3]) * 0.5,
                }
                document:updateObject(object.id, {
                    minimum = { center[1] - half[1], center[2] - half[2], center[3] - half[3] },
                    maximum = { center[1] + half[1], center[2] + half[2], center[3] + half[3] },
                })
                options.onObjectChanged(object.id)
                refreshInspector()
            end))
        else
            inspectorContent:AddChild(vectorFields(UI, "ORIGIN", object.origin, function(value)
                document:updateObject(object.id, { origin = value })
                options.onObjectChanged(object.id)
                refreshInspector()
            end))
            inspectorContent:AddChild(vectorFields(UI, "EDGE U", object.edgeU, function(value)
                document:updateObject(object.id, { edgeU = value })
                options.onObjectChanged(object.id)
                refreshInspector()
            end))
            inspectorContent:AddChild(vectorFields(UI, "EDGE V", object.edgeV, function(value)
                document:updateObject(object.id, { edgeV = value })
                options.onObjectChanged(object.id)
                refreshInspector()
            end))
        end

        inspectorContent:AddChild(UI.Button {
            text = "删除对象",
            variant = "danger",
            height = 32,
            fontSize = 10,
            onClick = function()
                local id = object.id
                if document:removeObject(id) then
                    options.onObjectRemoved(id)
                    state.selectedObjectId = nil
                    state.inspectorMode = "scene"
                    refreshHierarchy()
                    refreshInspector()
                    setStatus("已删除对象 · " .. object.name)
                end
            end,
        })
    end

    local function refreshMaterialInspector(name, descriptor)
        inspectorContent:AddChild(UI.Label {
            text = name,
            fontSize = 15,
            fontWeight = "bold",
            fontColor = TEXT,
            height = 28,
        })
        inspectorContent:AddChild(UI.Dropdown {
            value = descriptor.type,
            options = {
                { value = "lambertian", label = "Lambertian" },
                { value = "metal", label = "Metal" },
                { value = "dielectric", label = "Dielectric" },
                { value = "diffuseLight", label = "Diffuse Light" },
            },
            height = 32,
            onChange = function(_, value)
                local nextDescriptor = { type = value }
                if value == "metal" then
                    nextDescriptor.color = descriptor.color or { 0.75, 0.75, 0.78 }
                    nextDescriptor.fuzz = descriptor.fuzz or 0.15
                elseif value == "dielectric" then
                    nextDescriptor.ior = descriptor.ior or 1.5
                elseif value == "diffuseLight" then
                    nextDescriptor.color = descriptor.color or { 1, 0.9, 0.7 }
                    nextDescriptor.intensity = descriptor.intensity or 4
                else
                    nextDescriptor.color = descriptor.color or { 0.65, 0.68, 0.72 }
                end
                document:updateMaterial(name, nextDescriptor)
                options.onMaterialChanged(name)
                refreshMaterials()
                refreshInspector()
            end,
        })

        if descriptor.type == "dielectric" then
            inspectorContent:AddChild(numericField(UI, "IOR", descriptor.ior or 1.5, function(value)
                descriptor.ior = math.max(1, value)
                document:updateMaterial(name, descriptor)
                options.onMaterialChanged(name)
                refreshInspector()
            end))
        else
            local color = descriptor.color or { 0.65, 0.68, 0.72 }
            inspectorContent:AddChild(UI.ColorPicker {
                value = {
                    r = math.floor(color[1] * 255 + 0.5),
                    g = math.floor(color[2] * 255 + 0.5),
                    b = math.floor(color[3] * 255 + 0.5),
                    a = 255,
                },
                showAlpha = false,
                onChange = function(_, value)
                    descriptor.color = {
                        value.r / 255,
                        value.g / 255,
                        value.b / 255,
                    }
                    document:updateMaterial(name, descriptor)
                    options.onMaterialChanged(name)
                    refreshInspector()
                end,
            })
            if descriptor.type == "metal" then
                inspectorContent:AddChild(numericField(UI, "Fuzz", descriptor.fuzz or 0, function(value)
                    descriptor.fuzz = math.max(0, math.min(1, value))
                    document:updateMaterial(name, descriptor)
                    options.onMaterialChanged(name)
                    refreshInspector()
                end))
            elseif descriptor.type == "diffuseLight" then
                inspectorContent:AddChild(numericField(UI, "Intensity", descriptor.intensity or 1,
                    function(value)
                        descriptor.intensity = math.max(0, value)
                        document:updateMaterial(name, descriptor)
                        options.onMaterialChanged(name)
                        refreshInspector()
                    end))
            end
        end

        inspectorContent:AddChild(UI.Label {
            text = string.format("使用次数  %d", document:materialUsage(name)),
            fontSize = 9,
            fontColor = MUTED,
            height = 20,
        })
        inspectorContent:AddChild(UI.Button {
            text = name == "Default" and "Default 不可删除" or "删除材质",
            variant = "danger",
            disabled = name == "Default",
            height = 32,
            fontSize = 10,
            onClick = function()
                if document:removeMaterial(name) then
                    options.onMaterialRemoved(name)
                    state.selectedMaterial = nil
                    state.inspectorMode = "scene"
                    refreshMaterials()
                    refreshHierarchy()
                    refreshInspector()
                    setStatus("材质已删除，引用已切换到 Default")
                end
            end,
        })
    end

    local function refreshSceneInspector()
        local data = document:getData()
        inspectorContent:AddChild(UI.Label {
            text = "SCENE",
            fontSize = 15,
            fontWeight = "bold",
            fontColor = TEXT,
            height = 28,
        })
        inspectorContent:AddChild(UI.Label {
            text = data.metadata.title,
            fontSize = 10,
            fontColor = MUTED,
            height = 35,
            maxLines = 2,
        })
        inspectorContent:AddChild(UI.Label {
            text = string.format("%d objects  /  %d materials",
                #data.objects,
                (function()
                    local count = 0
                    for _ in pairs(data.materials) do count = count + 1 end
                    return count
                end)()),
            fontSize = 10,
            fontColor = ACCENT,
            height = 24,
        })
        inspectorContent:AddChild(sectionTitle(UI, "RENDER CAMERA"))
        inspectorContent:AddChild(vectorFields(UI, "LOOK FROM", data.camera.lookFrom, function(value)
            data.camera.lookFrom = value
            document:markDirty()
            refreshInspector()
        end))
        inspectorContent:AddChild(vectorFields(UI, "LOOK AT", data.camera.lookAt, function(value)
            data.camera.lookAt = value
            document:markDirty()
            refreshInspector()
        end))
        inspectorContent:AddChild(numericField(UI, "FOV", data.camera.verticalFov, function(value)
            data.camera.verticalFov = math.max(1, math.min(179, value))
            document:markDirty()
            refreshInspector()
        end))
        inspectorContent:AddChild(compactButton(UI, "从渲染摄像机观察", function()
            options.onUseRenderCamera()
        end))
        inspectorContent:AddChild(compactButton(UI, "当前视角设为渲染摄像机", function()
            options.onCaptureRenderCamera()
            refreshInspector()
        end))
        inspectorContent:AddChild(compactButton(UI, "恢复内置场景", function()
            options.onRestoreBuiltIn()
            state.selectedObjectId = nil
            state.selectedMaterial = nil
            state.inspectorMode = "scene"
            refreshHierarchy()
            refreshMaterials()
            refreshInspector()
            setStatus("已恢复内置 JSON 场景")
        end, "danger"))
    end

    refreshInspector = function()
        inspectorContent:ClearChildren()
        if state.inspectorMode == "object" then
            local object = document:findObject(state.selectedObjectId)
            if object ~= nil then
                refreshObjectInspector(object)
                return
            end
        elseif state.inspectorMode == "material" then
            local descriptor = document:getMaterials()[state.selectedMaterial]
            if descriptor ~= nil then
                refreshMaterialInspector(state.selectedMaterial, descriptor)
                return
            end
        end
        refreshSceneInspector()
    end

    local viewport = UI.Panel {
        id = "editor-viewport",
        flexGrow = 1,
        flexBasis = 0,
        minWidth = 180,
        height = "100%",
        backgroundColor = { 0, 0, 0, 0 },
        pointerEvents = "none",
    }

    local leftPanel = UI.Panel {
        width = "22%",
        minWidth = 150,
        maxWidth = 280,
        flexShrink = 1,
        height = "100%",
        padding = 9,
        gap = 7,
        backgroundColor = PANEL,
        borderRightWidth = 1,
        borderRightColor = BORDER,
        children = {
            sectionTitle(UI, "SCENE HIERARCHY"),
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                minHeight = 100,
                scrollY = true,
                showScrollbar = true,
                children = { hierarchyList },
            },
            sectionTitle(UI, "MATERIAL LIBRARY"),
            UI.Panel {
                height = 30,
                flexDirection = "row",
                gap = 5,
                children = {
                    compactButton(UI, "+ 新建", function()
                        local name = document:addMaterial()
                        refreshMaterials()
                        selectMaterial(name)
                        setStatus("已创建材质 · " .. name)
                    end),
                },
            },
            UI.ScrollView {
                height = "38%",
                minHeight = 90,
                scrollY = true,
                showScrollbar = true,
                children = { materialList },
            },
        },
    }

    local rightPanel = UI.Panel {
        width = "28%",
        minWidth = 190,
        maxWidth = 350,
        flexShrink = 1,
        height = "100%",
        padding = 11,
        backgroundColor = { 12, 21, 31, 230 },
        borderLeftWidth = 1,
        borderLeftColor = BORDER,
        children = {
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                showScrollbar = true,
                children = { inspectorContent },
            },
        },
    }

    local toolButtons = UI.Panel {
        flexDirection = "row",
        gap = 5,
        flexGrow = 1,
        flexShrink = 1,
        children = {
            compactButton(UI, "+ Quad", function() selectObject(options.onAddObject("quad")) end),
            compactButton(UI, "+ Box", function() selectObject(options.onAddObject("box")) end),
            compactButton(UI, "+ Sphere", function() selectObject(options.onAddObject("sphere")) end),
            compactButton(UI, "Move", function() options.onToolChanged("move") end),
            compactButton(UI, "Scale", function() options.onToolChanged("scale") end),
        },
    }

    local header = UI.Panel {
        height = 50,
        flexShrink = 0,
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = 12,
        gap = 8,
        backgroundColor = { 9, 17, 27, 255 },
        borderBottomWidth = 1,
        borderBottomColor = BORDER,
        children = {
            UI.Label {
                text = "SCENE EDITOR",
                width = 126,
                fontSize = 13,
                fontWeight = "bold",
                fontColor = TEXT,
            },
            toolButtons,
            UI.Button {
                text = "保存",
                variant = "secondary",
                width = 68,
                height = 32,
                fontSize = 10,
                onClick = function()
                    local ok, message = document:save()
                    setStatus(ok and "场景已保存" or ("保存失败 · " .. tostring(message)))
                end,
            },
            UI.Button {
                text = "渲染",
                variant = "primary",
                width = 74,
                height = 32,
                fontSize = 10,
                onClick = function()
                    setStatus("渲染工作区将在第二步接入")
                    options.onRenderRequested()
                end,
            },
        },
    }

    local footer = UI.Panel {
        height = 34,
        flexShrink = 0,
        paddingHorizontal = 12,
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = { 9, 17, 27, 255 },
        borderTopWidth = 1,
        borderTopColor = BORDER,
        children = {
            statusLabel,
            UI.Label {
                text = "RMB + WASD 漫游 · F 聚焦 · 单击选择",
                width = 270,
                fontSize = 9,
                fontColor = MUTED,
                textAlign = "right",
            },
        },
    }

    local root = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = { 0, 0, 0, 0 },
        pointerEvents = "box-none",
        children = {
            header,
            UI.Panel {
                flexGrow = 1,
                flexBasis = 0,
                minHeight = 160,
                flexDirection = "row",
                children = { leftPanel, viewport, rightPanel },
            },
            footer,
        },
    }

    refreshHierarchy()
    refreshMaterials()
    refreshInspector()

    return {
        root = root,
        viewport = viewport,
        selectObject = selectObject,
        refreshHierarchy = refreshHierarchy,
        refreshMaterials = refreshMaterials,
        refreshInspector = refreshInspector,
        setStatus = setStatus,
        getSelectedObjectId = function() return state.selectedObjectId end,
    }
end

return EditorWorkspace
