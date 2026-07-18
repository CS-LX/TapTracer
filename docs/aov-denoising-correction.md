# AOV 降噪语义纠偏与修复计划

## 1. 文档目的

本文记录当前纯 Lua AOV 引导降噪与业界常见 AOV/À-Trous/SVGF 降噪语义之间的偏差，并评估在以下约束内的修复可行性：

- Lua 5.4；
- CPU-only；
- 不使用线程、FFI、原生动态库、CUDA 或外部降噪进程；
- 默认 Preview 为 `256×144`、`32 spp`；
- 原始 `Film` 必须继续保存线性 HDR Beauty，降噪只作用于独立显示副本；
- UI、渲染核心、AOV 采集和显示滤波保持解耦。

本文是 `docs/raytracer-plan.md` 中 H-Preview 降噪阶段的专项纠偏文档。实施顺序以本文为准；在本文验收完成前，当前 AOV 多尺度滤波不得被视为可信的最终预览输出。

## 2. 调研基线

对照资料：

- Intel Open Image Denoise 官方文档：`https://www.openimagedenoise.org/documentation.html`
- Intel Open Image Denoise 官方仓库：`https://github.com/RenderKit/oidn`
- Edge-Avoiding À-Trous Wavelet Transform：`https://jo.dreggn.org/home/2010_atrous.pdf`
- NVIDIA SVGF：`https://research.nvidia.com/sites/default/files/pubs/2017-07_Spatiotemporal-Variance-Guided-Filtering%3A//svgf_preprint.pdf`

采用原则：

- OIDN/OptiX 的神经网络本体不能在当前纯 Lua 运行时中直接集成，但其 AOV 语义可作为正确性参考；
- 当前路线不是复刻 OIDN，而是在纯 Lua 中实现语义正确、亮度稳定、成本可控的空间域预览降噪；
- 标准算法中的高成本部分允许使用经过量化验证的低风险替代方案，但不能以明显亮度漂移换取平滑观感。

## 3. 当前问题结论

当前实现具备正确的外层结构：

```text
线性 HDR Film
+ Albedo / Normal / Depth AOV
        ↓
独立显示滤波副本
        ↓
Clamp / Image / Texture2D
```

但当前实现仍是“AOV 引导的多尺度空洞双边滤波原型”，不是语义完整的标准 AOV 降噪器。调查曾将水面整体变亮主要归因于显示滤波，后续事故复核确认这是两个问题叠加：

1. `069601e` 为 Dielectric 增加 `albedoAt()` 以采集 AOV 后，`sampleDirectLight()` 错误地以“存在 `albedoAt()`”作为漫反射直接光资格，使水面获得不属于 delta BSDF 的 Lambertian 直接光；该能量写入原始 Beauty Film，因此 denoise 开关两侧都会变亮；
2. Correct-2 之前的显示滤波又会把部分高能反射/透射样本扩散到邻域，使 denoise-on 结果进一步发白。

当前修复已把 Beauty 直接光接口与 AOV Albedo 解耦：只有 Lambertian 提供 `directLightAlbedo()` 并参与现有 NEE 公式；Dielectric 的 `albedoAt()` 仅供 AOV 使用，不再改变 radiance 或 shadow-ray 路径。Correct-2 的 delta 直通继续负责阻止显示端二次扩散。

## 4. 偏差与修复可行性

### 4.1 AOV 被最后一个 sample 覆盖

当前偏差：

- Beauty Film 是所有 sample 的运行平均；
- Albedo、Normal、Depth 只保留最后一个 sample；
- Beauty 与引导特征不对应，亚像素边缘和随机镜面路径尤其不稳定。

可行性：完全可行，优先级最高。

修复方案：

- `PrimaryAOV` 改为累积缓冲，至少记录 `hitCount/sampleCount`；
- Albedo 按与 Beauty 相同的 sample pass 累积；
- Normal 累积后在滤波读取边界归一化，不在写入时反复归一化；
- Depth 按有效命中样本累积，并同时保存覆盖率，避免 miss 被当作深度 0 参与平均；
- reset/cancel/restart 必须清理全部 AOV 累积状态；
- 固定 seed 下，阻塞渲染与分步渲染的 AOV 必须一致。

成本：

- 每像素增加少量标量累计与计数；
- `256×144` 下内存和写入成本可接受；
- 不增加场景求交次数。

预览影响：高。该项是后续所有 AOV 权重可信的前提。

### 4.2 Dielectric / 完美镜面路径的特征语义错误

当前偏差：

- 水面第一次命中 Dielectric 时记录白色 Albedo、水面法线和水面深度；
- 水面 Beauty 实际来自 Fresnel 反射、透射及后续命中；
- 滤波器因此把水面视为大面积同质漫反射表面，错误传播高能样本。

可行性：部分可行。完整的生产级 lobe 特征跟踪需要更多积分器信息，但低风险纠偏完全可行。

首选修复：

1. 为 AOV 增加材质分类，至少区分：
   - diffuse/glossy；
   - delta reflection；
   - delta transmission；
   - emission；
   - miss。
2. PathIntegrator 在主路径上允许 AOV 采集继续越过完美 delta 表面，记录第一次非 delta 的 diffuse/glossy 命中；
3. 使用实际 sample 的反射/透射分支累积后续特征，保证与该 sample 的 Beauty 路径一致；
4. 同时保留主表面 material class，用于阻止不同类别之间混合。

低风险替代方案：

- 若 delta 路径特征跟踪在首轮实现中成本或复杂度过高，则对 Dielectric/完美 Metal 禁止 step=2/4 的跨像素滤波，仅允许极弱的 step=1 或完全直通；
- 水面会保留更多噪声，但不会再产生大面积亮度漂移；
- 这是 Preview 可接受的保守退化，比错误提亮更可靠。

成本：

- 复用 PathIntegrator 已有命中，不应新增主射线求交；
- 需要扩展 AOV callback 的状态与材质分类；
- 不要求完整拆分 Beauty lobe。

预览影响：极高。水面漂移的直接修复点。

### 4.3 当前 3×3 kernel 不是标准 5×5 B3-spline À-Trous

当前偏差：

- 当前 kernel 为 3×3 `1/2/1`；
- 标准 Edge-Avoiding À-Trous/SVGF 常用可分离 5×5 B3-spline `1/4/6/4/1` 二维组合。

可行性：完全可行，但不应作为第一修复项。

方案选择：

- 正确性阶段可继续保留 3×3，以先验证 AOV、材质边界和亮度稳定；
- 稳定后增加可切换的 5×5 kernel，对比相同 spp 下的噪声、边缘和滤波耗时；
- 只有 5×5 的观感收益明显时才设为 Preview 默认。

成本：

- 直接 5×5 三轮约为当前 3×3 邻域访问量的 `25/9`；
- `256×144` 可运行，但纯 Lua 显示滤波时间会明显增加；
- 该项主要影响降噪质量，不是当前水面漂移的根因。

预览影响：中。保留 3×3 不会使语义必然错误，只会偏离标准 kernel 和影响质量上限。

### 4.4 缺少方差估计

当前偏差：

- 固定颜色阈值无法区分真实细节、阴影边缘、低概率高能样本与普通 Monte Carlo 噪声；
- 所有区域使用相同滤波强度。

可行性：完全可行，优先级高。

修复方案：

- Film 或独立统计缓冲记录每像素亮度的一阶矩与二阶矩；
- 使用稳定在线方差算法或 `E[x²] - E[x]²`，并处理低 spp 数值误差；
- 使用均值方差控制颜色 edge-stopping，而不是只依赖固定 RGB 差；
- 低样本邻域可使用小范围方差预滤波，避免 1～2 spp 时方差不可用；
- 方差只指导显示滤波，不修改 Beauty Film。

成本：

- 每 sample 增加少量标量计算；
- 每像素增加一至两个标量；
- 纯 Lua 和 `256×144` 下可接受。

预览影响：高。可显著降低高能样本扩散和过度模糊。

### 4.5 Normal 边缘权重存在固定 15% 泄漏

当前偏差：

- 法线完全不相似时仍保留至少 15% 权重；
- 多轮滤波可能跨越墙角、球体轮廓和水面边界。

可行性：完全可行，低成本。

修复方案：

- 使用可趋近 0 的 normal edge-stopping；
- 采用 `max(dot(n0, n1), 0)^power` 或等价指数函数；
- 未归一化的累积法线在参与点积前归一化；
- material class 不同直接令权重为 0。

成本：极低。

预览影响：高，尤其是彩球轮廓和墙面转角。

### 4.6 Depth 权重未考虑梯度与 À-Trous step

当前偏差：

- 只使用相对深度差；
- step 从 1 增至 4 时仍使用相同阈值语义；
- 斜面和远距离表面可能被误判。

可行性：完全可行。

修复方案：

- 为每像素估计局部深度梯度，或使用邻域有限差分；
- 深度阈值结合 `step`、邻域偏移和局部梯度；
- 覆盖率显著不同、material class 不同或 hit/miss 不同直接停止混合；
- 首版可使用保守阈值，宁可少滤波也不跨边界。

成本：

- 可预计算深度梯度，也可在滤波时读取少量邻居；
- `256×144` 下可接受。

预览影响：中高。主要避免大尺度 pass 跨越几何边缘。

### 4.7 完整 Beauty 未拆分 diffuse/specular/transmission lobe

当前偏差：

- diffuse、specular、transmission、emission、直接光和间接光混合后统一过滤；
- 手写空间滤波难以同时正确处理所有频率和能量分布。

可行性：部分可行，但完整拆分不适合作为当前第一轮修复。

原因：

- 当前 PathIntegrator 以总 radiance 和 throughput 为主，未保留逐 lobe contribution；
- 完整拆分需要扩展积分器返回值、Film 缓冲、直接光分类和组合路径；
- 这会扩大核心改动范围，并增加内存和测试矩阵。

替代方案：

- 先按主路径材质分类采用不同滤波强度；
- diffuse 表面允许多尺度滤波；
- glossy 表面限制尺度；
- delta reflection/transmission 默认直通或只做极弱 step=1；
- emission 默认不做跨像素滤波；
- 后续基准证明水面或高光噪声仍不可接受时，再单独建立 lobe Film。

预览影响：

- 不做完整 lobe 拆分会限制质量上限；
- 采用材质分类保守滤波后，对 Preview 的正确性影响可控；
- 对当前水面问题，保守直通已经能消除主要漂移。

### 4.8 缺少 Albedo demodulation

当前偏差：

- Albedo 只参与邻域权重；
- 未将 diffuse illumination 与高频材质颜色分离。

可行性：部分可行。

限制：

- 只有 diffuse contribution 适合直接执行 `beauty/albedo` 去调制；
- 当前 Beauty 混合了镜面、透射和发光，直接对完整 Beauty 去调制会产生新的错误；
- 在未拆分 lobe 前不能全局启用。

替代方案：

- 当前阶段继续把 Albedo 只用于边缘停止；
- 仅在主表面明确为 diffuse，且 Albedo 分量高于安全阈值时，实验性过滤近似 illumination；
- 若没有独立 diffuse lobe，则默认不启用 demodulation。

预览影响：中低。缺少该项可能导致纹理细节与照明噪声较难分离，但不是当前水面变亮的直接根因。

### 4.9 HDR 高能样本在 Clamp 前被扩散

当前偏差：

- 在线性 HDR 中滤波本身正确；
- 但当前没有方差、自适应阈值、firefly 控制或材质分类；
- 单个高能样本可能先扩散到邻域，再由多个像素一起 Clamp 成亮块。

可行性：完全可行，但需要避免破坏无偏 Film。

修复方案：

- 原始 Film 永远不做 firefly clamp；
- 显示滤波副本可依据局部均值与方差，对邻域贡献执行鲁棒权重或 Winsorization；
- 高能值应降低作为邻居的传播权重，而不是直接覆盖中心 Beauty；
- 记录滤波前后全图及指定区域的线性亮度均值；
- 增加中心样本最小权重或有限输出回拉，防止多轮漂移；
- 任何亮度稳定措施只存在于 Display 层。

成本：低至中。

预览影响：高。可直接抑制水面高亮扩散和大面积发白。

## 5. 总体可行性结论

| 纠偏项 | 可行性 | 当前阶段策略 | 对预览影响 |
|---|---|---|---|
| AOV 按 sample 累积 | 完全可行 | 必须实现 | 极高 |
| delta/specular 特征跟踪 | 部分可行 | 实现材质分类；优先尝试跟踪首次非 delta 命中 | 极高 |
| 5×5 标准 kernel | 完全可行 | 后置对比，非第一门禁 | 中 |
| 亮度方差估计 | 完全可行 | 必须实现 | 高 |
| Normal 权重归零 | 完全可行 | 必须实现 | 高 |
| Depth gradient + step | 完全可行 | 必须实现 | 中高 |
| 完整 lobe 拆分 | 部分可行 | 暂用材质分类保守滤波替代 | 中高 |
| Albedo demodulation | 部分可行 | 未拆 diffuse lobe 前默认关闭 | 中低 |
| HDR 高能样本鲁棒控制 | 完全可行 | 仅显示副本实现 | 高 |

结论：纠偏整体可行。没有任何一项要求违反纯 Lua CPU-only 边界。完整 lobe 拆分和全局 Albedo demodulation 不适合立即实现，但都有可接受的保守替代方案，不会阻断 Preview 降噪修复。

## 6. 分阶段实施路线

### AOV-Correct-1：恢复特征与 Beauty 的一致性（已完成，2026-07-18）

目标：先消除确定性的语义错误，不调滤波观感参数。

已完成：

- PrimaryAOV 已改为逐 sample 累积；
- 已增加 sampleCount、hitCount 和 coverage；
- Normal 在滤波读取边界归一化；
- Depth 只对有效命中累积；
- 固定 seed 下，阻塞渲染、分步渲染和 reset 后重渲染的 AOV 一致性测试通过；
- 未增加场景求交次数。

阶段边界说明：

- 本阶段只恢复 AOV 与 Beauty 的 sample 对应关系，不处理 Dielectric 的滤波策略；
- 水面在本阶段完成后仍可能保持纠偏前的错误提亮，这是已知基线，不代表最终降噪语义正确；
- 水面亮度漂移由紧随其后的 `AOV-Correct-2` 负责：加入材质分类，并对 delta reflection/transmission 采用首次非 delta 特征或保守直通策略；
- 因此“水面尚未变暗”不阻塞 AOV-Correct-1 验收，但会阻塞 AOV-Correct-2 和整个 H-Preview-3A 的最终验收。

已通过门禁：

- N spp AOV 与同样 N spp Beauty 使用相同 sample 序列；
- Tile budget 不改变最终 AOV；
- AOV 不再由最后一个 sample 覆盖，miss 也不会清空此前有效特征。

### AOV-Correct-2：材质分类与 delta 保守策略（已完成，2026-07-18）

目标：停止错误过滤镜面、透射和发光表面。

已实现：

- 材质已提供稳定 denoise class：Lambertian=`diffuse`、有 fuzz 的 Metal=`glossy`、完美 Metal=`delta_reflection`、Dielectric=`delta_transmission`、DiffuseLight=`emission`；
- Renderer 在现有首次命中回调中把 class 写入 PrimaryAOV，不增加 `scene:hit()`；
- Beauty Film 事故已修复：当前 Lambertian NEE 只接受 `directLightAlbedo()`，不再把 AOV 的 `albedoAt()` 当作直接光资格；Dielectric 保留 AOV Albedo，但不会获得漫反射直接光或额外 shadow ray；
- PrimaryAOV 逐 sample 累积 class；同一像素出现多个命中 class 时标记为 `mixed`，避免在几何或材质边界错误过滤；
- A-Trous 只过滤 `diffuse` 和 `glossy`，且邻域 class 必须与中心 class 完全相同；
- `delta_reflection`、`delta_transmission`、`emission`、`mixed`、`unknown` 和 miss 均逐通道精确直通原始 Film 显示副本；
- 未实现 delta 后首次非 delta 特征跟踪：本阶段先采用计划中的保守直通回退，以亮度稳定优先；仅当直通方案仍不能满足后续 Preview 质量目标时再评估该扩展；
- 自动化测试已覆盖材质分类、class 的阻塞/分步/reset 一致性、跨 class 硬边界、所有保守 class 的逐通道精确直通、Renderer 到 AOV 的分类传播、Dielectric 直接光拒绝，以及启用 AOV 回调前后 Beauty radiance 完全一致；
- Lua LSP 为 0 Error，RayTracer 专项断言全部通过，项目构建成功。

已通过黑盒门禁：

- Dielectric 水面已恢复正确的 Beauty Film 基线，开启降噪后不再产生大范围提亮；
- 保守直通使水面在 denoise on/off 下保持一致；
- 彩球、墙面与水面边界未观察到跨材质颜色泄漏；
- 关闭降噪时仍直接显示原始 Film；
- Poolcore Courtyard 黑盒视觉验收已通过，可以进入 AOV-Correct-3。

### AOV-Correct-3：方差与边缘停止函数（实现完成，等待黑盒验收，2026-07-18）

目标：让滤波强度由噪声和几何连续性决定。

已实现：

- Film 在原有逐 sample Beauty 运行平均旁，以 Welford 在线算法累积亮度均值与 `M2`，可分别读取 sample variance 和 mean variance；`clear()` 与 `set()` 同步重置统计；
- 方差统计使用与 Beauty 完全相同的 `Film:addSample()` 数据流，不增加场景求交，也不参与或改变 radiance；
- 颜色停止权重结合中心/邻居的亮度均值方差、亮度差与 RGB 差，不再只依赖固定颜色阈值；
- Normal 使用硬截止加幂次衰减，夹角超过门限时权重可精确归零，移除了原先固定 15% 泄漏；
- Depth 先估计局部 cardinal gradient，再按实际邻域空间距离（包含 À-Trous step）缩放容差；超出容差时权重精确归零；
- hit/miss、coverage 与 material class 作为硬边界：miss、class 不同或 coverage 差异过大的邻居不参与过滤；
- HDR 高能邻居依据局部方差与中心亮度降低传播权重，不修改高能中心样本，不对原始 Film 执行 firefly clamp；
- 继续只过滤 `diffuse` 和 `glossy`；`delta_transmission` 水面以及其他受保护 class 仍逐通道精确直通，因此本阶段不会把水面变亮，也不承诺显著降低水面自身的 delta 噪声；
- 保留 3×3 kernel 与现有迭代预算，避免把权重语义收益和 Correct-4 的 kernel 成本实验混在一起；
- 自动回归已覆盖亮度矩/方差、clear 重置、Normal/Depth/coverage 硬停止、HDR 邻居传播上限、滤波不修改 Film，以及全部 Correct-1/2 既有门禁；
- Lua LSP 全工作区 0 Error；RayTracer 脚本输出 `[RayTracerTests] all tests passed`；官方项目构建成功。

自动门禁已通过：

- 正交 Normal、显著 Depth 跳变和 coverage 跳变均不能污染中心像素；
- `50.0` 亮度 HDR 邻居不会把 `0.1` 中心扩散到 `0.2` 以上；
- 过滤前后源 Film RGB 逐通道完全一致；
- Dielectric 直通与 Beauty/AOV 接口隔离回归继续通过。

待黑盒门禁：

- 水面、白墙和地面指定区域的滤波前后线性平均亮度漂移受控；
- 强边缘梯度保留率不低于纠偏前基线；
- 高亮噪点不会扩散成大面积 Clamp 白块；
- Preview 交互与显示刷新成本仍处于可接受范围。

#### Correct-3 首轮黑盒结果：未通过（2026-07-18）

对比 Correct-3 前后的 Poolcore Courtyard 截图后确认：

- 彩球和部分几何边缘更锐利，说明 Normal/class/coverage 的保守停止方向有效；
- 右侧墙面出现沿屏幕 Y 轴延伸的竖向分带；
- 地面和侧边平台出现沿屏幕 X 轴延伸的横向分带；
- 水面噪声基本保持不变，这是 `delta_transmission` 精确直通的预期结果，不属于本次条纹事故；
- 新增条纹属于不可接受的结构化滤波伪影，因此 Correct-3 不能按当前状态完成，也不能直接进入 Correct-4。

根因分析：

- 首要嫌疑是首版 Depth stopping：每像素只保存一个无方向的最大 cardinal depth gradient，再按空间距离放大 tolerance；超过 tolerance 后权重突然归零；
- 平面透视深度在屏幕上具有明确方向：墙面主要沿 X 改变，错误接受/拒绝边界表现为竖纹；地面主要沿 Y 改变，对应表现为横纹；
- `step=2/4` 的 À-Trous 跳格采样会把离散权重差放大为可见分带；
- 未预滤波的 per-pixel mean variance 可能进一步放大相邻像素滤波强度差，但更可能产生不规则斑块，不足以单独解释当前方向明确的条纹；
- Normal cutoff、coverage/class 边界、显示放大和原始路径采样均不是同一平面内部规则条纹的首要解释；Correct-3 未改变路径采样，且回归已确认滤波不会写回 Film。

#### AOV-Correct-3.1：方向深度停止修复

执行顺序固定如下，避免把多个变量混在一起：

1. 保持 Film、方差、Normal、coverage/class、HDR、3×3 kernel 和迭代预算不变，只替换 Depth stopping；
2. 将无方向 `depthGradient` 改为屏幕空间 `depthGradientX/depthGradientY`；
3. 对邻居偏移 `(dx, dy)` 预测同一平面允许的深度变化，比较实际深度差与方向预测值的残差；
4. 使用连续的高斯式残差衰减，替代平面内部容易发生的突然归零；真正的大深度断层仍允许硬停止；
5. 自动测试同时覆盖“斜平面连续过滤”和“真实深度断层隔离”，防止只修复截图却放松几何边界；
6. 修复后仍保留 3×3 kernel，重新执行同场景黑盒验收；
7. 只有残余不规则斑块仍明显时，才单独评估 variance 3×3 预滤波；
8. Correct-3.1 黑盒通过后才进入 Correct-4 的 3×3/5×5 kernel 对比。

实现与自动门禁状态（2026-07-18）：

- 已将无方向最大深度梯度替换为 `depthGradientX/depthGradientY`；内部像素采用中心差分，单侧可用时采用前向或后向差分；
- 邻居 Depth 权重现在比较实际深度变化与方向梯度预测值的残差；
- 同一透视平面使用连续高斯式残差衰减，不再在基础 tolerance 边缘突然归零；
- 残差超过 `4 sigma` 时仍硬停止，保留真实几何断层隔离；
- 自动回归新增水平深度平面与垂直深度平面测试：其三轮滤波中心结果必须与等深平面一致，分别防止墙面竖纹和地面横纹；
- Correct-3 的大深度断层、Normal、coverage、HDR、Film 不变、Dielectric 直通与 Beauty 隔离测试继续通过；
- Lua LSP 全工作区 0 Error；RayTracer 脚本输出 `[RayTracerTests] all tests passed`；官方项目构建成功；
- Poolcore Courtyard 同预设黑盒复验与截图量化已通过，Correct-3.1 和 Correct-3 正式完成。

最终黑盒与量化结论（2026-07-18）：

- Correct-3.1 当前图与 Correct-3 前基线肉眼接近，符合本阶段“修正权重语义、亮度稳定优先，不追求最平滑”的目标；
- 对齐截图后，全图平均亮度变化约 `-0.008/255`，建筑区域约 `+0.039/255`，左右墙约 `+0.247/-0.101`，未出现可感知整体提亮或压暗；
- 天空区域近乎逐像素一致，变化集中于实际参与过滤的几何区域，排除了全局显示链路漂移；
- 相比出现条纹的首版 Correct-3，低频偏差在左墙、右墙和侧地面分别下降约 `31%`、`47%`、`66%`，竖纹与横纹事故已消除至基线附近；
- 当前墙面高频颗粒指标相对 Correct-3 前约降低 `3%～5%`，侧地面基本持平；收益保守但为实质变化，不是滤波失效；
- 水面保持 `delta_transmission` 直通，因此噪声与 Correct-3 前接近，且未重新出现整体变亮；
- 未观察到新的跨材质泄漏、强边缘模糊、HDR 白块或结构化条纹；Correct-3 的实现、自动回归和视觉门禁均通过。

明确保留、不回退的 Correct-3 内容：

- Film Welford 亮度矩与方差；
- Normal 权重允许归零；
- class、coverage 与 hit/miss 硬边界；
- HDR 高能邻居鲁棒传播；
- Dielectric 与其他受保护 class 精确直通；
- 显示滤波不修改原始 Film。

### AOV-Correct-4：kernel 与质量/成本重测（对比能力已实现，等待实测，2026-07-18）

目标：在语义正确后选择 Preview 的最终空间滤波预算。

已实现：

- 保留 Correct-3 已验收的 `3×3` tent kernel 作为默认，权重和为 `16`；
- 新增标准 `5×5` B3-spline kernel，由一维 `{1,4,6,4,1}` 外积生成，25 taps、权重和 `256`；
- 两种 kernel 共享完全相同的方差、Normal、方向 Depth、Albedo、coverage/class 和 HDR 权重语义，只改变空间支撑范围；
- `AOVAtrous.filter()` 支持 `{ kernel, iterations }` 配置，同时继续兼容旧的数字 iterations 调用；未知 kernel 明确报错，不静默回退；
- Inspector 新增 `3×3 Current / 5×5 B3-spline` 切换和 1～3 轮选择；默认仍为 `3×3 + 3轮`，因此现有已验收画面不会自动改变；
- 每次 AOV 滤波返回 kernel taps、passes、候选邻域访问数和有效权重访问数；
- 主程序单独记录最后一次与累计 AOV 滤波耗时、调用数和访问数，并继续分开记录显示编码总耗时与纹理上传耗时；
- 每次开始新渲染时重置 Correct-4 统计，避免多次实验相互污染；
- 自动回归覆盖 kernel taps/权重和、常量图归一化、候选访问计数、5×5 确定性、受保护 class 精确直通、跨 class 不泄漏和未知 kernel 拒绝；
- Correct-1～3 的全部回归继续通过；Lua LSP 全工作区 0 Error，RayTracer 脚本输出 `[RayTracerTests] all tests passed`，官方项目构建成功。

待实测矩阵：

- 固定同一 Preview 配置、seed 和 Film，比较 `3×3/5×5 × 1/2/3轮`；
- 分别测量 diffuse 平坦区域、强边缘、水面和 HDR 高光区域；
- 记录最后一次 AOV filter 秒数、候选/有效访问数、全图与区域亮度、颗粒指标和边缘梯度；
- 只有 5×5 或更高轮数的观感收益明显且 UI 仍可响应时，才考虑改变 Preview 默认值。

实测结果（Preview 32 spp，2026-07-18）：

| Kernel / 轮数 | 最后一次 AOV | 累计 AOV（33 次） | 最后候选访问 | 最后有效访问 | 视觉结论 |
|---|---:|---:|---:|---:|---|
| `3×3 / 1轮` | `0.427s` | `11.553s` | `129,668` | `112,493` | 墙面存在明显低频斑块，不可作为默认 |
| `3×3 / 3轮` | `0.841s` | `26.856s` | `384,324` | `304,754` | 墙面形成正常细腻过渡，Correct-3 已验收基线 |
| `5×5 / 1轮` | `0.794s` | `24.485s` | `357,588` | `290,193` | 比 3×3/1轮仅少量降噪，仍不能替代多尺度三轮 |
| `5×5 / 3轮` | `2.130s` | `61.248s` | `1,049,468` | `733,538` | 仅小幅减少残余噪点，成本显著过高 |

实测控制变量确认：

- 四组 paths=`1,179,648`、bounces=`2,855,906`、hits=`1,912,607`、misses=`943,299`、shadows=`1,113,536` 完全一致，证明画面差异只来自显示滤波；
- `3×3/3轮` 相对 `3×3/1轮`，左右墙高频颗粒指标分别约下降 `57%` 和 `56%`，墙面斑块转为细腻过渡；
- `5×5/1轮` 相对 `3×3/1轮`，左右墙高频颗粒仅约下降 `19%` 和 `17%`，说明扩大单轮 kernel 不能替代 À-Trous 多尺度传播；
- `5×5/3轮` 相对 `3×3/3轮`，左右墙高频颗粒仅再下降约 `9%` 和 `6%`；肉眼收益很小；
- 最后一次 AOV 成本方面，`5×5/3轮` 是 `3×3/3轮` 的约 `2.53×`；累计成本约 `2.28×`；
- `5×5/1轮` 与 `3×3/3轮` 成本接近，但前者仍有一轮方案的低频斑块，因此质量/成本不占优；
- 水面属于 `delta_transmission` 直通；截图中的水面差异来自各次截图对齐/显示捕获，不作为 kernel 质量选择依据。

最终决策：

- Preview 默认保持 `3×3 + 3轮`；
- `1轮` 因墙面低频斑块被淘汰，不再作为默认候选；
- `5×5` 保留为 Inspector 实验选项，不设为 Preview 默认；
- Correct-4 的 kernel/轮数比较完成，结论是“多尺度轮数收益显著，5×5 扩核收益不足以覆盖纯 Lua 成本”；
- 后续若需要进一步降低水面或高光噪声，应进入 lobe/transmission 专项评估，而不是继续扩大 diffuse 空间 kernel。

门禁：

- `256×144` Preview 的 UI 仍可响应；
- 降噪显示成本与路径积分成本分开统计；
- 默认方案以亮度稳定和材质可信为先，不以最平滑为先。

### AOV-Correct-5：transmission 最小诊断（已停止，2026-07-18）

目标：确认水面噪声的路径构成和终止去向，并在收益不足时停止 transmission 专项显示候选；不拆完整 lobe Film。

已实现的最小诊断：

- `Dielectric:scatter()` 增加第四个只读返回值，标记本次 Fresnel 选择为 `reflection` 或 `transmission`；原有方向、衰减、specular 标记和随机数调用顺序不变，旧的三返回值调用继续兼容；
- `PathIntegrator` 仅复用路径追踪过程中已经得到的 hit，统计主射线首次命中 `delta_transmission` 后的分支和去向，不增加任何 `scene:hit()`；
- 分支统计：主 transmission 总数、Fresnel reflection 数、refraction 数，以及缺少分支元数据的数量；
- 去向统计：沿连续 delta 链找到的首次 diffuse、glossy、emission、其他非 delta 命中，或 sky、Russian Roulette、scatter stop、depth limit 终止；
- 每条主 transmission 路径最多进入一个去向桶；日志额外输出 `unresolved`，用于发现统计未闭合；
- 渲染完成时输出两行 `[RayTracer][H5]`，不新增 Inspector 开关，不改变 Correct-4 默认 `3×3 + 3轮`；
- 本阶段不创建 diffuse/specular/transmission Film，不修改 Beauty Film 或 Primary AOV。

弱 transmission 显示候选决策：

- 已完成一次固定基准 Preview 量化实验：`256×144`、`32 spp`、`maxDepth=6`、denoise 开启、`3×3 + 3轮`；
- 候选曾以 `20%` 显示混合强度运行，统计确认 `6721` 个 transmission 像素参与，平均亮度变化 `-0.021%`，同类相邻亮度差变化 `-2.831%`；
- 虽然亮度门禁和数值噪声指标通过，但完整截图中水面没有可感知的降噪改善；
- 候选已移除，默认 `delta_transmission` 恢复直通；不保留候选开关、候选统计或额外显示成本；
- Correct-5 在 transmission 统计诊断完成、弱显示候选收益不足处停止；后续如需改善水面，应等待 MIS、路径指导或完整 transmission/lobe AOV 方案，不继续放宽当前显示滤波门禁。

自动回归：

- 强制覆盖 Dielectric Fresnel reflection 与 refraction，并校验事件标签、方向、衰减和 specular 契约；
- 覆盖主 transmission 的首次 diffuse、sky 和 depth-limit 分类；
- 用兼容旧三返回值的 Dielectric 包装与新诊断路径比较，确认相同随机输入下 Beauty RGB 完全一致；
- Correct-1～4 既有断言继续输出 `[RayTracerTests] all tests passed`；Lua LSP 全工作区 0 Error；官方项目构建成功。

黑盒辅助步骤：

1. Inspector 保持 `Preview / 256×144 / 32 spp / maxDepth 6`；
2. 保持 denoise 开启、kernel=`3×3`、iterations=`3`，不要在本次诊断中切换其他参数；
3. 点击开始并等待完整渲染，不要中途终止；
4. 从日志复制两行 `[RayTracer][H5]`；如水面观感与此前明显不同，再附一张完整截图；
5. 重点检查 `unclassifiedBranch=0` 与 `unresolved=0`。若不为零，先修统计闭合，不进入过滤原型。

候选决策门禁：

- 只有当 refraction 后首次命中 diffuse/glossy 的路径占比足够高，且水面噪声明显来自可稳定引导的后续表面时，才评估弱 transmission 显示候选；
- 若 sky、连续 delta 或 depth-limit 占主导，Primary AOV 不足以安全约束空间传播，应停止弱过滤并等待 MIS 或更完整的 lobe/path guidance；
- 任何候选仍须保持水面平均亮度变化不超过 `5%`、Film 与路径统计完全不变、默认 Dielectric 继续直通；
- 收益不足则在 Correct-5 停止，不为“完整 lobe 管线”增加无证据复杂度。

暂不实现：

- 独立 diffuse/specular/transmission/emission Film；
- Albedo demodulation；
- transmission 默认空间过滤；
- 额外路径求交或重新追踪；
- speculative Inspector 选项。

## 7. 验收与回归指标

固定基准：

- Poolcore Courtyard；
- `256×144`；
- seed 42；
- Preview `maxDepth=6`；
- 至少比较 `8 spp` 和 `32 spp`；
- 同一 Film 分别输出 denoise off/on，禁止重新采样后直接比较。

必须记录：

1. Film 与 AOV sample count；
2. 全图线性平均亮度；
3. 水面、左墙、地面、彩球边缘的区域平均亮度；
4. 开关降噪后的区域亮度相对变化；
5. 相邻像素亮度差或等价颗粒指标；
6. 强边缘梯度保留率；
7. 过滤耗时、邻域访问数和纹理上传耗时；
8. NaN、Inf 和空 AOV 像素计数。

建议初始门禁：

- diffuse 大区域平均亮度变化目标不超过 `3%`；
- Dielectric 水面平均亮度变化目标不超过 `5%`，若保守直通则应接近 `0%`；
- 不允许出现整片表面由暗变白的视觉跳变；
- Film、路径统计和 BVH 统计在开关降噪时必须完全一致；
- 任何不能满足亮度门禁的方案不得作为默认 Preview 降噪。

这些阈值是工程初始门禁，不是算法真理；后续可根据 32 spp 未降噪参考图和更高 spp 基线调整，但调整必须有数据记录。

## 8. 当前决策

- 当前 AOV A-Trous 原型保留为问题复现和差分基线，不作为可信完成态；
- `AOV-Correct-1` 已完成：AOV sample 累积、有效命中平均、coverage 和调度一致性测试均已落地；
- `AOV-Correct-2` 已完成：材质分类、delta/emission 保守直通、Beauty/AOV 接口解耦、自动化回归与 Poolcore Courtyard 黑盒视觉门禁均已通过；
- `AOV-Correct-3` 首版黑盒曾因无方向 Depth hard-stop 产生墙面竖纹与地面横纹；
- `AOV-Correct-3.1` 已以方向深度梯度残差修复该问题，自动回归、截图量化与 Poolcore Courtyard 黑盒均已通过；Correct-3 正式完成；
- `AOV-Correct-4` 已完成：四组 kernel/轮数黑盒与 H4 成本实测证明轮数是主要质量变量，5×5 的小幅收益不足以覆盖约 2.3～2.5 倍成本；Preview 默认保持 `3×3 + 3轮`；
- `AOV-Correct-5` 已完成并停止：transmission 统计闭环通过；弱 transmission 显示候选在固定基准下仅带来 `-2.831%` 相邻亮度差变化，肉眼无可感知收益，已恢复 `delta_transmission` 直通；后续等待 MIS、路径指导或完整 transmission/lobe AOV；
- Inspector 在渲染完成后切换 denoise 不主动刷新显示的既有行为按当前决策暂不修改；
- Correct-4 继续以亮度稳定和材质可信为首要门禁，不通过放宽权重或增加轮数单纯追求平滑。
