local RenderController = {}
RenderController.__index = RenderController

function RenderController.new(options)
    assert(options ~= nil and options.createRenderer ~= nil, "RenderController requires createRenderer")
    return setmetatable({
        createRenderer = options.createRenderer,
        renderer = nil,
        config = options.config or {},
        running = false,
        stopped = false,
    }, RenderController)
end

function RenderController:configure(config)
    if self.running then
        self:stop()
    end
    self.config = config
    self.renderer = nil
    self.stopped = false
end

function RenderController:start()
    if self.running then
        return false
    end
    self.renderer = self.createRenderer(self.config)
    self.running = true
    self.stopped = false
    return true
end

function RenderController:stop()
    if self.renderer ~= nil and not self.renderer:isComplete() then
        self.renderer:cancel()
    end
    self.running = false
    self.stopped = true
end

function RenderController:update(tileBudget)
    if not self.running or self.renderer == nil then
        return nil
    end
    self.renderer:step(tileBudget)
    if self.renderer:isComplete() or self.renderer:isCancelled() then
        self.running = false
        self.stopped = self.renderer:isCancelled()
    end
    return self.renderer
end

function RenderController:isRunning()
    return self.running
end

function RenderController:getRenderer()
    return self.renderer
end

return RenderController
