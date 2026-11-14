extends Node3D
## Desktop concept entry: boots the sim, hosts globe + diorama + camera.

var rig: DesktopRig
var third: ThirdPersonRig
var globe: OrbitGlobe
var diorama: FlatDiorama
var hud: DesktopHud
var rts: RtsController
var skirmish: SkirmishPossessionController
## World-locked AR (or the desktop fallback when ARCore is unavailable).
var ar: ARSessionController
## WorldAnchor: follows the AR anchor pose (identity on desktop).
var _anchor: Node3D
## DioramaPivot: player placement (offset / yaw / scale / magnify) under the
## anchor. The globe and diorama live below it in their own local space.
var _pivot: Node3D
var _environment: Environment


func _ready() -> void:
	_setup_environment()
	_anchor = Node3D.new()
	_anchor.name = "WorldAnchor"
	add_child(_anchor)
	_pivot = Node3D.new()
	_pivot.name = "DioramaPivot"
	_anchor.add_child(_pivot)
	globe = OrbitGlobe.new()
	globe.name = "OrbitGlobe"
	_pivot.add_child(globe)
	diorama = FlatDiorama.new()
	diorama.name = "FlatDiorama"
	diorama.visible = false
	_pivot.add_child(diorama)
	rig = DesktopRig.new()
	rig.name = "DesktopRig"
	_anchor.add_child(rig)
	third = ThirdPersonRig.new()
	third.name = "ThirdPersonRig"
	third.visible = false
	_anchor.add_child(third)
	hud = DesktopHud.new()
	add_child(hud)
	rts = RtsController.new()
	add_child(rts)
	skirmish = SkirmishPossessionController.new()
	skirmish.name = "SkirmishPossession"
	skirmish.third = third
	skirmish.rts = rts
	skirmish.hud = hud
	skirmish.view_lookup = _find_unit_view
	add_child(skirmish)
	rts.skirmish = skirmish
	GameState.bootstrap_concept_world()
	GameState.start_simulation()
	rts.camera = rig.camera
	rts.hud = hud
	rts.diorama = diorama
	ar = ARSessionController.new()
	ar.name = "ARSession"
	add_child(ar)
	ar.setup(_anchor, _pivot, rig, third, rts, _environment)
	hud._refresh()
	EventBus.region_selected.connect(_on_region_selected)
	EventBus.zoom_tier_changed.connect(_on_tier)
	EventBus.zoom_transition_progress.connect(_on_transition)
	EventBus.unit_possessed.connect(_on_possessed)
	EventBus.unit_released.connect(_on_released)
	if "--screenshots" in OS.get_cmdline_user_args():
		await _take_screenshots()


func _setup_environment() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.05, 0.06, 0.09)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.45, 0.5, 0.55)
	environment.ambient_light_energy = 0.7
	env.environment = environment
	_environment = environment
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 40.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = false
	add_child(sun)


func _on_region_selected(region_id: StringName) -> void:
	if GameState.world == null:
		return
	var data: RegionData = GameState.world.get_region_data(region_id)
	if data == null or not data.is_accessible:
		return
	rig.request_distance(0.75)


func _on_tier(new_tier: int, _prev: int) -> void:
	globe.visible = new_tier == int(GameState.ZoomTier.ORBIT)
	diorama.visible = new_tier >= int(GameState.ZoomTier.REGION)


func _on_transition(progress: float) -> void:
	if GameState.current_zoom_tier == GameState.ZoomTier.THIRD_PERSON:
		return
	if progress <= 0.0:
		globe.visible = true
		globe.scale = Vector3.ONE
		diorama.visible = false
		return
	globe.visible = true
	diorama.visible = true
	globe.scale = Vector3.ONE * (1.0 - 0.7 * progress)
	diorama.scale = Vector3.ONE * (0.4 + 0.6 * progress)
	if progress >= 1.0:
		globe.visible = false
		diorama.scale = Vector3.ONE


func _on_possessed(unit: Node3D) -> void:
	var view: UnitView = unit as UnitView
	if view == null:
		view = _find_unit_view(rts.selected_unit_id)
	rig.third_person = true
	rig.camera.current = false
	if view != null:
		third.attach(view)
	else:
		third.camera.current = true
		third.visible = true
	rts.camera = third.camera


func _on_released() -> void:
	third.detach()
	rig.third_person = false
	if ar != null and ar.is_ar():
		return  # ARSessionController restores the XR camera.
	rig.camera.current = true
	rts.camera = rig.camera
	rig.request_distance(0.4)


func _find_unit_view(unit_id: int) -> UnitView:
	if diorama == null or diorama._entities == null:
		return null
	for child in diorama._entities.get_children():
		if child is UnitView and (child as UnitView).unit_id == unit_id:
			return child as UnitView
	return null


func _take_screenshots() -> void:
	var dir: String = "/workspace/agr-shots"
	DirAccess.make_dir_recursive_absolute(dir)
	rig.frozen = true
	rig.camera.current = true
	hud._refresh()
	await _wait_frames(8)
	# Tier 1: globe with territory colors, pins, and rare-resource icons.
	rig.yaw = 0.6
	rig.pitch = 0.45
	rig.distance = 1.85
	rig._target_distance = 1.85
	GameState.current_zoom_tier = GameState.ZoomTier.ORBIT
	globe.visible = true
	globe.scale = Vector3.ONE
	diorama.visible = false
	hud._refresh()
	await _wait_frames(24)
	await _save(dir, "01-orbit-globe.png")
	# Tier 2: diorama hubs, resources, no individual units.
	EventBus.region_selected.emit(SimIds.PLAYABLE_REGION)
	rig.yaw = 0.7
	rig.pitch = 0.85
	rig.distance = 0.95
	rig._target_distance = 0.95
	GameState.current_zoom_tier = GameState.ZoomTier.REGION
	globe.visible = false
	diorama.visible = true
	diorama.scale = Vector3.ONE
	diorama._on_tier(int(GameState.ZoomTier.REGION), 0)
	hud._refresh()
	await _wait_frames(24)
	await _save(dir, "02-region-diorama.png")
	# Tier 3: RTS grid, buildings, units.
	rig.yaw = 0.55
	rig.pitch = 0.95
	rig.distance = 0.42
	rig._target_distance = 0.42
	GameState.current_zoom_tier = GameState.ZoomTier.RTS
	diorama._on_tier(int(GameState.ZoomTier.RTS), 0)
	hud._refresh()
	await _wait_frames(24)
	await _save(dir, "03-rts-scale.png")
	# Tier 3 build/claim mode: faint axial hex overlay and structure-claim borders.
	rig.distance = 0.62
	rig._target_distance = 0.62
	GameState.set_build_or_claim_mode(true)
	hud._refresh()
	await _wait_frames(24)
	await _save(dir, "04-rts-hex-overlay.png")
	GameState.set_build_or_claim_mode(false)
	print("SCREENSHOTS_SAVED %s" % dir)
	get_tree().quit(0)


func _wait_frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _save(dir: String, filename: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = "%s/%s" % [dir, filename]
	var err: Error = image.save_png(path)
	print("screenshot %s err=%s %dx%d" % [path, str(err), image.get_width(), image.get_height()])
