# Read-only pre-flight check for the Windows-GPU-UNLOCK headless USB route.
# Changes nothing: no BitLocker, Secure Boot, boot entry, disk or GPU setting is touched.
# Works without elevation; run it elevated for the most reliable BitLocker reading.
#
#   .\preflight.ps1 -Repo C:\TOOLS\Windows-GPU-UNLOCK -Assets C:\LOCAL-FIRMWARE\assets
param([string]$Repo,[string]$Assets)
$ErrorActionPreference='Stop'
$results=[Collections.Generic.List[object]]::new()
function Add([string]$check,[ValidateSet('OK','WARN','FAIL','INFO')][string]$status,[string]$detail) {
 $results.Add([pscustomobject]@{Check=$check;Status=$status;Detail=$detail})
}
function Reg([string]$path,[string]$name) {
 try{(Get-ItemProperty -LiteralPath $path -Name $name -ErrorAction Stop).$name}catch{$null}
}

# GPU
$smi=Get-Command nvidia-smi -ErrorAction SilentlyContinue
if($smi) {
 $gpu=(& nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>$null | Select-Object -First 1)
 if($gpu -match 'RTX 30'){Add 'NVIDIA GPU' OK $gpu}
 elseif($gpu){Add 'NVIDIA GPU' WARN "$gpu - the project targets specific RTX 30 cards, check docs/COMPATIBILITY.en.md"}
 else{Add 'NVIDIA GPU' FAIL 'nvidia-smi returned no GPU'}
} else {Add 'NVIDIA GPU' FAIL 'nvidia-smi not found - is the NVIDIA driver installed?'}
$others=@(Get-CimInstance Win32_VideoController | Where-Object {$_.Name -notmatch 'NVIDIA'} | ForEach-Object Name)
Add 'Other display adapters' INFO $(if($others.Count){$others -join ', '}else{'none (no iGPU in use)'})

# Firmware mode and Secure Boot
$fw=$env:firmware_type
if(!$fw){$fw=@{1='Legacy';2='UEFI'}[[int](Reg 'HKLM:\SYSTEM\CurrentControlSet\Control' 'PEFirmwareType')]}
if($fw -eq 'UEFI'){Add 'UEFI boot' OK 'Windows was started in UEFI mode'}
elseif($fw){Add 'UEFI boot' FAIL "Windows is running in $fw mode, UEFI is required"}
else{Add 'UEFI boot' WARN 'firmware mode unknown'}
$sb=Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' 'UEFISecureBootEnabled'
if($sb -eq 1){Add 'Secure Boot' FAIL 'enabled - the unsigned EFI will not start; disable it in the firmware setup'}
elseif($sb -eq 0){Add 'Secure Boot' OK 'disabled'}
else{Add 'Secure Boot' WARN 'state unknown'}

# BitLocker: elevated cmdlet first, shell property otherwise.
$bl=$null
try{$v=Get-BitLockerVolume -MountPoint C: -ErrorAction Stop;$bl=if([int]$v.ProtectionStatus -ne 0){1}elseif([int]$v.VolumeStatus -eq 0){2}else{5}}catch{}
if($null -eq $bl){$bl=(New-Object -ComObject Shell.Application).NameSpace('C:').Self.ExtendedProperty('System.Volume.BitLockerProtection')}
switch([int]$bl) {
 {$_ -in 1,3,6} {Add 'BitLocker on C:' FAIL 'protection ACTIVE - Windows will ask for the recovery key on a dark screen and power off. Suspend it first (see ANLEITUNG.md)'}
 5 {Add 'BitLocker on C:' WARN 'encrypted, protection suspended - OK for the unlock, resume it when you are done'}
 4 {Add 'BitLocker on C:' WARN 'decryption in progress - wait until it has finished'}
 default {Add 'BitLocker on C:' OK 'not protected'}
}

# Fast Startup keeps the GPU from a true cold start.
$hb=Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled'
if($hb -eq 1){Add 'Fast Startup' WARN 'enabled - "Shut down" is then not a full shutdown; disable it or use shutdown /s /t 0'}
else{Add 'Fast Startup' OK 'disabled'}

# Upstream project and local firmware assets
if($Repo) {
 $spec=Join-Path $Repo 'internal-boot/unlock/assets.json'
 if(Test-Path -LiteralPath $spec){Add 'Windows-GPU-UNLOCK' OK $Repo}else{Add 'Windows-GPU-UNLOCK' FAIL "not found or incomplete: $Repo"}
 if($Assets -and (Test-Path -LiteralPath $spec)) {
  $bad=@()
  foreach($a in (Get-Content -LiteralPath $spec -Raw | ConvertFrom-Json)) {
   $f=Join-Path $Assets $a.Name
   if(!(Test-Path -LiteralPath $f)){$bad+="$($a.Name) missing";continue}
   if((Get-Item -LiteralPath $f).Length -ne $a.Bytes -or (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash -ne $a.Sha256.ToUpperInvariant()){$bad+="$($a.Name) wrong hash"}
  }
  if($bad.Count){Add 'Firmware assets' FAIL ($bad -join '; ')}else{Add 'Firmware assets' OK "all files match assets.json in $Assets"}
 }
} else {Add 'Windows-GPU-UNLOCK' INFO 'not checked - pass -Repo (and -Assets) to verify the project and firmware files'}

# Optional benchmark prerequisites
$py=Get-Command python -ErrorAction SilentlyContinue
if($py){
 $torch=& $py.Source -I -c "import torch;print(torch.__version__, torch.cuda.is_available())" 2>$null
 if($torch -match 'True'){Add 'Benchmark (PyTorch)' OK "torch $torch"}else{Add 'Benchmark (PyTorch)' INFO 'PyTorch with CUDA not found - only needed for bench\bench_matmul.py'}
} else {Add 'Benchmark (PyTorch)' INFO 'python not found - only needed for bench\bench_matmul.py'}

$colors=@{OK='Green';WARN='Yellow';FAIL='Red';INFO='Gray'}
foreach($r in $results){Write-Host ('[{0,-4}] {1,-24} {2}' -f $r.Status,$r.Check,$r.Detail) -ForegroundColor $colors[$r.Status]}
$fail=@($results | Where-Object Status -eq 'FAIL').Count
if($fail){Write-Host "`n$fail blocking problem(s). Fix them before booting the unlock stick." -ForegroundColor Red;exit 1}
Write-Host "`nNo blocking problems found. This does not guarantee compatibility - follow the project guide for your exact profile." -ForegroundColor Green
