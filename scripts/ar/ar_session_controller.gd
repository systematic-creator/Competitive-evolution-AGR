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
## AR mode: ARCore session + camera passthrough. A reticle tracks the plane
## under the screen centre; a tap anchors the diorama there. Unlocked, one
## finger drags it, pinch scales, twist rotates. Locked, touches go to
## gameplay (RtsController) and pinch magnifies if Magnify is on. The phone's
## real distance to the diorama, divided by its scale, picks the zoom tier.
##
## Fallback mode (no ARCore: desktop, headless, unsupported phone): the
## existing DesktopRig camera, an identity anchor and an identity pivot, so
## the concept build behaves exactly as before.

enum Mode { FALLBACK, AR }
enum Phase { SEARCHING, READY, PLACED }

const RETICLE_RADIUS: float = 0.06
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

var _adjusting: bool = false
var _start_elapsed: float = 0.0
var _saved_background: int = Environment.BG_COLOR


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
		bridge = ARCoreBridge.new()
		if bridge.start(get_viewport()):
			_enter_ar()
			return
		fallback_reason = bridge.failure_reason
	elif fallback_reason.is_empty():
		fallback_reason = "No AR interface (desktop, headless, or a non-AR build)."
	_enter_fallback()


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


func _enter_ar() -> void:
	mode = Mode.AR
	phase = Phase.SEARCHING
	anchors = AnchorService.new(ARCoreAnchorBackend.new(bridge))
	anchors.tracking_changed.connect(_on_anchor_tracking_changed)
	placement = DioramaPlacement.new()
	placement.load_from()
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
	world_anchor.visible = false
	hud = ARHud.new()
	add_child(hud)
	hud.lock_toggled.connect(set_locked)
	hud.magnify_toggled.connect(func(on: bool) -> void: magnify_enabled = on)
	hud.recenter_pressed.connect(recenter)
	hud.replace_pressed.connect(begin_replace)
	hud.set_locked(placement.locked)
	EventBus.unit_possessed.connect(_on_unit_possessed)
	EventBus.unit_released.connect(_on_unit_released)
	hud.set_status("Move your phone slowly to find a table or floor.")


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

## Place (or re-place) the diorama on the plane under the reticle.
func place_at_reticle() -> bool:
	if not anchors.place_at_screen(Vector2(0.5, 0.5)):
		return false
	phase = Phase.PLACED
	reticle.visible = false
	world_anchor.visible = true
	_apply_transforms()
	if hud != null:
		hud.set_placed(true)
		hud.set_locked(placement.locked)
		hud.set_status(_placed_hint())
	EventBus.world_anchor_placed.emit(world_anchor.global_transform)
	return true


func begin_replace() -> void:
	if not is_ar():
		return
	anchors.clear()
	phase = Phase.SEARCHING
	world_anchor.visible = false
	if hud != null:
		hud.set_placed(false)
		hud.set_status("Point at a surface and tap to place the diorama.")


func recenter() -> void:
	placement.recenter()
	placement.save()
	_apply_transforms()


func set_locked(locked: bool) -> void:
	placement.locked = locked
	placement.save()
	gestures.reset()
	if hud != null:
		hud.set_locked(locked)
		hud.set_status(_placed_hint())


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
		return
	if not bridge.is_running():
		_start_elapsed += delta
		if _start_elapsed > START_GRACE_SECONDS:
			fall_back("ARCore session did not start.")
		return
	_start_elapsed = 0.0
	if phase != Phase.PLACED:
		_update_reticle()
		return
	anchors.poll()
	_apply_transforms()
	_drive_tier()


func _update_reticle() -> void:
	var hit: Dictionary = bridge.hit_test(Vector2(0.5, 0.5))
	var found: bool = bool(hit.get("hit", false))
	reticle.visible = found
	if found:
		var origin_xform: Transform3D = xr_origin.global_transform
		reticle.global_transform = origin_xform * AnchorService.upright(hit["pose"] as Transform3D)
		phase = Phase.READY
		hud.set_status("Tap to place the diorama here.")
	else:
		phase = Phase.SEARCHING
		hud.set_status("Move your phone slowly to find a table or floor.")


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
		hud.set_status(_placed_hint())
	else:
		hud.set_status("Tracking lost. Hold still and point at the table.")


func _placed_hint() -> String:
	if placement.locked:
		return "Locked. Walk closer to zoom in; tap units to play."
	return "Drag to move, pinch to scale, twist to rotate. Lock when done."


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
