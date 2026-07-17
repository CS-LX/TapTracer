local CallbackPresenter = {}
CallbackPresenter.__index = CallbackPresenter

function CallbackPresenter.new(options)
    options = options or {}
    assert(type(options.onTile) == "function", "CallbackPresenter requires onTile")
    return setmetatable({
        onTileCallback = options.onTile,
        onProgressCallback = options.onProgress,
        onStartCallback = options.onStart,
        onCompleteCallback = options.onComplete,
    }, CallbackPresenter)
end

function CallbackPresenter:onStart(width, height, renderer)
    if self.onStartCallback then
        self.onStartCallback(width, height, renderer)
    end
end

function CallbackPresenter:onTile(x, y, width, height, film, renderer)
    local pixels = {}
    for row = y, y + height - 1 do
        for column = x, x + width - 1 do
            local r, g, b = film:get(column, row)
            pixels[#pixels + 1] = { r = r, g = g, b = b }
        end
    end
    self.onTileCallback(x, y, width, height, pixels, renderer)
end

function CallbackPresenter:onProgress(done, total, renderer)
    if self.onProgressCallback then
        self.onProgressCallback(done, total, renderer)
    end
end

function CallbackPresenter:onComplete(film, renderer)
    if self.onCompleteCallback then
        self.onCompleteCallback(film, renderer)
    end
end

return CallbackPresenter
