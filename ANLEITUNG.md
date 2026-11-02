# Anleitung: RTX-30-Unlock unter Windows mit USB-Stick

**Deutsch** | [English](README.md)

Diese Anleitung begleitet den Headless-USB-Weg des Projekts
[Windows-GPU-UNLOCK](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK). Sie ergänzt
dessen Dokumentation um eine Vorabprüfung, eine Erfolgsmessung und die Lösung für
das häufigste Problem: **Der PC schaltet sich nach dem Unlock ab, ohne Windows zu
starten** ([#125](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/issues/125)).

> **Wichtig:** Das Verfahren ist experimentell und greift in den Startvorgang der
> Grafikkarte ein. Benutzung auf eigene Gefahr. Dieses Repository gehört nicht zum
> Originalprojekt und nicht zu NVIDIA. Es enthält **keine** Firmware-Dateien und
> keinen Code des Originalprojekts. Maßgeblich ist immer dessen Dokumentation.

## Was ihr braucht

- Eine unterstützte Kombination aus Grafikkarte und Mainboard. Prüft das **vor**
  allem anderen in [COMPATIBILITY](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/blob/main/docs/COMPATIBILITY.en.md)
  und [CONFIRMED-SETUPS](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/blob/main/docs/CONFIRMED-SETUPS.en.md).
- Windows 10/11 im UEFI-Modus
- Einen leeren USB-Stick, FAT32-formatiert
- Die Firmware-Dateien, die ihr nach [ASSETS](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/blob/main/docs/ASSETS.en.md)
  selbst beschafft. Diese Dateien dürfen nicht weitergegeben werden.
- Euren **BitLocker-Wiederherstellungsschlüssel**, falls C: verschlüsselt ist. Ihr
  findet ihn unter https://account.microsoft.com/devices/recoverykey.
- Optional für die Messung: Python mit einer CUDA-Version von PyTorch

## Schritt 1: Ausgangswert messen

Vor dem Unlock einmal messen, damit ihr später vergleichen könnt:

```powershell
python -I bench\bench_matmul.py locked
```

## Schritt 2: BitLocker pausieren

Das ist der Schritt, an dem es meistens scheitert. Startet der PC vom Stick und ist
Secure Boot aus, gibt das TPM den BitLocker-Schlüssel nicht mehr frei. Windows fragt
dann nach dem Wiederherstellungsschlüssel. Nach dem Unlock ist der Bildschirm aber
noch schwarz, und ihr seht die Abfrage nicht. Nach etwa einer Minute ohne Eingabe
schaltet Windows den PC absichtlich ab
([Microsoft](https://learn.microsoft.com/de-de/troubleshoot/windows-client/windows-security/bitlocker-recovery-auto-shutdown-in-uefi-mode)).

PowerShell **als Administrator** öffnen:

```powershell
manage-bde -status C:
Suspend-BitLocker -MountPoint "C:" -RebootCount 0
```

`-RebootCount 0` hält die Pause über alle Neustarts, bis ihr sie selbst beendet.
Eure Daten bleiben verschlüsselt. Solange BitLocker pausiert ist, liegt der
Schlüssel aber ungeschützt auf der Platte. Wer die SSD ausbaut, kann sie dann lesen.

## Schritt 3: Secure Boot ausschalten

Im BIOS/UEFI-Setup Secure Boot deaktivieren. Die Unlock-Datei ist nicht signiert
und startet sonst nicht. Den Wiederherstellungsschlüssel solltet ihr dabei bereithalten.

## Schritt 4: Vorabprüfung

```powershell
.\preflight.ps1 -Repo C:\TOOLS\Windows-GPU-UNLOCK -Assets C:\LOCAL-FIRMWARE\assets
```

Die Pfade passt ihr an euren Rechner an. Das Skript ändert nichts, es liest nur. Es
prüft Grafikkarte, UEFI-Modus, Secure Boot, BitLocker, Schnellstart, das Projekt und
die Prüfsummen der Firmware-Dateien. Bei **FAIL** erst das Problem beheben.
Als Administrator gestartet liest es BitLocker am zuverlässigsten.

## Schritt 5: Stick bauen

Folgt dafür genau der Projektanleitung:
[NEW-MACHINE](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/blob/main/docs/NEW-MACHINE.en.md)
für neue Rechner bzw. [HEADLESS-USB](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/blob/main/docs/HEADLESS-USB.en.md)
für bereits unterstützte Profile.

## Schritt 6: Unlock-Start

1. PC **komplett herunterfahren**, nicht neu starten.
2. Einschalten und das Boot-Menü öffnen (MSI: F11, ASUS: F8, Gigabyte: F12).
3. Den USB-Stick wählen. **Keine Taste drücken.**
4. Der Bildschirm bleibt eine Weile schwarz. Das Bild kommt zurück, sobald Windows
   den NVIDIA-Treiber geladen hat.

## Schritt 7: Erfolg prüfen

```powershell
python -I bench\bench_matmul.py unlocked
python -I bench\compare.py bench\results-locked-<zeit>.json bench\results-unlocked-<zeit>.json
```

FP32 bleibt gleich. TF32, FP16 und BF16 sollten etwa **1,6-mal so schnell** sein.
Beispiel RTX 3090 FE: BF16 von 69–71 auf 114–116 TFLOPS.

Der Unlock gilt bis zum nächsten Ausschalten. Für jeden weiteren Unlock wieder
vom Stick starten.

## Schritt 8: Danach

Wenn ihr den Unlock nicht mehr nutzt, aus einem normalen Windows-Start heraus:

```powershell
Resume-BitLocker -MountPoint "C:"
```

Danach im BIOS Secure Boot wieder einschalten. Wer den Unlock bei jedem Start
nutzen will, muss BitLocker dauerhaft pausiert lassen oder ausschalten. Diesen
Sicherheitskompromiss muss jeder selbst abwägen.

## Fehlersuche

| Was passiert | Wahrscheinliche Ursache | Lösung |
|---|---|---|
| PC schaltet sich etwa 1 Minute nach dem Unlock ab, das Log endet mit `FINAL status=0 … clean=1` | Unsichtbare BitLocker-Abfrage | Schritt 2, dann neu versuchen |
| Normaler Start fragt nach dem Wiederherstellungsschlüssel | Secure Boot wurde geändert | Schlüssel eingeben, dann Schritt 2 |
| Bildschirm bleibt lange schwarz | Kein Bild bis zum Laden des NVIDIA-Treibers | 2–3 Minuten warten, nicht ausschalten |
| Messwerte unverändert | Neustart statt Kaltstart, oder der Unlock hat sich selbst übersprungen | Komplett herunterfahren, Logs auf dem Stick prüfen |
| `preflight.ps1` meldet Schnellstart | „Herunterfahren“ ist dann kein echter Kaltstart | Schnellstart ausschalten oder `shutdown /s /t 0` |

Wenn ihr ein Problem im Originalprojekt meldet: **Niemals** Firmware, PROM/VBIOS-Dumps,
Wiederherstellungsschlüssel oder Seriennummern anhängen
([CONTRIBUTING](https://github.com/windows-GPU-UNLOCK/Windows-GPU-UNLOCK/blob/main/docs/CONTRIBUTING.en.md)).
