# Testing

## Desktop concept (OpenXR off)

The main scene is `scenes/main_desktop.tscn`. Scroll the mouse wheel to move
between Orbit / Region / RTS distances. Click a glowing pin (the only
accessible region is Verdant Basin). Rare-resource icons (iron / coal) appear
on the Tier 1 pins only after the player reaches that node's `reveal_era`
(coal at the steam era, iron at era 2). They stay hidden at Stone.
The faint axial hex overlay appears only in Tier 3 when a build or
outpost (claim) order is pending.

Left-click selects a unit, right-click moves or assigns gather. HUD buttons
train units (basic workers/soldiers use only common resources; Ironclads and
Steamwalkers need rare iron/coal) and enter build mode. Space pauses the sim.
P possesses a selected unit (WASD to walk). Esc releases.

**Tier 4 skirmish possession.** Put a soldier in an enemy-held hex of a
revealed rare node and press **Contest (possess)**. The controller possesses
one squad member (the selected unit if it is in the squad) and switches to
the SpringArm3D camera with the touch overlay: joystick bottom-left, Attack
and Auto-resolve bottom-right. Desktop keys: WASD / arrows move
(camera-relative), F or J attack, Q / E turn the camera, Esc auto-resolves.
The strategic tick is held while the fight is live and resumes once the
skirmish is resolved. If nobody can be possessed, the skirmish auto-battles.

If the editor warns that Vulkan is not supported, switch the renderer to
**Compatibility** (`--rendering-method gl_compatibility`).

## Headless tests

```bash
godot --headless --path . --import
godot --headless --path . res://scenes/debug/smoke_test.tscn   # 14 passed
godot --headless --path . res://scenes/debug/sim_tests.tscn    # 165 passed
```

Both print `PASS` / `FAIL` lines and quit non-zero on failure when headless.

Sim tests cover: faction bootstrap (Humans + Sylvari + Kraal + Cogforged),
AI construction over N ticks, the player command path, common-node
depletion, Sylvari common-node regrowth (rare nodes do not regrow), Kraal
faster depletion, era-gated rare-node reveal (coal at the steam era / index 1,
iron at era 2; visibility is per-faction; AI only targets visible nodes),
rare-cost gating for later era advances and specialized units, Cogforged
extractors boosting rare-node yield, hex ownership and claimed-hex yield
split, full-control capture, the outpost escalation ladder, auto-battle
skirmishes that flip a captured outpost, the possession stub, occupation
blocking enemy claims, and destroying a structure releasing its claim. They also cover per-species era tracks, world-era soft-cap cost scaling, each win condition (plus species subsets), and determinism (same seed + command log => identical state hash).

Tier 4 possession tests cover: the request leaving the skirmish pending,
the capped attacking squad as possession candidates (no enemies, no
workers), starting the live fight (both squads plus the outpost guard),
quantized steering inside the arena, the boosted possessed strike and its
cooldown, the strategic tick being held (and a forced tick fighting the
skirmish out first), a field victory that captures the outpost through
`resolve_skirmish_possessed`, the auto-battle fallback mid-fight, the
timeout verdict, replaying a full possession fight from the command log to
the same state hash, and the SkirmishPossessionController (ignores AI
requests, possesses via CommandService, joystick -> steer sector, Attack ->
strike, Auto-resolve, resolving a finished fight, falling back to
auto-battle when no unit can be possessed).

## Before AR export (not needed for this concept)

These are intentionally off so the project runs on a desktop or any phone
without an OpenXR runtime:

- `xr/openxr/enabled=true`
- `rendering/viewport/transparent_background=true`
- Install & enable the Godot OpenXR Vendors plugin.
- Point `application/run/main_scene` at `res://scenes/main_ar.tscn`.
