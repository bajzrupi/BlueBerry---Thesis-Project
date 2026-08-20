extends Node

# BlueBerry Time Speed Control
#
# Compact grand-strategy-style gameplay-time selector:
#     TIME   1x   2x   4x
#
# This changes Clock.time_scale only. It deliberately does NOT touch
# Engine.time_scale, so player movement, UI, animation playback, mouse input,
# and real-time autosave timing remain normal.
#
# Mouse:
# - The buttons can be clicked whenever the cursor is visible (for example
#   while holding the normal aim modifier or ALT).
#
# Selection:
# - Hold ALT to reveal the gameplay cursor, then click 1x / 3x / 6x.
# - There is intentionally no gameplay speed hotkey.
#
# The control only appears while a gameplay world is configured.

@export_category("Layout")

@export var hud_layer: int = 70
@export var top_margin: float = 12.0
@export var panel_width: float = 226.0
@export var panel_height: float = 44.0
@export var button_width: float = 48.0
@export var button_height: float = 30.0


@export_category("Diagnostics")

@export var debug_log: bool = false


const COLOR_PANEL_BG := Color(
	0.035,
	0.043,
	0.038,
	0.94
)

const COLOR_PANEL_BORDER := Color(
	0.31,
	0.40,
	0.32,
	0.96
)

const COLOR_BUTTON_BG := Color(
	0.075,
	0.085,
	0.075,
	0.98
)

const COLOR_BUTTON_HOVER := Color(
	0.13,
	0.15,
	0.12,
	1.0
)

const COLOR_ACTIVE_BG := Color(
	0.15,
	0.24,
	0.15,
	1.0
)

const COLOR_ACTIVE_BORDER := Color(
	0.52,
	0.84,
	0.49,
	1.0
)

const COLOR_TEXT := Color(
	0.89,
	0.89,
	0.79,
	1.0
)

const COLOR_MUTED := Color(
	0.60,
	0.63,
	0.57,
	1.0
)


var _canvas: CanvasLayer
var _panel: PanelContainer
var _buttons: Dictionary = {}

var _last_world_available: bool = false


# Initializes this system when the node becomes ready.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Never inherit a stale speed from an editor/runtime restart.
	Clock.reset_time_scale()

	_build_ui()
	_connect_clock()
	_refresh_active_button()
	_update_visibility()


# Updates this system every frame.
func _process(_delta: float) -> void:
	var world_available: bool = _has_gameplay_world()

	if world_available != _last_world_available:
		_last_world_available = world_available

		# Leaving gameplay must never leave the global Clock accelerated.
		if not world_available:
			Clock.reset_time_scale()

		_update_visibility()

	# Modal/pause screens own the foreground UI.
	if _panel != null:
		_panel.visible = (
			world_available
			and not get_tree().paused
		)


# Connects the clock signals and callbacks.
func _connect_clock() -> void:
	if not Clock.time_scale_changed.is_connected(
		_on_time_scale_changed
	):
		Clock.time_scale_changed.connect(
			_on_time_scale_changed
		)


# Builds the UI.
func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "TimeSpeedCanvas"
	_canvas.layer = hud_layer
	_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_canvas)

	_panel = PanelContainer.new()
	_panel.name = "TimeSpeedPanel"
	_panel.custom_minimum_size = Vector2(
		panel_width,
		panel_height
	)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override(
		"panel",
		_make_panel_style()
	)

	# Top-center keeps clear of the left toolbar and the right minimap /
	# progression HUD.
	_panel.set_anchors_preset(
		Control.PRESET_CENTER_TOP
	)
	_panel.position = Vector2(
		-panel_width * 0.5,
		top_margin
	)
	_canvas.add_child(_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_theme_constant_override(
		"margin_left",
		8
	)
	margin.add_theme_constant_override(
		"margin_right",
		8
	)
	margin.add_theme_constant_override(
		"margin_top",
		6
	)
	margin.add_theme_constant_override(
		"margin_bottom",
		6
	)
	_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override(
		"separation",
		5
	)
	margin.add_child(row)

	var caption := Label.new()
	caption.text = "TIME"
	caption.custom_minimum_size.x = 48.0
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_size_override(
		"font_size",
		10
	)
	caption.add_theme_color_override(
		"font_color",
		COLOR_MUTED
	)
	caption.add_theme_color_override(
		"font_outline_color",
		Color(
			0.0,
			0.0,
			0.0,
			0.90
		)
	)
	caption.add_theme_constant_override(
		"outline_size",
		2
	)
	row.add_child(caption)

	_add_speed_button(
		row,
		Clock.TIME_SCALE_NORMAL,
		"1×"
	)
	_add_speed_button(
		row,
		Clock.TIME_SCALE_FAST,
		"3×"
	)
	_add_speed_button(
		row,
		Clock.TIME_SCALE_VERY_FAST,
		"6×"
	)


# Adds the speed button.
func _add_speed_button(
	parent: HBoxContainer,
	speed: float,
	label_text: String
) -> void:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(
		button_width,
		button_height
	)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	button.tooltip_text = (
		"Hold ALT + click • %s gameplay time"
		% label_text
	)

	button.add_theme_font_size_override(
		"font_size",
		12
	)
	button.add_theme_color_override(
		"font_color",
		COLOR_TEXT
	)
	button.add_theme_color_override(
		"font_hover_color",
		Color.WHITE
	)
	button.add_theme_color_override(
		"font_pressed_color",
		Color.WHITE
	)
	button.add_theme_color_override(
		"font_outline_color",
		Color(
			0.0,
			0.0,
			0.0,
			0.90
		)
	)
	button.add_theme_constant_override(
		"outline_size",
		2
	)

	button.pressed.connect(
		_on_speed_pressed.bind(speed)
	)

	parent.add_child(button)
	_buttons[speed] = button


# Handles the speed pressed signal or callback.
func _on_speed_pressed(
	speed: float
) -> void:
	# Selection is deliberately ALT + click so normal gameplay mouse input
	# cannot change time speed accidentally.
	if not Input.is_key_pressed(KEY_ALT):
		return

	Clock.set_time_scale(speed)

	if debug_log:
		print(
			"[TimeSpeed] selected ",
			speed,
			"x effective_day=",
			Clock.get_effective_day_length_seconds(),
			"s"
		)


# Handles the time scale changed signal or callback.
func _on_time_scale_changed(
	_multiplier: float
) -> void:
	_refresh_active_button()


# Refreshes the active button.
func _refresh_active_button() -> void:
	if _buttons.is_empty():
		return

	var current: float = Clock.get_time_scale()

	for speed_variant: Variant in _buttons.keys():
		var speed: float = float(speed_variant)
		var button_variant: Variant = _buttons[speed_variant]

		if not button_variant is Button:
			continue

		var button := button_variant as Button
		var active: bool = is_equal_approx(
			current,
			speed
		)

		button.add_theme_stylebox_override(
			"normal",
			_make_button_style(active, false)
		)
		button.add_theme_stylebox_override(
			"hover",
			_make_button_style(active, true)
		)
		button.add_theme_stylebox_override(
			"pressed",
			_make_button_style(true, true)
		)


# Updates the visibility.
func _update_visibility() -> void:
	if _panel == null:
		return

	_panel.visible = (
		_has_gameplay_world()
		and not get_tree().paused
	)


# Checks whether gameplay world exists or is available.
func _has_gameplay_world() -> bool:
	var tilemap_variant: Variant = SaveSystem.get(
		"_tilemap"
	)
	var player_variant: Variant = SaveSystem.get(
		"_player"
	)

	# During scene replacement SaveSystem can temporarily still reference
	# gameplay Objects that have already been freed. Always validate first;
	# applying `is SomeType` to a freed Object raises a runtime error.
	return (
		is_instance_valid(tilemap_variant)
		and tilemap_variant is TileMap
		and is_instance_valid(player_variant)
		and player_variant is CharacterBody2D
	)


# Creates the panel style.
func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL_BG
	style.border_color = COLOR_PANEL_BORDER

	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1

	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6

	style.shadow_color = Color(
		0.0,
		0.0,
		0.0,
		0.34
	)
	style.shadow_size = 5
	style.shadow_offset = Vector2(
		0.0,
		2.0
	)

	return style


# Creates the button style.
func _make_button_style(
	active: bool,
	hovered: bool
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	if active:
		style.bg_color = COLOR_ACTIVE_BG
		style.border_color = COLOR_ACTIVE_BORDER
	else:
		style.bg_color = (
			COLOR_BUTTON_HOVER
			if hovered
			else COLOR_BUTTON_BG
		)
		style.border_color = (
			COLOR_PANEL_BORDER.lightened(0.18)
			if hovered
			else COLOR_PANEL_BORDER
		)

	var border_width: int = (
		2
		if active
		else 1
	)

	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width

	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4

	return style
