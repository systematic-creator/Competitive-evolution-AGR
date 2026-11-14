class_name ARSessionController
extends Node
## World-locked phone-camera AR for the diorama (view layer only).
##
## Scene shape (built by MainDesktop):
##   WorldAnchor (Node3D)      <- AnchorService pose (yaw-only, world space)
##     DioramaPivot (Node3D)   <- DioramaPlacement: magnify, offset, yaw, scale
##       OrbitGlobe, FlatDiorama (all gameplay visuals in diorama-local space)
##   XROrigin3D / XRCamera3D   <- created here in AR mode only
##
## AR mode: ARCore session + camera passthrough, driven by a CalibrationFlow:
## scan (live tracking status, feature points and found surfaces drawn on the
## video) -> a reticle on a surface + "Place board" -> adjust (drag / pinch /
## twist) -> Lock. If no surface turns up, "Place in front of me" anchors the
## board ~0.6 m ahead and "Play without AR" drops to the touch camera, so the
## player is never stuck. The gameplay HUD is hidden and the simulation (ticks
## and win checks) is paused until the board is locked. Locked, touches go to
## gameplay (RtsController) and pinch magnifies if Magnify is on. The phone's
## real distance to the diorama, divided by its scale, picks the zoom tier.
##
## Fallback mode (no ARCore: desktop, headless, unsupported phone): the
## existing DesktopRig camera, an identity anchor and an identity pivot, so
## the concept build behaves exactly as before.

enum Mode { FALLBACK, AR }
enum Phase { SEARCHING, READY, PLACED }

const RETICLE_RADIUS: float = 0.06
## "Place in front of me": metres ahead of and below the phone.
const FRONT_PLACE_DISTANCE: float = 0.6
const FRONT_PLACE_DROP: float = 0.35
## Seconds between diagnostics / surface overlay refreshes.
const DIAG_INTERVAL: float = 0.2
const MAX_OVERLAY_POINTS: int = 400
## Seconds to wait for ARCore to report an initialized session before falling back.
const START_GRACE_SECONDS: float = 6.0

var mode: Mode = Mode.FALLBACK
var phase: Phase = Phase.SEARCHING
var magnify_enabled: bool = false
var fallback_reason: String = ""

var world_anchor: Node3D
var pivot: Node3D
var rig: DesktopRig
var third: ThirdPersonRig
var rts: RtsController
var environment: Environment

var bridge: ARCoreBridge
var anchors: AnchorService
var placement: DioramaPlacement = DioramaPlacement.new()
var gestures: ARGestureTracker = ARGestureTracker.new()
var hud: ARHud
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var reticle: Node3D
var flow: CalibrationFlow = CalibrationFlow.new()
## The gameplay HUD (DesktopHud); hidden while calibrating.
var gameplay_hud: CanvasLayer
## Tests inject a fake bridge here; returns an ARCoreBridge.
var bridge_factory: Callable = Callable()
var tracking_info: Dictionary = {}

var _adjusting: bool = false
var _start_elapsed: float = 0.0
var _saved_background: int = Environment.BG_COLOR
var _awaiting_camera: bool = false
var _camera_denied: bool = false
var _permission_poll: float = 0.0
var _diag_elapsed: float = 0.0
var _overlay: Node3D
var _overlay_points: MultiMeshInstance3D
var _overlay_planes: Node3D


## Pick a mode from what the runtime offers (pure, unit-tested).
static func choose_mode(plugin_present: bool, xr_interface: XRInterface) -> Mode:
	if plugin_present and xr_interface != null:
		return Mode.AR
	return Mode.FALLBACK


## Distance in "diorama metres": what the zoom tiers are tuned for.
static func effective_distance(camera_position: Vector3, pivot_position: Vector3, total_scale: float) -> float:
	return camera_position.distance_to(pivot_position) / maxf(0.0001, total_scale)


## Wire up references, then start AR if possible (else the fallback).
func setup(p_world_anchor: Node3D, p_pivot: Node3D, p_rig: DesktopRig, p_third: ThirdPersonRig, p_rts: RtsController, p_environment: Environment) -> void:
	world_anchor = p_world_anchor
	pivot = p_pivot
	rig = p_rig
	third = p_third
	rts = p_rts
	environment = p_environment
	if ARCoreBridge.plugin_present():
		if not ARCoreBridge.camera_permission_granted():
			# Hold the game in the fallback view until the camera is allowed,
			# then switch to AR (polled in _process; see _poll_camera_permission).
			fallback_reason = "Waiting for camera permission."
			_awaiting_camera = true
			if not get_tree().on_request_permissions_result.is_connected(_on_permission_result):
				get_tree().on_request_permissions_result.connect(_on_permission_result)
			OS.request_permission(ARCoreBridge.CAMERA_PERMISSION)
			_enter_fallback()
			return
		if try_start_ar():
			return
	elif fallback_reason.is_empty():
		fallback_reason = "No AR interface (desktop, headless, or a non-AR build)."
	_enter_fallback()


## Start ARCore and enter AR mode; on failure keep (or enter) the fallback.
func try_start_ar() -> bool:
	bridge = bridge_factory.call() as ARCoreBridge if bridge_factory.is_valid() else ARCoreBridge.new()
	if bridge.start(get_viewport()):
		_enter_ar()
		return true
	fallback_reason = bridge.failure_reason
	push_warning("AR disabled: %s" % fallback_reason)
	bridge = null
	_sync_simulation()
	return false


## The camera was refused: play in the fallback view (keep polling in case
## the player grants it later from a second prompt or the settings).
func _on_permission_result(permission: String, granted: bool) -> void:
	if permission == ARCoreBridge.CAMERA_PERMISSION and not granted and mode == Mode.FALLBACK:
		_camera_denied = true
		fallback_reason = "Camera permission denied."
		_sync_simulation()


func is_ar() -> bool:
	return mode == Mode.AR


func is_placed() -> bool:
	return phase == Phase.PLACED


## True while AR owns touch input (placement, or adjusting while unlocked).
func captures_touch() -> bool:
	return is_ar() and (phase != Phase.PLACED or not placement.locked)


# --- Modes ------------------------------------------------------------------

func _enter_fallback() -> void:
	mode = Mode.FALLBACK
	anchors = AnchorService.new(LocalAnchorBackend.new())
	anchors.place_at_pose(Transform3D.IDENTITY)
	placement = DioramaPlacement.new()
	placement.scale = 1.0
	phase = Phase.PLACED
	if rig != null:
		rig.ar_mode = false
	apply_anchor_pose(Transform3D.IDENTITY)
	if pivot != null:
		pivot.transform = Transform3D.IDENTITY
	if world_anchor != null:
		world_anchor.visible = true
	_sync_simulation()


func _enter_ar() -> void:
	mode = Mode.AR
	phase = Phase.SEARCHING
	anchors = AnchorService.new(ARCoreAnchorBackend.new(bridge))
	anchors.tracking_changed.connect(_on_anchor_tracking_changed)
	placement = DioramaPlacement.new()
	placement.load_from()
	# Keep the saved size / rotation, but every session starts unlocked: the
	# board has to be placed again in this room.
	placement.locked = false
	flow.restart()
	tracking_info = {}
	xr_origin = XROrigin3D.new()
	xr_origin.name = "XROrigin3D"
	add_child(xr_origin)
	xr_camera = XRCamera3D.new()
	xr_camera.name = "XRCamera3D"
	xr_camera.near = 0.01
	xr_camera.far = 50.0
	xr_origin.add_child(xr_camera)
	xr_camera.current = true
	if environment != null:
		_saved_background = environment.background_mode
		# Let the ARCore background renderer's camera image show through.
		environment.background_mode = Environment.BG_CAMERA_FEED
	if rig != null:
		rig.ar_mode = true
		rig.camera.current = false
	if rts != null:
		rts.camera = xr_camera
		rts.touch_gate = captures_touch
	reticle = _make_reticle()
	add_child(reticle)
	reticle.visible = false
	_overlay = _make_overlay()
	add_child(_overlay)
	world_anchor.visible = false
	hud = ARHud.new()
	add_child(hud)
	hud.lock_toggled.connect(set_locked)
	hud.magnify_toggled.connect(func(on: bool) -> void: magnify_enabled = on)
	hud.recenter_pressed.connect(recenter)
	hud.replace_pressed.connect(begin_replace)
	hud.place_pressed.connect(func() -> void: place_at_reticle())
	hud.place_in_front_pressed.connect(func() -> void: place_in_front())
	hud.play_without_ar_pressed.connect(func() -> void: fall_back("Player chose to play without AR."))
	EventBus.unit_possessed.connect(_on_unit_possessed)
	EventBus.unit_released.connect(_on_unit_released)
	hud.apply_flow(flow)
	_sync_simulation()


## Leave AR for the desktop camera (ARCore failed after starting).
func fall_back(reason: String) -> void:
	if mode != Mode.AR:
		return
	fallback_reason = reason
	if anchors != null:
		anchors.clear()
	bridge.stop(get_viewport())
	if xr_origin != null:
		xr_origin.queue_free()
		xr_origin = null
		xr_camera = null
	if reticle != null:
		reticle.queue_free()
		reticle = null
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
		_overlay_points = null
		_overlay_planes = null
	if hud != null:
		hud.queue_free()
		hud = null
	if environment != null:
		environment.background_mode = _saved_background as Environment.BGMode
	if EventBus.unit_possessed.is_connected(_on_unit_possessed):
		EventBus.unit_possessed.disconnect(_on_unit_possessed)
		EventBus.unit_released.disconnect(_on_unit_released)
	if rig != null:
		rig.camera.current = true
	if rts != null:
		rts.camera = rig.camera
		rts.touch_gate = Callable()
	_enter_fallback()
	push_warning("AR disabled: %s" % reason)


# --- Placement / adjustment ---------------------------------------------------

## Place (or re-place) the diorama on the surface under the reticle.
func place_at_reticle() -> bool:
	if not is_ar() or phase == Phase.PLACED:
		return false
	if not anchors.place_at_screen(Vector2(0.5, 0.5)):
		return false
	_after_placed()
	return true


## Fallback when no surface is found: anchor the board ~0.6 m in front of
## and below the phone, level and facing the player.
func place_in_front() -> bool:
	if not is_ar() or phase == Phase.PLACED or xr_camera == null:
		return false
	var pose: Transform3D = front_pose(xr_camera.global_transform)
	var origin_xform: Transform3D = xr_origin.global_transform if xr_origin != null else Transform3D.IDENTITY
	if not anchors.place_at_pose(origin_xform.affine_inverse() * pose):
		if hud != null:
			hud.set_status("Can't place yet. %s" % CalibrationFlow.tracking_message(tracking_info))
		return false
	_after_placed()
	return true


## World pose FRONT_PLACE_DISTANCE ahead of (and FRONT_PLACE_DROP below) a
## camera, level, with -Z pointing away from the player. Pure; unit-tested.
static func front_pose(camera: Transform3D) -> Transform3D:
	var forward: Vector3 = -camera.basis.z
	forward.y = 0.0
	if forward.length() < 0.001:
		forward = -camera.basis.y if absf(camera.basis.z.y) > 0.5 else Vector3.FORWARD
		forward.y = 0.0
		if forward.length() < 0.001:
			forward = Vector3.FORWARD
	forward = forward.normalized()
	var origin: Vector3 = camera.origin + forward * FRONT_PLACE_DISTANCE + Vector3.DOWN * FRONT_PLACE_DROP
	return Transform3D(Basis.looking_at(forward, Vector3.UP), origin)


func _after_placed() -> void:
	phase = Phase.PLACED
	flow.placed()
	if reticle != null:
		reticle.visible = false
	if _overlay != null:
		_overlay.visible = false
	world_anchor.visible = true
	_apply_transforms()
	if hud != null:
		hud.apply_flow(flow)
	EventBus.world_anchor_placed.emit(world_anchor.global_transform)
	_sync_simulation()


func begin_replace() -> void:
	if not is_ar():
		return
	anchors.clear()
	phase = Phase.SEARCHING
	placement.locked = false
	flow.restart()
	world_anchor.visible = false
	if _overlay != null:
		_overlay.visible = true
	if hud != null:
		hud.apply_flow(flow)
	_sync_simulation()


func recenter() -> void:
	placement.recenter()
	placement.save()
	_apply_transforms()


func set_locked(locked: bool) -> void:
	if is_ar() and phase != Phase.PLACED:
		return
	placement.locked = locked
	placement.save()
	gestures.reset()
	flow.set_locked(locked)
	if hud != null:
		hud.apply_flow(flow)
	_sync_simulation()


## The simulation (ticks + win checks) runs only once the board is locked in
## AR, or in the fallback view (unless we are still waiting for the camera).
## Pausing only shifts wall-clock time; the tick sequence stays deterministic.
func should_run_simulation() -> bool:
	if mode == Mode.AR:
		return flow.should_run_simulation()
	return not _awaiting_camera or _camera_denied


func _sync_simulation() -> void:
	var run: bool = should_run_simulation()
	if run and not GameState.is_simulation_running:
		GameState.start_simulation()
	elif not run and GameState.is_simulation_running:
		GameState.stop_simulation()
	if gameplay_hud != null:
		gameplay_hud.visible = mode == Mode.FALLBACK or flow.step == CalibrationFlow.Step.LOCKED


## Put the world anchor at `anchor_pose` (Godot world space, made upright).
func apply_anchor_pose(anchor_pose: Transform3D) -> void:
	if world_anchor == null:
		return
	var origin_xform: Transform3D = xr_origin.global_transform if xr_origin != null else Transform3D.IDENTITY
	world_anchor.global_transform = origin_xform * AnchorService.upright(anchor_pose)


## Re-apply the anchor pose and the placement to the scene.
func _apply_transforms() -> void:
	apply_anchor_pose(anchors.pose)
	if pivot != null:
		pivot.transform = placement.pivot_transform()


# --- Per frame ----------------------------------------------------------------

func _process(delta: float) -> void:
	if mode != Mode.AR:
		if _awaiting_camera:
			_poll_camera_permission(delta)
		return
	if not bridge.is_running():
		_start_elapsed += delta
		if _start_elapsed > START_GRACE_SECONDS:
			fall_back("ARCore session did not start.")
		return
	_start_elapsed = 0.0
	if phase != Phase.PLACED:
		_diag_elapsed += delta
		var refresh: bool = _diag_elapsed >= DIAG_INTERVAL
		if refresh:
			_diag_elapsed = 0.0
			tracking_info = bridge.tracking_info()
		var found: bool = _update_reticle()
		flow.update(delta, tracking_info, found)
		if refresh:
			_update_overlay()
		if hud != null:
			hud.apply_flow(flow)
		return
	anchors.poll()
	_apply_transforms()
	_drive_tier()


func _poll_camera_permission(delta: float) -> void:
	_permission_poll += delta
	if _permission_poll < 0.5:
		return
	_permission_poll = 0.0
	if not ARCoreBridge.camera_permission_granted():
		return
	_awaiting_camera = false
	_camera_denied = false
	try_start_ar()


func _update_reticle() -> bool:
	var hit: Dictionary = bridge.hit_test(Vector2(0.5, 0.5))
	var found: bool = bool(hit.get("hit", false))
	reticle.visible = found
	if found:
		var origin_xform: Transform3D = xr_origin.global_transform
		reticle.global_transform = origin_xform * AnchorService.upright(hit["pose"] as Transform3D)
		phase = Phase.READY
	else:
		phase = Phase.SEARCHING
	return found


## Draw what ARCore sees: feature points and found surfaces, so the player
## can tell scanning is making progress.
func _update_overlay() -> void:
	if _overlay == null:
		return
	var origin_xform: Transform3D = xr_origin.global_transform if xr_origin != null else Transform3D.IDENTITY
	_overlay.global_transform = origin_xform
	var points: PackedVector3Array = bridge.point_cloud(MAX_OVERLAY_POINTS)
	var multimesh: MultiMesh = _overlay_points.multimesh
	multimesh.instance_count = points.size()
	for i: int in points.size():
		multimesh.set_instance_transform(i, Transform3D(Basis(), points[i]))
	for child: Node in _overlay_planes.get_children():
		child.queue_free()
	for entry: Variant in bridge.horizontal_planes():
		var plane: Dictionary = entry as Dictionary
		var mesh: ArrayMesh = plane_mesh(plane.get("polygon", PackedVector2Array()) as PackedVector2Array)
		if mesh == null:
			continue
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = _surface_material()
		instance.transform = plane.get("pose", Transform3D.IDENTITY) as Transform3D
		_overlay_planes.add_child(instance)


## Triangle fan for a plane polygon in plane-local (x, z). Null if degenerate.
static func plane_mesh(polygon: PackedVector2Array) -> ArrayMesh:
	if polygon.size() < 3:
		return null
	var vertices := PackedVector3Array()
	var center := Vector2.ZERO
	for p: Vector2 in polygon:
		center += p
	center /= float(polygon.size())
	for i: int in polygon.size():
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		vertices.append(Vector3(center.x, 0.002, center.y))
		vertices.append(Vector3(b.x, 0.002, b.y))
		vertices.append(Vector3(a.x, 0.002, a.y))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


var _surface_mat: StandardMaterial3D
func _surface_material() -> StandardMaterial3D:
	if _surface_mat == null:
		_surface_mat = StandardMaterial3D.new()
		_surface_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_surface_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_surface_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_surface_mat.albedo_color = Color(0.35, 0.95, 1.0, 0.28)
	return _surface_mat


func _make_overlay() -> Node3D:
	var root := Node3D.new()
	root.name = "ScanOverlay"
	_overlay_points = MultiMeshInstance3D.new()
	_overlay_points.name = "FeaturePoints"
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var dot := SphereMesh.new()
	dot.radius = 0.004
	dot.height = 0.008
	dot.radial_segments = 6
	dot.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.92, 0.35)
	dot.material = material
	multimesh.mesh = dot
	_overlay_points.multimesh = multimesh
	root.add_child(_overlay_points)
	_overlay_planes = Node3D.new()
	_overlay_planes.name = "Surfaces"
	root.add_child(_overlay_planes)
	return root


## Android lifecycle -> ARCore session (the plugin does not hook it itself).
func _notification(what: int) -> void:
	if bridge == null or mode != Mode.AR:
		return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		bridge.pause()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		bridge.resume()


## Walk closer = zoom in: tiers follow the phone's real distance to the diorama.
func _drive_tier() -> void:
	if GameState.current_zoom_tier == GameState.ZoomTier.THIRD_PERSON or xr_camera == null:
		return
	var distance: float = effective_distance(xr_camera.global_position, pivot.global_position, placement.total_scale())
	GameState.current_zoom_tier = ZoomTierController.tier_for_distance(distance)
	EventBus.zoom_transition_progress.emit(ZoomTierController.transition_progress(distance))


# --- Input --------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.AR or not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if GameState.current_zoom_tier == GameState.ZoomTier.THIRD_PERSON:
		return
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed and hud != null:
		if hud.is_over_ui((event as InputEventScreenTouch).position):
			return
	var gesture: Dictionary = gestures.handle(event)
	if phase != Phase.PLACED:
		if gesture.get("kind", &"") == &"tap" and phase == Phase.READY:
			place_at_reticle()
		return
	if placement.locked:
		# Gameplay owns taps/drags (RtsController); pinch magnifies if enabled.
		if magnify_enabled and gesture.get("kind", &"") == &"pinch":
			placement.magnify_by(float(gesture["scale"]))
		return
	match gesture.get("kind", &"") as StringName:
		&"drag":
			var before: Variant = _anchor_point(gesture["from"] as Vector2)
			var after: Variant = _anchor_point(gesture["to"] as Vector2)
			if before != null and after != null:
				_adjusting = placement.drag((after as Vector3) - (before as Vector3))
		&"pinch":
			placement.pinch(float(gesture["scale"]))
			# Screen clockwise twist turns the table clockwise seen from above.
			placement.twist(-float(gesture["twist"]))
			_adjusting = true
	if _adjusting and gestures.touch_count() == 0:
		_adjusting = false
		placement.save()


## Screen point -> point on the anchor's ground plane, in anchor space.
func _anchor_point(screen: Vector2) -> Variant:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or world_anchor == null:
		return null
	var ground := Plane(world_anchor.global_transform.basis.y.normalized(), world_anchor.global_position)
	var hit: Variant = ground.intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if hit == null:
		return null
	return world_anchor.to_local(hit as Vector3)


# --- Tier 4 hand-off ----------------------------------------------------------

## Third person drops AR tracking: render the virtual chase camera instead.
func _on_unit_possessed(_unit: Node3D) -> void:
	get_viewport().use_xr = false
	if environment != null:
		environment.background_mode = Environment.BG_COLOR
	if third != null and third.spring != null:
		third.spring.spring_length = 0.18 * placement.total_scale()


func _on_unit_released() -> void:
	if mode != Mode.AR:
		return
	get_viewport().use_xr = true
	if environment != null:
		environment.background_mode = Environment.BG_CAMERA_FEED
	if third != null and third.spring != null:
		third.spring.spring_length = 0.18
	xr_camera.current = true
	rts.camera = xr_camera


func _on_anchor_tracking_changed(state: int) -> void:
	if hud == null or phase != Phase.PLACED:
		return
	if state == AnchorBackend.Tracking.TRACKING:
		hud.apply_flow(flow)
	else:
		hud.set_status("Tracking lost. Point the phone back at the board and hold still.")


func _make_reticle() -> Node3D:
	var root := Node3D.new()
	root.name = "PlacementReticle"
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RETICLE_RADIUS * 0.82
	torus.outer_radius = RETICLE_RADIUS
	torus.rings = 32
	torus.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.35, 0.95, 1.0, 0.9)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	torus.material = material
	ring.mesh = torus
	ring.scale = Vector3(1.0, 0.15, 1.0)
	root.add_child(ring)
	return root
