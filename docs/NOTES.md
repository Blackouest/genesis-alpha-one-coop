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

## Phase 3l: not a camera fade (2026-10-25 14:17, probe v8b)
### Observations
- `SetManualCameraFade(0)` returned ok on the local controller of both windows; both stay black. View targets are the own pawns on both sides.
- Host F7: client connections 1, both characters at stable positions. Guest: connected, 31 visible levels, loading screen removed.
### Hypotheses (open)
- A global MaterialParameterCollection scalar (screen fade / blackout) set by the arriving player's load flow; it would black out every view in the world, host included.
- Pawn camera deactivated, or a post-process volume / camera post-process blackout.
### Next (probe v9)
- F2 render dump: every MaterialParameterCollection with current vs default scalar values (KismetMaterialLibrary.GetScalarParameterValue), pawn CameraComponent active state and post-process weight, camera location, PostProcessVolumes, pawn bHidden, PlayerHudWidget visibility/opacity.

## Phase 3m: full black, no UI at all (2026-10-25 14:35, probe v9)
### Observations
- Owner screenshot: both game windows are completely black, nothing drawn at all.
- F2 render dump (both windows): camera at the own pawn's eye height (host -190,373,178; guest 42,-155,399), pawn not hidden, PlayerHudWidget visibility 4 (SelfHitTestInvisible), opacity 1. No MaterialParameterCollection, pawn CameraComponent or PostProcessVolume was listed (FindAllOf returned none, or the loops failed silently: unknown).
- Exe strings include `SetEnableWorldRendering` / `GetEnableWorldRendering` (UGameplayStatics) and `SetSuppressViewportTransitionMessage`.
### Hypothesis
- The game's load flow calls `UGameplayStatics::SetEnableWorldRendering(false)` while it builds the ship, and the arriving guest re-triggers it on the host (GameMode PostLogin) and on the guest; it never gets re-enabled because the load never "finishes" for two players.
### Next (probe v10)
- F2 also logs GetEnableWorldRendering. F1 calls SetEnableWorldRendering(true) on the local window.
- Hooks: GameplayStatics.SetEnableWorldRendering (who switches it, with what value), GameModeBase.K2_PostLogin.

## Phase 3n: world rendering is on (2026-10-25 14:40, probe v10)
### Observations
- Both windows: `GetEnableWorldRendering = true` while black. F1 `SetEnableWorldRendering(true)` changes nothing. The hook saw no game call to SetEnableWorldRendering (only our own).
- `GameModeBase:K2_PostLogin` hook registered but never fired on the guest's arrival (BlueprintImplementableEvent the game may not implement, or hooks on BP events need another path: unknown).
### Hypothesis
- The frame is rendered but covered: a post-process blendable (helmet/visor, death/clone effect) on the pawn camera or the camera manager, or exposure.
### Next (probe v11)
- F1: `ShowFlag.PostProcessing 0`, `r.DefaultFeature.AutoExposure 0`, `r.TonemapperFilm 0`, list every CameraComponent (owner, active, PostProcessBlendWeight, blendable count) and set their weights to 0.

## Phase 3o: not post-processing either (2026-10-25 14:45, probe v11)
### Observations
- Solo control test (host only, F9 then F1): the image gets brighter, so the F1 console commands do reach the renderer in this build.
- Two-player test: F1 changes nothing on either window; both stay fully black.
- Camera components found: pawn `FirstPersonCamera` (active), `BuilderCharacter_C` camera, `BP_PlayerRemoteCamera_C` (host only), `CameraActor`s (one on host, two on guest), three inactive `CineCameraActor`s, and many terminal/workstation screen cameras (BP_StorageTerminal, BP_GreenhouseTerminal2, BP_HealthStation, BP_GalaxyTerminal, BP_TractorBeamTerminal, BP_RefineryTerminal, StandKeyboardWorkstationPlayer...). None has post-process blendables.
- PlayerCameraManager view target stays the own pawn on both sides (earlier dumps).
### Ruled out
- Camera fade, world rendering switch, post-process overlay, loading screen widget, wrong view target.
### Next (probe v12)
- Log what the game does when the guest arrives: KismetSystemLibrary.ExecuteConsoleCommand, PlayerController.ConsoleCommand, StartCameraFade, ClientSetCameraFade, (Client)SetCinematicMode, SetViewTargetWithBlend, ClientSetViewTarget, SetGamePaused, GameUserSettings.ApplySettings/SetScreenResolution, UserWidget.AddToViewport.

## Phase 3p: probe v12 crashed the game (2026-10-25 14:51)
### Observations
- With v12, the game crashed on reaching the main menu. UE4SS console: "Tried to execute UFunction::FuncPtr hook but there was no function map entry for UFunction: 0000000000000000 None. No original function to execute. Executing ProcessInternal instead.", then Object_ExecuteUbergraph / ProcessInternal.
- Last logged calls before it: AddToViewport StartGame_C (z=1), AddToViewport LoginFailedWidget_C (z=15). The test copy started outside the Epic launcher shows a login-failed widget.
- UE4SS reported "Registered native hook" for the new engine functions (e.g. GameUserSettings.ApplySettings/SetScreenResolution, UserWidget.AddToViewport) and "script hook" for K2_OnLogout.
### Derived (unverified)
- One of the new native hooks patched an exec thunk that MSVC identical-code-folding shares with another UFunction; when that other function ran, UE4SS found no map entry and crashed. Which hook: unknown.
### Lesson for the playbook (UE4SS 3.0.1 on shipping UE4 builds)
- Prefer RegisterBeginPlayPostHook / NotifyOnNewObject / RegisterProcessConsoleExecPreHook and script (BP) hooks over many native RegisterHook calls; add native hooks one at a time.
### Next (probe v13)
- Back to the v10 hook set (ran without crash) plus safe watchers, armed on F9/F8: every actor BeginPlay (class + name), every new UserWidget, every console command.
- v13 first upload had new code appended after `return M` in hooks.lua -> "hooks.lua:23: <eof> expected near 'M'", the whole CoopProbe mod failed to load, so that test logged nothing. Fixed; every script is now syntax-checked with Lua 5.4 (`tools/check_lua.sh`) before it is copied to the game.

## Phase 3q: what the host spawns when the guest arrives (2026-10-25 15:08, probe v13)
### Observations
- Host, at the second the guest joined (15:08:08), only these BeginPlays, no console command, no new widget:
  Genesis_PlayerState_C, CameraActor, PlayerCameraManager, BP_PlayerController_EdenAlpha_C, **BP_PlayerRemoteCamera_C, BP_PlayerInventoryAvatar_C, BuilderCharacter_C**, Eden_PlayerCharacter_C.
- The host's own set (spawned by the `?listen` reopen) has the same helper actors: BP_PlayerRemoteCamera_C, BP_PlayerInventoryAvatar_C, BuilderCharacter_C. So each player gets one of each, but single-player code most likely looks them up as "the" instance.
- Guest side: receives replicated ship modules (`BP_Bld_*`), crew (`CrewCharacterClass_C` with `Crew_HealthStatus_C` widgets), robots (`Rob1_Robot_C`), doors, weapons (pistol, energy barrier, multikit, biosucker, power shotgun, sentry gun), BP_Galaxy_C, Genesis_GameState_C/PlayerState_C, BP_MiniMapPlayer, PlayerSpectator_C. Nothing logged after 15:08:09 on the guest.
- UE object index suffixes count down: newer objects have smaller numbers.
### Hypothesis
- One of the guest's duplicate helpers (most likely BP_PlayerRemoteCamera_C) takes over the host's view or render target.
### Next (probe v14)
- F1 (host only): list the helper actors with owner/instigator/location, then destroy the newest duplicate of BP_PlayerRemoteCamera_C, then BuilderCharacter_C, then BP_PlayerInventoryAvatar_C, then CameraActor, one per press.

## Phase 3r: duplicate helper actors are not the cause (2026-10-25 15:14, probe v14)
### Observations
- Per-player helpers, each with Instigator = its player's Eden_PlayerCharacter_C and no owner: BP_PlayerRemoteCamera_C and BP_PlayerInventoryAvatar_C parked at (0,0,600000), BuilderCharacter_C at (0,0,-199900). Each PlayerCameraManager owns a CameraActor at 0,0,0. Three CineCameraActors (_0, _1, _3) in the map.
- Destroying the guest's BP_PlayerRemoteCamera_C, then its BuilderCharacter_C (host F1 x2+) did not bring the host image back.
### Next (probe v15)
- F1 in both windows: engine screenshots (`shot`, `HighResShot 1`) to tell "the frame is rendered black" from "the frame is fine but not presented".

## Phase 3s: the engine still renders the ship while the window is black (2026-10-25 15:18, probe v15)
### Observations
- F1 in both black windows: `HighResShot 1` wrote one file, `HighresScreenshot00000.png`, 1234x694: a normal, lit view of a ship corridor door with the crosshair. Both windows wrote the same name, so which window it came from is unknown.
- `shot` (the back-buffer screenshot) wrote no `ScreenShot*.png` at all.
### Derived (unverified)
- The scene renders; what fails is presenting the game viewport to the window (viewport draw/present stopped, or something drawn over it at the Slate level, e.g. an engine MoviePlayer loading screen).
- If `shot` also writes nothing in a solo session, its absence means nothing; if it does write in solo, the viewport is not being drawn during the black screen.
### Next (probe v15b)
- F1: host shoots now, client 4 s later (different file numbers). Owner runs a solo control first.

## Phase 3t: the host renders fine behind the black; opening the map brings the image back (2026-10-25 15:22, probe v15b)
### Observations
- Engine screenshots (`HighResShot 1`, scene only, no UMG): host solo 15:22:12 and host while black 15:22:52 show the **same, normal** corridor view (1234x694). Guest 15:22:56 (1280x720): almost empty black world with a single door segment floating (no ship levels were imported in this run).
- `shot` wrote no file even in the solo control -> no information from it in this build.
- Owner: opening the in-game map on the host brought the host image back. Log at that moment: `BuilderModeWidget_C` created, `BP_ShipCamera_C` and `BP_MapSensedAlienRadar_C` spawned (the map is the builder / ship view).
- After the host's `?listen` reopen the game ran `slomo 1` ten times (its own console calls).
- Picture: https://github.com/Blackouest/genesis-alpha-one-coop/blob/main/docs/img/2026-10-25_engine-shots_host-solo_host-black_guest.png
### Derived
- The host's scene is rendered; the black is drawn on top at the UI level (HighResShot excludes UMG). Most likely a full-screen black image inside the HUD widget tree that the guest's arrival turns on (single-player fade logic) and that switching to the builder/map UI turns off.
### Next (probe v16)
- F1: list every visible Image/Border whose widget chain reaches a widget in the viewport, with visibility, render opacity and colour; flag near-black opaque ones. F1 again hides the flagged ones.

## Phase 3u: BLACK SCREEN SOLVED - `FadeOutBorder` in the HUD (2026-10-25 15:30, probe v16)
### Observations
- F1 list on both windows: 128 visible Images/Borders inside viewport widgets. The only full-screen black one is **`Border FadeOutBorder` in `PlayerHudWidget_C`**, visibility 4 (SelfHitTestInvisible), render opacity 1, colour 0,0,0,1. The 17 others are ordinary dark panel backgrounds (PlayerHealthWidget, PlayerCurrentWeapon, AlienMotionTracker, CrewWeaponSelectionItem, TalkScreen, TutorialWarning, ControllerButtonHintWidget, LoadingScreen hint boxes).
- After hiding them (F1 twice): **both windows show the game**. Host: normal first-person view. Guest: world visible behind the "CHARGEMENT" loading screen (LoadingScreen_Widget_C, nested in PlayerHudWidget_C); the **host's weapon is seen moving as the host walks** (live replication works), but no host body (first-person-only mesh).
- LoadingScreen_Widget_C lives inside PlayerHudWidget_C on both machines.
- Picture: https://github.com/Blackouest/genesis-alpha-one-coop/blob/main/docs/img/2026-10-25_both-windows-after-hiding-FadeOutBorder.jpg
### Derived
- The single-player HUD fade (`FadeOutBorder`) is left fully black when the second player arrives, on the host and on the guest. Opening the map/builder UI also clears it (owner's observation).
- Remote players need a third-person body: the player mesh is first-person only.
### Next (probe v17, automatic flow)
- Host: F9 only. Exports the ship levels 6 s later.
- Guest: F8 only. Once connected with a pawn: import ship levels (+4 s), remove the loading screen (+6 s).
- Both: if FadeOutBorder stays fully black for 6 s, hide it. F1 now hides only FadeOutBorder.

## Phase 3v: v17 automatic flow ran, but the fade watch never fired (2026-10-25 15:40)
### Observations
- Host: F9 -> export 31 levels at +6 s. Guest: F8 -> connected with a pawn after 2 s, imported 31/31 levels at +4 s, removed 3 LoadingScreen_Widget copies at +10 s. Both screens stayed black; no "FadeOutBorder hidden" line.
- Owner: opening the map on the host clears the host's black again; nothing clears the guest's.
- Several PlayerHudWidget/LoadingScreen copies exist at once (old ones from earlier map loads).
### Derived
- The watch reset its counter whenever it met a non-black FadeOutBorder copy, so it never reached 3 ticks (bug in v17).
### Next (probe v17b)
- Fade watch counts "any copy black" and hides every black copy after 3 checks; logs copies/black count on change.

## Phase 3w: BOTH WINDOWS RENDER THE SHIP, automatically (2026-10-25 16:00, probe v17b)
### Observations
- Fade watch log: 3 FadeOutBorder copies on each side. Host: none black until the guest joined (16:00:10), then 1 black, hidden at 16:00:14. Guest: 1 black from connection (16:00:11), hidden at 16:00:15. **This confirms FadeOutBorder alone causes the black screen** (only it was hidden).
- Owner screenshot: host first-person view with weapon and HUD hints; guest sees the ship interior (imported modules, lit) with HUD hints. Picture: https://github.com/Blackouest/genesis-alpha-one-coop/blob/main/docs/img/2026-10-25_both-windows-render-ship-v17b.jpg
- Host: everything works. Guest: spawned high up, can only turn the camera; no movement, no weapon selection, no map.
- Earlier dumps already showed the guest pawn at z=319 on the guest vs z=98 on the host.
### Hypothesis
- The single-player load flow disables player input / movement until "loading done", and that event never fires for the guest.
### Next (probe v18)
- F2: dump local PC (move/look input ignored, cursor, interesting bool/number BP vars), pawn (location, velocity, InputEnabled, role, CharacterMovement mode/gravity/speed/active, BP vars), all player characters' locations. F2 again: ResetIgnoreInputFlags, SetIgnoreMove/LookInput(false), pawn EnableInput, SetMovementMode(Walking), SetInputMode_GameOnly.

## Phase 3x: the guest's player character is never initialized (2026-10-25 16:06, probe v18)
### Observations (F2 dump)
| | host's own pawn (server) | guest's own pawn (guest) |
|---|---|---|
| IsPlayerInitialized | true | **false** |
| BlockActionFPSPlayerInput | false | **true** |
| PlayerMovementSpeed | 1400 | **0** |
| CharacterMovement | mode 1 (Walking), active, MaxWalkSpeed 1400 | **mode 3 (Falling), inactive**, MaxWalkSpeed 1200 |
| ReplicatedMovementMode | 1 | 0 |
| location | -189,373,98 | 42,-155,319 (host sees it at 43,-310,98) |
- PlayerController: move/look input not ignored on either side; cursor off.
- Generic fixes (ResetIgnoreInputFlags, SetIgnoreMove/LookInput(false), EnableInput, SetMovementMode(Walking), SetInputMode_GameOnly) all ran, guest still cannot move, switch weapons or open the map.
- Owner: the guest does not see the rest of the ship (only part of it). Which parts are missing: unknown.
### Next (probe v19)
- F2: list init-like functions on Eden_PlayerCharacter_C and BP_PlayerController_EdenAlpha_C; show every player character's init state (host shows its copy of the guest too).
- F2 again: on every uninitialized, non-simulated player character, copy the initialized values (IsPlayerInitialized, BlockActionFPSPlayerInput=false, PlayerMovementSpeed, activate CharacterMovement, MaxWalkSpeed, Walking).

## Phase 3y: GUEST CAN MOVE (2026-10-25 16:17, probe v19)
### Observations
- Host's copy of the guest character (role 3) was also uninitialized: init=false, block=true, speed 0, CharacterMovement inactive. Guest's own pawn (role 2) the same, mode 3. The host's character as seen on the guest (role 1) also shows init=false (simulated proxy, left alone).
- F2 x2 set on both: IsPlayerInitialized=true, BlockActionFPSPlayerInput=false, PlayerMovementSpeed=1400, CharacterMovement active, MaxWalkSpeed 1400, Walking.
- Owner: **the guest now walks** in the ship; **player-to-player collision works**; host sees the guest. A ship door looks closed on the guest but can be walked through (door state not replicated, server-side collision wins).
- Guest still cannot: open the map, take a weapon (the weapon selection HUD appears), use lockers or screens.
- Init-related BP functions found on Eden_PlayerCharacter_C: InitializePlayer, OnLevelLoadedInitializePlayer, SetPlayerInitValues, InitWeaponsFromSave, InitializeFlashlight, InitializePostProcessess, InitializeAlienAbility, SpawnBuilderCharacter, SpawnPlayerRemoteCamera, SpawnPlayerInventoryAvatar, SetLoadedOxygen, SetTutorialAfterLoad, OnLoadingFinishedShowConfirm, PossessFinished, HolsterAndBlockPlayerWeaponSelection, InitializePlayerAfterBuildingMenu, OnGenesisInitiated, TeleportPlayerToRandomStartPosition... BP_PlayerController_EdenAlpha_C: SpawnMapMarker, EnableMouseCursor.
- Picture: https://github.com/Blackouest/genesis-alpha-one-coop/blob/main/docs/img/2026-10-25_guest-moves-v19.jpg
### Derived
- Movement works because UE's CharacterMovement already replicates (client prediction + ServerMove). Everything else the guest does runs the single-player Blueprint locally on the guest, without authority: spawning/equipping weapons, possessing the BuilderCharacter for the map/builder view, using terminals. Those have to run on the host for the guest.
### Plan (next session)
1. Call the game's own init (`OnLevelLoadedInitializePlayer` / `InitializePlayer`, `InitWeaponsFromSave`) on the host for the guest's character instead of copying values.
2. Guest-to-host action channel without new RPCs: an existing reliable server RPC carrying a string (candidate: `PlayerController:ServerChangeName`, hooked on the host), host-to-guest with `ClientMessage`.
3. Forward the guest's input actions (Blueprint `InpActEvt_*` functions, script hooks) to the host and run them there on the guest's pawn; then handle Blueprint code that uses GetPlayerController(0) / GetPlayerCharacter(0) (impersonation window, see the Doors of Trithius write-up).
4. Third-person body for remote players; door state sync; the parts of the ship the guest does not see.

## Phase 4a: guest actions, step 1 (2026-10-25, probe v20)
### Plan
- Guest movement works; every other guest action runs single-player Blueprint on the guest without authority.
- Message channel with existing engine RPCs: guest -> host `PlayerController.ServerChangeName("COOP|...")` hooked on the host; host -> guest `PlayerController.ClientMessage("COOP|...")` hooked on the guest. F6 on the guest sends a ping, the host must answer pong.
- F6 also installs script hooks on every `InpActEvt_*` Blueprint event of Eden_PlayerCharacter_C, BP_PlayerController_EdenAlpha_C and BuilderCharacter_C, so the log shows which input actions the guest's key presses trigger (weapon, map, use).
- Player init is now automatic: host initializes its copy of the guest after the reopen, guest its own pawn after the reveal (`initfix.apply`).

## Phase 4b: channel works; guest actions identified (2026-10-25 16:40, probe v20)
### Observations
- Auto init ran on both sides (host 16:39:39 for its copy of the guest, guest 16:39:50 for its pawn).
- **Channel works both ways:** guest `ServerChangeName("COOP|ping 16:40:10")` reached the host hook from the guest's BP_PlayerController_EdenAlpha_C; host `ClientMessage("COOP|pong 16:40:10")` reached the guest in the same second. No crash from these two native hooks.
- 154 `InpActEvt_*` events hooked (of 486 functions) on Eden_PlayerCharacter_C, BP_PlayerController_EdenAlpha_C, BuilderCharacter_C (`/Game/EdenAlpha1/Blueprints/Player/...`).
- Guest key presses fire locally: `InpActEvt_PC_SelectWeapon_1_..._50/_51` (pressed/released pairs), `PC_SelectWeapon_2_..._48/_49`, `PC_ActivateBuilderMode_..._23` (TAB, map/builder), plus movement events and very frequent `ChangeInputType_90` / `KeyboardAnyKeyConfirm_82`. On the host, TAB also fires `BuilderCharacter_C.InpActEvt_PC_ActivateBuilderMode_18` (the host then possesses its builder); `PC_Fire_25` seen on the host.
### Next (probe v21)
- Guest forwards every own-pawn action event except movement/look/jump/crouch/sprint/input-type noise as `act|<event name>`; host calls that same event on the sender's pawn with an empty FKey. Action hooks now install automatically.

## Phase 4c: forwarding works end to end, actions do nothing yet (2026-10-25 18:28, probe v21)
### Observations
- Every guest action reached the host and ran on the guest's pawn without a Lua error: `PC_SelectWeapon_1/2` (pressed/released), `PC_ActivateBuilderMode_23` (TAB), `PC_HoldUse_12/13`, `PC_Use_19/20`, `PC_Multitool_43`.
- Owner: weapon selection makes the weapon-selection HUD appear **on the host and on the guest**, but no weapon change. Map (TAB), PDA (T), lockers and screens: nothing.
### Derived
- The forwarded Blueprint uses player-0 helpers for UI (host's HUD shows the guest's selection).
- The guest's pawn on the host never got its loadout: our init copied flags only; the game's `InitWeaponsFromSave` never ran for it.
### Next (probe v22)
- F2: per player character, dump weapon/inventory/equipment/builder/tool/slot/item/flashlight/hud/oxygen properties (values, object names, array sizes). F2 again on the host: call `InitWeaponsFromSave` on the guest's character and dump again.

## Phase 4d: the guest has no weapons, and shares the host's HUD (2026-10-25 18:39, probe v22)
### Observations (host side, before and after forwarding the guest's weapon keys)
- Host's own pawn: WeaponSlot1=BP_WeaponPistol_C, WeaponSlot2=BP_WeaponPowerShotgun_C, NoWeapon=BP_NoWeapon_C, Multitool=BP_Weapon_Multikit_C, CurrentWeaponInUse=BP_NoWeapon_C.
- Host's copy of the guest: **WeaponSlot1/2, NoWeapon, Multitool, CurrentWeaponInUse all none**. It has its own BuilderCharacterOwner and PlayerInventoryAvatar.
- **Both pawns point at the same `PlayerHud` (PlayerHudWidget_C_2147482146)**, the host's HUD. On the guest, both pawns also point at the guest's one HUD. So any Blueprint path through `PlayerHud` acts on the local player's HUD.
- Calling `InitWeaponsFromSave` on the guest's pawn on the host did not give it weapons (slots still none); the pcall result printed as a function value, so the call itself may have failed: unknown.
- After the guest's forwarded `PC_SelectWeapon_1/2` and `PC_EquipSentryGun`, the **host's** pawn changed (CurrentWeaponInUse Pistol, IsWeaponEquiped true, CurrentInventorySlot 1, LastSelectedSlot 2) while the guest's stayed empty. Whether the owner also pressed keys in the host window at that time: unknown, but the pattern matches player-0 / shared-HUD routing.
### Derived
- Weapons for the guest must exist on the host: spawn the four weapon actors for the guest (same classes) owned by its pawn, or make the game's init run with the guest as "player 0".
- Forwarded actions need an impersonation window: while the host runs a guest action, player-0 lookups (and the HUD reference) must resolve to the guest.

## Phase 4e: giving the guest its own weapons (2026-10-26, probe v23)
### Plan
- F2 twice on the host now runs `weapons.give`: dump the host's slot weapons with class, attach parent/socket, owner, hidden; call `InitWeaponsFromSave` on the guest pawn with xpcall to get the real error; if slots stay empty, spawn the host's weapon classes for the guest (`BeginDeferredActorSpawnFromClass` + `FinishSpawningActor`, owner/instigator = guest pawn), attach them to the guest's component of the same name and socket, fill WeaponSlot1/2, NoWeapon, Multitool, CurrentWeaponInUse=NoWeapon.
- Set the guest pawn's `PlayerHud` to none on the host so forwarded actions stop driving the host's HUD.
- Test protocol: do not touch the host window while the guest presses keys (to separate guest effects from host input).

## Phase 4f: HUD detached; weapon calls fail (2026-10-26 14:52, probe v23)
### Observations
- Host's weapons: Pistol, PowerShotgun, NoWeapon, Multikit, all attached to the host pawn's `Mesh2P` at socket `HandRight`, no owner; only the current one (NoWeapon) is not hidden.
- Guest pawn on the host: all slots none, PlayerHud = the host's HUD before, set to none by the mod.
- `InitWeaponsFromSave()` and `GameplayStatics.BeginDeferredActorSpawnFromClass(...)` both failed in pcall with an error value that is a Lua function (`function: 00000189BE007250`, same value for all), no text.
- Owner: the guest still has no weapon, **but the host's HUD no longer pops up** when the guest switches weapons (PlayerHud=none on the guest pawn works).
### Next (probe v23b)
- Log the parameter list of InitWeaponsFromSave, BeginDeferredActorSpawnFromClass and FinishSpawningActor; call the error value to get its text; fall back to the CheatManager `summon <class>` and adopt the new actor.
- 2026-10-26 15:03 run: F2 never registered on the host (no dump, no weapons.give), so nothing was tested; the host HUD popped up again because PlayerHud was not cleared in that run (consistent with the previous result).
- Owner: in this game weapons cannot be dropped on the floor; they are stored in and taken from lockers. Possible later route: give the guest weapons through the locker flow.
- v23c: the host's auto flow calls `weapons.give` once a guest pawn exists and is initialized (no key needed).

## Phase 4g: weapon spawn attempts all fail the same odd way (2026-10-26 15:08, probe v23c)
### Observations
- Auto give ran 15:08:03 after auto-init. `InitWeaponsFromSave()` and `GameplayStatics.BeginDeferredActorSpawnFromClass` fail in pcall/xpcall with an error *value that is a Lua function* (same address for every call); calling it errors again with itself; the xpcall message handler output never shows. UE4SS.log has no error text for these calls.
- The `params(...)` diagnostics placed right after produced no log line at all (not even "not found").
- `summon BP_WeaponPistol_C` was executed (the console hook shows it ten times: once per world context/listener) but no new BP_WeaponPistol_C appeared.
- Owner: guest still unarmed; host HUD no longer reacts to guest weapon keys; nothing appears near the host.
### Next (probe v23d)
- Log `debug.getinfo` of the error function, control calls (K2_GetActorLocation, IsLocallyControlled) in the same context, the type of `g.InitWeaponsFromSave`, and a log line on entering `params`.

## Phase 4h: what fails is parameter marshalling (2026-10-26 15:14, probe v23d)
### Observations
- Control calls in the same game-thread context succeed: `K2_GetActorLocation`, `IsLocallyControlled`. `g.InitWeaponsFromSave` resolves (userdata).
- `InitWeaponsFromSave()` and `BeginDeferredActorSpawnFromClass(g, cls, xf, 1, g)` fail with an error value that is a C function (`debug.getinfo`: what=C, src=[C]) -> raised inside UE4SS's C++ call path, not by the game.
- `params()`: ForEachFunction finds both functions (the "not found" line is not printed) but `UFunction:ForEachProperty` errors the same odd way (as in v7), so parameter lists cannot be read with UE4SS 3.0.1 Lua.
- `summon <class>` runs (CheatManager enabled by UE4SS) but spawns nothing: unknown whether the cheat is stubbed in this shipping build.
### Next (probe v23e)
- InitWeaponsFromSave with (), (nil), (false), (nil,nil), (0); BeginDeferredActorSpawnFromClass with the class from StaticFindObject, without owner, with 3 args, with the host PC as world context.

## Phase 4i: all call variants fail on UE4SS 3.0.1; moving to UE4SS experimental (2026-10-26)
### Observations (probe v23e, 15:17)
- `InitWeaponsFromSave` with (), (nil), (false), (nil,nil), (0): all fail with the C-function error value.
- `BeginDeferredActorSpawnFromClass`: class from GetClass or StaticFindObject, with/without owner, 3 args, host PC as world context: all fail the same way. `summon` spawns nothing.
- Calls that work in the same context: K2_GetActorLocation, IsLocallyControlled, SetMovementMode, Activate, LoadLevelInstance (static, on the guest), Blueprint `InpActEvt_*` events.
### Decision
- Try UE4SS experimental: owner downloaded `UE4SS_v3.0.1-1183-gcdbc0b66.zip` from https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest, SHA-256 `e4a47e23e2eeb8379c4fc388d1b1686f01c6c5930d84a2ee4a6a9574b274e681` (zip test OK; not compared with GitHub's digest from this session).
- New layout: `dwmapi.dll` next to the exe, everything else in `<Win64>/ue4ss/` (UE4SS.dll, UE4SS-settings.ini, Mods with mods.txt **and** mods.json). Same settings changes as before (Major 4, Minor 23, consoles on, dx11). Old 3.0.1 files moved to `<Win64>/_ue4ss_3.0.1_backup/`.
- Probe v24: file paths go through `COOP_BASE` (ue4ss/Mods/CoopProbe/ or Mods/CoopProbe/), so the same scripts run on both UE4SS layouts.

## Phase 4j: UE4SS experimental unblocks the calls; GUEST HAS A WEAPON (2026-10-26 15:29, probe v24)
### Observations
- UE4SS `v3.0.1-1183-gcdbc0b66` loads with the same settings; only start-up warnings (ConsoleManagerSingleton found twice, unknown sizes for FStructProperty/FObjectPtrProperty/FEnumProperty, fallbacks to Default__ objects). Connection, rendering, guest movement still work.
- Errors are now readable. `InitWeaponsFromSave` takes one parameter, an array `WeaponSaveData` (its locals: LNextWeapon, Array_Get_Item struct...). `UFunction:ForEachProperty` works now.
- `BeginDeferredActorSpawnFromClass(g, cls, xf, 1, g)` + `FinishSpawningActor` **work**: guest got BP_WeaponPistol_C and BP_WeaponPowerShotgun_C (and the others) attached to its `Mesh2P` at `HandRight`, owner = guest pawn.
- Owner: **the guest holds a weapon, the host sees it move, the guest can fire.** Map, lockers and in-game screens still do nothing for the guest. Host shooting the guest damages the **host**. Guest shooting the host does nothing.
### Derived
- Damage and aim go through player-0 helpers: the forwarded Fire runs on the host with the host's camera as "player 0", and damage on a player character is applied to player 0.
- UE4SS experimental's RegisterHook can override return values (post callback return value), which allows an impersonation window.
### Next (probe v25)
- Host: post-hooks on GameplayStatics GetPlayerController / GetPlayerCharacter / GetPlayerPawn / GetPlayerCameraManager; while the host runs a forwarded guest action they return the guest's PC / pawn / camera manager (index 0 only). The act log shows how many player-0 lookups were redirected. Kill switch: `noimpersonate.txt` in the mod folder.

## Phase 4k: the impersonation window catches nothing (2026-10-26 16:11, probe v25)
### Observations
- The four GameplayStatics post-hooks registered fine, but for every forwarded guest action (Use/HoldUse, Multitool, SelectWeapon, Fire, ActivateBuilderMode) the window redirected **zero** player-0 lookups.
- Owner: guest fire shows no projectile on the guest's screen; on the host a projectile leaves the guest's weapon (only when the host looks at it) in the wrong direction. Lockers, screens, map still dead for the guest. PDA: the guest takes it out but its screen is empty. Guest shooting host: nobody loses health. Host shooting guest: **host** loses health. More crashes than before (three crash dumps today, stacks only show ntdll frames, unattributed).
### Derived
- The input-action events only start things (flags, timers, ticks, montages); the work that uses player 0 runs later, outside a synchronous window. Forwarding raw input to the host does not scale for this game.
- UI (lockers, screens, PDA content, map) is per-machine and must run on the guest; only the world effects must run on the host.
### Change
- Impersonation hooks disabled by default (`noimpersonate.txt`), they did nothing and fire on very hot functions.
### Proposed next step
- Stop guessing from the outside: extract the player Blueprints from the pak (repak, pak v8 unencrypted index) and read their bytecode (kismet-analyzer) to see exactly how Fire, Use, lockers, PDA, damage and builder mode work, then sync each feature deliberately (guest runs UI and local visuals, host runs world effects, messages in between).

## Phase 5a: reading the game's Blueprints (2026-10-26)
### Tools (in tools/, ours, MIT; no game data in the repo)
- `pakread.py`: minimal reader for UE4 pak v8 (this pak: version 8, 25,288 files, unencrypted index, zlib blocks with unnamed compression method). Run on the owner's PC against the test copy; extracts only the requested Blueprints into `<test dir>/_extract` (never published).
- `kismet.py`: reads cooked 4.23 packages (name/import/export maps) and disassembles Kismet bytecode to pseudo-code. The script is located from the end of each function export (BytecodeSize, StorageSize, ..., EX_EndOfScript, then FunctionFlags/EventGraph fields), candidates validated by a clean decode. All 724 extracted Blueprints decode without error (kismet-analyzer needs .NET and repak needs crates.io, both unreachable from this session).
### Findings
- `Eden_PlayerCharacter`: 360 functions, ubergraph of 32,819 bytes on disk. `InitWeaponsFromSave(WeaponSaveData)` just loops and calls **`AddEquipmentToInventory(WeaponID, Slot)`**, which spawns the weapon class from `TerminalLibrary.GetWeaponInfo`, attaches it to `Mesh2P` at the weapon's `PlayerSocket`, hides it, sets **`WeaponOwner = self`**, runs `MultiInitializeWeapon(ID)` and `PlayerHud.UpdateInventoryWeapons()`. Slots: 0 NoWeapon, 1 WeaponSlot1, 2 WeaponSlot2, 3 SentryGun, 4 EnergyBarrier, 5 SampleCollector, 6 MultiTool.
- `BP_Weapon_CLASS.ShootProjectile` aims with `WeaponOwner...GetControlRotation()`. Our v24 weapons had no WeaponOwner, hence projectiles flying the wrong way.
- `UseInteractionObject` does nothing unless `CurrentFocusedPlayerInteraction` (set by `CheckLineOfSightForInteractions`) is valid; then it switches on the interaction type (EPlayerInteractions).
- `PlayerLibrary.GetPlayerHud` returns `GetPlayerCharacter(0).PlayerHud` (or the builder's owner's). Damage events (`ReceivePointDamage` ...) on any player character update `GetPlayerHud(self).UpdatePlayerHealth(Health, HealthMax)`, i.e. the **host's** HUD on the host: the "host loses health" the owner saw is most likely the host HUD showing the guest's health.
- Player-0 lookups per asset: BuilderCharacter 21, FirstPersonGameMode 17, Eden_PlayerCharacter 16, Genesis_GameInstance 10, BP_Weapon_CLASS 6, PlayerHudWidget 5, plus several weapons and terminals.
### Next (probe v26)
- Guest weapons through `AddEquipmentToInventory(hostWeapon.WeaponID, slot)` for every slot the host has (including sentry gun, energy barrier, sample collector, multitool); start with NoWeapon in hand.

## Phase 5b: guest shots aim right (2026-10-26 17:50, probe v26)
### Observations (owner)
- With weapons from `AddEquipmentToInventory`, the guest's shots go in the right direction and hit (impact registered) even when the host is not looking.
- Projectiles and impacts are visible **only on the host**.
- Host shoots guest: the host "takes the damage". Guest shoots host: the host takes damage (expected).
### Derived
- Projectiles/impact FX are spawned by the host for the forwarded Fire and are not replicated. The guest's own pawn has no weapon references locally (slot variables are not replicated), so its local Fire does nothing visible.
- "Host takes the damage" when the host shoots the guest is probably the guest's health shown on the host HUD (GetPlayerHud = player 0); to be checked against real Health values.
### Next (probe v27)
- Host sends `weap|slot:id,...` to the guest after giving weapons; the guest calls `AddEquipmentToInventory` on its own pawn locally, so its local Fire shows its weapon, projectiles and impacts (damage stays authoritative on the host).
- Health of every player character logged on change, both sides.

## v28-v30: guest sees its own shots, health bar
- v28: host sends its PlayerState.Ammunition pool ("ammo|...") and the guest's real health ("hp|h|max") over the ClientMessage channel. Guest health and HUD values now follow the host.
- v29: tracing showed the guest's local Fire input never reaches AttemptToUpdatePrimaryAction, even with ammo and IsWeaponEquiped=true. Calling PlayerShootsWeapon() on the guest's own pawn 150 ms after a press (when the game did not shoot) runs ReduceAmmo -> WeaponShotEffects -> ShootProjectile locally: the guest now sees its projectile and impact. Confirmed in game.
- v30: on a health drop the guest plays the game's hit feedback locally (ClientPlayCameraShake with BP_CameraShake_PlayerHit*, Timeline_HitPostprocess), which otherwise only runs on the host's copy of the pawn.
- Open: hold-to-fire (automatic weapons) only fires once per press on the guest.
- v31: the game's hit feedback works on the guest when driven directly: PlayerCameraManager:PlayCameraShake(BP_CameraShake_PlayerHit*) and PlayerDamagePostProcess (bEnabled, BlendWeight faded by the mod). Confirmed in game.
- v32: guest death. PlayerDies runs on the host copy of the guest pawn, so the death/respawn HUD showed on the host and the game's own revive (health back to 100 after ~2 s) left the guest unable to take damage. The host now keeps the guest pawn off the host HUD, sends "dead|" (guest fades out), and after ~4 s revives the guest next to the host (IsDead/Block cleared, health full, movement on, view target back, death camera removed) and sends "revive|".
- v32 result: guest revives and takes damage again. But the guest pawn's feedback still played on the host (camera shake via GetPlayerController(0), unbound PlayerDamagePostProcess, death fade, promotion screen). Death flow found: PlayerDies -> KillPlayer, PlayerHud.OnPlayerDeath, death camera, StartFadeOut, 2.5 s, PromotionNewCaptain -> FindNewCrewCaptain, RessurectPlayer, crew member promoted then disintegrated (the game's rule: a death costs a crew member). GameOver if none left.
- v33: host hooks ReceiveDamage/ReceivePointDamage/ReceiveRadialDamage/PlayerDies/OnPromotionFinished on the guest pawn and undoes the effects on its own screen (StopAllCameraShakes, post-process off on the guest pawn, StartFadeIn, OnPromotionEnded, view target back).
