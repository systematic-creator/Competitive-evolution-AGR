# Project Architecture: Competitive Evolution AGR (Godot 4.x)

## 1. Engine & Target Specs
* **Engine:** Godot 4.3+ (Forward+ or Mobile Renderer). The desktop concept build uses the Compatibility renderer when captured in CI (`--rendering-method gl_compatibility`).
* **Language:** Strictly typed GDScript 2.0 (`class_name`, static typing on all variables/functions)
* **AR Backend:** Godot OpenXR Vendors Plugin (ARCore for Android / ARKit for iOS) with Passthrough enabled. **OpenXR stays disabled** (`xr/openxr/enabled=false`) until a dedicated AR export is wired up.
* **World Scale:** 1 Godot Unit = 1 Meter in real-world AR space (and in the desktop stand-in).

## 2. Core Design Rules for AI Generation
1. **Decoupled Simulation:** Keep Faction AI, Resource Tick loops, and Era Progression in pure `RefCounted` classes or Autoloads. Never tie simulation math to visual meshes or AR camera transforms.
2. **Signal-Driven UI & Visuals:** Systems communicate upward via Godot Signals (`EventBus`). Visual nodes listen to data changes rather than polling every frame. Unit *positions* may be read from `SimWorld` for interpolation; orders and state changes still go through signals or `CommandService`.
3. **Hybrid AR-to-Virtual Camera:**
   * Tiers 1–3 use the physical `XRCamera3D` moving relative to an `XRAnchor3D` (AR build) **or** `DesktopRig` distance (desktop concept: mouse wheel = camera distance).
   * Tier 4 (Third-Person) smoothly disables AR tracking influence (or the desktop boom) and interpolates a standard `Camera3D` behind a `CharacterBody3D`, adding a virtual joystick or WASD.

## 3. Folder Structure
res://
├── autoload/
│   ├── event_bus.gd          # Global signals (era_changed, zoom_tier_changed, region_selected, sim events)
│   └── game_state.gd         # Zoom tier, tick clock, selected region, owns SimWorld
├── data/
│   ├── eras/                 # .tres files (EraData: Stone, Bronze, Iron, Industrial)
│   ├── species/              # .tres files (SpeciesData: traits, starting bonuses)
│   ├── factions/             # .tres files (FactionData: player + AI factions)
│   ├── regions/              # .tres files (RegionData: globe pins, accessibility, grid, advertised rares)
│   └── nodes/                # ResourceNodeData types + RegionNodeLayout placements
├── resources/                # Custom Resource definitions (era, species, faction, region, resource nodes)
├── scenes/
│   ├── main_desktop.tscn     # Desktop concept entry (OpenXR off)
│   ├── main_ar.tscn          # Future XROrigin3D / XRCamera3D path (not in this concept)
│   ├── world/
│   │   ├── orbit_globe.tscn  # Tier 1: territory-colored sphere with region pins
│   │   └── flat_diorama.tscn # Tiers 2–4: terrain chunk, NavigationRegion3D, build grid
│   ├── entities/             # Building and Unit scenes with modular mesh slots
│   ├── ui/                   # Desktop HUD (stand-in for spatial / touch UI)
│   └── debug/                # smoke_test.tscn, sim_tests.tscn
└── scripts/
    ├── ar/                   # Plane detection, anchor placement, pinch-to-scale (future)
    ├── camera/               # ZoomTierController, DesktopRig, ThirdPersonRig
    ├── desktop/              # MainDesktop, RtsController
    ├── entities/             # BuildingView, UnitView
    ├── simulation/           # SimWorld, CommandService, FactionAI, ResourceTick, ...
    ├── ui/                   # DesktopHud
    └── world/                # OrbitGlobe, FlatDiorama, RegionPin, BuildGrid

## 4. The 4-Tier Zoom & Transition Pipeline
* **Tier 1: ORBIT (Camera distance > 1.2m from Anchor)**
  * Visible: `orbit_globe.tscn` (Rotating 3D planet with faction territories and pins).
  * Hidden: `flat_diorama.tscn`.
  * Interaction: Tap / click a glowing Region Pin on the sphere to lock onto that region and zoom in.
* **Transition (1.2m -> 0.9m):**
  * Crossfade/scale-down `orbit_globe` while scaling-up `flat_diorama` loaded with that region's biome and faction data.
* **Tier 2: REGION (0.9m – 0.55m)**
  * Visible: `flat_diorama.tscn` (Macro view: territory borders, city hubs, resource nodes).
  * Hidden: Individual worker units (simulated in the background; hidden visually).
* **Tier 3: RTS (0.55m – 0.20m)**
  * Visible: Active buildings, moving `NavigationAgent3D` units, health bars, build grids.
  * Interaction: Desktop — select/command with the mouse. AR — center-screen reticle + tap.
* **Tier 4: THIRD_PERSON (Triggered via "Possess Unit" in RTS tier)**
  * Camera detaches from `XRCamera3D` / desktop boom, lerps to the unit's `SpringArm3D`, enables WASD or a virtual joystick.

## 5. Data-Driven Era, Species, Faction, and Region System
* `EraData` (extends `Resource`):
  * `era_name: String`
  * `era_index: int`
  * `building_meshes: Dictionary` (Maps `StringName` building IDs like `&"town_center"` to `PackedScene` or `Mesh`)
  * `unit_meshes: Dictionary`
  * `production_multiplier: float`
* `SpeciesData` (extends `Resource`): identity, traits, starting resources, gather / build / research multipliers.
* `FactionData` (extends `Resource`): `faction_id`, `display_name`, `is_player`, `species`, `faction_color`, `home_region_id`.
* `RegionData` (extends `Resource`): `region_id`, globe lat/lon, `is_accessible`, optional `owner_faction_id` (for territory color), grid size and cell size.
* When `EventBus.era_changed` fires for a faction, existing `Building` / `Unit` nodes swap their child mesh/scene using `EraData` without losing grid coordinates or HP.

## 6. Desktop concept rules
* `GameState.world` (`SimWorld`, RefCounted) is the authoritative simulation. `CommandService` is the only way UI or tests issue orders.
* `PrimitiveCatalog` fills era mesh slots with simple primitive meshes at bootstrap so era swaps are visible without art files.
* Only one region (`verdant_basin`) is accessible in the concept. Other pins exist on the globe and show territory ownership but cannot be entered.

## 7. Resources, species, and era-gated reveal
* `ResourceNodeData`: `node_type_id`, `resource_id`, `display_name`, `is_rare`, `starting_amount`, `max_amount`, `gather_per_tick`, `depletion_per_tick`, `regen_per_tick`, `reveal_era` (0 = always visible).
* Common nodes (`timber`, `stone_deposit`, `forage`) are spread across the playable region and start revealed (`reveal_era = 0`). Rare nodes (`iron_vein` at era 2, `coal_seam` at the steam era / index 1) have fixed placements, often near contested borders, but stay hidden per faction until that faction's era index is `>= reveal_era`.
* `SimWorld.can_see_node` / `can_see_resource` is the visibility source of truth. Gather orders, extractor placement, ResourceTick gather/trickle, FactionAI targeting, diorama markers, Tier 1 pin icons, and RTS clicks all respect it. AI never assigns workers to nodes it cannot see.
* Era costs avoid a circular reveal: Bronze / Steamworks costs only common resources (and then reveals coal). Iron / Assembly costs commons + coal (and then reveals iron). Industrial costs commons + iron + coal. Specialized units (`ironclad`, `steamwalker`) also require the rare resources in their cost, and cannot be trained until those resources are revealed.
* Starter species (multipliers live on `SpeciesData`):
  * **Humans** (player, Sunward Compact): balanced, fastest era progression.
  * **Sylvari**: slow expansion; common nodes on owned territory regenerate; defense grows with hold time. Does not regrow rares.
  * **Kraal**: cheap numerous units, faster harvest that also depletes nodes faster, slower eras.
  * **Cogforged**: clockwork → steamworks → assembly → synthetics; high industry; durable constructed units; slow population; can build extractors that boost revealed rare-node yield.
