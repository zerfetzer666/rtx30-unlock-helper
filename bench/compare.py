"""Compare two bench_matmul.py result files.

Usage:   python -I compare.py results-locked-....json results-unlocked-....json
"""

import json
import sys
from pathlib import Path


def load(path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    before, after = load(sys.argv[1]), load(sys.argv[2])
    print(f"before: {before['meta']['label']} ({before['meta']['time']})")
    print(f"after:  {after['meta']['label']} ({after['meta']['time']})\n")
    print(f"{'n':>5}  {'mode':<5}  {'before':>8}  {'after':>8}  {'factor':>6}")
    for key, b in before["results"].items():
        a = after["results"].get(key)
        if a is None:
            continue
        n, mode = key.split("-")
        x, y = b["median_tflops"], a["median_tflops"]
        print(f"{n:>5}  {mode:<5}  {x:>8.2f}  {y:>8.2f}  {y / x:>5.2f}x")
    print("\nFP32 should stay unchanged. A factor of about 1.6x or more for "
          "TF32/FP16/BF16 means the unlock is active.")


if __name__ == "__main__":
    main()
