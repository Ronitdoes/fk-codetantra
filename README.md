# fk-codetantra

---

## Installation

### Option 1: One-Line PowerShell Install (Recommended)

Open **PowerShell** and run:

```powershell
irm https://raw.githubusercontent.com/Ronitdoes/fk-codetantra/main/scripts/install.ps1 | iex
```

*The script will automatically download the latest release, deploy it to your system, configure auto-start on login, and start the app.*

---

### Option 2: Manual ZIP Download

1. Download **`MyOverlay-Setup.zip`** from [Releases](https://github.com/Ronitdoes/fk-codetantra/releases).
2. Extract the ZIP file.
3. Double-click **`install.bat`** (or right-click `install.ps1` and select *Run with PowerShell*).

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| <kbd>Ctrl</kbd> + <kbd>Alt</kbd> + <kbd>Space</kbd> | Toggle overlay visibility |
| <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>C</kbd> | Capture active screen text & attach to prompt |
| <kbd>Enter</kbd> | Submit question |
| <kbd>Esc</kbd> | Dismiss overlay (expand back from sun icon) |
| Click **Sun Icon** badge (header) | Collapse overlay into a small pinned sun icon — click the icon to expand, drag to move |
| <kbd>Ctrl</kbd> + <kbd>N</kbd> | Clear conversation history |
| <kbd>Ctrl</kbd> + <kbd>Q</kbd> | Quit overlay |

---

## Uninstallation

### Option 1: One-Line PowerShell Uninstall

Open **PowerShell** and run:

```powershell
irm https://raw.githubusercontent.com/Ronitdoes/fk-codetantra/main/scripts/uninstall.ps1 | iex
```

---

### Option 2: Local Script

If you have the extracted ZIP, simply double-click **`uninstall.bat`** or run:

```powershell
powershell -ExecutionPolicy Bypass -File uninstall.ps1
```

To also remove stored API keys and user preferences, add `-CleanAppData`:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/uninstall.ps1 -CleanAppData
```

---

## License

Copyright &copy; 2026 fk-codetantra. All Rights Reserved.  
Proprietary closed-source software. Unauthorized reverse engineering, decompilation, or redistribution is strictly prohibited.
