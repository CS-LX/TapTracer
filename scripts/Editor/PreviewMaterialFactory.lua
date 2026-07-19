local PreviewMaterialFactory = {}
PreviewMaterialFactory.__index = PreviewMaterialFactory

local OPAQUE_TECHNIQUE = "Techniques/PBR/PBRNoTexture.xml"
local ALPHA_TECHNIQUE = "Techniques/PBR/PBRNoTextureAlpha.xml"

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function descriptorColor(document, descriptor)
    if descriptor.color ~= nil then
        return descriptor.color
    end
    if descriptor.texture ~= nil then
        local texture = document.textures[descriptor.texture]
        if texture ~= nil and texture.type == "checker" then
            return {
                (texture.even[1] + texture.odd[1]) * 0.5,
                (texture.even[2] + texture.odd[2]) * 0.5,
                (texture.even[3] + texture.odd[3]) * 0.5,
            }
        end
    end
    return { 0.65, 0.68, 0.72 }
end

function PreviewMaterialFactory.new(document)
    return setmetatable({
        document = document,
        materials = {},
    }, PreviewMaterialFactory)
end

function PreviewMaterialFactory:clear()
    for name, material in pairs(self.materials) do
        material:Dispose()
        self.materials[name] = nil
    end
end

function PreviewMaterialFactory:invalidate(name)
    local material = self.materials[name]
    if material ~= nil then
        material:Dispose()
        self.materials[name] = nil
    end
end

function PreviewMaterialFactory:get(name)
    local cached = self.materials[name]
    if cached ~= nil then
        return cached
    end

    local document = self.document:getData()
    local descriptor = document.materials[name]
        or { type = "lambertian", color = { 0.65, 0.68, 0.72 } }
    local color = descriptorColor(document, descriptor)
    local alpha = descriptor.type == "dielectric" and 0.28 or 1.0
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource(
        "Technique",
        descriptor.type == "dielectric" and ALPHA_TECHNIQUE or OPAQUE_TECHNIQUE
    ))
    material:SetShaderParameter("MatDiffColor", Variant(Color(
        color[1], color[2], color[3], alpha
    )))
    material:SetShaderParameter("MatSpecColor", Variant(Color(0.5, 0.5, 0.5, 1)))

    if descriptor.type == "metal" then
        material:SetShaderParameter("Metallic", Variant(1.0))
        material:SetShaderParameter("Roughness", Variant(clamp(descriptor.fuzz or 0, 0.05, 1)))
    elseif descriptor.type == "dielectric" then
        material:SetShaderParameter("Metallic", Variant(0.0))
        material:SetShaderParameter("Roughness", Variant(0.05))
    elseif descriptor.type == "diffuseLight" then
        local intensity = descriptor.intensity or 1
        material:SetShaderParameter("Metallic", Variant(0.0))
        material:SetShaderParameter("Roughness", Variant(0.45))
        material:SetShaderParameter("MatEmissiveColor", Variant(Color(
            color[1] * intensity,
            color[2] * intensity,
            color[3] * intensity,
            1
        )))
    else
        material:SetShaderParameter("Metallic", Variant(0.0))
        material:SetShaderParameter("Roughness", Variant(0.8))
    end

    self.materials[name] = material
    return material
end

return PreviewMaterialFactory
