class_name LocalAnchorBackend
extends AnchorBackend
## Anchors that never drift: fixed world poses. Used on desktop, headless and
## in tests. Its loopback "cloud" (a process-wide registry) lets tests and a
## future netcode pass exercise host_anchor() / resolve_anchor() without a
## network: an ID hosted by one AnchorService resolves in another.

## cloud_anchor_id (String) -> Transform3D, shared by every instance.
static var _cloud_registry: Dictionary = {}
static var _cloud_counter: int = 0

var cloud_enabled: bool = true
## Pose used by create_anchor_at_screen (no surfaces to hit off-device).
var screen_anchor_pose: Transform3D = Transform3D.IDENTITY
var _poses: Dictionary = {}
var _next_id: int = 1


func create_anchor(pose: Transform3D) -> int:
	var anchor_id: int = _next_id
	_next_id += 1
	_poses[anchor_id] = pose
	return anchor_id


func create_anchor_at_screen(_normalized_screen: Vector2) -> Dictionary:
	var anchor_id: int = create_anchor(screen_anchor_pose)
	return {"id": anchor_id, "pose": screen_anchor_pose}


func get_pose(anchor_id: int) -> Transform3D:
	return _poses.get(anchor_id, Transform3D.IDENTITY) as Transform3D


## Test hook: simulate ARCore refining an anchor's pose.
func set_pose(anchor_id: int, pose: Transform3D) -> void:
	if _poses.has(anchor_id):
		_poses[anchor_id] = pose


func tracking_state(anchor_id: int) -> int:
	return Tracking.TRACKING if _poses.has(anchor_id) else Tracking.UNKNOWN


func remove_anchor(anchor_id: int) -> void:
	_poses.erase(anchor_id)


func supports_cloud() -> bool:
	return cloud_enabled


func host_cloud_anchor(anchor_id: int) -> String:
	if not cloud_enabled or not _poses.has(anchor_id):
		return ""
	_cloud_counter += 1
	var cloud_id: String = "local-%d" % _cloud_counter
	_cloud_registry[cloud_id] = _poses[anchor_id]
	return cloud_id


func resolve_cloud_anchor(cloud_anchor_id: String) -> int:
	if not cloud_enabled or not _cloud_registry.has(cloud_anchor_id):
		return -1
	return create_anchor(_cloud_registry[cloud_anchor_id] as Transform3D)
