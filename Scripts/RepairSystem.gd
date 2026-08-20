extends Node

# Repair backend shared by the original-map Repair Corner and player-built anvils.

signal repair_station_opened(station_id: StringName)
signal repair_station_closed(station_id: StringName)


const BUILD_ID_REPAIR_ANVIL: StringName = &"repair_anvil"

# farming_fishing.png source 1, atlas (6,1): the 32x32 anvil/barrel tile.
const REPAIR_TILE_SOURCE_ID: int = 1
const REPAIR_TILE_ATLAS: Vector2i = Vector2i(6, 1)


@export_category("Map")

@export var fixed_station_layer_name: StringName = &"Intersections"


@export_category("Interaction")

@export_range(32.0, 160.0, 1.0)
var interaction_range_pixels: float = 92.0

@export var prompt_world_offset: Vector2 = Vector2(0.0, -28.0)

@export_range(0.0, 12.0, 0.5)
var prompt_bob_pixels: float = 3.0

@export_range(0.5, 6.0, 0.1)
var prompt_bob_speed: float = 2.2

@export_range(0.0, 1.0, 0.01)
var prompt_alpha_min: float = 0.58

@export_range(0.0, 1.0, 0.01)
var prompt_alpha_max: float = 0.92


@export_category("Debug Logging")

@export var debug_log: bool = false


var _tilemap: TileMap
var _player: CharacterBody2D
var _configured: bool = false
var _fixed_station_layer: int = -1

# station_id -> {"id": StringName, "cell": Vector2i, "fixed": bool}
var _stations: Dictionary = {}

var _nearby_station_id: StringName = &""
var _open_station_id: StringName = &""

var _ui_layer: CanvasLayer
var _prompt_label: Label
var _repair_dialog: ConfirmationDialog
var _info_dialog: AcceptDialog

var _previous_tree_paused: bool = false
var _previous_mouse_mode: int = Input.MOUSE_MODE_HIDDEN
var _dialog_state_captured: bool = false


# Initializes this system when the node becomes ready.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()

	if not BuildSystem.build_cell_placed.is_connected(
		_on_build_cell_changed
	):
		BuildSystem.build_cell_placed.connect(
			_on_build_cell_changed
		)

	if not BuildSystem.build_cell_removed.is_connected(
		_on_build_cell_changed
	):
		BuildSystem.build_cell_removed.connect(
			_on_build_cell_changed
		)

	if not BuildSystem.build_world_rebuilt.is_connected(
		_on_build_world_rebuilt
	):
		BuildSystem.build_world_rebuilt.connect(
			_on_build_world_rebuilt
		)

	if debug_log:
		print(
			"[Repair] ready tile_source=",
			REPAIR_TILE_SOURCE_ID,
			" atlas=",
			REPAIR_TILE_ATLAS,
			" range=",
			interaction_range_pixels
		)


# Connects this system to the current world references.
func configure(
	tilemap: TileMap,
	player: CharacterBody2D
) -> void:
	if tilemap == null or player == null:
		push_error(
			"[Repair] configure received missing world references."
		)
		return

	if _tilemap != null and _tilemap != tilemap:
		unconfigure(_tilemap)

	_tilemap = tilemap
	_player = player
	_fixed_station_layer = _find_layer_by_name(
		fixed_station_layer_name
	)

	if _fixed_station_layer < 0:
		push_error(
			"[Repair] TileMap layer not found: %s"
			% String(fixed_station_layer_name)
		)
		return

	_configured = true
	_rebuild_stations_from_world()
	_refresh_prompt()

	if debug_log:
		print(
			"[Repair] configured fixed_layer=",
			_fixed_station_layer,
			" stations=",
			_stations.size()
		)


# Disconnects this system from the current world references.
func unconfigure(tilemap: TileMap) -> void:
	if _tilemap != tilemap:
		return

	_finish_dialog_state()
	_tilemap = null
	_player = null
	_fixed_station_layer = -1
	_configured = false
	_stations.clear()
	_nearby_station_id = &""
	_open_station_id = &""

	if _prompt_label != null:
		_prompt_label.visible = false

	if debug_log:
		print("[Repair] unconfigured")


# Updates this system every frame.
func _process(_delta: float) -> void:
	if not _configured:
		_prompt_label.visible = false
		return

	if (
		_is_dialog_visible()
		or get_tree().paused
		or BuildSystem.is_active()
	):
		_nearby_station_id = &""
		_prompt_label.visible = false
		return

	_find_nearby_station()
	_refresh_prompt()


# Handles direct player input.
func _input(event: InputEvent) -> void:
	if (
		not _configured
		or _is_dialog_visible()
		or get_tree().paused
		or BuildSystem.is_active()
		or Input.is_action_pressed("aim_mode")
	):
		return

	if (
		event.is_action_pressed("interact")
		and _nearby_station_id != &""
	):
		_open_repair_for_current_tool(
			_nearby_station_id
		)
		get_viewport().set_input_as_handled()


# Opens the repair for current tool.
func _open_repair_for_current_tool(
	station_id: StringName
) -> void:
	if not _stations.has(station_id):
		return

	var tool_id: int = Toolsystem.current_tool

	if not Toolsystem.uses_durability(tool_id):
		_show_info(
			"Repair Anvil",
			"%s does not use durability."
			% Toolsystem.get_tool_name(tool_id)
		)
		return

	if Toolsystem.is_broken(tool_id):
		if debug_log:
			print(
				"[Repair] broken tool selected; replacement offered station=",
				station_id,
				" tool=",
				Toolsystem.get_tool_name(tool_id),
				" cost=",
				Toolsystem.get_replacement_cost(tool_id)
			)
		Toolsystem.request_replacement(tool_id)
		return

	var current: int = Toolsystem.get_durability(tool_id)

	if current >= Toolsystem.MAX_DURABILITY:
		_show_info(
			"Repair Anvil",
			"%s is already at 100%% durability."
			% Toolsystem.get_tool_name(tool_id)
		)
		return

	var restored: int = mini(
		Toolsystem.REPAIR_STEP,
		Toolsystem.MAX_DURABILITY - current
	)
	var target: int = mini(
		current + restored,
		Toolsystem.MAX_DURABILITY
	)
	var cost: int = Toolsystem.get_repair_cost(
		tool_id,
		restored
	)
	var money: int = EconomySystem.get_money()

	_open_station_id = station_id
	_repair_dialog.title = "Repair Anvil"
	_repair_dialog.dialog_text = (
		"%s\n\n"
		+ "Durability: %d%% -> %d%%\n"
		+ "Repair: +%d%%\n"
		+ "Cost: $%d\n"
		+ "Money: $%d"
	) % [
		Toolsystem.get_tool_name(tool_id),
		current,
		target,
		restored,
		cost,
		money
	]
	_repair_dialog.get_ok_button().text = (
		"Repair for $%d" % cost
	)
	_repair_dialog.get_ok_button().disabled = (
		not EconomySystem.can_afford(cost)
	)
	_repair_dialog.get_cancel_button().text = "Cancel"

	_capture_dialog_state()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_repair_dialog.popup_centered(
		Vector2i(390, 230)
	)
	repair_station_opened.emit(
		station_id
	)

	if debug_log:
		print(
			"[Repair] open station=",
			station_id,
			" tool=",
			Toolsystem.get_tool_name(tool_id),
			" durability=",
			current,
			"->",
			target,
			" cost=",
			cost
		)


# Handles the repair confirmed signal or callback.
func _on_repair_confirmed() -> void:
	var tool_id: int = Toolsystem.current_tool
	var result: Dictionary = (
		Toolsystem.repair_current_tool()
	)

	if debug_log:
		print(
			"[Repair] confirm tool=",
			Toolsystem.get_tool_name(tool_id),
			" result=",
			result
		)

	_close_repair_dialog()


# Handles the repair canceled signal or callback.
func _on_repair_canceled() -> void:
	_close_repair_dialog()


# Closes the repair dialog.
func _close_repair_dialog() -> void:
	var station_id: StringName = _open_station_id
	_open_station_id = &""

	if _repair_dialog != null:
		_repair_dialog.hide()

	_finish_dialog_state()

	if station_id != &"":
		repair_station_closed.emit(
			station_id
		)


# Shows the info.
func _show_info(
	title_text: String,
	message: String
) -> void:
	_info_dialog.title = title_text
	_info_dialog.dialog_text = message
	_info_dialog.get_ok_button().text = "OK"

	_capture_dialog_state()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_info_dialog.popup_centered(
		Vector2i(360, 170)
	)


# Handles the info closed signal or callback.
func _on_info_closed() -> void:
	if _info_dialog != null:
		_info_dialog.hide()

	_finish_dialog_state()


# Captures the dialog state for save, restore, or validation.
func _capture_dialog_state() -> void:
	if _dialog_state_captured:
		return

	_previous_tree_paused = get_tree().paused
	_previous_mouse_mode = Input.get_mouse_mode()
	_dialog_state_captured = true


# Finishes the dialog state.
func _finish_dialog_state() -> void:
	if not _dialog_state_captured:
		return

	get_tree().paused = _previous_tree_paused
	Input.set_mouse_mode(
		_previous_mouse_mode
	)
	_dialog_state_captured = false


# Checks the dialog visible condition.
func _is_dialog_visible() -> bool:
	return (
		(
			_repair_dialog != null
			and _repair_dialog.visible
		)
		or (
			_info_dialog != null
			and _info_dialog.visible
		)
	)


# Rebuilds the stations from world.
func _rebuild_stations_from_world() -> void:
	if not _configured:
		return

	_stations.clear()

	var fixed_count: int = 0
	var built_count: int = 0

	for cell: Vector2i in _tilemap.get_used_cells(
		_fixed_station_layer
	):
		if (
			_tilemap.get_cell_source_id(
				_fixed_station_layer,
				cell
			) != REPAIR_TILE_SOURCE_ID
		):
			continue

		if (
			_tilemap.get_cell_atlas_coords(
				_fixed_station_layer,
				cell
			) != REPAIR_TILE_ATLAS
		):
			continue

		var station_id := StringName(
			"repair_fixed_%d_%d"
			% [cell.x, cell.y]
		)

		_stations[station_id] = {
			"id": station_id,
			"cell": cell,
			"fixed": true
		}
		fixed_count += 1

	var built_cells: Dictionary = (
		BuildSystem.get_player_built_cells()
	)

	for cell_variant: Variant in built_cells.keys():
		if not (cell_variant is Vector2i):
			continue

		var cell: Vector2i = cell_variant
		var record_variant: Variant = built_cells[cell]

		if typeof(record_variant) != TYPE_DICTIONARY:
			continue

		var record: Dictionary = record_variant
		var object_id := StringName(
			record.get(
				"object_build_id",
				&""
			)
		)

		if object_id != BUILD_ID_REPAIR_ANVIL:
			continue

		var station_id := StringName(
			"repair_build_%d_%d"
			% [cell.x, cell.y]
		)

		_stations[station_id] = {
			"id": station_id,
			"cell": cell,
			"fixed": false
		}
		built_count += 1

	if debug_log:
		print(
			"[Repair] stations rebuilt fixed=",
			fixed_count,
			" built=",
			built_count,
			" total=",
			_stations.size(),
			" cells=",
			_station_debug_cells()
		)


# Finds the nearby station.
func _find_nearby_station() -> void:
	_nearby_station_id = &""

	if (
		_player == null
		or _tilemap == null
	):
		return

	var best_distance: float = INF

	for station_id_variant: Variant in _stations.keys():
		var station_id := StringName(
			String(station_id_variant)
		)
		var station: Dictionary = _stations[station_id]
		var cell_variant: Variant = station.get(
			"cell",
			null
		)

		if not (cell_variant is Vector2i):
			continue

		var cell: Vector2i = cell_variant
		var world_position: Vector2 = (
			_tilemap.to_global(
				_tilemap.map_to_local(cell)
			)
		)
		var distance: float = (
			_player.global_position.distance_to(
				world_position
			)
		)

		if (
			distance <= interaction_range_pixels
			and distance < best_distance
		):
			best_distance = distance
			_nearby_station_id = station_id


# Refreshes the prompt.
func _refresh_prompt() -> void:
	var should_show: bool = (
		_configured
		and not _is_dialog_visible()
		and _nearby_station_id != &""
		and not get_tree().paused
		and not BuildSystem.is_active()
	)

	_prompt_label.visible = should_show

	if not should_show:
		return

	var station: Dictionary = _stations.get(
		_nearby_station_id,
		{}
	)
	var cell_variant: Variant = station.get(
		"cell",
		null
	)

	if not (cell_variant is Vector2i):
		_prompt_label.visible = false
		return

	var cell: Vector2i = cell_variant
	var world_position: Vector2 = (
		_tilemap.to_global(
			_tilemap.map_to_local(cell)
		)
	)
	var screen_position: Vector2 = (
		get_viewport().get_canvas_transform()
		* (world_position + prompt_world_offset)
	)
	var animation_time: float = (
		float(Time.get_ticks_msec()) / 1000.0
	)
	var bob: float = sin(
		animation_time * prompt_bob_speed
	) * prompt_bob_pixels
	var pulse_01: float = (
		sin(
			animation_time
			* prompt_bob_speed
			* 0.85
		) * 0.5
		+ 0.5
	)
	var alpha: float = lerpf(
		prompt_alpha_min,
		prompt_alpha_max,
		pulse_01
	)

	_prompt_label.position = (
		screen_position
		- _prompt_label.size * 0.5
		+ Vector2(0.0, bob)
	)
	_prompt_label.modulate = Color(
		1.0,
		1.0,
		1.0,
		alpha
	)


# Creates the UI.
func _create_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "RepairSystemUI"
	_ui_layer.layer = 26
	add_child(_ui_layer)

	_prompt_label = Label.new()
	_prompt_label.name = "RepairWorldPrompt"
	_prompt_label.set_anchors_preset(
		Control.PRESET_TOP_LEFT
	)
	_prompt_label.position = Vector2.ZERO
	_prompt_label.custom_minimum_size = Vector2(
		28.0,
		28.0
	)
	_prompt_label.size = Vector2(
		28.0,
		28.0
	)
	_prompt_label.text = "E"
	_prompt_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_prompt_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	_prompt_label.add_theme_font_size_override(
		"font_size",
		17
	)
	_prompt_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.97, 0.76, 1.0)
	)
	_prompt_label.add_theme_color_override(
		"font_outline_color",
		Color(0.01, 0.015, 0.01, 0.95)
	)
	_prompt_label.add_theme_constant_override(
		"outline_size",
		3
	)
	_prompt_label.visible = false
	_prompt_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_ui_layer.add_child(_prompt_label)

	_repair_dialog = ConfirmationDialog.new()
	_repair_dialog.name = "RepairConfirmation"
	_repair_dialog.process_mode = (
		Node.PROCESS_MODE_ALWAYS
	)
	_repair_dialog.unresizable = true
	_repair_dialog.exclusive = true
	_repair_dialog.always_on_top = true
	_repair_dialog.confirmed.connect(
		_on_repair_confirmed
	)
	_repair_dialog.canceled.connect(
		_on_repair_canceled
	)
	_repair_dialog.close_requested.connect(
		_on_repair_canceled
	)
	add_child(_repair_dialog)

	_info_dialog = AcceptDialog.new()
	_info_dialog.name = "RepairInfo"
	_info_dialog.process_mode = (
		Node.PROCESS_MODE_ALWAYS
	)
	_info_dialog.unresizable = true
	_info_dialog.exclusive = true
	_info_dialog.always_on_top = true
	_info_dialog.confirmed.connect(
		_on_info_closed
	)
	_info_dialog.canceled.connect(
		_on_info_closed
	)
	_info_dialog.close_requested.connect(
		_on_info_closed
	)
	add_child(_info_dialog)


# Finds the layer by name.
func _find_layer_by_name(
	layer_name: StringName
) -> int:
	if _tilemap == null:
		return -1

	for index: int in range(
		_tilemap.get_layers_count()
	):
		if (
			StringName(
				_tilemap.get_layer_name(index)
			) == layer_name
		):
			return index

	return -1


# Handles the build cell changed signal or callback.
func _on_build_cell_changed(
	_cell: Vector2i,
	_build_id: StringName,
	_value: int
) -> void:
	if not _configured:
		return

	call_deferred(
		"_rebuild_stations_from_world"
	)


# Handles the build world rebuilt signal or callback.
func _on_build_world_rebuilt() -> void:
	if not _configured:
		return

	_rebuild_stations_from_world()
	_find_nearby_station()
	_refresh_prompt()


# Handles station debug cells.
func _station_debug_cells() -> Array:
	var result: Array = []

	for station_id_variant: Variant in _stations.keys():
		var station_id := StringName(
			String(station_id_variant)
		)
		var station: Dictionary = _stations[station_id]
		result.append({
			"id": String(station_id),
			"cell": station.get(
				"cell",
				Vector2i.ZERO
			),
			"fixed": bool(
				station.get(
					"fixed",
					false
				)
			)
		})

	return result
