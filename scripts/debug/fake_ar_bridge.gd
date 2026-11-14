class_name FakeARBridge
extends ARCoreBridge
## Headless stand-in for the ARCore plugin, used by ar_tests to drive the
## calibration flow without a device. Never used by the game itself.

var running: bool = false
## What the centre-of-screen hit test reports.
var surface_found: bool = false
var surface_pose: Transform3D = Transform3D(Basis(), Vector3(0.0, -0.4, -0.7))
var info: Dictionary = {"camera_state": 0, "failure_reason": 0, "frames": 30, "points": 64, "planes": 0, "upward_planes": 0}
var anchors_made: int = 0
var _poses: Dictionary = {}
var _next_id: int = 1


func start(_viewport: Viewport) -> bool:
	running = true
	return true


func stop(_viewport: Viewport) -> void:
	running = false


func is_running() -> bool:
	return running


func pause() -> void:
	pass


func resume() -> void:
	pass


func tracking_status() -> int:
	return XRInterface.XR_NORMAL_TRACKING


func tracking_info() -> Dictionary:
	return info


func horizontal_planes() -> Array:
	if not surface_found:
		return []
	return [{"pose": surface_pose, "polygon": PackedVector2Array([Vector2(-0.3, -0.2), Vector2(0.3, -0.2), Vector2(0.3, 0.2), Vector2(-0.3, 0.2)])}]


func point_cloud(_max_points: int) -> PackedVector3Array:
	return PackedVector3Array([Vector3(0.0, -0.4, -0.6), Vector3(0.1, -0.4, -0.7)])


func hit_test(_normalized_screen: Vector2) -> Dictionary:
	if not surface_found:
		return {"hit": false}
	return {"hit": true, "pose": surface_pose, "kind": "plane"}


func create_anchor_at_screen(_normalized_screen: Vector2) -> Dictionary:
	if not surface_found:
		return {"id": -1}
	var id: int = create_anchor(surface_pose)
	return {"id": id, "pose": surface_pose}


func create_anchor(pose: Transform3D) -> int:
	if int(info.get("camera_state", -1)) != 0:
		return -1
	var id: int = _next_id
	_next_id += 1
	_poses[id] = pose
	anchors_made += 1
	return id


func get_anchor_pose(anchor_id: int) -> Transform3D:
	return _poses.get(anchor_id, Transform3D.IDENTITY) as Transform3D


func get_anchor_tracking_state(anchor_id: int) -> int:
	return 0 if _poses.has(anchor_id) else -1


func remove_anchor(anchor_id: int) -> void:
	_poses.erase(anchor_id)
