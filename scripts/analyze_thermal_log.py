#!/usr/bin/env python3
"""Extract the phone's 10-second heat samples and 300-frame rendering summaries.

Usage: python3 scripts/analyze_thermal_log.py boot.txt --csv samples.csv
No third-party dependencies. Missing measurements remain empty, never inferred.
"""
import argparse
import csv
import re
from pathlib import Path

HEAT = re.compile(r"\[诊断\] 第 (\d+) 秒 CPU ([\d.]+)% 帧率 ([\d.]+) GPU ([\d.]+) / p95 ([\d.]+) ms.*?温控 (\d+).*?亮度 ([\d.]+)")
LOAD = re.compile(r"渲染负载 至帧 (\d+)：每帧 RenderPass ([\d.]+) Draw ([\d.]+) 附件Load ([\d.]+) MiB Store ([\d.]+) MiB 全量读写通道 ([\d.]+)；翻译CPU 准备 ([\d.]+) ms 执行 ([\d.]+) ms 提交 ([\d.]+) ms")
SCALE = re.compile(r"\[perf\] 温控 (\d+) 3D ([\d.]+) 帧率 ([\d.]+)")
FIELDS = ["seconds", "cpu_pct", "fps", "gpu_avg_ms", "gpu_p95_ms", "thermal", "brightness"]

def extract(text):
    rows, loads, scales = [], [], []
    for line in text.splitlines():
        m = HEAT.search(line)
        if m:
            sec, cpu, fps, avg, p95, thermal, bright = m.groups()
            rows.append(dict(zip(FIELDS, [int(sec), float(cpu), float(fps), float(avg), float(p95), int(thermal), float(bright)])))
        m = LOAD.search(line)
        if m:
            frame, *values = m.groups()
            loads.append(dict(frame=int(frame), render_pass=float(values[0]), draws=float(values[1]), load_mib=float(values[2]), store_mib=float(values[3]), full_rw=float(values[4]), prepare_ms=float(values[5]), replay_ms=float(values[6]), commit_ms=float(values[7])))
        m = SCALE.search(line)
        if m:
            state, scale, fps = m.groups()
            scales.append(dict(thermal=int(state), scale=float(scale), fps=float(fps)))
    return rows, loads, scales

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--csv", type=Path, help="Write sampled CPU/GPU/FPS/thermal readings")
    args = parser.parse_args()
    rows, loads, scales = extract(args.log.read_text(encoding="utf-8", errors="replace"))
    if args.csv:
        with args.csv.open("w", encoding="utf-8", newline="") as fh:
            writer = csv.DictWriter(fh, FIELDS); writer.writeheader(); writer.writerows(rows)
    print(f"Heat samples: {len(rows)}; render windows: {len(loads)}; 3D scale entries: {len(scales)}")
    if rows:
        print(f"Duration: {rows[-1]['seconds']} s; max CPU: {max(r['cpu_pct'] for r in rows):.1f}%; max thermal: {max(r['thermal'] for r in rows)}")
        for r in rows: print(f"{r['seconds']:>4}s CPU {r['cpu_pct']:>5.0f}% FPS {r['fps']:>5.1f} GPU {r['gpu_avg_ms']:>5.2f}/{r['gpu_p95_ms']:>5.2f} ms thermal {r['thermal']}")
    for r in loads:
        print(f"frame {r['frame']}: passes {r['render_pass']:.1f} draws {r['draws']:.0f} RT {r['load_mib']:.1f}/{r['store_mib']:.1f} MiB/frame; xlat CPU prepare/replay/commit {r['prepare_ms']:.2f}/{r['replay_ms']:.2f}/{r['commit_ms']:.2f} ms")

if __name__ == "__main__":
    main()
