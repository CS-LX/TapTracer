# 纯 Lua 5.4 CPU 光线追踪渲染器策划案

## 1. 项目定位

实现一个使用 Lua 5.4 编写的、与显示前端解耦的纯 CPU 光线追踪计算库。

核心库只负责：

- 场景、几何体、材质和相机的数据表达；
- 射线生成、求交、散射和辐射度积分；
- 逐像素或逐 Tile 产生线性 RGB 浮点颜色；
- 通过回调交付像素、进度和统计数据。

核心库不得依赖 OpenGL、DirectX、Vulkan、CUDA、窗口系统或 UI 框架。PPM 文件、ANSI 控制台、ASCII 灰度图、引擎纹理等均作为可替换输出适配器存在。

项目不是实时光追方案。第一目标是正确、可测试、可扩展的离线路径追踪器；第二目标才是 Lua 层性能优化。

## 2. 参考项目与采用原则

参考源码统一存放于 `references/raytracing/`，只用于研究，不直接参与产品构建。

### 2.1 主算法基线

- 仓库：`RayTracing/raytracing.github.io`
- 本地路径：`references/raytracing/raytracing.github.io/`
- 固定提交：`0ab7db4c08fe23f23c0d9d30fed166c83cefed91`
- 许可证：CC0-1.0，见 `COPYING.txt`
- 用途：作为数学公式、功能递进顺序、参考场景和正确性基线。

首期主要参考：

- `src/InOneWeekend/vec3.h`
- `src/InOneWeekend/ray.h`
- `src/InOneWeekend/interval.h`
- `src/InOneWeekend/hittable.h`
- `src/InOneWeekend/hittable_list.h`
- `src/InOneWeekend/sphere.h`
- `src/InOneWeekend/material.h`
- `src/InOneWeekend/camera.h`
- `src/InOneWeekend/color.h`

后续阶段参考 `src/TheNextWeek/` 中的 AABB、BVH、纹理、运动模糊、四边形、变换和体积实现。

### 2.2 完整 Lua 单文件参考

- 仓库：`LingDong-/teapot.lua`
- 本地路径：`references/raytracing/teapot.lua/`
- 固定提交：`288a2c8e939c9b5e02d9fe16b4a9ebc5f4550759`
- 许可证：MIT，见 `LICENSE`
- 用途：研究纯 Lua 下的 BVH、OBJ、BSDF、显式光源采样、PPM 输入输出和热点代码组织。

不照搬已发现的实现问题：

- 球体内部命中必须用最终选择的 `t` 计算命中点和法线；
- 最近命中必须把射线的最大距离更新为最近的 `t`，而不是远交点；
- LookAt 相机基向量必须保存归一化结果；
- 非均匀缩放下法线使用逆转置变换；
- 垂直 FOV 使用三角函数换算，不做线性近似；
- OBJ 按位置、UV、法线的索引三元组展开，支持负索引和硬边。

### 2.3 模块化 Lua 参考

- 仓库：`jonasgeiler/3d-raytracer-lua`
- 本地路径：`references/raytracing/3d-raytracer-lua/`
- 固定提交：`c1c262389bcde22f1d233584764ea525ba14c00c`
- 许可证：MIT，见 `LICENSE.md`
- 用途：研究模块边界、Hittable 包装、材质、纹理、BVH、场景定义和渲染进度组织。

不引入其 LuaJIT/Lua 5.1 假设。所有实现以 Lua 5.4 为基线，位运算使用 Lua 5.4 原生运算符，且不依赖 FFI、BitOp 或 C 扩展。

## 3. 许可证策略

- 产品实现以 CC0 算法基线进行独立 Lua 编写；
- 借鉴 MIT 项目的架构与算法时保留必要的许可证和归属记录；
- 不把三个参考仓库打包进最终构建；
- 不复制许可证不明确或强 copyleft 项目的代码；
- 产品源码中记录算法出处，但避免逐行翻译参考实现。

## 4. 技术边界

### 4.1 核心层允许依赖

- Lua 5.4 标准语言能力；
- `math`、`table`、`string` 等纯计算标准库；
- 调用方注入的随机数、时间、输出和取消回调。

### 4.2 核心层禁止依赖

- 任意图形 API；
- 窗口、UI 或纹理对象；
- `io`、`os`、引擎全局对象等平台特有能力；
- 网络、线程、FFI 或本地动态库；
- 全局可变渲染状态。

### 4.3 适配层

提供以下独立适配器：

1. `PPMWriter`：写出 P3 ASCII PPM；
2. `AnsiPresenter`：用 ANSI true-color 与半块字符输出终端预览；
3. `AsciiPresenter`：把亮度映射为字符，不要求真彩终端；
4. `CallbackPresenter`：把 Tile/像素交给调用方；
5. 可选平台适配器：在不污染核心层的前提下使用宿主提供的文件或图像接口。

标准 Lua CLI 可使用 `io.write` 适配器；UrhoX 环境使用 `File` 或像素回调适配器。二者共享同一计算核心。

## 5. 目录设计

正式实现阶段使用以下结构：

```text
scripts/
├── main.lua
├── RayTracer/
│   ├── Math/
│   │   ├── Vec3.lua
│   │   ├── Ray.lua
│   │   ├── Interval.lua
│   │   └── RNG.lua
│   ├── Core/
│   │   ├── HitRecord.lua
│   │   ├── Scene.lua
│   │   ├── Camera.lua
│   │   ├── Film.lua
│   │   ├── Renderer.lua
│   │   └── RenderSettings.lua
│   ├── Geometry/
│   │   ├── Sphere.lua
│   │   ├── Plane.lua
│   │   ├── Triangle.lua
│   │   └── TriangleMesh.lua
│   ├── Acceleration/
│   │   ├── AABB.lua
│   │   └── BVH.lua
│   ├── Material/
│   │   ├── Lambertian.lua
│   │   ├── Metal.lua
│   │   ├── Dielectric.lua
│   │   └── DiffuseLight.lua
│   ├── Texture/
│   │   ├── SolidColor.lua
│   │   ├── Checker.lua
│   │   └── ImageTexture.lua
│   ├── Integrator/
│   │   ├── NormalIntegrator.lua
│   │   └── PathIntegrator.lua
│   ├── IO/
│   │   ├── PPMWriter.lua
│   │   ├── AnsiPresenter.lua
│   │   ├── AsciiPresenter.lua
│   │   └── CallbackPresenter.lua
│   └── Scenes/
│       ├── Normals.lua
│       ├── Materials.lua
│       ├── RandomSpheres.lua
│       └── CornellBox.lua
└── Tests/
    └── RayTracerTests.lua
```

实现时可先合并过小模块，避免过度拆分；但数学、求交、材质、积分器和输出适配器必须保持边界清晰。

## 6. 公共 API 草案

### 6.1 构建场景

```lua
local RT = require "RayTracer"

local scene = RT.Scene.new()
scene:Add(RT.Sphere.new(
    RT.Vec3.new(0, 0, 1),
    0.5,
    RT.Lambertian.new(RT.Color.new(0.7, 0.3, 0.3))
))
```

### 6.2 配置相机

```lua
local camera = RT.Camera.new {
    aspectRatio = 16 / 9,
    verticalFov = 40,
    lookFrom = RT.Vec3.new(3, 2, -3),
    lookAt = RT.Vec3.new(0, 0, 0),
    up = RT.Vec3.new(0, 1, 0),
    defocusAngle = 0,
    focusDistance = 4,
}
```

坐标约定为 Y-up、左手坐标系，Z 轴向前。参考项目中的相机与叉乘方向必须显式转换并通过测试验证，不能直接假设符号一致。

### 6.3 渲染

```lua
local job = RT.Renderer.new {
    width = 320,
    height = 180,
    samplesPerPixel = 16,
    maxDepth = 8,
    tileSize = 16,
    seed = 42,
    integrator = RT.PathIntegrator.new(),
    presenter = RT.CallbackPresenter.new {
        onTile = function(x, y, width, height, pixels)
        end,
        onProgress = function(done, total, stats)
        end,
    },
}

job:Render(scene, camera)
```

### 6.4 可中断和分步执行

渲染器支持：

```lua
job:Step(tileBudget)
job:IsComplete()
job:Cancel()
job:GetStats()
```

这保证同一个核心既可阻塞式离线渲染，也可被游戏循环或 GUI 每帧推进少量工作。

## 7. 数据与数学约定

- 颜色在计算过程中使用线性 RGB 浮点数；
- `Film` 保存样本平均后的线性 HDR RGB，是渲染结果的原始数据源，允许分量小于 0 或大于 1，不因预览显示而覆盖；
- 当前 NanoVG 预览仅在量化边界执行非负截断与 `[0, 1]` Clamp，再转换为 8-bit RGB；Clamp 后的颜色只用于显示，不写回 `Film`；
- 后续显示质量优化统一放在独立输出转换层：固定曝光、连续亮度色调映射、可选高光趋白、Linear RGB 到 sRGB 编码，并由 NanoVG、PPM、ANSI 等 Presenter 共享；
- 射线有效区间使用 `tMin`/`tMax`，以 epsilon 避免自相交；
- `HitRecord:SetFaceNormal(ray, outwardNormal)` 统一维护正面标志与朝向射线的法线；
- 所有方向向量在要求单位长度的边界处显式归一化；
- FOV 使用弧度参与三角函数，公共 API 接收角度；
- 随机采样使用可复现的独立 PRNG，不依赖全局 `math.random` 状态；
- 每个 Tile 或像素从全局 seed 派生子序列，确保改变渲染顺序不会改变结果；
- 初期使用有限最大深度；加入 Russian Roulette 后仍保留硬上限。

## 8. 渲染算法路线

### 阶段 A：最小正确光线追踪器

目标：输出可验证的球体法线图。

- Vec3、Color、Ray、Interval；
- Perspective Camera；
- Sphere 求交；
- Hittable Scene；
- NormalIntegrator；
- 单样本渲染；
- PPM 和 ASCII 输出；
- 固定 seed；
- 64×36、160×90 测试分辨率。

验收：

- 中心射线命中测试球；
- 切线、球内射线、负半径和最近命中测试；
- 输出 PPM Header 与像素数量正确；
- 固定 seed 结果稳定。

### 阶段 B：基础路径追踪

目标：复现官方材质球场景。

- 多重子像素采样；
- Lambertian 漫反射；
- Metal 镜面与 fuzz；
- Dielectric 折射、全反射和 Schlick 近似；
- 天空背景；
- 最大反弹深度；
- Gamma 校正；
- Thin lens 景深。

验收：

- 与官方参考场景构图和材质行为一致；
- fuzz 限制在合法区间；
- 玻璃球内外法线和折射率切换正确；
- 不产生 NaN、Inf 或明显黑斑。

### 阶段 C：可用的离线渲染任务

目标：从 Demo 演进为可嵌入计算库。

- Tile 调度；
- `Step`、取消、进度与统计；
- Film 累积缓冲；
- 渐进式采样；
- PPM、ANSI、ASCII、Callback 四种输出；
- 配置校验放在公共 API 边界；
- 不同输出端产生相同的量化颜色。

验收：

- 阻塞渲染与逐步渲染结果一致；
- Tile 顺序变化不影响固定 seed 结果；
- 取消后不继续分配渲染工作；
- 核心模块不引用任何显示或文件 API。

### 阶段 D：几何与 BVH

目标：支持复杂静态场景。

- AABB slab 求交；
- Triangle 与 Möller–Trumbore 求交；
- 平面或 Quad；
- 中位数切分 BVH；
- 扁平数组 BVH；
- 显式栈遍历；
- 最近命中裁剪；
- 可选 SAH 分桶构建；
- OBJ Loader 作为独立 IO 模块。

验收：

- BVH 与暴力遍历命中结果逐射线一致；
- 支持从包围盒内部发出的射线；
- 平行轴方向无除零错误；
- OBJ 支持 `v`、`vt`、`vn`、多边形三角化和负索引；
- BVH 场景具有可测量的求交次数下降。

### 阶段 E：灯光、纹理与质量提升

目标：支持 Cornell Box 和更稳定的路径追踪。

- DiffuseLight；
- Solid、Checker 和 PPM Image Texture；
- UV；
- 当前已完成最小 `ImageTexture.fromPPM()`：核心接收 ASCII P3 PPM 文本，按命中记录的 `u/v` 采样并保持原始线性 RGB；文件读取继续留在宿主适配层，核心不直接依赖文件系统；
- 当前已将 BVH 接入 `Scene:hit()` 主查询路径：Scene 缓存可选加速器，`add/clear` 自动失效，未构建时回退暴力遍历，并保留命中结果差分与查询统计；
- 矩形面光源；
- 显式光源采样；
- 阴影射线；
- Russian Roulette；
- 当前阶段保留线性 HDR `Film`，预览端暂用直接 Clamp；统一曝光、色调映射与 sRGB 输出属于阶段 I；
- MIS 不属于当前阶段，必须在阶段 F 的基准、阶段 G 的累积采样、阶段 H 的分辨率档位和阶段 I 的输出转换稳定后，按阶段 J 的数据决定是否实现；

验收：

- Cornell Box 能稳定出图；
- 低样本下显式光源采样显著降低噪声；
- 材质发光和背景发光职责明确；
- Russian Roulette 不改变期望亮度。

### 阶段 F：性能基准与可观测性

目标：先用数据确定瓶颈，再进行任何热点优化或默认分辨率提升。

- 为渲染任务记录开始时间、结束时间和有效计算耗时；计时器由调用方注入，计算核心不直接依赖引擎或 `os`；
- 统计主相机样本数、路径数、总反弹数、阴影射线数、场景命中数和背景未命中数；
- 保留 BVH 的 AABB 测试数、Primitive 测试数、节点数、叶节点数和最大深度；
- 派生每秒主样本数、每秒路径数、平均路径深度、每像素平均耗时；
- 区分路径追踪计算耗时与宿主显示纹理上传耗时，防止把显示瓶颈误判为积分器瓶颈；
- 建立固定 seed、固定场景和固定配置的基准入口；
- 基准至少覆盖材质球、Cornell Box 回归场景和 Poolcore Courtyard 展示场景；
- 输出紧凑摘要，不恢复逐 Tile 日志洪流。

验收：

- 同一配置连续运行的核心统计完全一致，耗时指标允许平台波动；
- 阻塞渲染与 `Step` 渲染的 Film 和计数统计一致；
- 计算耗时与显示上传耗时可以分别读取；
- 能用数据回答当前主要瓶颈位于积分、BVH、对象分配还是显示上传；
- 完成本阶段前，不修改默认分辨率、不实现 MIS、不做大范围热点重构。

阶段 F 实测结果（2026-07-18）：

- 核心回归测试：`[RayTracerTests] all tests passed`；计时注入、PathIntegrator 统计、重置清零和命中/未命中守恒均通过；
- 官方项目构建：通过；入口为 `scripts/main.lua`；
- Poolcore 固定配置：`160×90`、`16 spp`、`maxDepth=8`、`seed=42`、BVH 开启、动态纹理逐扫描块上传；
- Poolcore 场景构建统计：80 个对象、95 个 BVH 节点、48 个叶节点、最大深度 7；
- 真实 GLES 截图验证：可正常启动并生成 `screenshots/phase-f-poolcore.png`；截图帧 120 处于真实扫描过程，证明显示链路仍为逐扫描段更新；
- 完整视觉渲染超过当前沙箱运行窗口，未取得最终完成摘要；该限制来自当前逐块动态 `Texture2D:SetData()` 和 CPU 路径追踪成本，不判定为脚本错误；
- headless 运行未发现 Lua runtime error，但 30 秒短基准也未完成全画面，因此不把未完成运行的吞吐量作为稳定基线；
- 当前可确认的瓶颈方向是 CPU 路径积分与频繁纹理上传的组合成本，后续优化必须以阶段 G 的逐轮采样和阶段 H 的档位控制为边界，不在阶段 F 越界重构。

### 阶段 G：全画面逐轮累积采样

目标：先快速得到完整低噪预览，再逐轮提升整张画面的样本质量。

- 将当前“单个像素一次完成全部 spp”改为按 sample pass 累积；
- 第一轮让所有像素各获得 1 spp，之后继续第 2、3 轮，直到目标 spp；
- Film 增加样本和或等价的稳定累积数据，并记录每像素样本数；
- 每轮仍按小 Tile/扫描段分步执行，保持主循环可响应；
- 进度同时展示当前 pass、目标 spp、当前 pass 内像素进度和总样本进度；
- 固定 seed 的样本序列只由像素索引和 sample pass 决定，不受 Tile 顺序或每帧预算影响；
- 取消和重置必须清理累积状态，暂停/继续不得重复计算已经完成的样本；
- 动态纹理只上传新完成区域或受控批次，不恢复逐像素 NanoVG 绘制。

阶段 G 当前实现：

- `Film:addSample()` 使用运行平均值累积，不丢弃线性 HDR 的原始平均结果；
- `Film` 为每个像素记录 sample count，`clear()` 和 `set()` 保持计数语义一致；
- `Renderer` 改为按 `currentPass` 逐轮遍历全部 Tile，每个像素每轮只生成一个 sample；
- sample seed 仍由固定的 `seed + pixelIndex + sampleIndex` hash 推导，与 Tile budget 和执行顺序无关；
- `progress()` 改为总 sample progress，Presenter 仍收到统一的进度回调；
- 宿主显示按刚完成的 Tile 上传，状态栏显示当前 pass、当前 pass 进度和总进度；
- 当前保留 `samplesPerPixel=16`、`160×90` 和 Poolcore 场景，不提前进入阶段 H 的分辨率调整。

验收：

- 第一轮结束时整幅场景已经可辨认，而不是只出现顶部扫描区域；
- 每完成一轮，Film 的有效 spp 精确增加 1；
- 逐轮累积到 N spp 的结果与阻塞式 N spp 在固定 seed 下逐像素一致；
- 改变每帧 Tile 预算不改变最终 Film；
- UI 保持可更新，单次工作预算由阶段 F 的基准约束。

### 阶段 H：分辨率与质量档位

目标：在已有基准和逐轮采样基础上提高空间分辨率，而不牺牲渐进预览可用性。

- 提供明确的渲染档位，而不是散落修改常量；
- `preview`：默认交互预览，建议 `256×144`、低初始 spp；
- `quality-square`：方形展示，建议 `256×256`，适合 Poolcore 或 Cornell 基准；
- `offline`：高质量离线输出，允许 `512×512` 或更高分辨率；
- Film 分辨率、显示纹理分辨率和屏幕布局保持解耦；
- 根据阶段 F 的实测数据给出每个档位的预计像素量、样本量和完成成本；
- 分辨率变化不改变相机纵向 FOV，使用 aspect ratio 调整横向视野；
- 高质量档位继续保留逐轮预览，不等待全部样本完成后才显示。

阶段 H 当前实现：

- 新增 `RayTracer.Config.QualityPresets`，集中定义质量档位，Renderer 和 Film 不感知档位名称；
- `preview`：`256×144`、`32 spp`，作为当前默认档位，兼顾交互式渐进预览与最终观感；
- `quality-square`：`256×256`、`64 spp`，用于方形展示和质量验证；
- `offline`：`512×512`、`64 spp`，明确作为高成本离线档位，不默认启用；
- 当前通过 `main.lua` 的单一 `ACTIVE_QUALITY` 常量选择档位，避免阶段 H 引入额外菜单、命令行协议或状态系统；
- 显示画布根据实际 Film 宽高计算比例，采样调度仍沿用阶段 G 的逐轮累积和 Tile 分步执行。

验收：

- `256×144` 和 `256×256` 均能完整渐进显示且不触发 NanoVG 顶点缓冲问题；
- `512×512` 被明确归类为离线模式，不阻塞默认预览体验；
- 不同档位使用同一核心渲染路径；
- 改变窗口大小或 DPR 时，显示画布保持正确比例和清晰布局。

### 阶段 I：独立输出转换层

目标：在不修改线性 HDR Film 的前提下，统一所有显示和文件输出的颜色转换。

- 新增独立的 OutputTransform 或等价模块；
- 输入始终为 Film 中的线性 HDR RGB，输出为显示或编码目标需要的颜色；
- 保留 `direct-clamp` 作为基准和回归开关；
- 增加固定曝光控制；
- 选择连续、可测试的 tone mapping 曲线；
- 增加 Linear RGB 到 sRGB 编码；
- 可选高光趋白只能作用于输出值，禁止写回 Film；
- NanoVG/Texture2D、PPM、ANSI 和 Callback Presenter 共享同一转换逻辑；
- 明确纹理的 sRGB 标记，避免软件编码后再次由 GPU 重复转换；
- 用蓝天、白墙、浅青水面和彩球验证饱和度、白点、暗部和高光。

验收：

- 切换输出转换模式不会改变 Film 数据或采样统计；
- `direct-clamp` 与当前显示结果保持回归一致；
- tone mapping 不再产生整体灰雾、抬高黑位或明显降低彩球饱和度；
- HDR 高光具有连续层次，不再只依赖逐通道截断；
- 所有 Presenter 对同一像素产生一致的 8-bit 结果。

### 阶段 J：MIS 评估与按需实现

目标：在前述基准、累积采样和输出转换稳定后，判断 Multiple Importance Sampling 是否值得引入。

- 先使用阶段 F 的固定场景测量显式光源采样下的方差和收敛速度；
- 对水面高光、小面积光源、漫反射间接光分别记录噪声表现；
- 仅在基准证明收益明确时，实现光源采样与 BSDF 采样的 PDF；
- 使用 power heuristic 或等价、可测试的权重；
- 处理镜面/折射 delta 路径，避免对不可比较 PDF 强行加权；
- 保持无 MIS 路径作为差分基线和回归开关；
- 不在第一版引入通用材质图或过度抽象的采样框架。

验收：

- 固定样本预算下，指定基准区域的方差可测量下降；
- MIS 不改变期望亮度，不重复计算发光贡献；
- 镜面、折射、漫反射和直接可见光源行为正确；
- 若实测收益不足以抵消复杂度，则记录结论并停止实现，而不是为了路线完整强行加入。

### 后续阶段执行顺序与门禁

严格按 `F → G → H → I → J` 执行，一次只推进一个阶段：

1. 当前阶段的代码、测试、官方构建和截图/基准验收全部通过；
2. 记录本阶段结果和已知限制；
3. 提交并推送稳定节点；
4. 才开始下一阶段。

禁止并行混入后续阶段功能。例如阶段 F 只建立基准，不顺手修改分辨率；阶段 G 只修改采样调度，不同时引入 tone mapping；阶段 H 不提前实现 MIS。

当前下一步固定为 **阶段 H-Preview-1：调度与显示上传**，原阶段 I/J 暂缓。

### 阶段 H-Preview：预览观感与交互速度优先

背景：阶段 G 已经解决“全画面逐轮累积采样”，但当前 preview 仍存在大面积地面/墙面噪点、单轮等待过长和低 spp 观感不佳的问题。因此原阶段 I（输出转换）与阶段 J（MIS）暂缓，先建立可在可观时间内获得漂亮 `256×144` 图像的 Preview Quality Track。

目标：

- `256×144` preview 在可观时间内完成首轮和可用质量预览；
- 噪声必须是正常 Monte Carlo 噪声，不得出现斜向黑带、固定网格黑纹或 Tile 边界伪影；
- 在不修改线性 HDR `Film` 的前提下，显示端可以平滑低 spp 结果；
- 每次优化都用固定 seed、固定 Poolcore 场景和阶段 F 统计判断收益。

当前质量档位调整：

- `preview` 固定为 `256×144`、`32 spp`，作为默认交互与质量预览；
- `quality-square` 固定为 `256×256`、`64 spp`，用于高样本方形质量验证；
- `offline` 固定为 `512×512`、`64 spp`，不作为默认预览；
- 档位只负责配置分辨率、spp 和调度预算，核心 `Renderer`、`Film`、`Integrator` 不感知档位名称。

执行顺序：

#### H-Preview-1：调度与显示上传

- 将当前 `64×1` Tile 和 `maxTilesPerStep=1` 的过度碎片化调度改为可控批次；
- 优先尝试 `64×4` 等较大 Tile，减少一轮需要的 Update 次数；
- 每次 Update 至少允许计算多个 Tile，但设置单帧预算，避免 UI 长时间卡死；
- 将 `Image` 像素写入与 `Texture2D:SetData()` 解耦，尽量做到每次 Update 至多上传一次整纹理；
- 保留计算耗时、上传耗时、最大单步耗时和上传次数统计；
- 不改变采样 seed、Film 数值和最终图像。

验收：

- `256×144` 单轮等待显著下降；
- UI 仍能持续响应；
- 显示上传次数显著下降；
- 固定 seed 下，调度批次变化不改变最终 Film。

#### H-Preview-2：单路径成本控制

- 在固定场景上测量 `maxDepth=5/6/8` 的速度、平均路径深度、亮度和噪声差异；
- 仅为 Preview 设置更低的路径预算，不修改质量档位和离线基线的核心语义；
- 评估更早 Russian Roulette 的收益，但必须验证期望亮度没有明显偏移；
- 在 `Quad.new()` 中预计算求交所需的 `uu/uv/vv/determinant`，减少每次命中的重复计算；
- 暂不进行全局 Vec3、Ray、Interval 或 BVH 的大范围重写。

验收：

- 单 sample 计算成本下降；
- Poolcore 的蓝天、白墙、水池和彩球构图保持稳定；
- 不新增黑带、错误阴影或明显亮度漂移；
- 统计可以区分路径积分成本、BVH 求交成本和显示上传成本。

#### H-Preview-3：显示端轻量降噪

- 新增独立的显示副本滤波，不修改 Film 原始线性 HDR 数据；
- 第一版只实现可关闭的 3×3 低风险、边缘感知滤波；
- 亮度/颜色差异过大的邻域不直接平均，避免抹平彩球、墙体和水面边缘；
- `denoise=false` 时必须恢复原始 Clamp 显示；
- 暂不引入深度/法线 AOV、复杂时域滤波或外部降噪器。

验收：

- `8～32 spp` 时地面和墙面颗粒明显下降；
- 彩球轮廓、墙体边界和水面边缘不严重模糊；
- 开关降噪不改变 Film 和采样统计；
- PPM、ANSI、Callback 仍读取未经显示滤波的 Film。

#### H-Preview-4：质量档位重测

完成 H-Preview-1～3 后，再根据实际数据决定：

- `preview` 目标固定为 `32 spp`，不再在 H-Preview-4 中重新降回 8 spp；
- `preview` 是否使用 `maxDepth=5/6`；
- `preview` 的单帧 Tile 预算和上传节流值；
- 降噪是否默认开启；
- `quality-square=256×256, 64 spp` 是否需要独立的更高计算预算。

禁止在数据出来前直接把 preview 提高到 `64 spp`，也不把“增加 spp”当作唯一降噪手段。

#### 暂缓的阶段 I/J

- 阶段 I 输出转换暂缓：当前主要问题是采样噪声、调度和单路径成本，不是曝光或 Tone Mapping；
- 阶段 J MIS 暂缓：只有 H-Preview 稳定后，才能用方差/收敛基准判断 MIS 是否值得引入；
- 在 H-Preview 完成前，不实现 MIS、不做大范围输出架构重构。

预览目标已经明确为 `32 spp`，其余档位为 `64 spp`；后续优化应围绕如何在可观时间内完成这些目标，而不是降低目标轮数。

## 9. 性能策略

按以下顺序优化，不提前引入复杂机制：

1. 先建立正确性测试和基准场景；
2. 减少热点循环中的临时 table；
3. 对 Vec3 提供清晰 API，同时在交点和积分热点中允许局部标量运算；
4. 缓存频繁使用的函数与字段到 local；
5. 使用扁平 Film 数组和扁平 BVH 节点数组；
6. BVH 遍历使用复用的显式栈；
7. 先遍历较近子节点并收紧 `tMax`；
8. 渲染以 Tile 为单位，降低回调和控制台刷新频率；
9. 提供低分辨率渐进预览；
10. 只有基准证明必要时，才增加多进程 Tile Worker 适配器。

首版不使用协程模拟并行。协程可以用于让出执行权，但不会提供 CPU 并行加速。

## 10. 测试方案

### 10.1 单元测试

- Vec3 加减乘除、点积、叉积、归一化、反射、折射；
- 零向量与 near-zero 判断；
- 球体外部、内部、切线和未命中；
- AABB 六个方向、平行方向和盒内起点；
- 三角形正反面、边缘和退化三角形；
- Face normal 与 frontFace；
- 固定 seed PRNG 序列；
- PPM Header、量化、Gamma 与像素顺序。

### 10.2 差分测试

- 同一场景使用暴力遍历与 BVH，比较命中对象、距离和法线；
- 阻塞式与 Step 式渲染比较像素缓冲；
- PPM、ANSI、Callback 在颜色量化前使用同一 Film 数据；
- 关键参考场景保存低分辨率 golden checksum。

### 10.3 基准场景

- 单球法线图：64×36，1 spp；
- 材质球：160×90，8 spp，8 depth；
- Random Spheres：320×180，16 spp；
- Cornell Box：320×320，32 spp；
- 三角网格：固定射线集比较暴力遍历和 BVH。

基准记录：总射线数、主射线数、反弹射线数、AABB 测试数、Primitive 测试数、耗时和每秒射线数。

## 11. 日志与可观测性

首次交付保留以下日志：

- 渲染配置摘要；
- 场景 Primitive 与材质数量；
- BVH 节点数、叶节点数、最大深度和构建耗时；
- 每个阶段的进度；
- 总射线数、平均路径深度、命中率；
- NaN/Inf 像素计数；
- 完成、取消和错误原因。

稳定后移除逐 Tile 调试日志，只保留任务开始、任务结束、关键统计和错误日志。

## 12. 风险与应对

### 12.1 Lua 性能

风险：高分辨率、高 spp 和深路径会导致长时间计算。

应对：低分辨率渐进预览、Tile 调度、BVH、固定性能基准、减少临时对象；明确定位为离线 renderer。

### 12.2 数值稳定性

风险：自相交、法线方向错误、全反射边界和除零产生黑斑或 NaN。

应对：统一 `Interval`、face normal、epsilon 策略和有限值检测；为球内射线、切线、平行盒面等边界建立测试。

### 12.3 坐标系迁移

风险：参考实现多采用不同相机方向约定，直接移植会造成画面镜像、前后颠倒或叉乘方向错误。

应对：本项目固定 Y-up 左手坐标系；相机基向量和测试场景按该约定重新推导，并通过中心、左上、右下射线方向测试锁定行为。

### 12.4 平台文件能力

风险：标准 Lua CLI 的 `io` 与受限宿主环境的文件 API 不一致。

应对：计算核心不执行文件操作；PPM Writer 只依赖注入的 `write(chunk)` sink，由 CLI 或宿主适配器提供。

### 12.5 参考实现缺陷传播

风险：教学仓库可能存在边界 Bug 或为简洁牺牲正确性。

应对：以数学推导和官方算法为主；Lua 仓库只作结构及性能参考；通过单元、差分和 golden 测试验证每个阶段。

## 13. 交付节点

### 交付 1：法线图内核

- 纯计算核心；
- Sphere 场景；
- PPM 与 ASCII 输出；
- 单元测试；
- 固定 seed 与基础统计。

### 交付 2：基础路径追踪器

- 三种基础材质；
- 抗锯齿、递归反弹、景深；
- 官方材质球参考场景；
- 渐进式 Tile 渲染。

### 交付 3：BVH 与网格

- AABB、Triangle、BVH；
- OBJ 导入；
- 暴力遍历/BVH 差分测试与性能对比。

### 交付 4：Cornell Box

- 发光材质、面光源、纹理；
- 显式光源采样；
- Cornell Box；
- 最终性能与正确性报告。

## 14. 后续阶段索引

- `stage-f`: 性能基准与可观测性，固定场景与统计口径；
- `stage-g`: 全画面逐轮累积采样；
- `stage-h`: 预览、方形质量和离线高分辨率档位；
- `stage-i`: 独立曝光、色调映射与 sRGB 输出转换；
- `stage-j`: 基于方差和收敛数据评估 MIS。

## 15. 当前路线状态

- 阶段 A～E：已完成并通过既有验收；
- 当前展示场景：开放式 Poolcore Courtyard，保留 Cornell Box 作为回归基准的后续入口；
- 显示链路：Film → Image → Texture2D → BorderImage，支持逐扫描段实时更新；
- 当前预览仍使用直接 Clamp，Film 保持线性 HDR；
- 下一步：只实施阶段 F，不跨阶段修改默认分辨率或采样算法。

## 16. 第一轮实施决策

开始编码时采用以下最小范围：

- Lua 5.4；
- 模块化而非单文件；
- 64×36 默认验证分辨率；
- NormalIntegrator 优先；
- Sphere 为唯一首期 Primitive；
- PPM sink 和 ASCII presenter；
- 固定 seed；
- 可阻塞 Render 和可分步 Step；
- 暂不实现 BVH、OBJ、多线程、MIS 或图形前端。

第一轮验收通过后再进入基础路径追踪材质阶段，避免在求交、坐标系或输出仍未验证时叠加复杂度。
