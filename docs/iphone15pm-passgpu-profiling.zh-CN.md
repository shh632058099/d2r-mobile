# iPhone 15 Pro Max 完整性能诊断

## 一次开启全部诊断

本仓库已有逐帧计时、长帧归因、温控采样、内存普查和逐线程 CPU 采样。本轮把它们整合为一个开关，避免每次改环境变量或重新编译不同诊断版本。

在 App 的 Documents 根目录（`boot.txt` 所在目录）创建一个**空文件** `diagnostics.enable`，然后完全退出并重新启动 App。不是 `D2R Mobile Resources` 子目录，也不要让文件名变成 `diagnostics.enable.txt`。

启用后会生成 / 更新：

| 文件 | 内容 |
|---|---|
| `boot.txt` | 每 300 帧的 CPU 阶段耗时、线程策略、进程 footprint、Metal 分配与资源普查、游戏堆余量和最大可分配块；如另建 `passdump.enable` 空文件，才额外把帧 6000–6002 的 RenderPass / 附件 / Shader 关联细节写在这里 |
| `frames.tsv` | 逐帧帧时间、GPU 时间、CPU 时间、出图等待、RenderPass / Draw、附件读写、上传、管线创建等指标；不记录大量函数调用计数 |
| `heat.tsv` | 每 10 秒的进程 CPU%、实际 FPS、GPU 均值/P95、温控等级、亮度、电量状态相关信息（电量和充电状态也会写入 `boot.txt`） |
| `threads.tsv` | 每 10 秒各线程 CPU 占用率及线程名，帮助确认是游戏线程、NVN 翻译线程还是其他线程吃 CPU |
| `memory.tsv` | 每 5 秒记录 phys_footprint、系统剩余内存、Metal 分配量和各类 VM 区域估算；区域估算可能重复计数，`footprint差值` 可为负，不能当作真实“未归属内存” |
| `passgpu.tsv` | 每 10 次提交采样一次的逐 RenderPass GPU 时间、尺寸、格式、Load 行为、Draw 数；`boot.txt` 每约 300 帧另有热点 Top 5 汇总 |
| `perf.txt` | 性能 / 长帧上下文记录；`# RUN START` 标记进程运行边界，`# PERF SEGMENT START` 标记文件轮转后的新段，避免把不同运行的进程秒数混在一起 |

`passgpu.tsv` 稀疏采样后文件体积和 GPU 计时开销会比逐提交采样小。完整诊断默认不启用高开销 pass dump。需要关联附件 / Shader 时，在 Documents 另外新建 `passdump.enable`，重启后仅记录帧 6000–6002；该三帧不应用于性能评价。删除文件并重启即可关闭。`DM_NVN_PASSDUMP_ALL` 不开启。非采样提交不等待计时环，也不写 GPU 时间戳。仍然属于诊断模式，不应用该次数据评价最终帧率、温度或耗电。

## iPhone 上如何取文件

项目已开启 iOS 文件共享。可以在 iPhone「文件」App 的「我的 iPhone」/ D2R Mobile Documents（不同安装方式显示名称可能不同）中，选择并分享 `frames.tsv`、`heat.tsv`、`threads.tsv` 和 `passgpu.tsv`。也可以通过 Finder 的文件共享功能取出 App Documents。请同时提供 `boot.txt` 和 `perf.txt`，方便按时间对齐。

## 运行时长与注意事项

1. 开启后运行游戏 3–5 分钟，至少覆盖温控升档前、升档后及一次明显长帧；不要开启 `DM_NVN_PASSGPU_SERIAL`，它会强制串行化通道，严重改变真实 GPU 并行行为。
2. 如果重点是内存增长，进入相同场景后尽量保持场景与活动稳定；`memory.tsv` 每 5 秒做一次 VM 分区扫描，`boot.txt` 每 300 帧记录一次 Metal 纹理/缓冲对象驻留普查。两种普查本身会增加 CPU 和少量内存开销，诊断期间的占用应视为带测量开销的数据。
3. 测完后删除 `diagnostics.enable` 并完全重启 App。若只想保留旧的 GPU 通道诊断，可继续使用 `passgpu.enable`，该旧开关不会开启其他日志。
4. 完整诊断默认只记录逐帧指标，不写 NVN 函数调用次数，控制文件大小。`passgpu.tsv` 约每 10 次提交采样一次；如果仍然太大，缩短测试时间即可。

## 离线分析

```bash
python3 dm/gfx/tools/passgpu_top.py /path/to/log-directory 300 15
```

工具读取目录中的 `passgpu.tsv`，输出耗时较高的通道。`gpu_ms` 是含流水重叠的通道跨度，**不能直接相加**；`inc_ms` 是时间线增量估算，更适合初步寻找热点。将其与 `frames.tsv` 同一时间的 `@gpu_ms`、`@proc_cpu_ms`、`@wait_ms`、`@sub_cpu_ms`，以及 `threads.tsv` 的线程占用和 `boot.txt` 的内存快照一起分析。

## 正常运行

`diagnostics.enable` 不存在时，这组额外诊断默认关闭；不会改变画质、帧率策略或 RenderPass 的 Load/Store 语义。