# Lords of the Realm II: Windows 11 fix

A fix for the Steam/GOG release of **Lords of the Realm II** (Sierra/Impressions, 1996) that crashes or won't start on Windows 11. Tested on Windows 11 24H2 (build 26200) with the Steam version.

## Symptoms

- The game crashes right at startup, or as the intro video starts.
- Event Viewer shows `Lords2.exe` crashing in `winmmbase.dll` (exception `0xc0000005`, offset `0x5ab3`), or in `Lords2.exe` itself.
- Double-clicking `Lords2.exe` makes it flash and close with no error.

## Quick fix (script)

1. Download this repository (green **Code** button → **Download ZIP**) and extract it.
2. Right-click `install-fix.ps1` → **Run with PowerShell**.
   If your game is not in the default Steam folder, run it from a PowerShell window instead:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install-fix.ps1 -GamePath "D:\Games\Lords of the Realm II"
   ```
   `-GamePath` is the folder that contains `Lords2.exe`.
3. Start the game from Steam or from the new **Lords of the Realm II** desktop shortcut.

The script does not need admin rights. It downloads [cnc-ddraw](https://github.com/FunkyFr3sh/cnc-ddraw) from its official GitHub releases. This repository doesn't ship any game files or third-party binaries.

Add `-Fullscreen` to the command if you'd rather play fullscreen than in a window.

## What's wrong and how the fix works

There are three separate problems.

### 1. 256-color DirectDraw graphics

The game draws in 8-bit (256-color) DirectDraw, which modern Windows handles poorly. **Fix:** put **cnc-ddraw** (`ddraw.dll`, `ddraw.ini`, `Shaders\`) next to `Lords2.exe`. It replaces DirectDraw with a modern OpenGL/Direct3D renderer. The script also sets these in `ddraw.ini`:

| Setting | Value | Why |
|---|---|---|
| `windowed` | `true` | Play in a resizable window |
| `width` / `height` | `960` / `720` | 1.5× the original 640×480 |
| `maintas` | `true` | Keep the original 4:3 shape |
| `no_compat_warning` | `true` | Hide cnc-ddraw's "compatibility mode detected" popup |

### 2. Compatibility-mode flags cause the crash

Steam's install script, and probably earlier attempts to fix the game, set compatibility flags on `Lords2.exe` and `Launcher\LOTR2Launcher.exe`: `WIN98`, `WINXPSP3`, `256COLOR`, `640X480`, `16BITCOLOR`, `DWM8And16BitMitigation`, `RUNASADMIN`.

A crash dump shows what goes wrong. The intro video player (`Smackw32.dll`) calls `waveOutOpen`, and with those flags active a Windows compatibility shim (`AcGenral.dll`) intercepts that call. Then `winmmbase.dll` crashes on a NULL pointer while opening the audio driver. Steam starts the game through `LOTR2Launcher.exe`, and the launcher's flags are passed on to the game, so the launcher has to be cleaned up too.

**Fix:** replace the per-user flags for both executables with only `RUNASINVOKER`:

```
HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers
  <game folder>\Lords2.exe                    = "~ RUNASINVOKER"
  <game folder>\Launcher\LOTR2Launcher.exe    = "~ RUNASINVOKER"
```

You can also do this by hand: right-click each exe → **Properties** → **Compatibility**, untick everything, then click **Change settings for all users** and untick everything there too.

The `HKEY_LOCAL_MACHINE` entry that Steam adds (`$ DWM8And16BitMitigation`) can stay. The game runs fine with it.

### 3. The game must start from its own folder

`Lords2.exe` quits silently within about half a second if its working directory isn't the game folder. On Windows 11 that's what happens when you double-click the exe. **Fix:** start it through Steam, or through a shortcut whose **Start in** field is the game folder. The script creates that shortcut on your desktop.

## Undo

- Delete `ddraw.dll`, `ddraw.ini`, `Shaders\` and `cnc-ddraw config.exe` from the game folder.
- Delete the two registry values above, or untick the compatibility settings again.
- Delete the desktop shortcut.

## Tips

- Run `cnc-ddraw config.exe` in the game folder to change graphics settings (window size, fullscreen, upscaling shaders) without editing files.
- If Steam's **Verify integrity of game files** brings the crash back, it may have restored the old compatibility flags. Run the script again.

## Credits

- [cnc-ddraw](https://github.com/FunkyFr3sh/cnc-ddraw) by FunkyFr3sh. It does the heavy lifting for the graphics.
