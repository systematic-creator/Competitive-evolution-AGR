class_name ARCoreAnchorBackend
extends AnchorBackend
## ARCore anchors via ARCoreBridge. Cloud Anchors are not wired yet: they need
## ARCore API authorization plus ArSession_hostCloudAnchorAsync /
## ArSession_resolveCloudAnchorAsync in the plugin, which the netcode pass adds.

var bridge: ARCoreBridge


func _init(p_bridge: ARCoreBridge) -> void:
	bridge = p_bridge


func create_anchor(pose: Transform3D) -> int:
	return bridge.create_anchor(pose)


func create_anchor_at_screen(normalized_screen: Vector2) -> Dictionary:
	return bridge.create_anchor_at_screen(normalized_screen)


func get_pose(anchor_id: int) -> Transform3D:
	return bridge.get_anchor_pose(anchor_id)


func tracking_state(anchor_id: int) -> int:
	return bridge.get_anchor_tracking_state(anchor_id)


func remove_anchor(anchor_id: int) -> void:
	bridge.remove_anchor(anchor_id)
