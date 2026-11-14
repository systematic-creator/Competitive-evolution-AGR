class_name AnchorService
extends RefCounted
## Owns the one world anchor the diorama hangs from.
##
## Multiplayer-ready stub: `host_anchor()` publishes the anchor as a Cloud
## Anchor and stores its `cloud_anchor_id`; `resolve_anchor(id)` recreates the
## same physical anchor on another phone. Each phone then renders the shared
## diorama from its own position. Everything gameplay-related (units,
## structures, orders) is in diorama-local space, so only this anchor (plus the
## placement adjustment) has to be shared. No networking happens here yet.

signal anchor_placed(anchor_id: int, pose: Transform3D)
signal anchor_cleared()
signal tracking_changed(state: int)
signal cloud_anchor_hosted(cloud_anchor_id: String)
signal cloud_anchor_resolved(cloud_anchor_id: String, pose: Transform3D)
signal cloud_anchor_failed(reason: String)

enum CloudState { NONE, HOSTING, HOSTED, RESOLVING, RESOLVED, FAILED }

var backend: AnchorBackend
var anchor_id: int = -1
## Cloud Anchor ID shared with other players by the (future) netcode pass.
var cloud_anchor_id: String = ""
var cloud_state: CloudState = CloudState.NONE
var tracking: int = AnchorBackend.Tracking.UNKNOWN
## Last polled anchor pose (Godot world space), kept upright (yaw only).
var pose: Transform3D = Transform3D.IDENTITY


func _init(p_backend: AnchorBackend) -> void:
	backend = p_backend


func has_anchor() -> bool:
	return anchor_id >= 0


## Anchor on the detected surface under a normalized screen point (AR placement).
func place_at_screen(normalized_screen: Vector2) -> bool:
	var result: Dictionary = backend.create_anchor_at_screen(normalized_screen)
	var new_id: int = int(result.get("id", -1))
	if new_id < 0:
		return false
	_adopt(new_id)
	return true


func place_at_pose(world_pose: Transform3D) -> bool:
	var new_id: int = backend.create_anchor(world_pose)
	if new_id < 0:
		return false
	_adopt(new_id)
	return true


func clear() -> void:
	if not has_anchor():
		return
	backend.remove_anchor(anchor_id)
	anchor_id = -1
	cloud_anchor_id = ""
	cloud_state = CloudState.NONE
	tracking = AnchorBackend.Tracking.UNKNOWN
	anchor_cleared.emit()


## Refresh the anchor pose and tracking state (call once per frame).
func poll() -> Transform3D:
	if not has_anchor():
		return pose
	var state: int = backend.tracking_state(anchor_id)
	if state != tracking:
		tracking = state
		tracking_changed.emit(state)
	if state == AnchorBackend.Tracking.TRACKING:
		pose = upright(backend.get_pose(anchor_id))
	return pose


## Publish the current anchor as a Cloud Anchor (stub until netcode).
func host_anchor() -> bool:
	if not has_anchor():
		return _cloud_fail("No anchor to host; place the diorama first.")
	if not backend.supports_cloud():
		return _cloud_fail("Cloud Anchors are not available in this build yet.")
	cloud_state = CloudState.HOSTING
	var hosted: String = backend.host_cloud_anchor(anchor_id)
	if hosted.is_empty():
		return _cloud_fail("Hosting the Cloud Anchor failed.")
	cloud_anchor_id = hosted
	cloud_state = CloudState.HOSTED
	cloud_anchor_hosted.emit(hosted)
	return true


## Recreate the anchor another player hosted (stub until netcode).
func resolve_anchor(p_cloud_anchor_id: String) -> bool:
	if p_cloud_anchor_id.is_empty():
		return _cloud_fail("Empty Cloud Anchor ID.")
	if not backend.supports_cloud():
		return _cloud_fail("Cloud Anchors are not available in this build yet.")
	cloud_state = CloudState.RESOLVING
	var resolved_id: int = backend.resolve_cloud_anchor(p_cloud_anchor_id)
	if resolved_id < 0:
		return _cloud_fail("Could not resolve Cloud Anchor %s." % p_cloud_anchor_id)
	if has_anchor():
		backend.remove_anchor(anchor_id)
	_adopt(resolved_id)
	cloud_anchor_id = p_cloud_anchor_id
	cloud_state = CloudState.RESOLVED
	cloud_anchor_resolved.emit(p_cloud_anchor_id, pose)
	return true


## What a netcode pass sends to other players: the shared anchor plus the
## anchor-relative placement. Never contains unit or structure positions.
func share_payload(placement: DioramaPlacement) -> Dictionary:
	return {
		"cloud_anchor_id": cloud_anchor_id,
		"placement": placement.to_dict() if placement != null else {},
	}


## Keep only the yaw of a pose so the diorama always sits level on the table.
static func upright(world_pose: Transform3D) -> Transform3D:
	var forward: Vector3 = -world_pose.basis.z
	forward.y = 0.0
	var yaw: float = 0.0
	if forward.length() > 0.0001:
		yaw = atan2(-forward.x, -forward.z)
	return Transform3D(Basis(Vector3.UP, yaw), world_pose.origin)


func _adopt(new_id: int) -> void:
	if has_anchor() and anchor_id != new_id:
		backend.remove_anchor(anchor_id)
	anchor_id = new_id
	cloud_anchor_id = ""
	cloud_state = CloudState.NONE
	tracking = backend.tracking_state(new_id)
	pose = upright(backend.get_pose(new_id))
	anchor_placed.emit(new_id, pose)


func _cloud_fail(reason: String) -> bool:
	cloud_state = CloudState.FAILED
	cloud_anchor_failed.emit(reason)
	return false
