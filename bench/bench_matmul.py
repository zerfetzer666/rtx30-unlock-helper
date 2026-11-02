"""Matmul benchmark for the RTX 30 unlock: FP32 (control), TF32, FP16, BF16.

torch.matmul with FP32 accumulation, median of 5 runs of 20 matmuls each.

Usage:   python -I bench_matmul.py <label>     (e.g. "locked" or "unlocked")
The result is saved as results-<label>-<time>.json next to this script.
"""

import json
import statistics
import subprocess
import sys
import time
from pathlib import Path

import torch

SIZES = (4096, 8192)
RUNS = 5
ITERS = 20
MODES = ("fp32", "tf32", "fp16", "bf16")


def smi(query):
    out = subprocess.run(
        ["nvidia-smi", f"--query-gpu={query}", "--format=csv,noheader,nounits"],
        capture_output=True, text=True, check=False,
    )
    return [v.strip() for v in out.stdout.strip().split(",")]


def bench(n, mode):
    # Force FP32 accumulation for FP16/BF16 (no reduced-precision reduction).
    torch.backends.cuda.matmul.allow_fp16_reduced_precision_reduction = False
    torch.backends.cuda.matmul.allow_bf16_reduced_precision_reduction = False
    torch.backends.cuda.matmul.allow_tf32 = mode == "tf32"
    dtype = {"fp32": torch.float32, "tf32": torch.float32,
             "fp16": torch.float16, "bf16": torch.bfloat16}[mode]
    a = torch.randn(n, n, device="cuda", dtype=dtype)
    b = torch.randn(n, n, device="cuda", dtype=dtype)
    for _ in range(5):
        torch.matmul(a, b)
    torch.cuda.synchronize()

    tflops = []
    for _ in range(RUNS):
        start = torch.cuda.Event(enable_timing=True)
        end = torch.cuda.Event(enable_timing=True)
        start.record()
        for _ in range(ITERS):
            torch.matmul(a, b)
        end.record()
        torch.cuda.synchronize()
        seconds = start.elapsed_time(end) / 1000
        tflops.append(2 * n ** 3 * ITERS / seconds / 1e12)
    power, sm_clock = smi("power.draw,clocks.sm")
    del a, b
    torch.cuda.empty_cache()
    return {"median_tflops": round(statistics.median(tflops), 2),
            "runs": [round(t, 2) for t in tflops],
            "power_w_after": power, "sm_clock_mhz_after": sm_clock}


def main():
    if not torch.cuda.is_available():
        sys.exit("PyTorch cannot see a CUDA GPU. Install a CUDA build of PyTorch.")
    label = sys.argv[1] if len(sys.argv) > 1 else "run"
    name, driver, power_limit = smi("name,driver_version,power.limit")
    meta = {"label": label, "time": time.strftime("%Y-%m-%d %H:%M:%S"),
            "gpu": name, "driver": driver, "power_limit_w": power_limit,
            "torch": torch.__version__, "cuda": torch.version.cuda,
            "method": f"torch.matmul, median of {RUNS} runs x {ITERS} matmuls"}
    print(f"{name} | driver {driver} | power limit {power_limit} W | torch {torch.__version__}")

    results = {}
    print(f"{'n':>5}  {'mode':<5}  {'TFLOPS':>7}   (W / MHz after)")
    for n in SIZES:
        for mode in MODES:
            r = bench(n, mode)
            results[f"{n}-{mode}"] = r
            print(f"{n:>5}  {mode:<5}  {r['median_tflops']:>7.2f}   "
                  f"({r['power_w_after']} W / {r['sm_clock_mhz_after']} MHz)")

    out = Path(__file__).with_name(f"results-{label}-{time.strftime('%Y%m%d-%H%M%S')}.json")
    out.write_text(json.dumps({"meta": meta, "results": results}, indent=2), encoding="utf-8")
    print(f"\nSaved: {out}")


if __name__ == "__main__":
    main()
