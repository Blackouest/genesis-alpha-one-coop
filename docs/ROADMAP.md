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
- [x] Guest movement (character never initialized by the game; the mod initializes it)
- [ ] Call the game's own player init on the host for the guest (OnLevelLoadedInitializePlayer / InitializePlayer / InitWeaponsFromSave)
- [x] Guest-to-host action channel (existing string RPC, e.g. ServerChangeName) and host-to-guest (ClientMessage)
- [x] Forward the guest's input actions to the host (InpActEvt_* hooks) and run them on the guest's pawn; handle GetPlayerController(0) assumptions
- [ ] Door state sync; ship parts missing on the guest
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

### Player state (in progress)
- [x] Guest weapons, aim and real damage on the host
- [x] Guest sees its own shots and impacts (local PlayerShootsWeapon)
- [x] Guest health bar and hit feedback (shake, red flash)
- [x] Guest death: revive, can move and take damage again
- [ ] Keep the guest's hints, death and promotion screens off the host and show them on the guest (v34 in test)
- [ ] Hold-to-fire for automatic weapons on the guest
- [ ] Slot-2 weapon visible on the host
- [ ] Lockers, screens, PDA and map (builder) for the guest
- [ ] Ship colours identical on both sides

### Death rules (owner's choice)
- [ ] Original rule for both players: a death costs a clone / crew member, and the player comes back as that crew member
- [ ] With two players and one clone left: a player who dies waits; as soon as a new clone is created, that player can respawn
- [ ] Game over only when no clone is left for a dead player and the other player is dead too (to confirm in play)

## Phase 6: QA
- [ ] Bot-driven tests with two real game clients (coop-anything tools: chaos, flight, bots)

## Phase 7: ship
- [ ] Steam relay (Spacewar) or other NAT-friendly transport. The Epic build has no steam_api64.dll.
- [ ] Two buttons in the game's main menu: "Host a co-op game" and "Join a co-op game" (owner's request), replacing F9/F8
- [ ] Install as an add-on into the Epic install so DLC still works
