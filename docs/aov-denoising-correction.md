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

### AOV-Correct-3：方差与边缘停止函数

目标：让滤波强度由噪声和几何连续性决定。

- 累积亮度矩与方差；
- Normal 权重允许归零；
- Depth 权重加入 gradient 与 step；
- hit/miss、coverage 和 material class 参与硬边界判断；
- HDR 高能邻居使用方差驱动的鲁棒传播权重；
- 保留 3×3 kernel，先隔离权重语义的收益。

门禁：

- 水面、白墙和地面指定区域的滤波前后线性平均亮度漂移受控；
- 强边缘梯度保留率不低于纠偏前基线；
- 高亮噪点不会扩散成大面积 Clamp 白块。

### AOV-Correct-4：kernel 与质量/成本重测

目标：在语义正确后选择 Preview 的最终空间滤波预算。

- 比较 3×3 与 5×5 B3-spline；
- 比较 1、2、3 轮及 step 组合；
- 分别测量 diffuse 区域、边缘、水面和高光区域；
- 记录滤波耗时、邻域访问数、亮度漂移和颗粒下降；
- 只在收益明确时启用 5×5 或第三轮。

门禁：

- `256×144` Preview 的 UI 仍可响应；
- 降噪显示成本与路径积分成本分开统计；
- 默认方案以亮度稳定和材质可信为先，不以最平滑为先。

### AOV-Correct-5：可选 lobe 评估

目标：只在保守策略仍不能满足 Preview 时评估更大改造。

- 评估独立 diffuse/specular/transmission Film；
- 只有独立 diffuse lobe 存在时才评估 Albedo demodulation；
- 测量内存、积分器复杂度、组合正确性和真实视觉收益；
- 收益不足则明确停止，不为追求“行业完整度”强行实现。

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
- 下一开发阶段固定为 `AOV-Correct-3`：引入亮度方差与更严格的边缘停止函数；
- 完整 lobe 拆分、Albedo demodulation 和 5×5 kernel 均后置，不阻塞首轮纠偏；
- 在 AOV-Correct-1～3 完成前，不继续通过放宽颜色权重或增加滤波轮数追求更平滑画面。
