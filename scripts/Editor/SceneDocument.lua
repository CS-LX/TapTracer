local SceneDocument = {}
SceneDocument.__index = SceneDocument

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[deepCopy(key)] = deepCopy(item)
    end
    return result
end

local function readResource(resourcePath)
    assert(cache:Exists(resourcePath), "Scene resource not found: " .. resourcePath)
    local file = cache:GetFile(resourcePath)
    assert(file ~= nil and file:IsOpen(), "Cannot open scene resource: " .. resourcePath)
    local source = file:ReadString()
    file:Close()
    local ok, document = pcall(cjson.decode, source)
    assert(ok and type(document) == "table", "Invalid scene JSON: " .. resourcePath)
    return document
end

local function ensureIds(document)
    local used = {}
    local nextId = 1
    for index, object in ipairs(document.objects or {}) do
        local id = object.id
        if type(id) ~= "string" or id == "" or used[id] then
            repeat
                id = string.format("object-%03d", nextId)
                nextId = nextId + 1
            until not used[id]
            object.id = id
        end
        used[id] = true
        if type(object.name) ~= "string" or object.name == "" then
            object.name = string.format("%s %d", object.type or "Object", index)
        end
    end
end

local function ensureDocumentDefaults(document)
    document.materials = document.materials or {}
    if document.materials.Default == nil then
        document.materials.Default = {
            type = "lambertian",
            color = { 0.65, 0.68, 0.72 },
        }
    end
    document.objects = document.objects or {}
    ensureIds(document)
end

function SceneDocument.load(resourcePath, overridePath)
    local document = nil
    local source = resourcePath
    if overridePath ~= nil and fileSystem:FileExists(overridePath) then
        local file = File(overridePath, FILE_READ)
        if file:IsOpen() then
            local ok, decoded = pcall(cjson.decode, file:ReadString())
            file:Close()
            if ok and type(decoded) == "table" then
                document = decoded
                source = overridePath
            end
        end
    end
    if document == nil then
        document = readResource(resourcePath)
    end
    ensureDocumentDefaults(document)
    return setmetatable({
        data = document,
        resourcePath = resourcePath,
        overridePath = overridePath,
        sourcePath = source,
        dirty = false,
        revision = 1,
        nextObjectNumber = #(document.objects or {}) + 1,
    }, SceneDocument)
end

function SceneDocument:getData()
    return self.data
end

function SceneDocument:snapshot()
    return deepCopy(self.data)
end

function SceneDocument:isDirty()
    return self.dirty
end

function SceneDocument:markDirty()
    self.dirty = true
    self.revision = self.revision + 1
end

function SceneDocument:getObjects()
    return self.data.objects
end

function SceneDocument:getMaterials()
    return self.data.materials
end

function SceneDocument:findObject(id)
    for index, object in ipairs(self.data.objects) do
        if object.id == id then
            return object, index
        end
    end
    return nil, nil
end

function SceneDocument:updateObject(id, changes)
    local object = self:findObject(id)
    if object == nil then
        return false
    end
    for key, value in pairs(changes) do
        object[key] = deepCopy(value)
    end
    self:markDirty()
    return true
end

local function defaultMaterialId(materials)
    if materials.Default ~= nil then
        return "Default"
    end
    local first = next(materials)
    return first
end

function SceneDocument:addObject(objectType)
    assert(objectType == "box" or objectType == "sphere" or objectType == "quad",
        "Unsupported editor object type")
    local serial = self.nextObjectNumber
    self.nextObjectNumber = serial + 1
    local material = defaultMaterialId(self.data.materials)
    local object = {
        id = string.format("object-%03d", serial),
        name = string.format("%s %d", objectType:gsub("^%l", string.upper), serial),
        type = objectType,
        material = material,
    }
    if objectType == "box" then
        object.minimum = { -0.5, 0, -0.5 }
        object.maximum = { 0.5, 1, 0.5 }
    elseif objectType == "sphere" then
        object.center = { 0, 1, 0 }
        object.radius = 1
    else
        object.origin = { -1, 0, -1 }
        object.edgeU = { 2, 0, 0 }
        object.edgeV = { 0, 0, 2 }
    end
    self.data.objects[#self.data.objects + 1] = object
    self:markDirty()
    return object
end

function SceneDocument:removeObject(id)
    local _, index = self:findObject(id)
    if index == nil then
        return false
    end
    table.remove(self.data.objects, index)
    self:markDirty()
    return true
end

function SceneDocument:materialUsage(name)
    local count = 0
    for _, object in ipairs(self.data.objects) do
        if object.material == name then
            count = count + 1
        end
    end
    return count
end

function SceneDocument:addMaterial()
    local serial = 1
    local name
    repeat
        name = "Material" .. serial
        serial = serial + 1
    until self.data.materials[name] == nil
    self.data.materials[name] = {
        type = "lambertian",
        color = { 0.65, 0.68, 0.72 },
    }
    self:markDirty()
    return name
end

function SceneDocument:updateMaterial(name, descriptor)
    if self.data.materials[name] == nil then
        return false
    end
    self.data.materials[name] = deepCopy(descriptor)
    self:markDirty()
    return true
end

function SceneDocument:removeMaterial(name)
    if name == "Default" or self.data.materials[name] == nil then
        return false
    end
    if self.data.materials.Default == nil then
        self.data.materials.Default = {
            type = "lambertian",
            color = { 0.65, 0.68, 0.72 },
        }
    end
    for _, object in ipairs(self.data.objects) do
        if object.material == name then
            object.material = "Default"
        end
    end
    self.data.materials[name] = nil
    self:markDirty()
    return true
end

function SceneDocument:save()
    if self.overridePath == nil then
        return false, "No override path configured"
    end
    local directory = self.overridePath:match("^(.*)/[^/]+$")
    if directory ~= nil and directory ~= "" then
        fileSystem:CreateDir(directory)
    end
    local file = File(self.overridePath, FILE_WRITE)
    if not file:IsOpen() then
        return false, "Cannot open override file"
    end
    file:WriteString(cjson.encode(self.data))
    file:Close()
    self.dirty = false
    self.sourcePath = self.overridePath
    return true
end

function SceneDocument:restoreBuiltIn()
    if self.overridePath ~= nil
            and fileSystem:FileExists(self.overridePath) then
        fileSystem:Delete(self.overridePath)
    end
    self.data = readResource(self.resourcePath)
    ensureDocumentDefaults(self.data)
    self.sourcePath = self.resourcePath
    self.dirty = false
    self.revision = self.revision + 1
    self.nextObjectNumber = #self.data.objects + 1
end

return SceneDocument
