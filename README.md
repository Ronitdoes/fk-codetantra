# fk-codetantra

---

## Installation

Open **PowerShell** and run:

```powershell
irm https://raw.githubusercontent.com/Ronitdoes/fk-codetantra/main/scripts/install.ps1 | iex
```

*The script will automatically download and verify the latest release, deploy it to your system, configure auto-start on login, and start the app.*

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

Open **PowerShell** and run:

```powershell
irm https://raw.githubusercontent.com/Ronitdoes/fk-codetantra/main/scripts/uninstall.ps1 | iex
```

To also remove stored API keys and user preferences:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Ronitdoes/fk-codetantra/main/scripts/uninstall.ps1))) -CleanAppData
```

---

## License

Copyright &copy; 2026 fk-codetantra. All Rights Reserved.  
Proprietary closed-source software. Unauthorized reverse engineering, decompilation, or redistribution is strictly prohibited.
