local Material = {}
Material.__index = Material

function Material.new()
    return setmetatable({}, Material)
end

function Material:scatter(ray, record, rng)
    return nil, nil
end

return Material
