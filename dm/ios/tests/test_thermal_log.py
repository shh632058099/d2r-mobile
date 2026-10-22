import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[3] / "scripts" / "analyze_thermal_log.py"
spec = importlib.util.spec_from_file_location("thermal_log", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class ThermalLogTests(unittest.TestCase):
    def test_old_build_without_render_summary(self):
        text = "[dm] [诊断] 第 30 秒 CPU 91% 帧率 59.9 GPU 9.71 / p95 14.08 ms（599 帧） 温控 0 亮度 0.65 电量 50%\n"
        rows, loads, scales = mod.extract(text)
        self.assertEqual((len(rows), len(loads), len(scales)), (1, 0, 0))
        self.assertEqual(rows[0]["gpu_avg_ms"], 9.71)

    def test_render_summary_and_scale(self):
        text = "[dm] [nvn] 渲染负载 至帧 600：每帧 RenderPass 38.5 Draw 1520 附件Load 31.25 MiB Store 80.75 MiB 全量读写通道 2.5；翻译CPU 准备 0.200 ms 执行 2.400 ms 提交 0.350 ms\n[dm] [perf] 温控 1 3D 0.70 帧率 59.8\n"
        rows, loads, scales = mod.extract(text)
        self.assertFalse(rows)
        self.assertEqual(loads[0]["render_pass"], 38.5)
        self.assertEqual(loads[0]["replay_ms"], 2.4)
        self.assertEqual(scales[0]["scale"], 0.70)

if __name__ == "__main__":
    unittest.main()
