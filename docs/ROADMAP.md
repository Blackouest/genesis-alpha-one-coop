# Roadmap

Follows the Co-op Anything phase map. `[x]` = verified by a test run, see NOTES.md.

## Phase 3: understand
- [x] Identify build, engine (UE 4.23), tooling (UE4SS 3.0.1)
- [x] Listen server via IpNetDriver
- [x] Second instance joins, gets its own possessed character
- [x] Check for OptionalLevelNameOverride in 4.23: not present
- [ ] Ship modules on the guest with the host's exact instance names (plan B: line up the instance counter, or a native hook)
- [ ] Log which package names the guest reports and why it is kicked
- [x] Guest sees the ship (levels copied, loading screen and fade removed by the mod)
- [ ] Give the guest control: movement, weapons, map (input/movement left disabled by the load flow?)
- [ ] Third-person body for remote players (player mesh is first-person only)
- [ ] Find what the guest's loading screen waits for (`LoadingScreen_Widget_C`), to replace the workaround
- [x] Find why the host's screen goes black when the guest joins (HUD FadeOutBorder left opaque)
- [ ] Separate save folder for test copies
- [ ] Find out whether the startup crash also happens without UE4SS

## Phase 4: choose the design
- [ ] Host authority: host runs the whole simulation, guest is a client of UE's own replication
- [ ] List which game Blueprints assume a single player (GetPlayerController(0) / GetPlayerCharacter(0))

## Phase 5: build
- [ ] Ship layout sync on join and when modules are built or removed
- [ ] Crew, clones, enemies and infestations (check what the Blueprints already replicate)
- [ ] Interactions: workstations, doors, tractor beam, building UI
- [ ] Planet expeditions and level travel with two players
- [ ] Saves: host only; guest progress rules
- [ ] DLC: same content on both sides?

## Phase 6: QA
- [ ] Bot-driven tests with two real game clients (coop-anything tools: chaos, flight, bots)

## Phase 7: ship
- [ ] Steam relay (Spacewar) or other NAT-friendly transport. The Epic build has no steam_api64.dll.
- [ ] One-click host and join UI
- [ ] Install as an add-on into the Epic install so DLC still works
