extends Node

# Player-facing Field Sprinkler configuration UI.
#
# Uses the same AutomationMachineBase API as the other machine panels; only
# sprinkler-specific moisture/event labels remain unique.
#
# Interaction:
# - Stand near a sprinkler.
# - Press the existing "interact" action (E).
# - Configure ON/OFF, watering interval, and machine upgrades.
#
# The UI is generated entirely from this script, so no scene file is needed.

@export_category("Interaction")

@export_range(32.0, 180.0, 1.0)
var interaction_range_pixels: float = 92.0

@export var prompt_text: String = "E"

# World-space style used by the other interactable objects:
# pale floating E above the object, with a dark outline and a gentle bob/pulse.
@export var prompt_world_offset: Vector2 = Vector2(0.0, -28.0)

@export_range(0.0, 12.0, 0.5)
var prompt_bob_amplitude: float = 3.0

@export_range(0.1, 8.0, 0.1)
var prompt_bob_speed: float = 2.2

@export_range(0.0, 1.0, 0.05)
var prompt_alpha_min: float = 0.58

@export_range(0.0, 1.0, 0.05)
var prompt_alpha_max: float = 0.92

# Do not steal E from normal tool use while the player is holding Aim Mode.
@export var block_while_aiming: bool = true


@export_category("UI")

@export var canvas_layer: int = 24

@export var panel_width: float = 390.0

@export var show_cell_coordinates: bool = false


@export_category("Debug Logging")

@export var debug_log: bool = false


var _canvas: CanvasLayer

var _prompt_label: Label
var _prompt_phase: float = 0.0

var _overlay: ColorRect
var _config_panel: PanelContainer

var _title_label: Label
var _subtitle_label: Label
var _level_label: Label
var _range_label: Label
var _moisture_label: Label
var _status_label: Label
var _next_label: Label
var _money_label: Label

var _power_button: Button
var _interval_buttons: Dictionary = {}
var _upgrade_button: Button
var _close_button: Button

var _nearby_cell: Variant = null
var _active_cell: Variant = null

var _modal_open: bool = false
var _previous_tree_paused: bool = false
var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE

var _refresh_accumulator: float = 0.0
var _message_text: String = ""
var _message_timer: float = 0.0


# Initializes this system when the node becomes ready.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_ui()

	if not SprinklerSystem.machine_state_changed.is_connected(
		_on_machine_state_changed
	):
		SprinklerSystem.machine_state_changed.connect(
			_on_machine_state_changed
		)

	if debug_log:
		print(
			"[SprinklerUI] ready range=",
			interaction_range_pixels,
			" layer=",
			canvas_layer
		)


# Updates this system every frame.
func _process(delta: float) -> void:
	if _modal_open:
		_refresh_accumulator += delta

		if _message_timer > 0.0:
			_message_timer = maxf(
				_message_timer - delta,
				0.0
			)

			if _message_timer <= 0.0:
				_message_text = ""

		if _refresh_accumulator >= 0.20:
			_refresh_accumulator = 0.0
			_refresh_modal()

		return

	_refresh_prompt(delta)

	if _can_open_from_keyboard():
		open_nearby_sprinkler()


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


# Builds the UI.
func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "SprinklerInteractionCanvas"
	_canvas.layer = canvas_layer
	_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_canvas)

	_build_prompt()
	_build_config_modal()


# Builds the prompt.
func _build_prompt() -> void:
	_prompt_label = Label.new()
	_prompt_label.name = "FloatingInteractPrompt"
	_prompt_label.text = prompt_text
	_prompt_label.visible = false
	_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_label.custom_minimum_size = Vector2(
		28.0,
		28.0
	)
	_prompt_label.size = Vector2(
		28.0,
		28.0
	)
	_prompt_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_prompt_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)

	# Same visual direction as Seed Storage / Repair:
	# pale white-yellow character with a small dark outline.
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

	_canvas.add_child(_prompt_label)


# Builds the config modal.
func _build_config_modal() -> void:
	_overlay = ColorRect.new()
	_overlay.name = "SprinklerOverlay"
	_overlay.visible = false
	_overlay.color = Color(0.0, 0.0, 0.0, 0.48)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas.add_child(_overlay)

	_config_panel = PanelContainer.new()
	_config_panel.name = "SprinklerConfigPanel"
	_config_panel.custom_minimum_size = Vector2(
		panel_width,
		0.0
	)
	_config_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_config_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style(
			Color(0.035, 0.055, 0.04, 0.97),
			Color(0.68, 0.92, 0.54, 0.88),
			2,
			10
		)
	)
	_config_panel.set_anchors_preset(
		Control.PRESET_CENTER
	)
	_config_panel.position = Vector2(
		-panel_width * 0.5,
		-220.0
	)
	_overlay.add_child(_config_panel)

	var outer_margin := MarginContainer.new()
	outer_margin.add_theme_constant_override(
		"margin_left",
		18
	)
	outer_margin.add_theme_constant_override(
		"margin_right",
		18
	)
	outer_margin.add_theme_constant_override(
		"margin_top",
		16
	)
	outer_margin.add_theme_constant_override(
		"margin_bottom",
		16
	)
	_config_panel.add_child(outer_margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override(
		"separation",
		9
	)
	outer_margin.add_child(column)

	_title_label = _make_label(
		"FIELD SPRINKLER",
		19,
		Color(0.90, 1.0, 0.82, 1.0)
	)
	_title_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	column.add_child(_title_label)

	_subtitle_label = _make_label(
		"",
		11,
		Color(0.70, 0.80, 0.71, 0.95)
	)
	_subtitle_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	column.add_child(_subtitle_label)

	column.add_child(_make_separator())

	var stat_grid := GridContainer.new()
	stat_grid.columns = 2
	stat_grid.add_theme_constant_override(
		"h_separation",
		18
	)
	stat_grid.add_theme_constant_override(
		"v_separation",
		6
	)
	column.add_child(stat_grid)

	stat_grid.add_child(
		_make_stat_caption("LEVEL")
	)
	_level_label = _make_stat_value()
	stat_grid.add_child(_level_label)

	stat_grid.add_child(
		_make_stat_caption("RANGE")
	)
	_range_label = _make_stat_value()
	stat_grid.add_child(_range_label)

	stat_grid.add_child(
		_make_stat_caption("WATERING")
	)
	_moisture_label = _make_stat_value()
	stat_grid.add_child(_moisture_label)

	stat_grid.add_child(
		_make_stat_caption("STATUS")
	)
	_status_label = _make_stat_value()
	stat_grid.add_child(_status_label)

	stat_grid.add_child(
		_make_stat_caption("NEXT WATERING")
	)
	_next_label = _make_stat_value()
	stat_grid.add_child(_next_label)

	stat_grid.add_child(
		_make_stat_caption("MONEY")
	)
	_money_label = _make_stat_value()
	stat_grid.add_child(_money_label)

	column.add_child(_make_separator())

	var power_row := HBoxContainer.new()
	power_row.add_theme_constant_override(
		"separation",
		10
	)
	column.add_child(power_row)

	var power_caption := _make_label(
		"AUTOMATIC WATERING",
		12,
		Color(0.78, 0.86, 0.79, 1.0)
	)
	power_caption.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	power_caption.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	power_row.add_child(power_caption)

	_power_button = _make_button(
		"TURN OFF",
		118.0
	)
	_power_button.pressed.connect(
		_on_power_pressed
	)
	power_row.add_child(_power_button)

	var interval_caption := _make_label(
		"WATERING INTERVAL",
		12,
		Color(0.78, 0.86, 0.79, 1.0)
	)
	column.add_child(interval_caption)

	var interval_row := HBoxContainer.new()
	interval_row.add_theme_constant_override(
		"separation",
		6
	)
	column.add_child(interval_row)

	for minutes: int in SprinklerSystem.get_interval_options():
		var interval_button := _make_button(
			_interval_short_text(minutes),
			0.0
		)
		interval_button.size_flags_horizontal = (
			Control.SIZE_EXPAND_FILL
		)
		interval_button.pressed.connect(
			_on_interval_pressed.bind(minutes)
		)
		interval_row.add_child(interval_button)
		_interval_buttons[minutes] = (
			interval_button
		)

	column.add_child(_make_separator())

	_upgrade_button = _make_button(
		"UPGRADE",
		0.0
	)
	_upgrade_button.custom_minimum_size.y = 42.0
	_upgrade_button.pressed.connect(
		_on_upgrade_pressed
	)
	column.add_child(_upgrade_button)

	var info_label := _make_label(
		"Upgrades increase both sprinkler range and watering strength.",
		11,
		Color(0.67, 0.75, 0.68, 0.92)
	)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	column.add_child(info_label)

	_close_button = _make_button(
		"CLOSE",
		0.0
	)
	_close_button.pressed.connect(
		close_config
	)
	column.add_child(_close_button)


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
		Color(0.01, 0.02, 0.01, 1.0)
	)
	label.add_theme_constant_override(
		"outline_size",
		2
	)
	return label


# Creates the stat caption.
func _make_stat_caption(
	text_value: String
) -> Label:
	var label := _make_label(
		text_value,
		11,
		Color(0.62, 0.72, 0.64, 0.95)
	)
	label.custom_minimum_size.x = 135.0
	return label


# Creates the stat value.
func _make_stat_value() -> Label:
	var label := _make_label(
		"-",
		13,
		Color(0.94, 0.98, 0.94, 1.0)
	)
	label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	return label


# Creates the separator.
func _make_separator() -> HSeparator:
	var separator := HSeparator.new()
	separator.add_theme_constant_override(
		"separation",
		6
	)
	return separator


# Creates the button.
func _make_button(
	text_value: String,
	minimum_width: float
) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(
		minimum_width,
		34.0
	)
	button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)

	button.add_theme_font_size_override(
		"font_size",
		12
	)

	button.add_theme_stylebox_override(
		"normal",
		_make_button_style(false, false)
	)
	button.add_theme_stylebox_override(
		"hover",
		_make_button_style(false, true)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_make_button_style(true, true)
	)
	button.add_theme_stylebox_override(
		"disabled",
		_make_disabled_button_style()
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


# Creates the button style.
func _make_button_style(
	selected: bool,
	hovered: bool
) -> StyleBoxFlat:
	var background := Color(
		0.09,
		0.14,
		0.10,
		0.82
	)
	var border := Color(
		0.42,
		0.58,
		0.45,
		0.62
	)
	var border_width := 1

	if hovered:
		background = Color(
			0.14,
			0.21,
			0.15,
			0.92
		)
		border = Color(
			0.70,
			0.90,
			0.54,
			0.86
		)

	if selected:
		background = Color(
			0.22,
			0.32,
			0.18,
			0.94
		)
		border = Color(
			0.78,
			1.0,
			0.48,
			1.0
		)
		border_width = 2

	return _make_panel_style(
		background,
		border,
		border_width,
		6
	)


# Creates the disabled button style.
func _make_disabled_button_style() -> StyleBoxFlat:
	return _make_panel_style(
		Color(0.07, 0.08, 0.07, 0.55),
		Color(0.30, 0.34, 0.30, 0.40),
		1,
		6
	)


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

	var player := _find_player()

	if player == null:
		_set_prompt_visible(false)
		_nearby_cell = null
		return

	var nearest: Variant = (
		SprinklerSystem.get_nearest_machine_cell(
			player.global_position,
			interaction_range_pixels
		)
	)

	_nearby_cell = nearest

	if nearest == null:
		_set_prompt_visible(false)
		return

	var cell: Vector2i = nearest
	var world_position: Vector2 = (
		SprinklerSystem.get_machine_world_position(
			cell
		)
	)

	if world_position == Vector2.INF:
		_set_prompt_visible(false)
		return

	# Machine-family prompt arbitration: if a Fertilizer Injector is closer
	# than this sprinkler, its E prompt owns the interaction instead.
	var fertilizer_system: Node = get_node_or_null(
		"/root/FertilizerInjectorSystem"
	)

	if (
		fertilizer_system != null
		and fertilizer_system.has_method(
			"get_nearest_machine_cell"
		)
	):
		var fertilizer_cell: Variant = fertilizer_system.call(
			"get_nearest_machine_cell",
			player.global_position,
			interaction_range_pixels
		)

		if fertilizer_cell != null:
			var fertilizer_world: Vector2 = fertilizer_system.call(
				"get_machine_world_position",
				fertilizer_cell
			)

			if (
				fertilizer_world != Vector2.INF
				and player.global_position.distance_to(
					fertilizer_world
				)
				< player.global_position.distance_to(
					world_position
				)
			):
				_set_prompt_visible(false)
				_nearby_cell = null
				return

	# If a Soil Neutralizer is closer, its E prompt owns the interaction.
	var neutralizer_system: Node = get_node_or_null(
		"/root/SoilNeutralizerSystem"
	)

	if (
		neutralizer_system != null
		and neutralizer_system.has_method(
			"get_nearest_machine_cell"
		)
	):
		var neutralizer_cell: Variant = neutralizer_system.call(
			"get_nearest_machine_cell",
			player.global_position,
			interaction_range_pixels
		)

		if neutralizer_cell != null:
			var neutralizer_world: Vector2 = neutralizer_system.call(
				"get_machine_world_position",
				neutralizer_cell
			)

			if (
				neutralizer_world != Vector2.INF
				and player.global_position.distance_to(
					neutralizer_world
				)
				< player.global_position.distance_to(
					world_position
				)
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
					world_position
				)
			):
				_set_prompt_visible(false)
				_nearby_cell = null
				return

	_prompt_phase += delta * prompt_bob_speed

	var bob: float = sin(_prompt_phase) * (
		prompt_bob_amplitude
	)

	var pulse_01: float = (
		sin(_prompt_phase * 0.85) * 0.5
		+ 0.5
	)
	var alpha: float = lerpf(
		prompt_alpha_min,
		prompt_alpha_max,
		pulse_01
	)

	# Canvas transform converts the world-space sprinkler position to the
	# screen-space CanvasLayer coordinate system, so the E stays over the
	# sprinkler while the camera moves.
	var screen_position: Vector2 = (
		get_viewport().get_canvas_transform()
		* world_position
	)

	var prompt_size: Vector2 = _prompt_label.size

	if prompt_size.x <= 0.0 or prompt_size.y <= 0.0:
		prompt_size = Vector2(
			28.0,
			28.0
		)

	_prompt_label.position = (
		screen_position
		+ prompt_world_offset
		+ Vector2(0.0, bob)
		- prompt_size * 0.5
	)

	_prompt_label.modulate = Color(
		1.0,
		1.0,
		1.0,
		alpha
	)
	_set_prompt_visible(true)


# Checks whether open from keyboard is allowed.
func _can_open_from_keyboard() -> bool:
	if _modal_open:
		return false

	if _nearby_cell == null:
		return false

	if get_tree().paused:
		return false

	if BuildSystem.is_active():
		return false

	if (
		block_while_aiming
		and InputMap.has_action("aim_mode")
		and Input.is_action_pressed("aim_mode")
	):
		return false

	if not InputMap.has_action("interact"):
		return false

	return Input.is_action_just_pressed(
		"interact"
	)


# Sets the prompt visible.
func _set_prompt_visible(
	value: bool
) -> void:
	if _prompt_label != null:
		_prompt_label.visible = value


# Finds the player.
func _find_player() -> CharacterBody2D:
	var scene: Node = get_tree().current_scene

	if scene == null:
		return null

	var direct := scene.get_node_or_null(
		"Player"
	)

	if direct is CharacterBody2D:
		return direct as CharacterBody2D

	var found := scene.find_child(
		"Player",
		true,
		false
	)

	if found is CharacterBody2D:
		return found as CharacterBody2D

	return null


# Opens the nearby sprinkler.
func open_nearby_sprinkler() -> bool:
	if _nearby_cell == null:
		return false

	var cell: Vector2i = _nearby_cell
	return open_config(cell)


# Opens the config.
func open_config(
	cell: Vector2i
) -> bool:
	if not SprinklerSystem.has_machine(cell):
		return false

	_active_cell = cell
	_modal_open = true
	_message_text = ""
	_message_timer = 0.0
	_refresh_accumulator = 0.0

	_previous_tree_paused = get_tree().paused
	_previous_mouse_mode = Input.mouse_mode

	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_set_prompt_visible(false)

	if _overlay != null:
		_overlay.visible = true

	_refresh_modal()

	# Enforce the visible cursor again after the modal becomes visible.
	call_deferred(
		"_enforce_modal_mouse"
	)

	if debug_log:
		print(
			"[SprinklerUI] OPEN cell=",
			cell,
			" state=",
			SprinklerSystem.get_machine_state(cell)
		)

	return true


# Closes the config.
func close_config() -> void:
	if not _modal_open:
		return

	var previous_cell: Variant = _active_cell

	_modal_open = false
	_active_cell = null
	_message_text = ""
	_message_timer = 0.0

	if _overlay != null:
		_overlay.visible = false

	get_tree().paused = _previous_tree_paused
	Input.mouse_mode = _previous_mouse_mode

	if debug_log:
		print(
			"[SprinklerUI] CLOSE cell=",
			previous_cell
		)


# Checks whether this interface is currently open.
func is_open() -> bool:
	return _modal_open


# Enforces the modal mouse.
func _enforce_modal_mouse() -> void:
	if _modal_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# Refreshes the modal.
func _refresh_modal() -> void:
	if not _modal_open:
		return

	if _active_cell == null:
		close_config()
		return

	var cell: Vector2i = _active_cell

	if not SprinklerSystem.has_machine(cell):
		close_config()
		return

	var state: Dictionary = (
		SprinklerSystem.get_machine_state(cell)
	)

	if state.is_empty():
		close_config()
		return

	var level: int = int(
		state.get("level", 1)
	)
	var max_level: int = int(
		state.get("max_level", 3)
	)
	var radius: int = int(
		state.get("radius", 0)
	)
	var moisture: float = float(
		state.get(
			"moisture_per_cycle",
			0.0
		)
	)
	var enabled: bool = bool(
		state.get("enabled", true)
	)
	var event_disabled: bool = bool(
		state.get("event_disabled", false)
	)
	var interval_minutes: int = int(
		state.get(
			"interval_minutes",
			180
		)
	)
	var effective_interval_minutes: int = int(
		state.get(
			"effective_interval_minutes",
			interval_minutes
		)
	)
	var minutes_until_next: int = int(
		state.get(
			"minutes_until_next",
			-1
		)
	)

	_level_label.text = "%d / %d" % [
		level,
		max_level
	]
	_range_label.text = "%d tiles" % radius
	_moisture_label.text = "+%d%% moisture" % int(
		round(moisture * 100.0)
	)

	if event_disabled:
		_status_label.text = "OUT OF SERVICE • EVENT"
		_status_label.modulate = Color(
			1.0,
			0.58,
			0.50,
			1.0
		)
		_next_label.text = "UNAVAILABLE"
		_power_button.text = "EVENT LOCKED"
		_power_button.disabled = true
	elif enabled:
		var interval_text: String = _interval_long_text(
			interval_minutes
		)

		if effective_interval_minutes != interval_minutes:
			interval_text += " • EVENT MODIFIER"

		_status_label.text = "ON • %s" % interval_text
		_status_label.modulate = Color(
			0.78,
			1.0,
			0.66,
			1.0
		)
		_next_label.text = _format_minutes(
			minutes_until_next
		)
		_power_button.text = "TURN OFF"
		_power_button.disabled = false
	else:
		_status_label.text = "OFF"
		_status_label.modulate = Color(
			1.0,
			0.72,
			0.65,
			1.0
		)
		_next_label.text = "DISABLED"
		_power_button.text = "TURN ON"
		_power_button.disabled = false

	_money_label.text = "$%d" % (
		EconomySystem.get_money()
	)

	if show_cell_coordinates:
		_subtitle_label.text = "CELL %d, %d" % [
			cell.x,
			cell.y
		]
	else:
		if _message_text != "":
			_subtitle_label.text = _message_text
		else:
			_subtitle_label.text = (
				"INDIVIDUAL IRRIGATION CONTROL"
			)

	_refresh_interval_buttons(
		interval_minutes,
		enabled and not event_disabled
	)

	_refresh_upgrade_button(cell)


# Refreshes the interval buttons.
func _refresh_interval_buttons(
	selected_minutes: int,
	enabled: bool
) -> void:
	for minutes_variant: Variant in _interval_buttons.keys():
		var minutes: int = int(minutes_variant)
		var button: Button = (
			_interval_buttons[minutes]
		)

		button.disabled = not enabled

		var selected: bool = (
			minutes == selected_minutes
		)

		button.add_theme_stylebox_override(
			"normal",
			_make_button_style(
				selected,
				false
			)
		)
		button.add_theme_stylebox_override(
			"hover",
			_make_button_style(
				selected,
				true
			)
		)
		button.add_theme_stylebox_override(
			"pressed",
			_make_button_style(
				true,
				true
			)
		)


# Refreshes the upgrade button.
func _refresh_upgrade_button(
	cell: Vector2i
) -> void:
	var status: Dictionary = (
		SprinklerSystem.get_upgrade_status(
			cell
		)
	)
	var reason: String = String(
		status.get("reason", "")
	)

	if reason == AutomationMachineBase.REASON_MAX_LEVEL:
		_upgrade_button.text = "MAX LEVEL"
		_upgrade_button.disabled = true
		return

	var next_level: int = int(
		status.get(
			"next_level",
			SprinklerSystem.get_machine_level(cell) + 1
		)
	)
	var cost: int = int(
		status.get(
			"cost",
			SprinklerSystem.get_upgrade_cost(cell)
		)
	)

	_upgrade_button.text = (
		"UPGRADE TO LEVEL %d  •  $%d"
		% [
			next_level,
			cost
		]
	)

	_upgrade_button.disabled = (
		not bool(status.get("ok", false))
	)

	if reason == AutomationMachineBase.REASON_INSUFFICIENT_MONEY:
		_upgrade_button.tooltip_text = (
			"Not enough money."
		)
	else:
		_upgrade_button.tooltip_text = ""


# Handles the power pressed signal or callback.
func _on_power_pressed() -> void:
	if _active_cell == null:
		return

	var cell: Vector2i = _active_cell
	var currently_enabled: bool = (
		SprinklerSystem.is_machine_enabled(
			cell
		)
	)

	var result: Dictionary = (
		SprinklerSystem.set_machine_enabled(
			cell,
			not currently_enabled
		)
	)

	if bool(result.get("ok", false)):
		_show_message(
			"AUTOMATIC WATERING %s"
			% (
				"ON"
				if not currently_enabled
				else "OFF"
			)
		)

	_refresh_modal()


# Handles the interval pressed signal or callback.
func _on_interval_pressed(
	minutes: int
) -> void:
	if _active_cell == null:
		return

	var cell: Vector2i = _active_cell

	var result: Dictionary = (
		SprinklerSystem.set_machine_interval(
			cell,
			minutes
		)
	)

	if bool(result.get("ok", false)):
		_show_message(
			"INTERVAL SET TO %s"
			% _interval_long_text(minutes)
		)

	_refresh_modal()


# Handles the upgrade pressed signal or callback.
func _on_upgrade_pressed() -> void:
	if _active_cell == null:
		return

	var cell: Vector2i = _active_cell
	var result: Dictionary = (
		SprinklerSystem.upgrade_machine(
			cell
		)
	)

	if bool(result.get("ok", false)):
		var new_level: int = int(
			result.get("new_level", 1)
		)
		var cost: int = int(
			result.get("cost", 0)
		)

		_show_message(
			"UPGRADED TO LEVEL %d • -$%d"
			% [
				new_level,
				cost
			]
		)
	else:
		var reason: String = String(
			result.get("reason", "")
		)

		if reason == AutomationMachineBase.REASON_INSUFFICIENT_MONEY:
			_show_message("NOT ENOUGH MONEY")
		elif reason == AutomationMachineBase.REASON_MAX_LEVEL:
			_show_message("MAX LEVEL")

	_refresh_modal()


# Shows the message.
func _show_message(
	text_value: String
) -> void:
	_message_text = text_value
	_message_timer = 2.0


# Refreshes the open panel when the shared machine state changes.
func _on_machine_state_changed(
	cell: Vector2i,
	_state: Dictionary
) -> void:
	if not _modal_open or _active_cell == null:
		return

	var active_cell: Vector2i = _active_cell

	if cell == active_cell:
		_refresh_modal()


# Formats an interval as short UI text.
func _interval_short_text(
	minutes: int
) -> String:
	match minutes:
		60:
			return "1 H"
		180:
			return "3 H"
		360:
			return "6 H"
		720:
			return "12 H"
		_:
			return "%d M" % minutes


# Formats interval long for UI display.
func _interval_long_text(
	minutes: int
) -> String:
	if minutes % 60 == 0:
		var hours: int = minutes / 60

		if hours == 1:
			return "1 HOUR"

		return "%d HOURS" % hours

	return "%d MINUTES" % minutes


# Formats the minutes for display.
func _format_minutes(
	minutes: int
) -> String:
	if minutes < 0:
		return "-"

	var hours: int = minutes / 60
	var remaining_minutes: int = minutes % 60

	if hours <= 0:
		return "%d min" % remaining_minutes

	if remaining_minutes <= 0:
		return "%dh" % hours

	return "%dh %02dm" % [
		hours,
		remaining_minutes
	]
