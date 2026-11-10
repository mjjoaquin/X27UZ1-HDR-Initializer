# Acer Display Fix

Automates the HDR refresh and brightness setting for Acer X27U Z1 displays on Windows.

# Why?

Acer display firmware fails to apply HDR mode after going to sleep or toggling Nvidia suorround, even when met with an HDR signal from the GPU. It must be manually set through display settings or the Acer Display Widget. This script automates that process, and can also set brightness to a user-specified level.

## What It Does

- Refreshes Acer HDR mode, then sets the requested brightness. Brightness returns the Acer preset to User mode.
- In NVIDIA Surround, uses NVAPI/DDC-CI to apply and verify the mode refresh and brightness on each grid member.
- Brightness defaults to `60` (reccomended for OLED lifespan). A value of `0` is a no-op: no displays are changed.

## Requirements And Limits

- 64-bit Windows PowerShell and Acer Display Widget must be installed.
- NVIDIA Surround support requires an NVIDIA GPU/driver with NVAPI and DDC/CI access to each panel.
- If NVAPI is unavailable or reports a single display, the script uses Acer's native Windows path, which may reach only the primary logical display. Errors while mapping or commanding a multi-panel grid stop the run.
- The NVIDIA HDR readback describes the output signal; it does not guarantee that HDR looks correct in every application or on-screen mode.

## Run

From PowerShell in this folder:

```powershell
.\Set-AcerX27UZ1.ps1
.\Set-AcerX27UZ1.ps1 -Brightness 40
.\Set-AcerX27UZ1.ps1 40
.\Set-AcerX27UZ1.ps1 -Brightness 0
.\Set-AcerX27UZ1.ps1 -WhatIf
```

The shortcut launcher accepts the same arguments:

```powershell
.\Apply-AcerDisplayFix.cmd
.\Apply-AcerDisplayFix.cmd -Brightness 40
```

Reccomended: Create a shortcut then set that macro to a hotkey in Windows.

## Security

Do not run random scripts from the internet without reviewing and trusting their source. This script sends commands that change monitor settings and loads Acer and NVIDIA native libraries. Use it only if you understand and trust the code and the installed software it depends on.

Created with the assistance of LLM technology.
