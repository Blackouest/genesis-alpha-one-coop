# Genesis Alpha One Co-op

An attempt to make **Genesis Alpha One** (Radiant Worlds / Team17, 2019) playable in online co-op.
The game is single-player only and its developers said there are no multiplayer plans.

**Status: research prototype. Not playable yet.**

Part of [Co-op Anything](https://github.com/cranebeaker/coop-anything), claim issue
[#199](https://github.com/cranebeaker/coop-anything/issues/199).

## What works so far (tested 2026-10-25, two instances on one PC)

| Step | Result |
|---|---|
| UE4SS 3.0.1 loads into the game (UE 4.23, Epic Games Store build) | works |
| Engine netcode is compiled in (IpNetDriver, replication) | yes |
| Host a listen server (`open <map>?listen`) after pointing `GameNetDriver` at `IpNetDriver` | works |
| Second instance joins over `127.0.0.1` | works: host sees 2 controllers and 2 characters, guest possesses its own character |
| Ship modules on the guest | **not replicated**: the ship is built from ~31 runtime level instances the guest never gets |
| Copying the module list to the guest | modules load, then the guest is disconnected (instance names differ from the host's) |
| Host screen after the guest joins | goes black, cause unknown |

Full lab notes, with observations, hypotheses and unknowns kept apart: [docs/NOTES.md](docs/NOTES.md).
Plan: [docs/ROADMAP.md](docs/ROADMAP.md).

## Tested game build

| | |
|---|---|
| Store | Epic Games Store |
| Engine | Unreal Engine 4.23 (`++UE4+Release-4.23-CL-0`) |
| `Genesis_EGS/Binaries/Win64/Genesis-Win64-Shipping.exe` SHA-256 | `e009335b33199dd5dddc37213823b12180076aa71b9b7e0da5f144af319d953c` |

Other builds (Steam, GOG, Game Pass) are untested.

## Trying the probe (developers only)

1. Copy your game install to a separate folder. Don't mod your real install. Note that the copy still uses
   your real save folder `%LOCALAPPDATA%\Genesis_EGS\Saved`, so back it up first.
2. Install [UE4SS v3.0.1](https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1)
   (`UE4SS_v3.0.1.zip`, SHA-256 `4b47d4bceddd2f561a4e395bfa00924ccfc945af576a2d0c613e6537846c57ec`)
   into `Genesis_EGS/Binaries/Win64/` of the copy. In `UE4SS-settings.ini` set `MajorVersion = 4`, `MinorVersion = 23`.
3. Copy `mod/CoopProbe` to `Genesis_EGS/Binaries/Win64/Mods/CoopProbe` and add `CoopProbe : 1` to `Mods/mods.txt`.
4. Copy `mod/Launch_second_window.bat` next to the exe.

Keys (UE4SS key binds reach **every** running game window; each window locks its role on the first F9 or F8):

| Key | Action |
|---|---|
| F9 | host: switch to IpNetDriver and reopen the current map with `?listen` |
| F8 | join the address in `Mods/CoopProbe/host.txt` (default `127.0.0.1`) |
| F7 | dump network state, controllers, characters, streaming levels, widgets |
| F6 | force the camera fade to 0 (SetManualCameraFade) and view your own pawn |
| F5 | host: write the ship's streaming levels to `Mods/CoopProbe/levels.txt` |
| F4 | guest: load those levels (engine-chosen names; 4.23 has no name override) and log the names |
| F3 | guest: force the loaded ship levels visible and hide the loading screen |
| F2 | render dump: material parameter collections, pawn camera, post-process volumes, HUD |
| F1 | engine screenshot (`shot`, `HighResShot 1`) in every window, saved under Saved/Screenshots |

Each window logs to `Mods/CoopProbe/probe_HHMMSS.log`.

## Rules

No game files or assets in this repo. Co-op only: nothing here touches anti-cheat, online services or other people's games.
DLC content needs the game to be started from the Epic launcher, so the finished mod will be an add-on dropped into the Epic install.

## License

MIT
