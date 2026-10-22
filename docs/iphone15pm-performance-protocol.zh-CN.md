# iPhone 15 Pro Max 发热定位与 30/60 FPS 对照

目标：降低持续功耗，同时保持游戏正确性。测量不是自动优化，不声称 RenderPass/带宽数值等于实际能耗。

## 本次插桩

- 正常 boot 日志每 300 帧新增一行「渲染负载」：实际 Metal RenderPass/Draw、估算附件 Load/Store MiB/帧、全量读写通道；计数源直接复用 nvn_mtl.m 的累积统计。
- 同一行显示 NVN 翻译线程的 CPU 时间三段：准备（begin/index）、执行（命令 replay）、提交（Metal commit）；阶段加起来不一定严格等于既有提交 CPU（还有 snap 回收和计时器自身）。
- 原有 10 秒「诊断」行保留 FPS、CPU、GPU avg/p95、温控、亮度。
- 附件带宽是依据 RenderPass 的 Load/Store 模型计算的**估算量**，不是硬件实际 DRAM 流量。翻译 CPU 分段包含若干时钟读取，采用累积计数避免逐命令写日志。

## 真机测试

1. 同一 iPhone 15 Pro Max、同一 iOS、同一关卡、相同画质，关掉充电，固定亮度（如 40%），尽量相近的室温；先待机冷却至温控 0。
2. A：手动省电关（60 FPS），连续正常战斗 10–15 分钟，导出游戏「分享日志」或 Documents/boot.txt。
3. 充分冷却至温控 0；B：手动省电开（30 FPS），同场景同时间重测。第二轮结束也导出日志。请分别命名 A-60.txt 和 B-30.txt，防止 boot.previous.txt 被覆盖。
4. 必要时第三轮：60 FPS + 智能散热，对照温控进入 Fair/Serious 后自动降帧行为。诊断环境变量 DM_FPS 会强制 FPS，仅用于实验；普通玩家不设置。
5. 在本仓库运行 `python3 scripts/analyze_thermal_log.py A-60.txt --csv A-60.csv`，对 B 同理；或直接把两份日志发给 ChatGPT。
6. 对比第 2 分钟后的相同场景：平均/峰值 CPU、GPU p95、RenderPass、Draw、附件 MiB/帧及其乘以 FPS 的 MiB/秒；优先观察哪个项随 FPS/画面模式变化。

注意：iPhone 机身温度和芯片真实瓦数没有包含在日志里，只有 NSProcessInfo 温控档位。不能从 CPU% 或 GPU 毫秒直接换算功耗。此阶段不默认开启曾在 A17 上重影/卡顿的 DM_RT_AB=1 渲染实验。
