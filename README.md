# RTX 30 Unlock Helper

**Guide:** [English](GUIDE.md) | [Deutsch](ANLEITUNG.md)

Companion tools for the headless USB route of
[Windows-GPU-UNLOCK](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK):

| File | Purpose |
|---|---|
| `preflight.ps1` | Read-only check before the unlock boot: GPU, UEFI mode, Secure Boot, **BitLocker**, Fast Startup, project and firmware asset hashes |
| `bench/bench_matmul.py` | FP32/TF32/FP16/BF16 matmul benchmark (PyTorch) |
| `bench/compare.py` | Compares a locked and an unlocked run |
| [`GUIDE.md`](GUIDE.md) | Step-by-step guide in English |
| [`ANLEITUNG.md`](ANLEITUNG.md) | Step-by-step guide in German |

> **Disclaimer:** The unlock is experimental and changes how the GPU is initialized.
> Use at your own risk. This repository is not affiliated with the upstream project
> or with NVIDIA. It contains **no** firmware and no upstream code. Always follow the
> upstream documentation for your exact hardware profile.

## The most common failure: silent power-off after the unlock

If the PC switches off about a minute after a clean unlock (`FINAL status=0 … clean=1`)
without reaching Windows, BitLocker is the most likely cause
([#125](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/125)). Booting the
unsigned stick with Secure Boot off changes the measured boot chain, so Windows Boot
Manager asks for the recovery key. The display is still dark at that point, and
after about a minute without input, Windows powers off by design
([Microsoft](https://learn.microsoft.com/en-us/troubleshoot/windows-client/windows-security/bitlocker-recovery-auto-shutdown-in-uefi-mode)).

Fix (elevated PowerShell, recovery key at hand):

```powershell
Suspend-BitLocker -MountPoint "C:" -RebootCount 0
```

Resume protection when you no longer use the unlock:

```powershell
Resume-BitLocker -MountPoint "C:"
```

While suspended, the volume key is stored in the clear on the disk.

## Quick start

```powershell
# 1. Baseline
python -I bench\bench_matmul.py locked
# 2. Suspend BitLocker (see above), disable Secure Boot in the firmware setup
# 3. Pre-flight
.\preflight.ps1 -Repo C:\TOOLS\Windows-GPU-UNLOCK -Assets C:\LOCAL-FIRMWARE\assets
# 4. Build and stage the stick per upstream docs/HEADLESS-USB.en.md
# 5. Full shutdown, boot the stick from the boot menu, press nothing
# 6. Verify
python -I bench\bench_matmul.py unlocked
python -I bench\compare.py bench\results-locked-<time>.json bench\results-unlocked-<time>.json
```

FP32 stays unchanged; TF32/FP16/BF16 should be about 1.6× faster.

### Example: RTX 3090 Founders Edition, MSI B550, Ryzen 9 5900X

| Precision | Locked | Unlocked | Factor |
|---|---|---|---|
| BF16 | 69–71 TFLOPS | 114–116 TFLOPS | 1.60–1.68× |
| FP16 | 68–69 TFLOPS | 111–113 TFLOPS | 1.60–1.65× |
| TF32 | 34–38 TFLOPS | 57–61 TFLOPS | 1.63–1.65× |
| FP32 | 24 TFLOPS | 24 TFLOPS | 0.99× |

## License

MIT, see [LICENSE](LICENSE). The upstream project is GPL-2.0-only; nothing from it
is included here.
