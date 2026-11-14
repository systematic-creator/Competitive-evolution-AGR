# Competitive Evolution AGR

Mobile AR real-time strategy and species/faction evolution game built in **Godot 4.3+** (strictly typed GDScript 2.0). Players anchor a virtual world to physical space and move closer or farther to travel across four gameplay scales.

This repository also includes a **desktop concept build**: a full orbit globe, one playable region, three AI factions, and one player faction, with the AR zoom stand-in mapped to mouse-wheel camera distance. OpenXR stays off so the project runs on a desktop or headless CI machine.

## Quick start (desktop)

1. Open the project in Godot 4.3 (or run the official Linux editor binary).
2. The main scene is `scenes/main_desktop.tscn`.
3. Press Play.
    - **Scroll** to move between Orbit / Region / RTS distances (1.2m / 0.9m / 0.55m / 0.20m).
    - **Click a glowing region pin** on the globe to enter the Verdant Basin (the only accessible region in this concept).
    - **Left-click** a unit to select, **right-click** the ground to move. HUD buttons train units and enter build/claim mode (the faint hex overlay appears in the RTS tier); left-click a cell to place. Outposts hard-claim revealed rare nodes. Auto-Battle resolves a hex skirmish in the sim; **Contest (possess)** drops you into Tier 4 to fight the skirmish yourself (see below).
    - **P** possesses a selected unit (Tier 4). **WASD** moves it. **P** or **Esc** releases.
    - **Space** pauses or resumes the simulation.
    - **Skirmish possession (Tier 4):** with a soldier standing in an enemy-held hex of a revealed rare node, press **Contest (possess)**. You take over one squad member behind a SpringArm3D camera. **WASD** / arrows or the on-screen joystick move (camera-relative), **F** / **J** or the Attack button strike, **Q** / **E** or a drag on empty screen turn the camera, **Esc** or Auto-resolve falls back to auto-battle. The strategic clock is held while you fight; it resumes when the skirmish is resolved.

## Headless tests

```bash
godot --headless --path . res://scenes/debug/smoke_test.tscn
godot --headless --path . res://scenes/debug/sim_tests.tscn
```

Both scenes print `PASS` / `FAIL` lines and quit with a non-zero exit code on failure when running headless.

## Architecture

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the engine rules, folder map, zoom pipeline, and data-driven era/species system. Simulation logic (faction AI, resource ticks, era progression) is decoupled from visual nodes and camera tracking via the `EventBus` autoload.

Starter data lives under `data/eras`, `data/species`, `data/factions`, `data/regions`, and `data/nodes`.

## Branching note

The playable project lives on `claude/godot-project-init-fywmz7` (and the local `concept-build` branch). `main` currently only contains a leftover bootstrap script in `README.md` and should receive this work in a merge, replacing that file with this README.

## License / status

Concept / work-in-progress. Art is primitive engine meshes on purpose.
