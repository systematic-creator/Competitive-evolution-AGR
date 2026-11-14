class_name AnchorBackend
extends RefCounted
## Where anchors live. `ARCoreAnchorBackend` on an AR device;
## `LocalAnchorBackend` on desktop, headless and in tests.
## Poses are Godot world-space transforms.

enum Tracking { TRACKING = 0, PAUSED = 1, STOPPED = 2, UNKNOWN = -1 }


func create_anchor(_pose: Transform3D) -> int:
	return -1


## Anchor on the surface under a normalized screen point.
## Returns {"id": int, "pose": Transform3D}; id -1 when nothing was hit.
func create_anchor_at_screen(_normalized_screen: Vector2) -> Dictionary:
	return {"id": -1}


func get_pose(_anchor_id: int) -> Transform3D:
	return Transform3D.IDENTITY


func tracking_state(_anchor_id: int) -> int:
	return Tracking.UNKNOWN


func remove_anchor(_anchor_id: int) -> void:
	pass


## Cloud Anchors (shared multiplayer anchor). Not wired to a real service yet.
func supports_cloud() -> bool:
	return false


## Returns a Cloud Anchor ID, or "" on failure.
func host_cloud_anchor(_anchor_id: int) -> String:
	return ""


## Returns a new local anchor id for `cloud_anchor_id`, or -1 on failure.
func resolve_cloud_anchor(_cloud_anchor_id: String) -> int:
	return -1
