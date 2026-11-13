cat << 'EOF' > ARCHITECTURE.md
# Project Architecture: Competitive Evolution AGR (Godot 4.x)

## 1. Engine & Target Specs
* **Engine:** Godot 4.3+ (Forward+ or Mobile Renderer)
* **Language:** Strictly typed GDScript 2.0 (`class_name`, static typing on all variables/functions)
* **AR Backend:** Godot OpenXR Vendors Plugin (ARCore for Android / ARKit for iOS) with Passthrough enabled.
* **World Scale:** 1 Godot Unit = 1 Meter in real-world AR space.

## 2. Core Design Rules for AI Generation
1. **Decoupled Simulation:** Keep Faction AI, Resource Tick loops, and Era Progression in pure `RefCounted` classes or Autoloads. Never tie simulation math to visual meshes or AR camera transforms.
2. **Signal-Driven UI & Visuals:** Systems communicate upward via Godot Signals (`EventBus`). Visual nodes listen to data changes rather than polling every frame.
3. **Hybrid AR-to-Virtual Camera:** 
   * Tiers 1–3 use the physical `XRCamera3D` moving relative to an `XRAnchor3D`.
   * Tier 4 (Third-Person) smoothly disables AR tracking influence and interpolates a standard `Camera3D` behind a `CharacterBody3D`, adding a virtual touchscreen joystick.

## 3. Folder Structure
res://
├── autoload/
│   ├── event_bus.gd          # Global signals (era_changed, zoom_tier_changed, region_selected)
│   └── game_state.gd         # Active factions, global tick timer, current zoom tier
├── data/
│   ├── eras/                 # .tres files (EraData resources: Stone, Bronze, Industrial, etc.)
│   └── species/              # .tres files (SpeciesData resources: traits, starting bonuses)
├── resources/                # Custom Resource definitions (era_data.gd, species_data.gd)
├── scenes/
│   ├── main_ar.tscn          # XROrigin3D, XRCamera3D, WorldEnvironment (transparent bg), AR Anchor
│   ├── world/
│   │   ├── orbit_globe.tscn  # Tier 1: Low-poly 3D sphere with clickable region markers
│   │   └── flat_diorama.tscn # Tiers 2–4: Floating flat terrain chunk with NavigationRegion3D
│   ├── entities/             # Base Building and Unit scenes with modular mesh slots
│   └── ui/                   # Minimal spatial UI & Third-person touch controls
└── scripts/
    ├── ar/                   # Plane detection, anchor placement, pinch-to-scale
    ├── camera/               # ZoomTierController & ThirdPersonRig
    └── simulation/           # FactionManager, ResourceTick, BuildingUpgradeSystem

## 4. The 4-Tier Zoom & Transition Pipeline
* **Tier 1: ORBIT (Camera distance > 1.2m from Anchor)**
  * Visible: `orbit_globe.tscn` (Rotating 3D planet).
  * Hidden: `flat_diorama.tscn`.
  * Interaction: Tap a glowing Region Pin on the sphere to lock onto that region and zoom in.
* **Transition (1.2m -> 0.9m):**
  * Crossfade/scale-down `orbit_globe` while scaling-up `flat_diorama` loaded with that region's biome and faction data.
* **Tier 2: REGION (0.9m – 0.55m)**
  * Visible: `flat_diorama.tscn` (Macro view: territory borders, city hubs, resource nodes).
  * Hidden: Individual worker units (simulated abstractly in background).
* **Tier 3: RTS (0.55m – 0.20m)**
  * Visible: Active buildings, moving `NavigationAgent3D` units, health bars, build grids.
  * Interaction: Center-screen reticle + tap to select/command squads.
* **Tier 4: THIRD_PERSON (Triggered via "Possess Unit" button in RTS tier)**
  * Camera detaches from `XRCamera3D` transform, lerps to unit's `SpringArm3D`, enables virtual joystick.

## 5. Data-Driven Era & Species System
* `EraData` (extends `Resource`):
  * `era_name: String`
  * `era_index: int`
  * `building_meshes: Dictionary` (Maps `StringName` building IDs like `&"town_center"` to `PackedScene` or `Mesh`)
  * `unit_meshes: Dictionary`
  * `production_multiplier: float`
* When `EventBus.era_changed` fires for a faction, existing `Building` nodes swap their child mesh/scene using `EraData` without losing their grid coordinates or HP.
EOF

git add ARCHITECTURE.md
git commit -m "Add Godot 4 AR multi-scale architecture blueprint"
git push origin main
