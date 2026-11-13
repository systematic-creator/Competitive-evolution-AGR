class_name DesktopHud
extends CanvasLayer
## Desktop stand-in HUD: resources, era, build/train commands, hints.

var _status: Label
var _log: Label
var _build_type: StringName = &""


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
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	col.add_child(buttons)
	_add_btn(buttons, "Farm", func() -> void: _build_type = SimIds.FARM)
	_add_btn(buttons, "House", func() -> void: _build_type = SimIds.HOUSE)
	_add_btn(buttons, "Lumber", func() -> void: _build_type = SimIds.LUMBER_CAMP)
	_add_btn(buttons, "Quarry", func() -> void: _build_type = SimIds.QUARRY)
	_add_btn(buttons, "Barracks", func() -> void: _build_type = SimIds.BARRACKS)
	_add_btn(buttons, "Foundry", func() -> void: _build_type = SimIds.FOUNDRY)
	_add_btn(buttons, "Extractor", func() -> void: _build_type = SimIds.EXTRACTOR)
	_add_btn(buttons, "Worker", func() -> void: _train(SimIds.WORKER))
	_add_btn(buttons, "Soldier", func() -> void: _train(SimIds.SOLDIER))
	_add_btn(buttons, "Ironclad", func() -> void: _train(SimIds.IRONCLAD))
	_add_btn(buttons, "Advance Era", func() -> void: _advance())
	_add_btn(buttons, "Possess (P)", func() -> void: EventBus.unit_possessed.emit(null))
	_log = Label.new()
	_log.text = "Scroll to zoom. Click a glowing pin to enter Verdant Basin. Left-click select, right-click move. OpenXR is off."
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_log)
	EventBus.simulation_ticked.connect(func(_t: int) -> void: _refresh())
	EventBus.era_changed.connect(func(_a: StringName, _b: EraData, _c: EraData) -> void: _refresh())
	_refresh()


func pending_build_type() -> StringName:
	return _build_type


func clear_build() -> void:
	_build_type = &""
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
	var region: SimRegion = GameState.world.playable
	var build: String = String(_build_type) if _build_type != &"" else "none"
	_status.text = "Tier %s  |  %s  Era: %s  |  Food %d  Wood %d  Stone %d  Iron %d  Coal %d  |  Pop %d/%d  |  Build: %s  |  Tick %d" % [
		str(GameState.ZoomTier.keys()[int(GameState.current_zoom_tier)]),
		faction.data.display_name,
		era_name,
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
