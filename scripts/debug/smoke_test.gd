extends Control
## On-device smoke test for the core architecture (autoloads + data Resources).
##
## Runs automatically on launch and prints PASS/FAIL lines. Touch buttons let
## you poke the zoom tier and simulation tick live. Safe to delete once real
## scenes exist (and point `run/main_scene` at `main_ar.tscn`).

const FONT_SIZE: int = 30
const LOG_FONT_SIZE: int = 24
const BUTTON_HEIGHT: float = 96.0

var _log: RichTextLabel
var _status: Label
var _sim_button: Button
var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_build_ui()
	_run_checks()
	EventBus.zoom_tier_changed.connect(_on_zoom_tier_changed)
	EventBus.simulation_ticked.connect(_on_simulation_ticked)


# --- Checks -----------------------------------------------------------------

func _run_checks() -> void:
	GameState.reset()
	_passed = 0
	_failed = 0
	_log.clear()
	_info("Godot %s on %s" % [Engine.get_version_info().string, OS.get_name()])
	_info("GPU: %s" % RenderingServer.get_video_adapter_name())
	var backend: String = "Vulkan (Mobile)" if RenderingServer.get_rendering_device() != null else "OpenGL (Compatibility)"
	_info("Renderer: %s" % backend)
	var openxr: XRInterface = XRServer.find_interface("OpenXR")
	_info("OpenXR interface: %s" % ("initialized" if openxr != null and openxr.is_initialized() else "off (expected for this test)"))

	# Autoloads
	_check("EventBus autoload present", get_node_or_null(^"/root/EventBus") != null)
	_check("GameState autoload present", get_node_or_null(^"/root/GameState") != null)
	_check("GameState starts in ORBIT tier", GameState.current_zoom_tier == GameState.ZoomTier.ORBIT)

	# EraData: Mesh visual
	var era := EraData.new()
	era.era_name = "Stone"
	era.building_meshes[&"town_center"] = BoxMesh.new()
	var mesh_visual: Node3D = era.instantiate_building_visual(&"town_center")
	_check("EraData builds MeshInstance3D from Mesh", mesh_visual is MeshInstance3D)
	if mesh_visual != null:
		mesh_visual.free()

	# EraData: PackedScene visual
	var scene_root := Node3D.new()
	var packed := PackedScene.new()
	var pack_result: Error = packed.pack(scene_root)
	scene_root.free()
	era.unit_meshes[&"worker"] = packed
	var scene_visual: Node3D = era.instantiate_unit_visual(&"worker")
	_check("EraData instantiates PackedScene visual", pack_result == OK and scene_visual != null)
	if scene_visual != null:
		scene_visual.free()

	_check("EraData returns null for unknown ID", era.instantiate_building_visual(&"missing") == null)
	_check("EraData has_building / has_unit", era.has_building(&"town_center") and era.has_unit(&"worker"))

	# SpeciesData
	var species := SpeciesData.new()
	species.species_id = &"smoke_species"
	species.traits.append(&"aquatic")
	species.starting_resources[&"food"] = 50
	_check("SpeciesData has_trait", species.has_trait(&"aquatic") and not species.has_trait(&"flying"))
	_check("SpeciesData starting resource", species.get_starting_resource(&"food") == 50)
	_check("SpeciesData missing resource = 0", species.get_starting_resource(&"gold") == 0)

	# Zoom signal round-trip
	var received: Array[int] = []
	var capture := func(new_tier: int, _previous_tier: int) -> void: received.append(new_tier)
	EventBus.zoom_tier_changed.connect(capture)
	GameState.current_zoom_tier = GameState.ZoomTier.RTS
	GameState.current_zoom_tier = GameState.ZoomTier.RTS  # same value: must not re-emit
	EventBus.zoom_tier_changed.disconnect(capture)
	_check("zoom_tier_changed emitted exactly once", received.size() == 1 and received[0] == GameState.ZoomTier.RTS)

	# Faction registration
	var faction_seen: Array[StringName] = []
	var on_faction := func(faction_id: StringName, _s: SpeciesData) -> void: faction_seen.append(faction_id)
	EventBus.faction_registered.connect(on_faction)
	GameState.register_faction(&"smoke_faction", species)
	EventBus.faction_registered.disconnect(on_faction)
	_check("register_faction emits signal", faction_seen.size() == 1 and faction_seen[0] == &"smoke_faction")
	_check("get_faction_species round-trip", GameState.get_faction_species(&"smoke_faction") == species)

	# Region selection
	EventBus.region_selected.emit(&"region_alpha")
	_check("region_selected updates GameState", GameState.selected_region_id == &"region_alpha")

	GameState.reset()
	var color: String = "lime" if _failed == 0 else "red"
	_log.append_text("\n[b][color=%s]%d passed, %d failed[/color][/b]\n" % [color, _passed, _failed])
	print("%d passed, %d failed" % [_passed, _failed])
	_refresh_status()
	if DisplayServer.get_name() == "headless":
		get_tree().quit(1 if _failed > 0 else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
		_log.append_text("[color=lime]PASS[/color]  %s\n" % label)
		print("PASS  %s" % label)
	else:
		_failed += 1
		_log.append_text("[color=red]FAIL[/color]  %s\n" % label)
		print("FAIL  %s" % label)
		push_error("Smoke test failed: %s" % label)


func _info(text: String) -> void:
	_log.append_text("[color=gray]%s[/color]\n" % text)
	print(text)


# --- Live controls ----------------------------------------------------------

func _on_next_tier_pressed() -> void:
	var next: int = (GameState.current_zoom_tier + 1) % GameState.ZoomTier.size()
	GameState.current_zoom_tier = next as GameState.ZoomTier


func _on_sim_pressed() -> void:
	if GameState.is_simulation_running:
		GameState.stop_simulation()
	else:
		GameState.start_simulation()
	_refresh_status()


func _on_rerun_pressed() -> void:
	_run_checks()


func _on_zoom_tier_changed(new_tier: int, previous_tier: int) -> void:
	_info("zoom_tier_changed: %s -> %s" % [_tier_name(previous_tier), _tier_name(new_tier)])
	_refresh_status()


func _on_simulation_ticked(_tick: int) -> void:
	_refresh_status()


func _refresh_status() -> void:
	var sim_text: String = "running" if GameState.is_simulation_running else "stopped"
	_status.text = "Tier: %s   Tick: %d   Sim: %s" % [
		_tier_name(GameState.current_zoom_tier), GameState.tick_count, sim_text]
	_sim_button.text = "Stop sim" if GameState.is_simulation_running else "Start sim"


func _tier_name(tier: int) -> String:
	return str(GameState.ZoomTier.keys()[tier])


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.08, 0.09, 0.11)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 40)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Competitive Evolution AGR — Smoke Test"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", FONT_SIZE + 4)
	column.add_child(title)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", FONT_SIZE)
	_status.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	column.add_child(_status)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	column.add_child(grid)
	_add_button(grid, "Next zoom tier", _on_next_tier_pressed)
	_sim_button = _add_button(grid, "Start sim", _on_sim_pressed)
	_add_button(grid, "Re-run checks", _on_rerun_pressed)

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", LOG_FONT_SIZE)
	_log.add_theme_font_size_override("bold_font_size", LOG_FONT_SIZE + 2)
	column.add_child(_log)


func _add_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
