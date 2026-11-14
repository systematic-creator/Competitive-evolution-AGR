extends Node
## Headless tests for the AR layer (no device, no ARCore).
## Run: godot --headless --path . res://scenes/debug/ar_tests.tscn

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_mode_selection()
	await _test_fallback_camera_loads()
	await _test_diorama_local_invariance()
	_test_anchor_service()
	_test_cloud_anchor_stub()
	_test_placement()
	_test_gestures()
	_test_effective_distance_tiers()
	_test_calibration_flow()
	_test_front_pose_and_surface_mesh()
	_test_no_win_at_start()
	await _test_ar_calibration_controller()
	GameState.reset()
	print("%d passed, %d failed" % [_passed, _failed])
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1 if _failed > 0 else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("PASS  %s" % label)
	else:
		_failed += 1
		print("FAIL  %s" % label)
		push_error("AR test failed: %s" % label)


func _near(a: Vector3, b: Vector3, eps: float = 0.0005) -> bool:
	return a.distance_to(b) <= eps


func _xform_near(a: Transform3D, b: Transform3D, eps: float = 0.0005) -> bool:
	return (
		_near(a.origin, b.origin, eps)
		and _near(a.basis.x, b.basis.x, eps)
		and _near(a.basis.y, b.basis.y, eps)
		and _near(a.basis.z, b.basis.z, eps)
	)


# --- Fallback -----------------------------------------------------------------

func _test_mode_selection() -> void:
	_check("no ARCore XR interface is registered headless", XRServer.find_interface(ARCoreBridge.INTERFACE_NAME) == null)
	_check("ARCore plugin is absent headless", not ARCoreBridge.plugin_present())
	_check("camera permission counts as granted off Android", ARCoreBridge.camera_permission_granted())
	_check("no plugin and no interface selects the fallback", (
		ARSessionController.choose_mode(false, null) == ARSessionController.Mode.FALLBACK
	))
	_check("plugin without an XR interface still selects the fallback", (
		ARSessionController.choose_mode(true, null) == ARSessionController.Mode.FALLBACK
	))
	_check("plugin plus an XR interface selects AR", (
		ARSessionController.choose_mode(true, XRInterfaceExtension.new()) == ARSessionController.Mode.AR
	))
	var bridge := ARCoreBridge.new()
	_check("ARCoreBridge.start refuses cleanly without the plugin", (
		not bridge.start(get_viewport()) and not bridge.failure_reason.is_empty() and not get_viewport().use_xr
	))


func _load_main() -> Node:
	GameState.reset()
	var main: Node = (load("res://scenes/main_desktop.tscn") as PackedScene).instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	return main


func _test_fallback_camera_loads() -> void:
	var main: Node = await _load_main()
	var ar: ARSessionController = main.get("ar") as ARSessionController
	var rig: DesktopRig = main.get("rig") as DesktopRig
	var rts: RtsController = main.get("rts") as RtsController
	_check("fallback: main scene creates an AR session controller", ar != null)
	_check("fallback: controller is in FALLBACK mode with a reason", (
		ar.mode == ARSessionController.Mode.FALLBACK and not ar.fallback_reason.is_empty()
	))
	_check("fallback: the desktop rig camera is the current camera", (
		rig.camera.current and get_viewport().get_camera_3d() == rig.camera and not rig.ar_mode
	))
	_check("fallback: viewport does not render XR", not get_viewport().use_xr)
	_check("fallback: no XROrigin3D / XRCamera3D is created", (
		main.find_children("*", "XROrigin3D", true, false).is_empty()
		and main.find_children("*", "XRCamera3D", true, false).is_empty()
	))
	_check("fallback: gameplay orders use the desktop camera", rts.camera == rig.camera)
	_check("fallback: AR never captures touch", not ar.captures_touch())
	var anchor: Node3D = main.get("_anchor") as Node3D
	var pivot: Node3D = main.get("_pivot") as Node3D
	_check("fallback: anchor and pivot are identity (desktop unchanged)", (
		_xform_near(anchor.global_transform, Transform3D.IDENTITY)
		and _xform_near(pivot.transform, Transform3D.IDENTITY)
	))
	_check("fallback: an identity local anchor is in place", ar.anchors.has_anchor() and ar.is_placed())
	main.queue_free()
	await get_tree().process_frame
	GameState.reset()


# --- Diorama-local space ------------------------------------------------------

func _test_diorama_local_invariance() -> void:
	var main: Node = await _load_main()
	GameState.stop_simulation()
	var ar: ARSessionController = main.get("ar") as ARSessionController
	var diorama: FlatDiorama = main.get("diorama") as FlatDiorama
	var rts: RtsController = main.get("rts") as RtsController
	var pivot: Node3D = main.get("_pivot") as Node3D
	var world: SimWorld = GameState.world
	await get_tree().physics_frame
	var views: Array[Node3D] = []
	var before: Array[Transform3D] = []
	for child: Node in diorama._entities.get_children():
		if child is UnitView or child is BuildingView:
			views.append(child as Node3D)
			before.append((child as Node3D).transform)
	var hash_before: int = world.state_hash()
	var units_local_ok: bool = true
	for view: Node3D in views:
		if view is UnitView:
			var unit: SimUnit = world.playable.get_unit((view as UnitView).unit_id)
			units_local_ok = units_local_ok and _near(view.position, UnitView.local_target(unit))
	_check("diorama: unit views sit at their sim position in diorama-local space", (
		views.size() >= 8 and units_local_ok
	))
	# Move the anchor somewhere odd and scale / rotate / magnify the placement.
	var anchor_pose := Transform3D(Basis(Vector3.UP, 0.8), Vector3(1.2, 0.74, -0.6))
	ar.apply_anchor_pose(anchor_pose)
	ar.placement = DioramaPlacement.new()
	ar.placement.scale = 0.37
	ar.placement.yaw = 1.1
	ar.placement.offset = Vector3(0.05, 0.0, -0.03)
	ar.placement.magnify = 2.5
	pivot.transform = ar.placement.pivot_transform()
	for _i in 6:
		await get_tree().physics_frame
	var unchanged: bool = true
	for i: int in views.size():
		unchanged = unchanged and _xform_near(views[i].transform, before[i])
	_check("diorama: local transforms are unchanged by anchor pose and scale", unchanged)
	_check("diorama: the simulation state is untouched by the anchor", world.state_hash() == hash_before)
	_check("diorama: the pivot really moved and scaled in the world", (
		not _near(diorama.global_position, Vector3.ZERO, 0.01)
		and is_equal_approx(pivot.global_transform.basis.get_scale().x, 0.37 * 2.5)
	))
	# Orders: a world-space tap on a unit maps back to its diorama-local position.
	var round_trip: bool = true
	var unit_view: UnitView = null
	for view: Node3D in views:
		if view is UnitView:
			unit_view = view as UnitView
			var unit: SimUnit = world.playable.get_unit(unit_view.unit_id)
			var local: Vector3 = rts.to_diorama_local(view.global_position)
			round_trip = round_trip and _near(local, Vector3(unit.position.x, 0.0, unit.position.z), 0.001)
	_check("diorama: world hits convert back to diorama-local order coordinates", round_trip)
	var ground: Plane = rts.diorama_ground_plane()
	_check("diorama: the order ground plane follows the anchored diorama", (
		absf(ground.distance_to(diorama.global_position)) < 0.0001
		and _near(ground.normal, Vector3.UP, 0.0001)
	))
	var target_local := Vector3(0.1, 0.0, 0.05)
	var target_world: Vector3 = diorama.to_global(target_local)
	GameState.commands.move_unit(unit_view.unit_id, rts.to_diorama_local(target_world))
	var unit_after: SimUnit = world.playable.get_unit(unit_view.unit_id)
	_check("diorama: a move order lands in diorama-local space", _near(unit_after.destination, target_local, 0.001))
	main.queue_free()
	await get_tree().process_frame
	GameState.reset()


# --- AnchorService ------------------------------------------------------------

func _test_anchor_service() -> void:
	var backend := LocalAnchorBackend.new()
	var service := AnchorService.new(backend)
	var placed: Array[int] = []
	service.anchor_placed.connect(func(id: int, _pose: Transform3D) -> void: placed.append(id))
	var tilted := Transform3D(Basis(Vector3.UP, 0.5) * Basis(Vector3.RIGHT, 0.3), Vector3(0.2, 0.9, -1.0))
	_check("anchor: place_at_pose creates an anchor", service.place_at_pose(tilted) and service.has_anchor())
	_check("anchor: placement emits anchor_placed", placed == [service.anchor_id])
	var level: Transform3D = service.pose
	_check("anchor: the pose is kept upright (yaw only)", (
		_near(level.basis.y, Vector3.UP) and _near(level.origin, tilted.origin)
		and is_equal_approx(AnchorService.upright(Transform3D(Basis(Vector3.UP, 0.5), Vector3.ZERO)).basis.get_euler().y, 0.5)
	))
	backend.set_pose(service.anchor_id, Transform3D(Basis.IDENTITY, Vector3(0.25, 0.9, -1.0)))
	_check("anchor: poll follows ARCore refining the anchor", _near(service.poll().origin, Vector3(0.25, 0.9, -1.0)))
	var states: Array[int] = []
	service.tracking_changed.connect(func(state: int) -> void: states.append(state))
	backend.remove_anchor(service.anchor_id)
	service.poll()
	_check("anchor: losing the anchor reports a tracking change and keeps the last pose", (
		states == [AnchorBackend.Tracking.UNKNOWN] and _near(service.pose.origin, Vector3(0.25, 0.9, -1.0))
	))
	service.clear()
	_check("anchor: clear drops the anchor", not service.has_anchor() and service.cloud_anchor_id.is_empty())
	backend.screen_anchor_pose = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.8, -0.5))
	_check("anchor: place_at_screen anchors on the surface under the reticle", (
		service.place_at_screen(Vector2(0.5, 0.5)) and _near(service.pose.origin, Vector3(0.0, 0.8, -0.5))
	))


func _test_cloud_anchor_stub() -> void:
	var host := AnchorService.new(LocalAnchorBackend.new())
	var reasons: Array[String] = []
	host.cloud_anchor_failed.connect(func(reason: String) -> void: reasons.append(reason))
	_check("cloud: host_anchor without an anchor fails", not host.host_anchor() and host.cloud_state == AnchorService.CloudState.FAILED)
	host.place_at_pose(Transform3D(Basis(Vector3.UP, 1.0), Vector3(0.3, 0.75, -0.8)))
	var hosted: Array[String] = []
	host.cloud_anchor_hosted.connect(func(id: String) -> void: hosted.append(id))
	_check("cloud: host_anchor fills the Cloud Anchor ID field", (
		host.host_anchor() and not host.cloud_anchor_id.is_empty()
		and host.cloud_state == AnchorService.CloudState.HOSTED and hosted == [host.cloud_anchor_id]
	))
	var guest := AnchorService.new(LocalAnchorBackend.new())
	_check("cloud: another phone resolves the same anchor pose by ID", (
		guest.resolve_anchor(host.cloud_anchor_id)
		and guest.cloud_state == AnchorService.CloudState.RESOLVED
		and _xform_near(guest.pose, host.pose)
	))
	_check("cloud: resolving an unknown ID fails", not guest.resolve_anchor("missing-id"))
	var arcore_like := LocalAnchorBackend.new()
	arcore_like.cloud_enabled = false
	var offline := AnchorService.new(arcore_like)
	offline.place_at_pose(Transform3D.IDENTITY)
	var offline_reasons: Array[String] = []
	offline.cloud_anchor_failed.connect(func(reason: String) -> void: offline_reasons.append(reason))
	_check("cloud: a backend without Cloud Anchors fails host_anchor with a reason", (
		not offline.host_anchor() and offline_reasons.size() == 1 and offline.cloud_anchor_id.is_empty()
	))
	_check("cloud: the real ARCore backend reports Cloud Anchors as not wired yet", not ARCoreAnchorBackend.new(ARCoreBridge.new()).supports_cloud())
	var placement := DioramaPlacement.new()
	placement.scale = 0.8
	var payload: Dictionary = host.share_payload(placement)
	_check("cloud: the share payload is the anchor ID plus anchor-relative placement only", (
		payload.get("cloud_anchor_id") == host.cloud_anchor_id
		and is_equal_approx(float((payload["placement"] as Dictionary)["scale"]), 0.8)
		and payload.size() == 2
	))


# --- Placement ------------------------------------------------------------------

func _test_placement() -> void:
	var placement := DioramaPlacement.new()
	placement.offset = Vector3(0.1, 0.0, 0.2)
	placement.yaw = 0.5
	placement.scale = 0.5
	var pivot: Transform3D = placement.pivot_transform()
	_check("placement: pivot = offset, yaw, scale relative to the anchor", (
		_near(pivot.origin, Vector3(0.1, 0.0, 0.2))
		and is_equal_approx(pivot.basis.get_scale().x, 0.5)
		and is_equal_approx(pivot.basis.get_euler().y, 0.5)
	))
	placement.magnify = 2.0
	_check("placement: magnify scales about the anchor (anchor point stays put)", (
		_near(placement.pivot_transform() * Vector3.ZERO, Vector3(0.2, 0.0, 0.4))
		and is_equal_approx(placement.total_scale(), 1.0)
	))
	placement.recenter()
	_check("placement: recenter returns to the anchor and keeps scale/rotation", (
		_near(placement.offset, Vector3.ZERO) and placement.magnify == 1.0
		and placement.scale == 0.5 and placement.yaw == 0.5
	))
	_check("placement: unlocked drag moves on the plane only", (
		placement.drag(Vector3(0.1, 0.3, 0.0)) and _near(placement.offset, Vector3(0.1, 0.0, 0.0))
	))
	_check("placement: pinch scale is clamped", (
		placement.pinch(100.0) and placement.scale == DioramaPlacement.MAX_SCALE
	))
	placement.locked = true
	var snapshot: Dictionary = placement.to_dict()
	_check("placement: locked ignores drag, pinch and twist", (
		not placement.drag(Vector3.ONE) and not placement.pinch(0.5) and not placement.twist(1.0)
		and placement.to_dict() == snapshot
	))
	placement.magnify_by(3.0)
	_check("placement: magnify still works while locked", is_equal_approx(placement.magnify, 3.0))
	var path: String = "user://ar_placement_test.cfg"
	placement.save(path)
	var restored := DioramaPlacement.new()
	_check("placement: scale/rotation/offset/lock persist; magnify does not", (
		restored.load_from(path) and restored.to_dict() == snapshot and restored.magnify == 1.0
	))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- Gestures -------------------------------------------------------------------

func _touch(index: int, position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	return event


func _drag(index: int, position: Vector2, relative: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	event.relative = relative
	return event


func _test_gestures() -> void:
	var tracker := ARGestureTracker.new()
	tracker.handle(_touch(0, Vector2(100, 100), true))
	var tap: Dictionary = tracker.handle(_touch(0, Vector2(102, 101), false))
	_check("gesture: a short touch is a tap", tap.get("kind") == &"tap")
	tracker.handle(_touch(0, Vector2(100, 100), true))
	var drag: Dictionary = tracker.handle(_drag(0, Vector2(160, 100), Vector2(60, 0)))
	var after_drag: Dictionary = tracker.handle(_touch(0, Vector2(160, 100), false))
	_check("gesture: one-finger movement is a drag, not a tap", (
		drag.get("kind") == &"drag" and _near(Vector3((drag["to"] as Vector2).x, 0, 0), Vector3(160, 0, 0))
		and after_drag.is_empty()
	))
	tracker.handle(_touch(0, Vector2(100, 100), true))
	tracker.handle(_touch(1, Vector2(200, 100), true))
	var pinch: Dictionary = tracker.handle(_drag(1, Vector2(300, 100), Vector2(100, 0)))
	_check("gesture: spreading two fingers is a 2x pinch", (
		pinch.get("kind") == &"pinch" and is_equal_approx(float(pinch["scale"]), 2.0)
	))
	var twist: Dictionary = tracker.handle(_drag(1, Vector2(100, 300), Vector2(-200, 200)))
	_check("gesture: rotating the second finger 90 degrees clockwise is a +90 twist", (
		twist.get("kind") == &"pinch" and is_equal_approx(float(twist["twist"]), PI * 0.5)
	))


# --- Viewing ----------------------------------------------------------------------

func _test_effective_distance_tiers() -> void:
	var pivot := Vector3(0.0, 0.75, -0.5)
	var far: float = ARSessionController.effective_distance(pivot + Vector3(0, 0.6, 0), pivot, 0.5)
	var mid: float = ARSessionController.effective_distance(pivot + Vector3(0, 0.4, 0), pivot, 0.5)
	var near: float = ARSessionController.effective_distance(pivot + Vector3(0, 0.2, 0), pivot, 0.5)
	var magnified: float = ARSessionController.effective_distance(pivot + Vector3(0, 0.4, 0), pivot, 0.5 * 2.0)
	_check("viewing: effective distance is real distance / diorama scale", is_equal_approx(far, 1.2))
	_check("viewing: standing back at 0.6 m (scale 0.5) shows the orbit tier", (
		ZoomTierController.tier_for_distance(far) == GameState.ZoomTier.ORBIT
	))
	_check("viewing: stepping in to 0.4 m switches to the region tier", (
		ZoomTierController.tier_for_distance(mid) == GameState.ZoomTier.REGION
	))
	_check("viewing: leaning in to 0.2 m switches to the RTS tier", (
		ZoomTierController.tier_for_distance(near) == GameState.ZoomTier.RTS
	))
	_check("viewing: 2x magnify at 0.4 m reaches the RTS tier without moving", (
		ZoomTierController.tier_for_distance(magnified) == GameState.ZoomTier.RTS
	))


# --- Calibration --------------------------------------------------------------

func _test_calibration_flow() -> void:
	var flow := CalibrationFlow.new()
	_check("calibration: starts scanning with no place button", (
		flow.step == CalibrationFlow.Step.SCANNING and not bool(flow.controls()["place"])
		and bool(flow.controls()["sweep_hint"]) and flow.is_calibrating()
	))
	_check("calibration: the simulation is paused while scanning", not flow.should_run_simulation())
	var tracking: Dictionary = {"camera_state": 0, "frames": 10, "points": 4}
	flow.update(5.0, tracking, false)
	_check("calibration: few feature points ask the player to sweep", flow.message().begins_with("Sweep the phone"))
	_check("calibration: no fallback offer before the timeout", not flow.offers_fallback())
	_check("calibration: tracking failures read as plain English", (
		CalibrationFlow.tracking_message({"camera_state": 1, "frames": 5, "failure_reason": 2}).contains("too dark")
		and CalibrationFlow.tracking_message({"camera_state": 1, "frames": 5, "failure_reason": 3}).contains("too fast")
		and CalibrationFlow.tracking_message({"camera_state": 1, "frames": 5, "failure_reason": 4}).contains("not enough detail")
		and CalibrationFlow.tracking_message({}).begins_with("Starting the camera")
	))
	flow.update(CalibrationFlow.FALLBACK_OFFER_SECONDS, tracking, false)
	_check("calibration: after the timeout, Place in front of me / Play without AR are offered", (
		flow.offers_fallback() and bool(flow.controls()["place_in_front"]) and bool(flow.controls()["play_without_ar"])
	))
	flow.update(0.1, tracking, true)
	_check("calibration: a surface shows the Place board button", (
		flow.step == CalibrationFlow.Step.SURFACE_FOUND and bool(flow.controls()["place"])
		and not flow.offers_fallback()
	))
	flow.set_locked(true)
	_check("calibration: lock is ignored before the board is placed", flow.step == CalibrationFlow.Step.SURFACE_FOUND)
	flow.placed()
	_check("calibration: placing moves to adjust (Lock + Re-place, still paused)", (
		flow.step == CalibrationFlow.Step.ADJUSTING and bool(flow.controls()["lock"])
		and bool(flow.controls()["replace"]) and not flow.should_run_simulation()
	))
	flow.set_locked(true)
	_check("calibration: locking starts play", (
		flow.step == CalibrationFlow.Step.LOCKED and flow.should_run_simulation() and not flow.is_calibrating()
		and bool(flow.controls()["unlock"])
	))
	flow.set_locked(false)
	_check("calibration: unlocking returns to adjust and pauses", (
		flow.step == CalibrationFlow.Step.ADJUSTING and not flow.should_run_simulation()
	))
	flow.restart()
	_check("calibration: re-place restarts scanning", flow.step == CalibrationFlow.Step.SCANNING and flow.scan_seconds == 0.0)


func _test_front_pose_and_surface_mesh() -> void:
	var camera := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-30.0)), Vector3(0.0, 1.4, 0.0))
	var pose: Transform3D = ARSessionController.front_pose(camera)
	_check("place in front: 0.6 m ahead and below the camera, level", (
		_near(pose.origin, Vector3(0.0, 1.4 - ARSessionController.FRONT_PLACE_DROP, -ARSessionController.FRONT_PLACE_DISTANCE), 0.001)
		and _near(pose.basis.y, Vector3.UP, 0.001) and _near(-pose.basis.z, Vector3.FORWARD, 0.001)
	))
	var straight_down := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90.0)), Vector3(0.0, 1.0, 0.0))
	var down_pose: Transform3D = ARSessionController.front_pose(straight_down)
	_check("place in front: still level when the phone points straight down", _near(down_pose.basis.y, Vector3.UP, 0.001))
	var square := PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	var mesh: ArrayMesh = ARSessionController.plane_mesh(square)
	_check("surface overlay: a plane polygon becomes a triangle fan", (
		mesh != null and mesh.surface_get_array_len(0) == 12
	))
	_check("surface overlay: degenerate polygons are skipped", ARSessionController.plane_mesh(PackedVector2Array([Vector2.ZERO, Vector2.ONE])) == null)


func _test_no_win_at_start() -> void:
	GameState.reset()
	GameState.bootstrap_concept_world()
	var victory: VictorySystem = GameState.world.victory
	var any_held: bool = false
	for key: Variant in victory.hold:
		any_held = any_held or int(victory.hold[key]) > 0
	_check("victory: nobody has won or is holding a condition at tick 0", victory.winner_id == &"" and not any_held)
	GameState.reset()


func _test_ar_calibration_controller() -> void:
	var main: Node = await _load_main()
	var ar: ARSessionController = main.get("ar") as ARSessionController
	var hud: CanvasLayer = main.get("hud") as CanvasLayer
	var fake := FakeARBridge.new()
	ar.bridge_factory = func() -> ARCoreBridge: return fake
	GameState.tick_interval = 0.02
	_check("ar calibration: AR starts through the injected bridge", ar.try_start_ar() and ar.is_ar())
	_check("ar calibration: the sim is paused and the gameplay HUD hidden while calibrating", (
		not GameState.is_simulation_running and not hud.visible and ar.hud != null
	))
	var ticks_before: int = GameState.tick_count
	await get_tree().create_timer(0.25).timeout
	_check("ar calibration: no ticks (and no win checks) before the board is locked", (
		GameState.tick_count == ticks_before and GameState.world.victory.winner_id == &""
	))
	_check("ar calibration: scanning shows the sweep hint and live stats", (
		ar.flow.step == CalibrationFlow.Step.SCANNING and ar.hud.sweep_hint.visible
		and ar.hud.stats_label.text.contains("64")
	))
	ar.flow.scan_seconds = CalibrationFlow.FALLBACK_OFFER_SECONDS + 1.0
	await get_tree().process_frame
	await get_tree().process_frame
	_check("ar calibration: the fallback buttons appear after the timeout", (
		ar.hud.place_in_front_button.visible and ar.hud.play_without_ar_button.visible
	))
	fake.info = {"camera_state": 1, "failure_reason": 2, "frames": 30, "points": 0}
	ar.tracking_info = fake.info
	_check("ar calibration: place in front refuses while tracking is lost", not ar.place_in_front() and not ar.is_placed())
	fake.info = {"camera_state": 0, "failure_reason": 0, "frames": 30, "points": 64}
	_check("ar calibration: place in front anchors the board", ar.place_in_front() and ar.is_placed() and fake.anchors_made == 1)
	_check("ar calibration: adjusting keeps the sim paused and shows Lock", (
		ar.flow.step == CalibrationFlow.Step.ADJUSTING and not GameState.is_simulation_running
		and ar.hud.lock_button.visible and not hud.visible
	))
	ar.set_locked(true)
	await get_tree().create_timer(0.25).timeout
	_check("ar calibration: locking starts the sim and shows the gameplay HUD", (
		GameState.is_simulation_running and hud.visible and GameState.tick_count > ticks_before
		and not ar.hud.lock_button.visible and ar.hud.unlock_button.visible
	))
	ar.begin_replace()
	_check("ar calibration: re-place pauses again and restarts scanning", (
		not GameState.is_simulation_running and not hud.visible and ar.flow.step == CalibrationFlow.Step.SCANNING
		and not ar.is_placed()
	))
	fake.surface_found = true
	await get_tree().process_frame
	await get_tree().process_frame
	_check("ar calibration: a found surface shows the reticle and Place board", (
		ar.flow.step == CalibrationFlow.Step.SURFACE_FOUND and ar.hud.place_button.visible and ar.reticle.visible
	))
	_check("ar calibration: Place board anchors on the surface", ar.place_at_reticle() and ar.is_placed())
	ar.fall_back("Player chose to play without AR.")
	_check("ar calibration: Play without AR resumes the sim in the touch view", (
		not ar.is_ar() and GameState.is_simulation_running and hud.visible
	))
	GameState.tick_interval = GameState.DEFAULT_TICK_INTERVAL
	main.queue_free()
	await get_tree().process_frame
	GameState.reset()
