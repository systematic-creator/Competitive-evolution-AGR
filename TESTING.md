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

If the editor warns that Vulkan is not supported, switch the renderer to
**Compatibility** (`--rendering-method gl_compatibility`).

## Headless tests

```bash
godot --headless --path . res://scenes/debug/smoke_test.tscn
godot --headless --path . res://scenes/debug/sim_tests.tscn
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
blocking enemy claims, and destroying a structure releasing its claim.

## Before AR export (not needed for this concept)

These are intentionally off so the project runs on a desktop or any phone
without an OpenXR runtime:

- `xr/openxr/enabled=true`
- `rendering/viewport/transparent_background=true`
- Install & enable the Godot OpenXR Vendors plugin.
- Point `application/run/main_scene` at `res://scenes/main_ar.tscn`.
