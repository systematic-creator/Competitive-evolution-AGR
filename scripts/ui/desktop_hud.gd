class_name DesktopHud
extends CanvasLayer
## Desktop stand-in HUD: resources, era, build/train commands, hints.

var _status: Label
var _log: Label
var _victory: Label
var _build_type: StringName = &""
var _buttons: HFlowContainer


func _ready() -> void:
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 16)
	root.add_theme_constant_override("margin_top", 12)
	root.add_theme_constant_override("margin_right", 16)
	root.add_theme_constant_override("margin_bottom", 12)
	add_child(root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	root.add_child(col)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	var buttons := HFlowContainer.new()
	_buttons = buttons
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 6)
	col.add_child(buttons)
	_add_btn(buttons, "Farm", func() -> void: _select_build(SimIds.FARM))
	_add_btn(buttons, "House", func() -> void: _select_build(SimIds.HOUSE))
	_add_btn(buttons, "Lumber", func() -> void: _select_build(SimIds.LUMBER_CAMP))
	_add_btn(buttons, "Quarry", func() -> void: _select_build(SimIds.QUARRY))
	_add_btn(buttons, "Barracks", func() -> void: _select_build(SimIds.BARRACKS))
	_add_btn(buttons, "Foundry", func() -> void: _select_build(SimIds.FOUNDRY))
	_add_btn(buttons, "Extractor", func() -> void: _select_build(SimIds.EXTRACTOR))
	_add_btn(buttons, "Outpost", func() -> void: _select_build(SimIds.OUTPOST))
	_add_btn(buttons, "Auto-Battle", func() -> void: _auto_battle())
	_add_btn(buttons, "Contest (possess)", func() -> void: _contest_possess())
	_add_btn(buttons, "Worker", func() -> void: _train(SimIds.WORKER))
	_add_btn(buttons, "Soldier", func() -> void: _train(SimIds.SOLDIER))
	_add_btn(buttons, "Ironclad", func() -> void: _train(SimIds.IRONCLAD))
	_add_btn(buttons, "Advance Era", func() -> void: _advance())
	_add_btn(buttons, "Possess (P)", func() -> void: EventBus.unit_possessed.emit(null))
	_log = Label.new()
	_log.text = "Scroll to zoom. Click a glowing pin to enter Verdant Basin. Left-click select, right-click move. OpenXR is off."
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_log)
	_victory = Label.new()
	_victory.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_victory)
	EventBus.simulation_ticked.connect(func(_t: int) -> void: _refresh())
	EventBus.era_changed.connect(func(_a: StringName, _b: EraData, _c: EraData) -> void: _refresh())
	EventBus.world_era_changed.connect(func(_i: int, _a: EraData, _b: EraData) -> void: _refresh())
	EventBus.victory_progress.connect(func(_a: StringName, _b: StringName, _c: float, _d: int, _e: int) -> void: _refresh())
	EventBus.victory_achieved.connect(func(_a: StringName, _b: StringName, _c: WinConditionData) -> void: _refresh())
	_refresh()


## True if a screen position lands on a HUD button (so touch taps there are
## not also treated as taps on the world behind the HUD).
func is_over_ui(screen_position: Vector2) -> bool:
	if _buttons == null:
		return false
	for child: Node in _buttons.get_children():
		var control: Control = child as Control
		if control != null and control.visible and control.get_global_rect().has_point(screen_position):
			return true
	return false


func show_message(text: String) -> void:
	if _log != null:
		_log.text = text


func pending_build_type() -> StringName:
	return _build_type


func clear_build() -> void:
	_build_type = &""
	GameState.set_build_or_claim_mode(false)
	_refresh()


func _select_build(building_type: StringName) -> void:
	_build_type = building_type
	GameState.set_build_or_claim_mode(building_type != &"")
	_refresh()


func _auto_battle() -> void:
	if GameState.world == null or GameState.commands == null:
		return
	var target: Dictionary = GameState.world.claims.find_skirmish_target(GameState.world, GameState.get_player_faction_id())
	if target.is_empty():
		return
	GameState.commands.start_skirmish(
		GameState.get_player_faction_id(),
		target["node_id"] as StringName,
		target["hex"] as Vector2i,
		true
	)
	_refresh()


func _contest_possess() -> void:
	if GameState.world == null or GameState.commands == null:
		return
	var target: Dictionary = GameState.world.claims.find_skirmish_target(GameState.world, GameState.get_player_faction_id())
	if target.is_empty():
		show_message("Contest needs a soldier standing in an enemy-held hex of a revealed rare node.")
		return
	# Start a possession skirmish. SkirmishPossessionController answers the
	# possession request (Tier 4), or falls back to auto-battle.
	GameState.commands.start_skirmish(
		GameState.get_player_faction_id(),
		target["node_id"] as StringName,
		target["hex"] as Vector2i,
		false
	)
	_refresh()


func _add_btn(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _train(unit_type: StringName) -> void:
	if GameState.commands != null:
		GameState.commands.train_unit(GameState.get_player_faction_id(), unit_type)
	_refresh()


func _advance() -> void:
	if GameState.commands != null:
		GameState.commands.advance_era(GameState.get_player_faction_id())
	_refresh()


func _refresh() -> void:
	if GameState.world == null:
		_status.text = "Simulation not booted."
		return
	var faction: SimFaction = GameState.world.get_faction(GameState.get_player_faction_id())
	if faction == null:
		return
	var era_name: String = faction.species.era_label(faction.era) if faction.species != null else faction.era.era_name
	var world_era: EraData = GameState.world.world_era()
	var world_era_name: String = world_era.era_name if world_era != null else str(GameState.world.world_era_index)
	var region: SimRegion = GameState.world.playable
	var build: String = String(_build_type) if _build_type != &"" else "none"
	_status.text = "Tier %s  |  %s  Era: %s  |  World: %s  |  Food %d  Wood %d  Stone %d  Iron %d  Coal %d  |  Pop %d/%d  |  Build: %s  |  Tick %d" % [
		str(GameState.ZoomTier.keys()[int(GameState.current_zoom_tier)]),
		faction.data.display_name,
		era_name,
		world_era_name,
		faction.get_resource(SimIds.FOOD),
		faction.get_resource(SimIds.WOOD),
		faction.get_resource(SimIds.STONE),
		faction.get_resource(SimIds.IRON),
		faction.get_resource(SimIds.COAL),
		region.population(faction.faction_id()),
		region.population_cap(faction.faction_id()),
		build,
		GameState.tick_count,
	]
	if _victory != null:
		_victory.text = _victory_line(GameState.world, faction)


func _victory_line(world: SimWorld, faction: SimFaction) -> String:
	if world == null or world.victory == null:
		return ""
	if world.victory.winner_id != &"":
		var winner: SimFaction = world.get_faction(world.victory.winner_id)
		var wname: String = String(world.victory.winner_id) if winner == null or winner.data == null else winner.data.display_name
		return "VICTORY: %s — %s" % [wname, String(world.victory.winner_condition_id).replace("_", " ").capitalize()]
	var bits: PackedStringArray = PackedStringArray()
	for row: Dictionary in world.victory.player_rows(world):
		var pct: int = int(round(float(row.get("progress", 0.0)) * 100.0))
		bits.append("%s %d%% (%d/%d)" % [
			str(row.get("name", "")),
			pct,
			int(row.get("held", 0)),
			int(row.get("required", 1)),
		])
	if bits.is_empty():
		return "Win conditions: none available."
	return "Win: " + "  ·  ".join(bits)
