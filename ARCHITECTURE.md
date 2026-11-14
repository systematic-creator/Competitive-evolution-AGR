# Project Architecture: Competitive Evolution AGR (Godot 4.x)

## 1. Engine & Target Specs
* **Engine:** Godot 4.4.1+ (4.4 is required by the ARCore plugin's camera passthrough: `CameraFeed.set_external()`; Forward+ or Mobile Renderer). The desktop concept build uses the Compatibility renderer when captured in CI (`--rendering-method gl_compatibility`).
* **Language:** Strictly typed GDScript 2.0 (`class_name`, static typing on all variables/functions)
* **AR Backend (Android):** the GodotVR `godot_arcore` GDExtension plugin, patched with horizontal-plane hit tests and ARCore anchors (`tools/arcore_plugin/`), shipped in a Gradle build. (The OpenXR Vendors plugin targets headsets, not phone AR, so **OpenXR stays disabled**.) iOS/ARKit is not covered.
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
    ├── ar/                   # ARSessionController, AnchorService, DioramaPlacement, ARCoreBridge, gestures, ARHud
    ├── camera/               # ZoomTierController, DesktopRig, ThirdPersonRig
    ├── desktop/              # MainDesktop, RtsController, SkirmishPossessionController
    ├── entities/             # BuildingView, UnitView
    ├── simulation/           # SimWorld, CommandService, FactionAI, ResourceTick, SkirmishCombat, ...
    ├── ui/                   # DesktopHud, SkirmishTouchControls, VirtualJoystick
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

## 8. Hex claims, the escalation ladder, and skirmishes
* `HexGrid` (axial `q, r`, flat-top) is the sim-side source of truth for territory, borders, and resource areas. The square cell grid is still used to place buildings.
* **Structures claim, units occupy.** Town centers, outposts, extractors, and other constructed buildings radiate claims (see `SimCatalog.building_territory_radius`). Units occupy the hex they stand in: they provide presence, can block an enemy structure from claiming that hex, and are required to start a skirmish. Occupation never grants yield.
* Each rare node covers a radius-1 cluster (7 hexes). Yield is split by the share of *claimed* hexes. Full control (every cluster hex claimed by one faction) grants the whole yield. Destroying or capturing the radiating structure releases its claims.
* Escalation on contested rares is a ladder, not instant war:
  1. **Borders / soft claim:** a node whose center hex lies in a faction's structure territory is soft-claimed.
  2. **Outposts / hard claim:** an outpost on or near a visible rare hard-claims it and extends borders (radius 2).
  3. **Skirmishes:** limited squad fights over a specific hex. The player may auto-battle (resolved by the sim) or fight it in Tier 4 possession (section 10). A won skirmish on a structure's hex captures that structure and transfers its claims.
* FactionAI picks the next step with `node_value × personality`: Kraal aggressive, Sylvari defensive, Cogforged methodical.
* The faint hex overlay (borders from hex ownership) is shown only in Tier 3 build/claim mode.

## 9. Win conditions, species eras, and determinism
* `WinConditionData` lives in `data/win_conditions/`. The pool is Complete Domination (hold 60% of all claimed hexes for 4 ticks), Unbridgeable Superiority (era lead + 1.5x economy over every living rival for 4 ticks), and Utter Destruction (no remaining rival units or structures).
* Each species lists the subset it may pursue. **Humans (balanced / player) may use all three.** Kraal: destruction + domination. Sylvari: domination + superiority. Cogforged: superiority + destruction. EventBus emits `victory_progress` and `victory_achieved`; the desktop HUD shows the player's progress.
* Each species has its own `EraData` track (Humans: Stone–Industrial; Sylvari: Roots–Elderwood; Kraal: Brood–Empire; Cogforged: Clockwork–Synthetics). A shared **world era** advances every 24 ticks and is a soft cap: a faction may be one era ahead at normal cost; each extra era above that multiplies advance costs by 2 (not a hard block).
* Multiplayer readiness: `SimWorld` owns a seeded `RandomNumberGenerator`. Ticks are fixed-step. All orders go through `CommandService` as tick-stamped dictionaries in `command_log`, which can be replayed. `state_hash()` is the determinism check.

## 10. Tier 4 skirmish possession
* **Flow:** `start_skirmish(..., auto_battle = false)` emits `skirmish_possession_requested`. `SkirmishPossessionController` (view side) answers for the player with `CommandService.possess_skirmish_unit`, choosing a member of the capped attacking squad (the RTS selection if it is in the squad). With nobody to possess, or while another fight is live, it falls back to `resolve_skirmish_auto`.
* **Sim:** `SkirmishCombat` (RefCounted, no RNG) holds the squads, the possessed unit, a stationary guard for a defending structure, and an arena (the contested hex plus its ring). `SimWorld.step_combat()` advances every live fight by one fixed combat step (0.1 s). The possessed unit moves only along the steered sector and strikes only when an attack is queued (1.5x damage, cooldown). Every other combatant follows the same deterministic rules. A fight ends when one side is gone, or at 600 steps by remaining strength (ties go to the defender).
* **Clock:** the strategic tick is held while a fight is live (`GameState` runs combat steps instead). `SimWorld.step()` fights out any live skirmish before advancing, so `(tick, combat_step)` totally orders events. Commands are stamped with both, and `CommandService.replay(log, final_tick, final_combat_step)` reproduces a possession fight exactly.
* **Orders:** `possess_skirmish_unit`, `steer_possessed` (16 quantized sectors, sent only on change), `possessed_attack`, `resolve_skirmish_possessed` (after `skirmish_combat_finished`) and `resolve_skirmish_auto` (fallback at any time). The controller defers its reactions to sim signals so orders land between combat steps.
* **Views:** `UnitView` follows `SimUnit.position` / `facing` while `in_combat` (navigation stands down). `ThirdPersonRig` (SpringArm3D) excludes the possessed body from boom collision, and its yaw is driven by the controller so movement is camera-relative. `SkirmishTouchControls` provides the `VirtualJoystick`, Attack and Auto-resolve buttons; desktop uses WASD, F / J, Q / E and Esc.
* **Signals:** `skirmish_possession_started`, `skirmish_combat_stepped`, `skirmish_unit_damaged`, `skirmish_combat_finished`, `skirmish_possession_ended`, `unit_killed`.

## 11. World-locked phone AR (Android)
* **Hierarchy:** `WorldAnchor` (anchor pose, yaw only) → `DioramaPivot` (player placement) → `OrbitGlobe` + `FlatDiorama`. `XROrigin3D` / `XRCamera3D` are created next to it in AR mode only.
* **Diorama-local space is the contract.** `SimUnit` / `SimBuilding` / node positions are diorama-local. Views set local `position` and never write back to the sim (`UnitView` is a pure follower; `view_attached` is no longer used). `RtsController` converts screen hits into diorama-local coordinates (`to_diorama_local`, ground plane = the diorama's local y = 0) before calling `CommandService`. Anchor pose, scale and magnify therefore never reach the simulation.
* **Modes:** `ARSessionController.setup()` starts AR through `ARCoreBridge` when the plugin singleton and `ARCoreInterface` exist and the session starts. Otherwise (desktop, headless, the plain APK, unsupported phones, camera permission denied, or ARCore not starting within 6 s) it keeps the `DesktopRig` camera with an identity anchor and pivot, so the concept build is unchanged.
* **Placement:** a reticle follows the nearest tracked upward-facing plane under the screen centre; a tap anchors the diorama there through `AnchorService.place_at_screen()` (an ARCore anchor attached to the plane). The anchor pose is polled every frame and kept upright.
* **Lock / adjust:** unlocked, one-finger drag moves the diorama on the anchor plane, pinch scales it and twist rotates it. Locked, it is immovable and touches go to gameplay (`RtsController.touch_gate`). Offset, yaw, scale and the lock state persist in `user://ar_placement.cfg` (anchor-relative).
* **Viewing:** the phone is the camera. The zoom tier comes from `distance(camera, pivot) / (scale × magnify)` against the existing thresholds. **Magnify** (pinch while locked with Magnify on) scales about the anchor without moving it. **Recenter** returns to the anchor and drops magnify; **Re-place** removes the anchor and starts placement again. Tier 4 turns XR rendering off and uses the third-person chase camera, then restores the AR camera on release.
* **Multiplayer seam:** `AnchorService.host_anchor()` / `resolve_anchor(id)` and the `cloud_anchor_id` field form the hand-off for netcode. `share_payload()` is the Cloud Anchor ID plus the anchor-relative placement, with no unit or structure positions. `LocalAnchorBackend` provides an in-process loopback "cloud" for tests. The ARCore backend reports Cloud Anchors as not yet available (they need ARCore API authorization plus the async host/resolve calls in the plugin).

