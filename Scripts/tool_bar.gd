extends CanvasLayer

# Compact transparent text-based tool rail.
# Designed to keep every tool on screen in slimmer rows while still showing:
# - hotkey number
# - tool name
# - durability percent / READY / BROKEN
# - a thin health / durability bar

@export_category("Tool Bar")

# Controls the CanvasLayer drawing order.
@export var hud_layer: int = 6

# Positions the toolbar from the top-left corner.
@export var screen_offset: Vector2 = Vector2(16.0, 78.0)

# Compact row size that still fits the full tool names.
@export var row_size: Vector2 = Vector2(214.0, 38.0)

# Space between tool rows.
@export var row_separation: int = 4

# Overall rail padding.
@export var rail_padding: int = 6

# Optional title shown above the tool list.
@export var show_title: bool = true
@export var title_text: String = "TOOLS"

# Displays tool durability percent text on the right side.
@export var show_durability_percent: bool = true

# Displays a durability / health bar for tools that wear down.
@export var show_durability_bar: bool = true


@export_category("Debug Logging")

# Enables toolbar initialization and selection logs.
@export var debug_log: bool = false


var _toolbar_root: Control
var _row_buttons: Array[Button] = []
var _tool_name_labels: Array[Label] = []
var _tool_status_labels: Array[Label] = []
var _durability_tracks: Array[ColorRect] = []
var _durability_fills: Array[ColorRect] = []

var _button_group := ButtonGroup.new()


# Initializes this system when the node becomes ready.
func _ready() -> void:
	layer = hud_layer

	_hide_legacy_toolbar()
	_build_text_toolbar()

	if not Toolsystem.tool_changed.is_connected(
		_on_tool_changed
	):
		Toolsystem.tool_changed.connect(
			_on_tool_changed
		)

	if not Toolsystem.durability_changed.is_connected(
		_on_durability_changed
	):
		Toolsystem.durability_changed.connect(
			_on_durability_changed
		)

	_on_tool_changed(Toolsystem.current_tool)
	_refresh_all_durability()

	if debug_log:
		print(
			"[ToolBar] compact text redesign ready layer=",
			layer,
			" offset=",
			screen_offset,
			" tools=",
			_row_buttons.size()
		)


# Hides the old scene-authored toolbar if it still exists in ToolBar.tscn.
func _hide_legacy_toolbar() -> void:
	var legacy_panel := get_node_or_null("Panel") as Control

	if legacy_panel == null:
		return

	legacy_panel.visible = false
	legacy_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE


# Builds the text toolbar.
func _build_text_toolbar() -> void:
	_toolbar_root = Control.new()
	_toolbar_root.name = "TextToolBar"
	_toolbar_root.position = screen_offset
	_toolbar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toolbar_root)

	var rail_panel := PanelContainer.new()
	rail_panel.name = "ToolRailPanel"
	rail_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rail_panel.add_theme_stylebox_override(
		"panel",
		_create_rail_style()
	)
	_toolbar_root.add_child(rail_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", rail_padding)
	margin.add_theme_constant_override("margin_top", rail_padding)
	margin.add_theme_constant_override("margin_right", rail_padding)
	margin.add_theme_constant_override("margin_bottom", rail_padding)
	rail_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_theme_constant_override(
		"separation",
		row_separation
	)
	margin.add_child(column)

	if show_title:
		column.add_child(_create_title_label())

	for index in range(Toolsystem.order.size()):
		var tool_id: int = Toolsystem.order[index]
		var row := _create_tool_row(index, tool_id)
		column.add_child(row)
		_row_buttons.append(row)


# Creates the title label.
func _create_title_label() -> Label:
	var title := Label.new()
	title.name = "ToolbarTitle"
	title.text = title_text
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.custom_minimum_size = Vector2(
		row_size.x,
		18.0
	)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override(
		"font_color",
		Color(0.86, 0.94, 0.88, 0.90)
	)
	title.add_theme_color_override(
		"font_outline_color",
		Color(0.02, 0.03, 0.02, 0.95)
	)
	title.add_theme_constant_override(
		"outline_size",
		2
	)
	return title


# Creates the tool row.
func _create_tool_row(
	index: int,
	tool_id: int
) -> Button:
	var button := Button.new()
	button.name = "ToolRow%d" % (index + 1)
	button.custom_minimum_size = row_size
	button.toggle_mode = true
	button.button_group = _button_group
	button.focus_mode = Control.FOCUS_NONE
	button.text = ""
	button.tooltip_text = "%d - %s" % [
		index + 1,
		Toolsystem.get_tool_name(tool_id)
	]
	button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	button.pressed.connect(
		_on_button_pressed.bind(index)
	)
	_apply_button_styles(button, false)

	var key_box := ColorRect.new()
	key_box.name = "HotkeyBox"
	key_box.position = Vector2(6.0, 5.0)
	key_box.size = Vector2(22.0, 16.0)
	key_box.color = Color(1.0, 1.0, 1.0, 0.10)
	key_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(key_box)

	var hotkey_label := Label.new()
	hotkey_label.name = "Hotkey"
	hotkey_label.position = key_box.position
	hotkey_label.size = key_box.size
	hotkey_label.text = str(index + 1)
	hotkey_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hotkey_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hotkey_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hotkey_label.add_theme_font_size_override("font_size", 11)
	hotkey_label.add_theme_color_override(
		"font_color",
		Color(0.92, 0.96, 0.92, 0.95)
	)
	hotkey_label.add_theme_color_override(
		"font_outline_color",
		Color(0.02, 0.03, 0.02, 1.0)
	)
	hotkey_label.add_theme_constant_override(
		"outline_size",
		2
	)
	button.add_child(hotkey_label)

	var tool_name := Label.new()
	tool_name.name = "ToolName"
	tool_name.position = Vector2(34.0, 3.0)
	tool_name.size = Vector2(row_size.x - 102.0, 18.0)
	tool_name.text = Toolsystem.get_tool_name(tool_id)
	tool_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tool_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tool_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tool_name.add_theme_font_size_override("font_size", 13)
	tool_name.add_theme_color_override(
		"font_color",
		Color(0.93, 0.97, 0.93, 1.0)
	)
	tool_name.add_theme_color_override(
		"font_outline_color",
		Color(0.02, 0.03, 0.02, 1.0)
	)
	tool_name.add_theme_constant_override(
		"outline_size",
		2
	)
	button.add_child(tool_name)

	var status_label := Label.new()
	status_label.name = "Status"
	status_label.position = Vector2(
		row_size.x - 60.0,
		3.0
	)
	status_label.size = Vector2(52.0, 18.0)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override(
		"font_color",
		Color(0.82, 0.88, 0.83, 0.95)
	)
	status_label.add_theme_color_override(
		"font_outline_color",
		Color(0.02, 0.03, 0.02, 1.0)
	)
	status_label.add_theme_constant_override(
		"outline_size",
		2
	)
	button.add_child(status_label)

	var track := ColorRect.new()
	track.name = "DurabilityTrack"
	track.position = Vector2(34.0, 23.0)
	track.size = Vector2(row_size.x - 46.0, 6.0)
	track.color = Color(0.02, 0.025, 0.02, 0.72)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(track)

	var fill := ColorRect.new()
	fill.name = "DurabilityFill"
	fill.position = track.position
	fill.size = track.size
	fill.color = Color(0.32, 0.86, 0.34, 1.0)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(fill)

	_tool_name_labels.append(tool_name)
	_tool_status_labels.append(status_label)
	_durability_tracks.append(track)
	_durability_fills.append(fill)

	return button


# Creates the rail style.
func _create_rail_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.025, 0.16)
	style.border_color = Color(0.55, 0.70, 0.61, 0.18)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.14)
	style.shadow_size = 2
	return style


# Creates the row style.
func _create_row_style(
	selected: bool,
	hovered: bool = false
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	if selected:
		style.bg_color = Color(0.18, 0.28, 0.20, 0.26)
		style.border_color = Color(0.76, 0.98, 0.44, 0.95)
	elif hovered:
		style.bg_color = Color(0.16, 0.20, 0.17, 0.20)
		style.border_color = Color(0.66, 0.77, 0.70, 0.42)
	else:
		style.bg_color = Color(0.08, 0.10, 0.09, 0.12)
		style.border_color = Color(0.58, 0.67, 0.61, 0.16)

	var border_width := 1
	if selected:
		border_width = 2

	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


# Applies the button styles.
func _apply_button_styles(
	button: Button,
	selected: bool
) -> void:
	button.add_theme_stylebox_override(
		"normal",
		_create_row_style(selected)
	)
	button.add_theme_stylebox_override(
		"hover",
		_create_row_style(selected, true)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_create_row_style(true, true)
	)
	button.add_theme_stylebox_override(
		"focus",
		_create_row_style(selected)
	)


# Handles the button pressed signal or callback.
func _on_button_pressed(index: int) -> void:
	Toolsystem.set_tool_by_index(index)

	if debug_log:
		print(
			"[ToolBar] clicked index=",
			index,
			" tool=",
			Toolsystem.get_tool_name(
				Toolsystem.order[index]
			)
		)


# Handles the tool changed signal or callback.
func _on_tool_changed(tool_id: int) -> void:
	var selected_index := Toolsystem.order.find(tool_id)

	for index in range(_row_buttons.size()):
		var is_selected := index == selected_index
		var button := _row_buttons[index]

		button.button_pressed = is_selected
		_apply_button_styles(button, is_selected)

		if index < _tool_name_labels.size():
			_tool_name_labels[index].modulate = (
				Color(1.0, 1.0, 1.0, 1.0)
				if is_selected
				else Color(0.93, 0.97, 0.93, 0.95)
			)

	_refresh_all_durability()

	if debug_log and selected_index >= 0:
		print(
			"[ToolBar] selected index=",
			selected_index,
			" tool=",
			Toolsystem.get_tool_name(tool_id)
		)


# Refreshes the durability slot.
func _refresh_durability_slot(index: int) -> void:
	if (
		index < 0
		or index >= Toolsystem.order.size()
		or index >= _row_buttons.size()
		or index >= _tool_status_labels.size()
		or index >= _durability_tracks.size()
		or index >= _durability_fills.size()
	):
		return

	var tool_id: int = Toolsystem.order[index]
	var button: Button = _row_buttons[index]
	var status_label: Label = _tool_status_labels[index]
	var track: ColorRect = _durability_tracks[index]
	var fill: ColorRect = _durability_fills[index]

	if not Toolsystem.uses_durability(tool_id):
		status_label.text = "READY"
		track.visible = false
		fill.visible = false
		button.tooltip_text = (
			"%d - %s\nDurability: no wear"
			% [
				index + 1,
				Toolsystem.get_tool_name(tool_id)
			]
		)
		return

	track.visible = show_durability_bar
	fill.visible = show_durability_bar

	var durability: int = Toolsystem.get_durability(tool_id)
	var ratio: float = clampf(
		float(durability) / float(Toolsystem.MAX_DURABILITY),
		0.0,
		1.0
	)

	fill.size = Vector2(
		track.size.x * ratio,
		track.size.y
	)

	if ratio >= 0.60:
		fill.color = Color(0.32, 0.86, 0.34, 1.0)
	elif ratio >= 0.30:
		fill.color = Color(0.96, 0.79, 0.20, 1.0)
	else:
		fill.color = Color(0.94, 0.25, 0.20, 1.0)

	if durability <= 0:
		status_label.text = "BROKEN"
		status_label.modulate = Color(1.0, 0.78, 0.78, 1.0)
	else:
		if show_durability_percent:
			status_label.text = "%d%%" % durability
		else:
			status_label.text = "OK"

		status_label.modulate = Color(1.0, 1.0, 1.0, 1.0)

	var durability_text: String = (
		"BROKEN"
		if durability <= 0
		else "%d%%" % durability
	)

	button.tooltip_text = (
		"%d - %s\nDurability: %s"
		% [
			index + 1,
			Toolsystem.get_tool_name(tool_id),
			durability_text
		]
	)


# Refreshes the all durability.
func _refresh_all_durability() -> void:
	for index: int in range(
		Toolsystem.order.size()
	):
		_refresh_durability_slot(index)


# Handles the durability changed signal or callback.
func _on_durability_changed(
	tool_id: int,
	_previous_value: int,
	_new_value: int,
	_delta: int
) -> void:
	var index: int = Toolsystem.order.find(tool_id)

	if index >= 0:
		_refresh_durability_slot(index)


# Handles input that was not consumed by the UI.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return

	var key_event := event as InputEventKey

	if not key_event.pressed or key_event.echo:
		return

	var keycode := key_event.keycode

	if keycode < KEY_1 or keycode > KEY_9:
		return

	var index := int(keycode - KEY_1)

	if index >= Toolsystem.order.size():
		return

	Toolsystem.set_tool_by_index(index)
