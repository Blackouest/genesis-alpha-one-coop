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
- Picture: docs/img/2026-10-25_engine-shots_host-solo_host-black_guest.png
### Derived
- The host's scene is rendered; the black is drawn on top at the UI level (HighResShot excludes UMG). Most likely a full-screen black image inside the HUD widget tree that the guest's arrival turns on (single-player fade logic) and that switching to the builder/map UI turns off.
### Next (probe v16)
- F1: list every visible Image/Border whose widget chain reaches a widget in the viewport, with visibility, render opacity and colour; flag near-black opaque ones. F1 again hides the flagged ones.

## Phase 3u: BLACK SCREEN SOLVED - `FadeOutBorder` in the HUD (2026-10-25 15:30, probe v16)
### Observations
- F1 list on both windows: 128 visible Images/Borders inside viewport widgets. The only full-screen black one is **`Border FadeOutBorder` in `PlayerHudWidget_C`**, visibility 4 (SelfHitTestInvisible), render opacity 1, colour 0,0,0,1. The 17 others are ordinary dark panel backgrounds (PlayerHealthWidget, PlayerCurrentWeapon, AlienMotionTracker, CrewWeaponSelectionItem, TalkScreen, TutorialWarning, ControllerButtonHintWidget, LoadingScreen hint boxes).
- After hiding them (F1 twice): **both windows show the game**. Host: normal first-person view. Guest: world visible behind the "CHARGEMENT" loading screen (LoadingScreen_Widget_C, nested in PlayerHudWidget_C); the **host's weapon is seen moving as the host walks** (live replication works), but no host body (first-person-only mesh).
- LoadingScreen_Widget_C lives inside PlayerHudWidget_C on both machines.
- Picture: docs/img/2026-10-25_both-windows-after-hiding-FadeOutBorder.jpg
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
- Owner screenshot: host first-person view with weapon and HUD hints; guest sees the ship interior (imported modules, lit) with HUD hints. Picture: docs/img/2026-10-25_both-windows-render-ship-v17b.jpg
- Host: everything works. Guest: spawned high up, can only turn the camera; no movement, no weapon selection, no map.
- Earlier dumps already showed the guest pawn at z=319 on the guest vs z=98 on the host.
### Hypothesis
- The single-player load flow disables player input / movement until "loading done", and that event never fires for the guest.
### Next (probe v18)
- F2: dump local PC (move/look input ignored, cursor, interesting bool/number BP vars), pawn (location, velocity, InputEnabled, role, CharacterMovement mode/gravity/speed/active, BP vars), all player characters' locations. F2 again: ResetIgnoreInputFlags, SetIgnoreMove/LookInput(false), pawn EnableInput, SetMovementMode(Walking), SetInputMode_GameOnly.
