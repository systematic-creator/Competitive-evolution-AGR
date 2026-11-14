class_name SkirmishPossessionController
extends Node
## Tier 4 skirmish possession, view side.
##
## Answers `EventBus.skirmish_possession_requested` for the player by
## possessing one squad member through CommandService, drives the
## ThirdPersonRig (SpringArm3D) and the touch overlay, and turns WASD /
## joystick / Attack input into quantized CommandService orders. When the
## sim reports the fight finished, it resolves the skirmish through
## CommandService. Auto-battle stays available: automatically when no unit
## can be possessed, and on demand (Auto-resolve button or Esc).
##
## Never mutates the sim directly; reactions to sim signals are deferred so
## every order is stamped between combat steps and replays exactly.

const CAMERA_TURN_SPEED: float = 2.2
const CAMERA_DRAG_SENSITIVITY: float = 0.008

var third: ThirdPersonRig
var rts: RtsController
var hud: DesktopHud
## (unit_id: int) -> UnitView (may return null)
var view_lookup: Callable
var controls: SkirmishTouchControls

var skirmish_id: int = -1
var unit_id: int = -1
var camera_yaw: float = 0.0
## Last steering sector sent; -2 means "nothing sent yet".
var _last_sector: int = -2
var _camera_touch: int = -1


func _ready() -> void:
	controls = SkirmishTouchControls.new()
	controls.name = "SkirmishTouchControls"
	controls.visible = false
	add_child(controls)
	controls.auto_resolve_pressed.connect(request_auto_resolve)
	EventBus.skirmish_possession_requested.connect(_on_possession_requested)
	EventBus.skirmish_possession_started.connect(_on_possession_started)
	EventBus.skirmish_combat_finished.connect(_on_combat_finished)
	EventBus.skirmish_possession_ended.connect(_on_possession_ended)
	EventBus.unit_killed.connect(_on_unit_killed)


func is_active() -> bool:
	return skirmish_id >= 0


## Fallback: settle the current fight by the sim's auto-battle rules.
func request_auto_resolve() -> void:
	if not is_active() or GameState.commands == null:
		return
	GameState.commands.resolve_skirmish_auto(skirmish_id)


# --- Sim signals ------------------------------------------------------------

func _on_possession_requested(sid: int, faction_id: StringName, _node_id: StringName, _hex: Vector2i) -> void:
	if GameState.world == null or faction_id != GameState.get_player_faction_id():
		return
	_begin_possession.call_deferred(sid)


func _begin_possession(sid: int) -> void:
	var world: SimWorld = GameState.world
	var commands: CommandService = GameState.commands
	if world == null or commands == null:
		return
	if is_active():
		_message("Already fighting a skirmish; auto-battling the new one.")
		commands.resolve_skirmish_auto(sid)
		return
	var chosen: int = _choose_unit(world.claims.possession_candidates(world, sid))
	if chosen < 0 or not commands.possess_skirmish_unit(sid, chosen):
		_message("No soldier in the contested hex can be possessed; auto-battle resolved it.")
		commands.resolve_skirmish_auto(sid)


func _on_possession_started(sid: int, new_unit_id: int) -> void:
	var world: SimWorld = GameState.world
	if world == null:
		return
	var combat: SkirmishCombat = world.claims.combat_for(sid)
	if combat == null or combat.attacker_id != GameState.get_player_faction_id():
		return
	if is_active() and sid != skirmish_id:
		return
	var entering: bool = not is_active()
	skirmish_id = sid
	unit_id = new_unit_id
	_last_sector = -2
	var unit: SimUnit = world.playable.get_unit(new_unit_id)
	if unit != null:
		var to_center: Vector3 = combat.center - unit.position
		to_center.y = 0.0
		if to_center.length() > 0.001:
			camera_yaw = SkirmishCombat.yaw_for_direction(to_center)
	third.follow_target_yaw = false
	third.yaw = camera_yaw
	var view: UnitView = _view_for(new_unit_id)
	if entering:
		controls.visible = true
		GameState.current_zoom_tier = GameState.ZoomTier.THIRD_PERSON
		EventBus.unit_possessed.emit(view)
		_message("Possessed a soldier. WASD / joystick to move, F / Attack to strike, Q/E or drag to turn the camera, Esc to auto-resolve.")
	elif view != null:
		third.attach(view)
		_message("Control passed to another squad member.")


func _on_unit_killed(dead_id: int, _faction_id: StringName) -> void:
	if is_active() and dead_id == unit_id:
		unit_id = -1
		_repossess.call_deferred()


func _repossess() -> void:
	var world: SimWorld = GameState.world
	if not is_active() or world == null or unit_id >= 0:
		return
	var candidates: Array[SimUnit] = world.claims.possession_candidates(world, skirmish_id)
	if candidates.is_empty():
		_message("Your soldier fell.")
		return
	GameState.commands.possess_skirmish_unit(skirmish_id, candidates[0].id)


func _on_combat_finished(sid: int, _winner_id: StringName) -> void:
	if sid == skirmish_id:
		_resolve_finished.call_deferred(sid)


func _resolve_finished(sid: int) -> void:
	if GameState.commands != null:
		GameState.commands.resolve_skirmish_possessed(sid)


func _on_possession_ended(sid: int, winner_id: StringName) -> void:
	if sid != skirmish_id:
		return
	var won: bool = winner_id == GameState.get_player_faction_id()
	skirmish_id = -1
	unit_id = -1
	_last_sector = -2
	_camera_touch = -1
	controls.visible = false
	third.follow_target_yaw = true
	GameState.current_zoom_tier = GameState.ZoomTier.RTS
	EventBus.unit_released.emit()
	_message("Skirmish won: the hex is yours." if won else "Skirmish lost: the defenders held.")


# --- Input ------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_active():
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed and _camera_touch < 0 and not controls.is_over_controls(touch.position):
			_camera_touch = touch.index
		elif not touch.pressed and touch.index == _camera_touch:
			_camera_touch = -1
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == _camera_touch and not controls.joystick.owns_touch(drag.index):
			camera_yaw -= drag.relative.x * CAMERA_DRAG_SENSITIVITY


func _process(delta: float) -> void:
	if not is_active():
		return
	var world: SimWorld = GameState.world
	var commands: CommandService = GameState.commands
	if world == null or commands == null:
		return
	if Input.is_key_pressed(KEY_Q):
		camera_yaw += CAMERA_TURN_SPEED * delta
	if Input.is_key_pressed(KEY_E):
		camera_yaw -= CAMERA_TURN_SPEED * delta
	third.yaw = camera_yaw
	var combat: SkirmishCombat = world.claims.live_combat(skirmish_id)
	if combat == null:
		return
	_update_status(world, combat)
	if combat.possessed_unit_id < 0:
		return
	var sector: int = SkirmishCombat.direction_to_sector(camera_relative_direction(_move_input(), camera_yaw))
	if sector != _last_sector:
		if commands.steer_possessed(skirmish_id, sector):
			_last_sector = sector
	var attack_held: bool = Input.is_key_pressed(KEY_F) or Input.is_key_pressed(KEY_J) or controls.attack_held
	if attack_held and combat.can_possessed_attack():
		commands.possessed_attack(skirmish_id)


## Keyboard + joystick input in screen space (x right, y down), unit length max.
func _move_input() -> Vector2:
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input.x += 1.0
	input += controls.joystick.value
	return input.limit_length(1.0)


## Map screen-space stick input to a world XZ direction for a camera at `yaw`.
static func camera_relative_direction(input: Vector2, yaw: float) -> Vector3:
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return right * input.x - forward * input.y


func _update_status(world: SimWorld, combat: SkirmishCombat) -> void:
	var unit: SimUnit = world.playable.get_unit(combat.possessed_unit_id)
	var hp_text: String = "fallen" if unit == null else "HP %d/%d" % [unit.hp, unit.max_hp]
	var guard_text: String = ""
	if combat.guard_max_hp > 0:
		guard_text = "  |  Guard %d/%d" % [combat.guard_hp, combat.guard_max_hp]
	var seconds_left: int = int(ceil(float(SkirmishCombat.MAX_STEPS - combat.steps) * SkirmishCombat.STEP_SECONDS))
	controls.set_status("SKIRMISH  |  You: %s  |  Allies %d  vs  Enemies %d%s  |  %ds" % [
		hp_text,
		combat.living(world, combat.attackers).size(),
		combat.living(world, combat.defenders).size(),
		guard_text,
		seconds_left,
	])


func _choose_unit(candidates: Array[SimUnit]) -> int:
	if candidates.is_empty():
		return -1
	if rts != null:
		for unit: SimUnit in candidates:
			if unit.id == rts.selected_unit_id:
				return unit.id
	return candidates[0].id


func _view_for(id: int) -> UnitView:
	if not view_lookup.is_valid():
		return null
	return view_lookup.call(id) as UnitView


func _message(text: String) -> void:
	if hud != null:
		hud.show_message(text)
