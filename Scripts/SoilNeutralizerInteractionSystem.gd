extends Node

# Player-facing configuration UI for the Level 30 Soil Neutralizer.
#
# Stand near the machine -> E:
# - ON/OFF
# - interval 1h / 3h / 6h / 12h
# - AUTO / LIME / ACID mode
# - Level 1-3 upgrades

@export_category("Interaction")

@export_range(32.0, 180.0, 1.0)
var interaction_range_pixels: float = 92.0

@export var prompt_text: String = "E"
@export var prompt_world_offset: Vector2 = Vector2(0.0, -28.0)

@export_range(0.0, 12.0, 0.5)
var prompt_bob_amplitude: float = 3.0

@export_range(0.1, 8.0, 0.1)
var prompt_bob_speed: float = 2.2

@export var block_while_aiming: bool = true


@export_category("UI")

@export var canvas_layer: int = 25
@export var panel_width: float = 410.0


@export_category("Debug Logging")

@export var debug_log: bool = false


var _canvas: CanvasLayer
var _prompt_label: Label
var _prompt_phase: float = 0.0

var _overlay: ColorRect
var _panel: PanelContainer

var _level_label: Label
var _range_label: Label
var _dosage_label: Label
var _mode_label: Label
var _target_label: Label
var _status_label: Label
var _next_label: Label
var _money_label: Label
var _message_label: Label

var _power_button: Button
var _interval_buttons: Dictionary = {}
var _mode_buttons: Dictionary = {}
var _upgrade_button: Button

var _nearby_cell: Variant = null
var _active_cell: Variant = null

var _modal_open: bool = false
var _previous_tree_paused: bool = false
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE
var _refresh_accumulator: float = 0.0


# Initializes this system when the node becomes ready.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()

	if not SoilNeutralizerSystem.machine_state_changed.is_connected(
		_on_machine_state_changed
	):
		SoilNeutralizerSystem.machine_state_changed.connect(
			_on_machine_state_changed
		)


# Updates this system every frame.
func _process(delta: float) -> void:
	if _modal_open:
		_refresh_accumulator += delta

		if _refresh_accumulator >= 0.20:
			_refresh_accumulator = 0.0
			_refresh_modal()

		return

	_refresh_prompt(delta)

	if _can_open_from_keyboard():
		open_nearby_machine()


# Handles direct player input.
func _input(event: InputEvent) -> void:
	if not _modal_open:
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey

		if (
			key_event.pressed
			and not key_event.echo
			and (
				key_event.keycode == KEY_ESCAPE
				or (
					InputMap.has_action("interact")
					and event.is_action_pressed("interact")
				)
			)
		):
			close_config()
			get_viewport().set_input_as_handled()


# ------------------------------------------------------------
# Prompt / machine arbitration
# ------------------------------------------------------------

# Refreshes the prompt.
func _refresh_prompt(delta: float) -> void:
	if (
		_prompt_label == null
		or _modal_open
		or get_tree().paused
		or BuildSystem.is_active()
	):
		_set_prompt_visible(false)
		_nearby_cell = null
		return

	if (
		block_while_aiming
		and InputMap.has_action("aim_mode")
		and Input.is_action_pressed("aim_mode")
	):
		_set_prompt_visible(false)
		_nearby_cell = null
		return

	var player: CharacterBody2D = _find_player()

	if player == null:
		_set_prompt_visible(false)
		_nearby_cell = null
		return

	var nearest: Variant = SoilNeutralizerSystem.get_nearest_machine_cell(
		player.global_position,
		interaction_range_pixels
	)

	if nearest == null:
		_set_prompt_visible(false)
		_nearby_cell = null
		return

	var cell: Vector2i = nearest
	var machine_world: Vector2 = SoilNeutralizerSystem.get_machine_world_position(
		cell
	)

	if machine_world == Vector2.INF:
		_set_prompt_visible(false)
		_nearby_cell = null
		return

	var own_distance: float = player.global_position.distance_to(
		machine_world
	)

	# Existing machine family wins ties in stable order:
	# Sprinkler -> Fertilizer -> Neutralizer.
	var sprinkler_cell: Variant = SprinklerSystem.get_nearest_sprinkler_cell(
		player.global_position,
		interaction_range_pixels
	)

	if sprinkler_cell != null:
		var sprinkler_world: Vector2 = SprinklerSystem.get_sprinkler_world_position(
			sprinkler_cell
		)

		if (
			sprinkler_world != Vector2.INF
			and player.global_position.distance_to(
				sprinkler_world
			) <= own_distance
		):
			_set_prompt_visible(false)
			_nearby_cell = null
			return

	var fertilizer_cell: Variant = FertilizerInjectorSystem.get_nearest_machine_cell(
		player.global_position,
		interaction_range_pixels
	)

	if fertilizer_cell != null:
		var fertilizer_world: Vector2 = FertilizerInjectorSystem.get_machine_world_position(
			fertilizer_cell
		)

		if (
			fertilizer_world != Vector2.INF
			and player.global_position.distance_to(
				fertilizer_world
			) <= own_distance
		):
			_set_prompt_visible(false)
			_nearby_cell = null
			return

	# If a Plant Protection Station is strictly closer, its E prompt owns
	# the interaction. Existing machine type keeps equal-distance ties.
	var protection_system: Node = get_node_or_null(
		"/root/PlantProtectionStationSystem"
	)

	if (
		protection_system != null
		and protection_system.has_method(
			"get_nearest_machine_cell"
		)
	):
		var protection_cell: Variant = protection_system.call(
			"get_nearest_machine_cell",
			player.global_position,
			interaction_range_pixels
		)

		if protection_cell != null:
			var protection_world: Vector2 = protection_system.call(
				"get_machine_world_position",
				protection_cell
			)

			if (
				protection_world != Vector2.INF
				and player.global_position.distance_to(
					protection_world
				)
				< player.global_position.distance_to(
					machine_world
				)
			):
				_set_prompt_visible(false)
				_nearby_cell = null
				return

	_nearby_cell = cell
	_prompt_phase += delta * prompt_bob_speed

	var bob: float = sin(_prompt_phase) * prompt_bob_amplitude
	var screen_position: Vector2 = (
		get_viewport().get_canvas_transform()
		* machine_world
	)

	_prompt_label.position = (
		screen_position
		+ prompt_world_offset
		+ Vector2(0.0, bob)
		- _prompt_label.size * 0.5
	)
	_set_prompt_visible(true)


# Checks whether open from keyboard is allowed.
func _can_open_from_keyboard() -> bool:
	if (
		_modal_open
		or _nearby_cell == null
		or get_tree().paused
		or BuildSystem.is_active()
	):
		return false

	if (
		block_while_aiming
		and InputMap.has_action("aim_mode")
		and Input.is_action_pressed("aim_mode")
	):
		return false

	return (
		InputMap.has_action("interact")
		and Input.is_action_just_pressed("interact")
	)


# Finds the player.
func _find_player() -> CharacterBody2D:
	var candidate: Variant = SaveSystem.get("_player")

	if (
		is_instance_valid(candidate)
		and candidate is CharacterBody2D
	):
		return candidate as CharacterBody2D

	return null


# Sets the prompt visible.
func _set_prompt_visible(value: bool) -> void:
	if _prompt_label != null:
		_prompt_label.visible = value


# ------------------------------------------------------------
# Modal
# ------------------------------------------------------------

# Opens the nearby machine.
func open_nearby_machine() -> bool:
	if _nearby_cell == null:
		return false

	return open_config(_nearby_cell)


# Opens the config.
func open_config(cell: Vector2i) -> bool:
	if not SoilNeutralizerSystem.has_machine(cell):
		return false

	_active_cell = cell
	_modal_open = true
	_refresh_accumulator = 0.0

	_previous_tree_paused = get_tree().paused
	_previous_mouse_mode = Input.mouse_mode

	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_set_prompt_visible(false)
	_overlay.visible = true
	_message_label.text = ""

	_refresh_modal()
	call_deferred("_enforce_modal_mouse")
	return true


# Closes the config.
func close_config() -> void:
	if not _modal_open:
		return

	_modal_open = false
	_active_cell = null
	_overlay.visible = false

	get_tree().paused = _previous_tree_paused
	Input.mouse_mode = _previous_mouse_mode


# Checks whether this interface is currently open.
func is_open() -> bool:
	return _modal_open


# Enforces the modal mouse.
func _enforce_modal_mouse() -> void:
	if _modal_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------
# Refresh
# ------------------------------------------------------------

# Refreshes the modal.
func _refresh_modal() -> void:
	if (
		not _modal_open
		or _active_cell == null
	):
		return

	var cell: Vector2i = _active_cell

	if not SoilNeutralizerSystem.has_machine(cell):
		close_config()
		return

	var state: Dictionary = SoilNeutralizerSystem.get_machine_state(
		cell
	)

	if state.is_empty():
		close_config()
		return

	var level: int = int(state.get("level", 1))
	var max_level: int = int(state.get("max_level", 3))
	var radius: int = int(state.get("radius", 0))
	var dosage: float = float(
		state.get("ph_dosage", 0.0)
	)
	var mode: StringName = StringName(
		state.get(
			"mode",
			SoilNeutralizerSystem.MODE_AUTO
		)
	)
	var enabled: bool = bool(state.get("enabled", true))
	var interval: int = int(
		state.get("interval_minutes", 180)
	)
	var next_minutes: int = int(
		state.get("minutes_until_next", -1)
	)

	_level_label.text = "%d / %d" % [
		level,
		max_level
	]
	_range_label.text = "%d tiles" % radius
	_dosage_label.text = "±%.2f pH" % dosage
	_mode_label.text = _mode_text(mode)
	_target_label.text = "Plant-safe range"

	if enabled:
		_status_label.text = "ON • %s" % _interval_text(
			interval
		)
		_status_label.modulate = Color(
			0.72,
			1.0,
			0.72,
			1.0
		)
		_power_button.text = "TURN OFF"
		_next_label.text = _minutes_text(
			next_minutes
		)
	else:
		_status_label.text = "OFF"
		_status_label.modulate = Color(
			1.0,
			0.66,
			0.50,
			1.0
		)
		_power_button.text = "TURN ON"
		_next_label.text = "DISABLED"

	_money_label.text = "$%d" % EconomySystem.get_money()

	for interval_variant: Variant in _interval_buttons.keys():
		var button := _interval_buttons[interval_variant] as Button

		if button != null:
			button.button_pressed = (
				int(interval_variant) == interval
			)

	for mode_variant: Variant in _mode_buttons.keys():
		var button := _mode_buttons[mode_variant] as Button

		if button != null:
			button.button_pressed = (
				StringName(mode_variant) == mode
			)

	if level >= max_level:
		_upgrade_button.text = "MAX LEVEL"
		_upgrade_button.disabled = true
	else:
		var cost: int = SoilNeutralizerSystem.get_upgrade_cost(
			cell
		)
		_upgrade_button.text = "UPGRADE TO L%d • $%d" % [
			level + 1,
			cost
		]
		_upgrade_button.disabled = (
			not EconomySystem.can_afford(cost)
		)


# Handles the machine state changed signal or callback.
func _on_machine_state_changed(
	cell: Vector2i,
	_state: Dictionary
) -> void:
	if (
		_modal_open
		and _active_cell != null
		and cell == _active_cell
	):
		_refresh_modal()


# ------------------------------------------------------------
# Actions
# ------------------------------------------------------------

# Handles the power pressed signal or callback.
func _on_power_pressed() -> void:
	if _active_cell == null:
		return

	var cell: Vector2i = _active_cell
	var enabled: bool = SoilNeutralizerSystem.is_machine_enabled(
		cell
	)

	SoilNeutralizerSystem.set_machine_enabled(
		cell,
		not enabled
	)

	_message_label.text = (
		"Automatic pH control enabled."
		if not enabled
		else "Automatic pH control disabled."
	)


# Handles the interval pressed signal or callback.
func _on_interval_pressed(interval: int) -> void:
	if _active_cell == null:
		return

	var result: Dictionary = SoilNeutralizerSystem.set_machine_interval(
		_active_cell,
		interval
	)

	_message_label.text = (
		"Interval set to %s." % _interval_text(interval)
		if bool(result.get("ok", false))
		else "Interval change failed."
	)


# Handles the mode pressed signal or callback.
func _on_mode_pressed(mode: StringName) -> void:
	if _active_cell == null:
		return

	var result: Dictionary = SoilNeutralizerSystem.set_machine_mode(
		_active_cell,
		mode
	)

	if not bool(result.get("ok", false)):
		_message_label.text = "Mode change failed."
		return

	match mode:
		SoilNeutralizerSystem.MODE_LIME:
			_message_label.text = "Mode: raise pH toward target."
		SoilNeutralizerSystem.MODE_ACID:
			_message_label.text = "Mode: lower pH toward target."
		_:
			_message_label.text = "Mode: automatic plant-safe pH."


# Handles the upgrade pressed signal or callback.
func _on_upgrade_pressed() -> void:
	if _active_cell == null:
		return

	var result: Dictionary = SoilNeutralizerSystem.upgrade_machine(
		_active_cell
	)

	if bool(result.get("ok", false)):
		_message_label.text = "Machine upgraded."
	else:
		var reason: String = String(
			result.get("reason", "")
		)

		if reason == AutomationMachineBase.REASON_INSUFFICIENT_MONEY:
			_message_label.text = "Not enough money."
		elif reason == AutomationMachineBase.REASON_MAX_LEVEL:
			_message_label.text = "Already at maximum level."
		else:
			_message_label.text = "Upgrade unavailable."


# ------------------------------------------------------------
# UI construction
# ------------------------------------------------------------

# Builds the UI.
func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "SoilNeutralizerCanvas"
	_canvas.layer = canvas_layer
	_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_canvas)

	_prompt_label = Label.new()
	_prompt_label.text = prompt_text
	_prompt_label.visible = false
	_prompt_label.size = Vector2(28.0, 28.0)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_label.add_theme_font_size_override(
		"font_size",
		17
	)
	_prompt_label.add_theme_color_override(
		"font_color",
		Color(
			0.78,
			0.88,
			1.0,
			1.0
		)
	)
	_prompt_label.add_theme_color_override(
		"font_outline_color",
		Color(
			0.01,
			0.01,
			0.02,
			0.95
		)
	)
	_prompt_label.add_theme_constant_override(
		"outline_size",
		3
	)
	_canvas.add_child(_prompt_label)

	_overlay = ColorRect.new()
	_overlay.visible = false
	_overlay.color = Color(
		0.0,
		0.0,
		0.0,
		0.50
	)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas.add_child(_overlay)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(
		panel_width,
		0.0
	)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(
			Color(
				0.035,
				0.040,
				0.075,
				0.98
			),
			Color(
				0.52,
				0.66,
				0.94,
				0.92
			),
			2,
			10
		)
	)
	_panel.set_anchors_preset(
		Control.PRESET_CENTER
	)
	_panel.position = Vector2(
		-panel_width * 0.5,
		-270.0
	)
	_overlay.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override(
		"margin_left",
		18
	)
	margin.add_theme_constant_override(
		"margin_right",
		18
	)
	margin.add_theme_constant_override(
		"margin_top",
		14
	)
	margin.add_theme_constant_override(
		"margin_bottom",
		14
	)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(
		"separation",
		8
	)
	margin.add_child(column)

	var title := _make_label(
		"SOIL NEUTRALIZER",
		19,
		Color(
			0.82,
			0.88,
			1.0,
			1.0
		)
	)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var subtitle := _make_label(
		"AUTOMATED SOIL CHEMISTRY",
		10,
		Color(
			0.64,
			0.69,
			0.84,
			1.0
		)
	)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)

	column.add_child(HSeparator.new())

	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override(
		"h_separation",
		18
	)
	stats.add_theme_constant_override(
		"v_separation",
		5
	)
	column.add_child(stats)

	_level_label = _add_stat(
		stats,
		"LEVEL"
	)
	_range_label = _add_stat(
		stats,
		"RANGE"
	)
	_dosage_label = _add_stat(
		stats,
		"DOSAGE"
	)
	_mode_label = _add_stat(
		stats,
		"MODE"
	)
	_target_label = _add_stat(
		stats,
		"TARGET"
	)
	_status_label = _add_stat(
		stats,
		"STATUS"
	)
	_next_label = _add_stat(
		stats,
		"NEXT CYCLE"
	)
	_money_label = _add_stat(
		stats,
		"MONEY"
	)

	column.add_child(HSeparator.new())

	var power_row := HBoxContainer.new()
	column.add_child(power_row)

	var power_caption := _make_label(
		"AUTOMATIC pH CONTROL",
		12,
		Color(
			0.76,
			0.80,
			0.92,
			1.0
		)
	)
	power_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	power_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	power_row.add_child(power_caption)

	_power_button = _make_button(
		"TURN OFF",
		118.0
	)
	_power_button.pressed.connect(
		_on_power_pressed
	)
	power_row.add_child(_power_button)

	column.add_child(
		_make_label(
			"CYCLE INTERVAL",
			11,
			Color(
				0.62,
				0.67,
				0.82,
				1.0
			)
		)
	)

	var interval_row := HBoxContainer.new()
	interval_row.add_theme_constant_override(
		"separation",
		6
	)
	column.add_child(interval_row)

	for interval: int in SoilNeutralizerSystem.get_interval_options():
		var button := _make_button(
			_interval_short_text(interval),
			0.0
		)
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(
			_on_interval_pressed.bind(interval)
		)
		interval_row.add_child(button)
		_interval_buttons[interval] = button

	column.add_child(
		_make_label(
			"CONTROL MODE",
			11,
			Color(
				0.62,
				0.67,
				0.82,
				1.0
			)
		)
	)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override(
		"separation",
		6
	)
	column.add_child(mode_row)

	for mode: StringName in SoilNeutralizerSystem.get_mode_options():
		var button := _make_button(
			_mode_text(mode),
			0.0
		)
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(
			_on_mode_pressed.bind(mode)
		)
		mode_row.add_child(button)
		_mode_buttons[mode] = button

	var explanation := _make_label(
		"AUTO follows the compatible pH range of plants in each covered zone.",
		10,
		Color(
			0.62,
			0.67,
			0.78,
			1.0
		)
	)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(explanation)

	column.add_child(HSeparator.new())

	_upgrade_button = _make_button(
		"UPGRADE",
		0.0
	)
	_upgrade_button.pressed.connect(
		_on_upgrade_pressed
	)
	column.add_child(_upgrade_button)

	_message_label = _make_label(
		"",
		11,
		Color(
			0.82,
			0.88,
			1.0,
			1.0
		)
	)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.custom_minimum_size.y = 20.0
	column.add_child(_message_label)

	var close_button := _make_button(
		"CLOSE",
		0.0
	)
	close_button.pressed.connect(
		close_config
	)
	column.add_child(close_button)


# Adds the stat.
func _add_stat(
	grid: GridContainer,
	caption: String
) -> Label:
	var caption_label := _make_label(
		caption,
		10,
		Color(
			0.58,
			0.62,
			0.76,
			1.0
		)
	)
	grid.add_child(caption_label)

	var value_label := _make_label(
		"-",
		12,
		Color(
			0.91,
			0.93,
			1.0,
			1.0
		)
	)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(value_label)
	return value_label


# Creates the label.
func _make_label(
	text_value: String,
	font_size: int,
	color: Color
) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override(
		"font_size",
		font_size
	)
	label.add_theme_color_override(
		"font_color",
		color
	)
	label.add_theme_color_override(
		"font_outline_color",
		Color(
			0.0,
			0.0,
			0.0,
			0.80
		)
	)
	label.add_theme_constant_override(
		"outline_size",
		2
	)
	return label


# Creates the button.
func _make_button(
	text_value: String,
	min_width: float
) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(
		min_width,
		34.0
	)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override(
		"font_size",
		11
	)
	return button


# Creates the panel style.
func _make_panel_style(
	background: Color,
	border: Color,
	border_width: int,
	radius: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.shadow_color = Color(
		0.0,
		0.0,
		0.0,
		0.35
	)
	style.shadow_size = 5
	return style


# ------------------------------------------------------------
# Formatting
# ------------------------------------------------------------

# Formats an interval as short UI text.
func _interval_short_text(minutes: int) -> String:
	return "%dh" % maxi(
		floori(
			float(minutes) / 60.0
		),
		1
	)


# Formats an interval for the configuration UI.
func _interval_text(minutes: int) -> String:
	return "Every %d hours" % maxi(
		floori(
			float(minutes) / 60.0
		),
		1
	)


# Formats game minutes for UI display.
func _minutes_text(minutes: int) -> String:
	if minutes < 0:
		return "DISABLED"

	if minutes == 0:
		return "NOW"

	var hours: int = floori(
		float(minutes) / 60.0
	)
	var remainder: int = minutes % 60

	if hours > 0 and remainder > 0:
		return "%dh %dm" % [
			hours,
			remainder
		]

	if hours > 0:
		return "%dh" % hours

	return "%dm" % remainder


# Formats the current machine mode for display.
func _mode_text(mode: StringName) -> String:
	match mode:
		SoilNeutralizerSystem.MODE_LIME:
			return "LIME"
		SoilNeutralizerSystem.MODE_ACID:
			return "ACID"
		_:
			return "AUTO"
