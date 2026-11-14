class_name ResourceNodeData
extends Resource
## Data definition for a gatherable node type (timber stand, iron vein, ...).
## Instances live as `.tres` files in `res://data/nodes/types/`.

@export var node_type_id: StringName = &""
@export var display_name: String = ""
@export var resource_id: StringName = &""
## Rare nodes are scarce, sit near contested borders, and gate specialized
## units and later era advances. Common nodes can be regrown by Sylvari.
@export var is_rare: bool = false
## Minimum era_index a faction must have reached before this node is visible
## to them (per-faction). Common nodes use 0 (visible from the start).
## Iron uses 2 (Iron / Assembly); coal uses 1 (Steamworks / Bronze).
@export var reveal_era: int = 0
@export var capacity: int = 200
@export var base_gather: int = 3
## Color used for globe pin icons and diorama markers.
@export var pin_color: Color = Color.WHITE
