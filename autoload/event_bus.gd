extends Node
## Global signal hub (autoload: `EventBus`).
##
## Simulation systems emit upward through these signals; visual nodes and UI
## connect to them instead of polling. This script holds no state and no logic.
##
## Zoom tiers are passed as `int` values of `GameState.ZoomTier` so this script
## has no parse-time dependency on other autoloads.

# --- Eras -------------------------------------------------------------------

## A faction advanced (or regressed) to a new era. Building/unit visuals swap
## their meshes from `new_era` while keeping grid coordinates and HP.
@warning_ignore("unused_signal")
signal era_changed(faction_id: StringName, new_era: EraData, previous_era: EraData)

# --- Camera / zoom ----------------------------------------------------------

## The active zoom tier changed. Values are `GameState.ZoomTier`.
@warning_ignore("unused_signal")
signal zoom_tier_changed(new_tier: int, previous_tier: int)

## Normalized progress (0.0 -> 1.0) of the ORBIT -> REGION crossfade.
@warning_ignore("unused_signal")
signal zoom_transition_progress(progress: float)

# --- World / selection ------------------------------------------------------

## A region pin on the orbit globe was tapped and locked on.
@warning_ignore("unused_signal")
signal region_selected(region_id: StringName)

## The AR world anchor was placed (or re-placed) in physical space.
@warning_ignore("unused_signal")
signal world_anchor_placed(anchor_transform: Transform3D)

# --- Simulation -------------------------------------------------------------

## Fired once per global simulation tick by `GameState`.
@warning_ignore("unused_signal")
signal simulation_ticked(tick: int)

## A faction joined the simulation.
@warning_ignore("unused_signal")
signal faction_registered(faction_id: StringName, species: SpeciesData)

## A faction's stockpile of a resource changed.
@warning_ignore("unused_signal")
signal faction_resource_changed(faction_id: StringName, resource_id: StringName, amount: int)

# --- Third-person -----------------------------------------------------------

## The player possessed a unit (enter Tier 4). `unit` is the CharacterBody3D.
@warning_ignore("unused_signal")
signal unit_possessed(unit: Node3D)

## The player released the possessed unit (return to RTS tier).
@warning_ignore("unused_signal")
signal unit_released()
