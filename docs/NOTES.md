# Genesis Alpha One — co-op notes

## Phase 0: Triage (2026-10-25)

### Observations (sourced)
- Developer: Radiant Worlds, publisher Team17, released 2019. Steam app 712190.
- Engine: Unreal Engine 4 (Epic developer interview, https://www.unrealengine.com/developer-interviews/how-a-trio-of-developers-elegantly-blended-multiple-genres-to-create-first-person-shooter-ship-builder-genesis-alpha-one).
- Single-player only. Developers said there are no plans for multiplayer/co-op (Steam thread https://steamcommunity.com/app/712190/discussions/0/3809532340214341715; https://playco-opgame.com/genesis-alpha-one/).
- No entry in this repo's DIRECTORY.md, games/, or playbook. No co-op mod found on the web.

### Game identity (observed on owner's install, 2026-10-25)
- Store: Epic Games Store (.egstore manifest; CatalogItemId 983b27f33cff4600990584a9ba37b271, AppName "Puma"). Folder name `Genesis_EGS`.
- Build files dated 2022-07-26. OS: Windows 64-bit.
- `Genesis_EGS/Binaries/Win64/Genesis-Win64-Shipping.exe` 52,022,272 bytes,
  SHA-256 e009335b33199dd5dddc37213823b12180076aa71b9b7e0da5f144af319d953c
- `Genesis.exe` (launcher stub) SHA-256 be78b86cb93bd91e33c16b1c189cfd2ae0851feeb8752652d0c3b87633ec9fa4
- Engine string in exe: `++UE4+Release-4.23-CL-0` -> Unreal Engine 4.23.
- One pak, `Genesis_EGS-WindowsNoEditor.pak` (6.3 GB), pak version 8, encrypted-index flag 0 and zero encryption GUID -> index not encrypted (asset encryption unverified).
- Exe strings: GameNetDriver, PendingNetGame, BeaconNetDriver, DemoNetDriver,
  ReplicatedMovement / OnRep_ReplicatedMovement, /Script/OnlineSubsystemUtils, NoOnlineSubsystem,
  OnlineSubsystemMcp. Engine netcode is compiled in. The class name `IpNetDriver` was not found
  by `strings` (only cvar `net.IpNetDriverUseReceiveThread`) -> whether a listen server starts is
  **unknown**; test at runtime with `open <map>?listen`.
- No steam_api64.dll (Epic build): the Steam Spacewar relay would need the mod to ship its own Steamworks DLL.

### Tools (2026-10-25)
- UE4SS v3.0.1 (latest stable), https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/v3.0.1
  - UE4SS_v3.0.1.zip SHA-256 4b47d4bceddd2f561a4e395bfa00924ccfc945af576a2d0c613e6537846c57ec
  - zDEV-UE4SS_v3.0.1.zip SHA-256 af777d2af33fce4d520de35a8665e417376bcc530fec647778012ce6cdf51b2b
  - Zip CRCs OK. NOT yet compared with GitHub's published digests (release page unreachable from this session).
- Dumper-7: source only, no prebuilt release; commit 90d1f390d26e31a1f71d29af56c6bd2f240b7493. Needs MSVC on Windows. UE4SS's own SDK/header dump may be enough for UE 4.23.

### Unknowns
- Whether the shipping build still contains IpNetDriver / listen-server support.
- Whether UE4SS supports this build.
- Claim issue opened by owner: https://github.com/cranebeaker/coop-anything/issues/199 (2026-10-25). No other Genesis issues/PRs found in the repo listing.

### Hypotheses (unverified)
- Path 2 (build from zero). UE4 ships replication in the engine; if the game's
  Blueprints/C++ weren't written for it, player 2 needs a puppet + host-authority sync
  of enemies, ship modules, crew/clones and procedural planets.
- Base tooling: UE4SS (Lua/C++ hooks, console) + Dumper-7 SDK dump, per playbook/engine-families.md.
</content>
</invoke>

## Phase 2: Workspace (2026-10-25)
- Test copy made of the whole install (rsync, size + exe SHA-256 + last-1MiB pak hash match the original). Owner's install untouched.
- UE4SS v3.0.1 (UE4SS_v3.0.1.zip) unzipped into `<test dir>/Genesis_EGS/Binaries/Win64/` (dwmapi.dll proxy).
- UE4SS-settings.ini changes (original kept as .orig): MajorVersion=4, MinorVersion=23, ConsoleEnabled=1, GuiConsoleVisible=1, GraphicsAPI=dx11.
- Added read-only probe mod `Mods/CoopProbe` (F7: log net driver classes, NetDriverDefinitions, world/gamemode/pawn; F9: `open <current map>?listen`).
- Not yet run. Unknown whether the copy launches outside the Epic launcher (exe contains OnlineSubsystemMcp).

## Phase 3: first runtime probe (2026-10-25, owner launched the test copy's Shipping exe directly)
### Observations (UE4SS.log)
- The test copy runs outside the Epic launcher. UE4SS v3.0.1 attaches and finds GUObjectArray etc. with the default config (no game-specific config needed).
- First launch: owner reported a Fatal Error; the log was overwritten by the second launch, so cause **unknown**. Second launch ran fine.
- Classes present: IpNetDriver, IpConnection, NetDriver, DemoNetDriver, OnlineBeaconHost.
- `GameEngine.NetDriverDefinitions`: 1 entry, `GameNetDriver -> OnlineSubsystemSteam.SteamNetDriver` (leftover from the Steam build).
- Start world `/Game/Maps/GameStart_Gb`, GameMode `FirstPersonGameMode_C`, pawn `Eden_PlayerCharacter_C`. World.NetDriver = none (standalone).
- ConsoleEnablerMod: "ConsoleClass, GameViewport, or ViewportConsole is invalid" at start, then registers console keys (F10, ^) once in game.
- Probe v1 F9 failed: `PlayerController:ConsoleCommand` call errors with "UObject instance is nullptr". Fixed in v2 by calling `KismetSystemLibrary.ExecuteConsoleCommand`.
### Hypothesis
- `open ?listen` would fail as-is because SteamNetDriver may be missing from the Epic build; v2 rewrites the definition in memory to IpNetDriver before opening.
- Owner report: DLC content is only available when the game is started through the Epic launcher (entitlement check, likely via OnlineSubsystemMcp / launcher auth args). The test copy started directly has no DLC.
  - Plan: feasibility and sync work without DLC in the test copy; for real play, ship the mod as an add-on (UE4SS dwmapi.dll + UE4SS.dll + Mods/) dropped into the Epic install, so Epic launches it with DLC. Never handle the launcher's auth tokens.
  - Unknown: whether DLC entitlements must match between host and guest.

## Phase 3b: listen server works (2026-10-25)
### Observations (UE4SS.log, probe v2)
- `OnlineSubsystemSteam.SteamNetDriver` and `SteamNetConnection` classes are **missing** in the Epic build, so the stock `GameNetDriver` definition cannot work.
- After rewriting `GameNetDriver` in memory to `/Script/OnlineSubsystemUtils.IpNetDriver` and running
  `open /Game/Maps/LoadGame?listen` through `KismetSystemLibrary.ExecuteConsoleCommand`:
  World.NetDriver = `IpNetDriver /Engine/Transient.IpNetDriver_...`, same GameMode/pawn classes. Windows Firewall prompted (socket opened).
- Owner was in world `/Game/Maps/LoadGame` at the time (not GameStart_Gb). Reopening the map reloads it; whether game progress survives is unknown.
### Next
- Probe v3: F8 joins `host.txt` address (default 127.0.0.1), F7 logs role, client connection count, PlayerControllers and player characters; each instance logs to its own `Mods/CoopProbe/probe_HHMMSS.log`.
- `Lancer_fenetre.bat` in Win64 starts a second windowed instance for a same-PC join test.

## Phase 3c: first same-PC join attempt failed (2026-10-25)
### Observations (per-instance probe logs)
- Two instances of the test copy run at the same time on one PC (second one windowed via Lancer_fenetre.bat).
- **UE4SS key binds fire in every running instance, focused or not.** Each F8/F9 the owner pressed in one window ran in both: the host's `open 127.0.0.1` tore down its own listen server, the client's F9 re-hosted it. So no valid join was attempted; join result **unknown**.
- Host did reach `role: SERVER/listen, client connections: 0` once (10:45:33).
- Main menu world is `/Game/Maps/MainMenu` (MainMenuGameMode_C, MainMenuCharacter_C).
### Fix
- Probe v4: role lock per instance (first F9 -> host, ignores F8; first F8 -> client, ignores F9).
### Lesson for the playbook (UE4SS multi-instance)
- RegisterKeyBind is global across processes on the same desktop; multi-instance tests need a per-instance role (lock, CLI arg or file), not focus.

## Phase 3d: FIRST SUCCESSFUL JOIN (2026-10-25, same PC, 127.0.0.1, probe v4)
### Observations
- Host: `SERVER/listen`, client connections 1, PlayerControllers 2, Eden_PlayerCharacter_C 2. GameMode FirstPersonGameMode_C spawned a second player character for the guest.
- Client: `CLIENT (connected to a server)`, world `/Game/Maps/LoadGame` loaded over the net, sees 2 player characters (replicated), GameMode none (correct for a client), its first PlayerController has Pawn none.
- Owner sees: client window stuck on a loading screen; host screen goes black when the guest joins.
### Hypotheses (unverified)
- Host black screen: single-player Blueprint logic on the new character / PostLogin (GetPlayerController(0), camera fade, view target) acting on the host's own controller.
- Client loading screen: a loading widget waits for game init that only runs on the server or for a possessed pawn.
### Next
- Probe v5 `deep.lua`: F7 dumps every PC (local, pawn, view target, fade), every player character (controller, role, location), streaming levels, widgets in viewport. F6 = stop camera fade + view own pawn on the local controller.

## Phase 3e: startup crash and save-folder finding (2026-10-25)
### Observations
- Intermittent crash at startup (2 of ~8 launches of the test copy), "Unhandled exception", SecondsSinceStart 0, no Lua or key input involved (UE4SS.log ends right after "Event loop start"). Crash reports in `%LOCALAPPDATA%\Genesis_EGS\Saved\Crashes`.
  Stack: ~70 frames of ntdll recursion (+161dd4 / +1623d4) plus frames in Genesis-Win64-Shipping (+1062b02, +10636b8, +10637d7, +13a7eaa, +13ac1f4, +14ac86b, +16079e3, +19e8b91, +1c81846). No UE4SS.dll frames. No PDB, not symbolized.
- Unknown: whether the crash also happens without UE4SS (test: launch with dwmapi.dll renamed).
- **The test copy shares the real game's save and config folder** (`%LOCALAPPDATA%\Genesis_EGS\Saved`): SaveGames/Savegame2.sav and PlayerProfile2.sav were rewritten during tests. Backup of SaveGames + Config taken into `<test dir>/_backup_saves_20261025` (SHA-256 checked). Ground rule 2 needs a per-copy save dir; how to redirect in a UE 4.23 shipping build is unknown.

## Phase 3f: why the guest is stuck (2026-10-25, probe v5 deep dump)
### Observations
- Host: PCs `BP_PlayerController_EdenAlpha_C` x2 (local=true with FirstPersonHUD_C; remote one with its own pawn). Both view their own pawn. Characters role=3 (Authority), remote=2 (AutonomousProxy).
- Client: local PC `BP_PlayerController_EdenAlpha_C` possesses its own `Eden_PlayerCharacter_C` (role=2 AutonomousProxy), HUD FirstPersonHUD_C; host's character visible as SimulatedProxy (role=1); an extra plain `PlayerController` (non-local, no pawn) also exists.
- **Host world has 31 `LevelStreamingDynamic` levels (the ship modules, created at runtime from the save); client has 0.** Runtime-created dynamic level instances are not replicated by UE4.
- Widgets in viewport on both: BlueprintSubtitleWidget_C, PlayerHudWidget_C. No loading-screen UserWidget seen.
- F6 (StopCameraFade + SetViewTarget own pawn) did not clear the host black screen -> not a PlayerCameraManager fade (or not that one). `FadeAmount` read returned an object wrapper, not a number (dump bug).
### Hypotheses
- Guest loading screen waits for the ship levels it never gets.
- Host black screen: unknown, maybe HUD/post-process logic run on the guest's arrival.
### Next (probe v6)
- `levels.lua`: F5 on host writes each streaming level's PackageNameToLoad/WorldAsset + LevelTransform to `Mods/CoopProbe/levels.txt`; F4 on client loads them with `LevelStreamingDynamic::LoadLevelInstance` (same-PC file hand-off, test only).
- deep dump also lists any UserWidget whose class name has load/fade/black/transit/screen, with visibility.

## Phase 3g: ship levels load on the guest, then the guest is kicked (2026-10-25, probe v6)
### Observations
- Host export: 31 dynamic levels, all from `/Game/Maps/Structure/` (GB_Bridge, hm_Divider_Glass*, hm_Corridor_Glass*, su_Greenhouse_medium, hm_Crewq_big, re_storage_sml, Re_TractorBeam, re_refinery_sml...). Instance packages are named `<Short>_LevelInstance_<N>` with N = 32..62 in load order; positions on a 384-unit grid, yaw 0/90/180 only.
- Client: `LoadLevelInstance` returned a valid object for 31/31. Then the guest went back to the main menu; host shows client connections 0, a leftover PC without pawn and a character at 0,0,0.
- Host has a `LoadingScreen_Widget_C` (not in viewport). Client has two `LoadingScreen_Widget_C`, one with visibility 0 (Visible).
### Hypothesis (unverified, matches UE4 source behaviour)
- The client's instances get its own `_LevelInstance_<N>` numbers. When they turn visible the client calls `ServerUpdateLevelVisibility(<client name>)`; the server does not know that package and closes the connection. Module actors are also addressed by those package paths, so the names must match exactly anyway.
### Next (probe v7)
- Export also stores the host's instance short name; import calls `LoadLevelInstance(..., OptionalLevelNameOverride=<host name>)` only if that parameter exists in this build (logs the UFunction's parameters), then lists the client's loaded instance names after 4 s.

## Phase 3h: no level-name override in 4.23 (2026-10-25)
### Observations
- Probe v7 F4 failed before loading anything: `StaticFindObject("/Script/Engine.LevelStreamingDynamic:LoadLevelInstance"):ForEachProperty` -> "UObject instance is nullptr" (UE4SS 3.0.1).
- Exe strings contain `LoadLevelInstance`, `LoadLevelInstanceBySoftObjectPtr`, `_LevelInstance_`, `ServerUpdateLevelVisibility(_Validate)` but **not** `OptionalLevelNameOverride` -> this 4.23 build cannot choose instance names from Blueprint/Lua.
- In the v6 test, host numbers were 32..62 and the client had also loaded its own save before joining, so its numbers may already have matched; client names were never logged. The kick hypothesis is unverified.
### Next (probe v7b)
- Import loads with engine-chosen names and lists the client's instance names every second for 6 s.
- `hooks.lua`: RegisterHook on ServerUpdateLevelVisibility (host sees what the guest reports), ClientWasKicked, ClientReturnToMainMenu(WithTextReason), ClientUpdateLevelStreamingStatus, GameModeBase K2_OnLogout.

## Phase 3i: instance names DO match (2026-10-25 14:02, probe v7b)
### Observations
- Each instance names its first save load `_LevelInstance_1..31`; the host's `?listen` reopen gives `32..62`.
- The guest also loaded its own save first (1..31), so its F4 import produced `_LevelInstance_32..62` in the same order: **identical to the host, all 31** (listed at t+1 s).
- `ServerUpdateLevelVisibility` hook fires on the calling side too (seen in standalone), with the instance package name.
- Up to t+6 s after the import, no visibility RPC from the guest showed up on either side, and no kick/return-to-menu RPC. Connection state after that: pending owner's F7.
### Conclusion so far
- The v6 kick was **not** caused by a name mismatch (or names were already matching then too). Cause still unknown.
- Instance numbering is deterministic per process (a global counter), which a real mod can rely on or line up.

## Phase 3j: guest stays connected with the ship loaded but invisible (2026-10-25 14:05)
### Observations (guest F7 after F4 import)
- Still `CLIENT (connected to a server)`, possesses its pawn, StreamingLevels 31 (names identical to host).
- No `ServerUpdateLevelVisibility` call after the import (its only 31 calls are from its own single-player load before joining) -> the imported levels never became visible.
- `LoadingScreen_Widget_C` x2 on the guest, one with visibility 0 (Visible): this is the endless loading screen.
- Guest's own pawn at 42,-155,319 vs host's view of it at 43,-310,98 (position not converged).
### Next (probe v8)
- F3 (guest): log IsLevelLoaded/IsLevelVisible/ShouldBeLoaded, call SetShouldBeLoaded/SetShouldBeVisible(true) on every level, collapse and remove LoadingScreen_Widget_C.
- Ask owner whether the host's black screen clears when window 1 gets focus back (unfocused render?).

## Phase 3k: ship visible on the guest, both screens black (2026-10-25 14:10, probe v8)
### Observations
- Guest after F4 import: its streaming levels are loaded, visible and ShouldBeLoaded (31/31 visible before F3 forced anything; the v7b "no visibility RPC" was only because the hook does not log it in that case or it came later, unknown).
- F3 collapsed and removed both `LoadingScreen_Widget_C` (visibility 2 and 0). The guest window then shows **black** instead of the loading screen. Host window stays black, focus does not change it.
- Guest still connected, local PC possesses its pawn.
### Derived
- The black on both sides is the same thing and sits under the loading screen. Likely a camera fade, as F6 used `StopCameraFade`, which in UE 4.23 sets FadeAmount to the fade *target* (FadeAlpha.Y), so it cannot clear a fade to black.
### Next (probe v8b)
- F6 now calls `PlayerCameraManager:SetManualCameraFade(0, black, false)` on the local controller of each window.
