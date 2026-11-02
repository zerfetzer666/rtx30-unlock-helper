# Guide: RTX 30 unlock on Windows from a USB stick

**English** | [Deutsch](ANLEITUNG.md)

This guide accompanies the headless USB route of
[Windows-GPU-UNLOCK](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK). It adds
a pre-flight check, a way to measure the result, and the fix for the most common
problem: **the PC powers off after the unlock without starting Windows**
([#125](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/125)).

> **Important:** The procedure is experimental and changes how the GPU is
> initialized. Use at your own risk. This repository is not affiliated with the
> upstream project or with NVIDIA. It contains **no** firmware and no upstream code.
> The upstream documentation always takes precedence.

## What you need

- A supported GPU and mainboard combination. Check this **before** anything else in
  [COMPATIBILITY](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/blob/main/docs/COMPATIBILITY.en.md)
  and [CONFIRMED-SETUPS](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/blob/main/docs/CONFIRMED-SETUPS.en.md).
- Windows 10/11 running in UEFI mode
- An empty USB stick formatted as FAT32
- The firmware files, which you obtain yourself as described in
  [ASSETS](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/blob/main/docs/ASSETS.en.md).
  These files must not be redistributed.
- Your **BitLocker recovery key** if C: is encrypted. You can find it at
  https://account.microsoft.com/devices/recoverykey.
- Optional, for measuring: Python with a CUDA build of PyTorch

## Step 1: Measure the baseline

Measure once before the unlock so you have something to compare against:

```powershell
python -I bench\bench_matmul.py locked
```

## Step 2: Suspend BitLocker

This is where it usually goes wrong. When the PC boots from the stick with Secure
Boot off, the TPM no longer releases the BitLocker key, and Windows asks for the
recovery key. After the unlock the display is still dark, so you cannot see the
prompt. After about a minute without input, Windows powers off on purpose
([Microsoft](https://learn.microsoft.com/en-us/troubleshoot/windows-client/windows-security/bitlocker-recovery-auto-shutdown-in-uefi-mode)).

Open PowerShell **as administrator**:

```powershell
manage-bde -status C:
Suspend-BitLocker -MountPoint "C:" -RebootCount 0
```

`-RebootCount 0` keeps protection suspended across all restarts until you resume
it yourself. Your data stays encrypted, but while BitLocker is suspended the key is
stored unprotected on the disk. Anyone who removes the SSD can read it.

## Step 3: Disable Secure Boot

Disable Secure Boot in the BIOS/UEFI setup. The unlock file is unsigned and will
not start otherwise. Keep the recovery key at hand while doing this.

## Step 4: Pre-flight check

```powershell
.\preflight.ps1 -Repo C:\TOOLS\Windows-GPU-UNLOCK -Assets C:\LOCAL-FIRMWARE\assets
```

Adjust the paths to your machine. The script only reads and changes nothing. It
checks the GPU, UEFI mode, Secure Boot, BitLocker, Fast Startup, the project and
the firmware file hashes. On **FAIL**, fix the problem first. Run it as
administrator for the most reliable BitLocker reading.

## Step 5: Build the stick

Follow the upstream guide exactly:
[NEW-MACHINE](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/blob/main/docs/NEW-MACHINE.en.md)
for new machines, or [HEADLESS-USB](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/blob/main/docs/HEADLESS-USB.en.md)
for profiles that are already supported.

## Step 6: Unlock boot

1. **Shut the PC down completely.** Do not restart.
2. Power on and open the boot menu (MSI: F11, ASUS: F8, Gigabyte: F12).
3. Select the USB stick. **Do not press any keys.**
4. The screen stays black for a while. The picture returns once Windows has loaded
   the NVIDIA driver.

## Step 7: Verify

```powershell
python -I bench\bench_matmul.py unlocked
python -I bench\compare.py bench\results-locked-<time>.json bench\results-unlocked-<time>.json
```

FP32 stays the same. TF32, FP16 and BF16 should be about **1.6× faster**.
Example RTX 3090 FE: BF16 from 69–71 to 114–116 TFLOPS.

The unlock lasts until the next power-off. For every further unlock, boot from
the stick again.

## Step 8: Afterwards

When you no longer use the unlock, run this from a normal Windows boot:

```powershell
Resume-BitLocker -MountPoint "C:"
```

Then turn Secure Boot back on in the BIOS. If you want the unlock on every boot,
BitLocker has to stay suspended or be turned off. That security trade-off is
yours to weigh.

## Troubleshooting

| What happens | Likely cause | Fix |
|---|---|---|
| PC powers off about 1 minute after the unlock; the log ends with `FINAL status=0 … clean=1` | Invisible BitLocker prompt | Step 2, then try again |
| A normal boot asks for the recovery key | Secure Boot was changed | Enter the key, then step 2 |
| Screen stays black for a long time | No picture until the NVIDIA driver loads | Wait 2–3 minutes, do not power off |
| Benchmark values unchanged | Restart instead of a cold boot, or the unlock skipped itself | Shut down completely, check the logs on the stick |
| `preflight.ps1` reports Fast Startup | "Shut down" is then not a real cold boot | Disable Fast Startup or use `shutdown /s /t 0` |

When reporting a problem upstream: **never** attach firmware, PROM/VBIOS dumps,
recovery keys or serial numbers
([CONTRIBUTING](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/blob/main/docs/CONTRIBUTING.en.md)).
