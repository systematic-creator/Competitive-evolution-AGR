# Testing on the Godot Android Editor

The project is set up so it opens and runs inside the **Godot 4.3+ Android editor**
(Google Play / Meta Horizon store build, or the APK from godotengine.org).

## Import

1. Copy `Competitive-evolution-AGR.zip` to your phone (e.g. `Download/`).
2. Open Godot → Project Manager → **Import** → pick the `.zip`.
3. Choose an empty folder to extract into → **Import & Edit**.
4. The first open builds the `.godot/` cache; wait for the import bar to finish.

## Run

Press **Play** (▶). The main scene is `scenes/debug/smoke_test.tscn`. It runs
self-checks on the autoloads and data Resources and should end with
`N passed, 0 failed` in green. The buttons let you:

- **Next zoom tier**: cycles ORBIT → REGION → RTS → THIRD_PERSON via `GameState`,
  logged through `EventBus.zoom_tier_changed`.
- **Start/Stop sim**: runs the 1-second simulation tick (watch `Tick:`).
- **Re-run checks**: resets `GameState` and runs all checks again.

If the editor warns that Vulkan is not supported, switch the renderer to
**Compatibility** (top-right renderer menu, or
`rendering/renderer/rendering_method.mobile="gl_compatibility"`).

## Before AR export (not needed for this test)

These are intentionally off so the project runs on any phone without an
OpenXR runtime:

- `xr/openxr/enabled=true`
- `rendering/viewport/transparent_background=true`
- Install & enable the Godot OpenXR Vendors plugin.
- Point `application/run/main_scene` at `res://scenes/main_ar.tscn`.
