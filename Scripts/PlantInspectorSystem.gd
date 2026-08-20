extends Node

# BlueBerry Plant Inspector
#
# Hold ALT and hover a planted tile to inspect the plant and its soil.
# Values are color coded:
# - green: healthy / inside the plant's preferred range
# - yellow: needs attention / slightly outside the preferred range
# - red: poor / far outside the preferred range
#
# This system is intentionally read-only. It does not modify plant, biome,
# inventory, progression, or tool state.

@export_category("Interaction")

# The feature uses the physical ALT key directly, so no Input Map action
# needs to be added.
@export var enabled: bool = true

# Prevent the inspector from competing with Build Mode.
@export var hide_while_building: bool = true


@export_category("Layout")

@export var card_size: Vector2 = Vector2(278.0, 268.0)
@export var cursor_offset: Vector2 = Vector2(20.0, 18.0)
@export var screen_edge_margin: float = 10.0


@export_category("Condition Thresholds")

# Normalized soil values such as moisture and nutrients use an absolute
# warning margin outside the plant's preferred interval.
@export_range(0.01, 0.30, 0.01)
var normalized_warning_margin: float = 0.10

# pH uses its own natural scale.
@export_range(0.10, 2.00, 0.05)
var ph_warning_margin: float = 0.50

# Health is treated as a percentage of the plant's configured max health.
@export_range(0.0, 1.0, 0.05)
var health_good_threshold: float = 0.70

@export_range(0.0, 1.0, 0.05)
var health_warning_threshold: float = 0.40

# Lower pest/disease values are better.
@export_range(0.0, 1.0, 0.05)
var bio_good_max: float = 0.10

@export_range(0.0, 1.0, 0.05)
var bio_warning_max: float = 0.30


# ------------------------------------------------------------------
# Colors
# ------------------------------------------------------------------

const COLOR_CARD_BG := Color(
	0.035,
	0.043,
	0.038,
	0.97
)

const COLOR_CARD_BORDER := Color(
	0.36,
	0.48,
	0.37,
	0.96
)

const COLOR_TITLE := Color(
	0.94,
	0.93,
	0.82,
	1.0
)

const COLOR_LABEL := Color(
	0.70,
	0.72,
	0.67,
	1.0
)

const COLOR_NEUTRAL := Color(
	0.88,
	0.86,
	0.76,
	1.0
)

const COLOR_GOOD := Color(
	0.43,
	0.82,
	0.46,
	1.0
)

const COLOR_WARNING := Color(
	0.93,
	0.76,
	0.27,
	1.0
)

const COLOR_BAD := Color(
	0.92,
	0.34,
	0.30,
	1.0
)

const COLOR_MUTED := Color(
	0.48,
	0.51,
	0.47,
	1.0
)


# ------------------------------------------------------------------
# Runtime state
# ------------------------------------------------------------------

var _canvas: CanvasLayer
var _card: PanelContainer

var _title_label: Label
var _stage_label: Label
var _soil_label: Label

var _value_labels: Dictionary = {}

var _tilemap: TileMap = null
var _hovered_cell: Vector2i = Vector2i.ZERO
var _hovered_plant: Node = null

var _alt_was_down: bool = false
var _forced_mouse_visible: bool = false
var _mouse_mode_before_alt: Input.MouseMode = Input.MOUSE_MODE_HIDDEN


# ------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------

# Initializes this system when the node becomes ready.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# test_level.gd also manages mouse visibility. A high process priority
	# lets this read-only inspector apply its ALT cursor state afterwards
	# without requiring changes to the gameplay scene script.
	process_priority = 1000

	_build_ui()
	_hide_card()


# Updates this system every frame.
func _process(_delta: float) -> void:
	if not enabled:
		_restore_mouse_after_alt()
		_hide_card()
		return

	_resolve_tilemap()

	var alt_down: bool = Input.is_key_pressed(KEY_ALT)

	_update_alt_mouse_visibility(alt_down)

	if not _can_inspect(alt_down):
		_hide_card()
		_alt_was_down = alt_down
		return

	var mouse_world: Vector2 = _tilemap.get_global_mouse_position()
	var local_position: Vector2 = _tilemap.to_local(mouse_world)
	var cell: Vector2i = _tilemap.local_to_map(local_position)
	var plant: Node = PlantRegistry.get_plant(cell)

	if (
		plant == null
		or not is_instance_valid(plant)
	):
		_hide_card()
		_hovered_plant = null
		_hovered_cell = cell
		_alt_was_down = alt_down
		return

	var data_variant: Variant = plant.get("data")

	if not data_variant is PlantData:
		_hide_card()
		_hovered_plant = null
		_hovered_cell = cell
		_alt_was_down = alt_down
		return

	_hovered_cell = cell
	_hovered_plant = plant

	_refresh_card(
		plant,
		data_variant as PlantData,
		cell
	)
	_position_card()
	_card.visible = true

	_alt_was_down = alt_down


# ------------------------------------------------------------------
# World / input state
# ------------------------------------------------------------------

# Resolves the tilemap.
func _resolve_tilemap() -> void:
	if (
		_tilemap != null
		and is_instance_valid(_tilemap)
	):
		return

	_tilemap = null

	var candidate: Variant = BiomeSystem.get("_tilemap")

	# Scene changes can leave BiomeSystem holding a Variant that points to an
	# already-freed gameplay TileMap for a frame. Validate the Object BEFORE
	# using the `is` type operator, because `freed_instance is TileMap` raises
	# "Left operand of 'is' is a previously freed instance."
	if (
		is_instance_valid(candidate)
		and candidate is TileMap
	):
		_tilemap = candidate as TileMap


# Checks whether inspect is allowed.
func _can_inspect(
	alt_down: bool
) -> bool:
	if not alt_down:
		return false

	if get_tree().paused:
		return false

	if (
		_tilemap == null
		or not is_instance_valid(_tilemap)
	):
		return false

	if (
		hide_while_building
		and BuildSystem.is_active()
	):
		return false

	return true


# Updates the Alt mouse visibility.
func _update_alt_mouse_visibility(
	alt_down: bool
) -> void:
	var world_available: bool = (
		_tilemap != null
		and is_instance_valid(_tilemap)
	)

	if (
		alt_down
		and not _alt_was_down
		and world_available
		and not get_tree().paused
	):
		_mouse_mode_before_alt = Input.get_mouse_mode()
		_forced_mouse_visible = true

	if (
		alt_down
		and _forced_mouse_visible
		and world_available
		and not get_tree().paused
	):
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE
		)

	if (
		not alt_down
		and _alt_was_down
	):
		_restore_mouse_after_alt()


# Restores the mouse after Alt from saved or temporary state.
func _restore_mouse_after_alt() -> void:
	if not _forced_mouse_visible:
		_alt_was_down = false
		return

	# If another gameplay mode currently wants a visible cursor, do not fight it.
	if BuildSystem.is_active():
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE
		)
	elif (
		InputMap.has_action("aim_mode")
		and Input.is_action_pressed("aim_mode")
	):
		Input.set_mouse_mode(
			Input.MOUSE_MODE_VISIBLE
		)
	else:
		Input.set_mouse_mode(
			_mouse_mode_before_alt
		)

	_forced_mouse_visible = false
	_alt_was_down = false


# ------------------------------------------------------------------
# UI creation
# ------------------------------------------------------------------

# Builds the UI.
func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "PlantInspectorCanvas"
	_canvas.layer = 80
	_canvas.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_canvas)

	_card = PanelContainer.new()
	_card.name = "PlantInspectorCard"
	_card.custom_minimum_size = card_size
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override(
		"panel",
		_make_card_style()
	)
	_canvas.add_child(_card)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override(
		"margin_left",
		16
	)
	margin.add_theme_constant_override(
		"margin_right",
		16
	)
	margin.add_theme_constant_override(
		"margin_top",
		13
	)
	margin.add_theme_constant_override(
		"margin_bottom",
		13
	)
	_card.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override(
		"separation",
		5
	)
	margin.add_child(column)

	_title_label = _make_label(
		"PLANT",
		18,
		COLOR_TITLE
	)
	_title_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	column.add_child(_title_label)

	_stage_label = _make_label(
		"Growing",
		11,
		COLOR_NEUTRAL
	)
	_stage_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	column.add_child(_stage_label)

	_soil_label = _make_label(
		"LOAMY",
		10,
		COLOR_MUTED
	)
	_soil_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	column.add_child(_soil_label)

	var divider := HSeparator.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.add_theme_constant_override(
		"separation",
		4
	)
	column.add_child(divider)

	_add_value_row(
		column,
		"health",
		"Health"
	)
	_add_value_row(
		column,
		"moisture",
		"Moisture"
	)
	_add_value_row(
		column,
		"nutrients",
		"Nutrients"
	)
	_add_value_row(
		column,
		"ph",
		"pH"
	)
	_add_value_row(
		column,
		"pests",
		"Pests"
	)
	_add_value_row(
		column,
		"disease",
		"Disease"
	)

	var footer_divider := HSeparator.new()
	footer_divider.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	column.add_child(footer_divider)

	var footer := _make_label(
		"ALT • plant status",
		9,
		COLOR_MUTED
	)
	footer.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	column.add_child(footer)


# Adds the value row.
func _add_value_row(
	parent: VBoxContainer,
	key: String,
	caption: String
) -> void:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(
		"separation",
		8
	)
	parent.add_child(row)

	var caption_label := _make_label(
		caption,
		12,
		COLOR_LABEL
	)
	caption_label.size_flags_horizontal = (
		Control.SIZE_EXPAND_FILL
	)
	row.add_child(caption_label)

	var value_label := _make_label(
		"-",
		12,
		COLOR_NEUTRAL
	)
	value_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	value_label.custom_minimum_size.x = 76.0
	row.add_child(value_label)

	_value_labels[key] = value_label


# Creates the label.
func _make_label(
	text_value: String,
	font_size: int,
	color: Color
) -> Label:
	var label := Label.new()
	label.text = text_value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
			0.88
		)
	)
	label.add_theme_constant_override(
		"outline_size",
		2
	)
	return label


# Creates the card style.
func _make_card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_CARD_BG
	style.border_color = COLOR_CARD_BORDER

	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2

	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7

	style.shadow_color = Color(
		0.0,
		0.0,
		0.0,
		0.46
	)
	style.shadow_size = 7
	style.shadow_offset = Vector2(
		0.0,
		3.0
	)

	return style


# ------------------------------------------------------------------
# Card refresh
# ------------------------------------------------------------------

# Refreshes the card.
func _refresh_card(
	plant: Node,
	data: PlantData,
	cell: Vector2i
) -> void:
	_title_label.text = data.display_name.to_upper()

	var dead: bool = bool(
		plant.get("is_dead")
	)
	var stage: int = int(
		plant.get("stage")
	)

	if dead:
		_stage_label.text = "Dead"
		_stage_label.add_theme_color_override(
			"font_color",
			COLOR_BAD
		)
	elif stage >= data.max_stage:
		_stage_label.text = "Ready to harvest"
		_stage_label.add_theme_color_override(
			"font_color",
			COLOR_GOOD
		)
	else:
		var growth_percent: int = int(
			round(
				_get_growth_progress(
					plant,
					data
				)
				* 100.0
			)
		)

		_stage_label.text = (
			"Growing • %d%%"
			% growth_percent
		)
		_stage_label.add_theme_color_override(
			"font_color",
			COLOR_NEUTRAL
		)

	var soil: String = BiomeSystem.get_soil_type_at_cell(
		cell
	)

	if soil.strip_edges() == "":
		soil = "Unknown soil"

	_soil_label.text = soil.to_upper()

	var max_health: float = maxf(
		data.max_health,
		0.001
	)
	var health_ratio: float = clampf(
		float(plant.get("health"))
		/ max_health,
		0.0,
		1.0
	)

	_set_value(
		"health",
		_percent_text(health_ratio),
		_health_color(health_ratio)
	)

	var moisture: float = BiomeSystem.get_moisture(
		cell
	)

	_set_value(
		"moisture",
		_percent_text(moisture),
		_range_color(
			moisture,
			data.optimal_moisture_min,
			data.optimal_moisture_max,
			normalized_warning_margin
		)
	)

	var nutrients: float = BiomeSystem.get_nutrients(
		cell
	)

	_set_value(
		"nutrients",
		_percent_text(nutrients),
		_range_color(
			nutrients,
			data.optimal_nutrients_min,
			data.optimal_nutrients_max,
			normalized_warning_margin
		)
	)

	var ph: float = BiomeSystem.get_ph(
		cell
	)

	_set_value(
		"ph",
		"%.1f" % ph,
		_range_color(
			ph,
			data.optimal_ph_min,
			data.optimal_ph_max,
			ph_warning_margin
		)
	)

	var pests: float = clampf(
		float(plant.get("pest_level")),
		0.0,
		1.0
	)

	_set_value(
		"pests",
		_percent_text(pests),
		_low_is_good_color(pests)
	)

	var disease: float = clampf(
		float(plant.get("disease_level")),
		0.0,
		1.0
	)

	_set_value(
		"disease",
		_percent_text(disease),
		_low_is_good_color(disease)
	)


# Sets the value.
func _set_value(
	key: String,
	text_value: String,
	color: Color
) -> void:
	var label_variant: Variant = _value_labels.get(
		key,
		null
	)

	if not label_variant is Label:
		return

	var label := label_variant as Label
	label.text = text_value
	label.add_theme_color_override(
		"font_color",
		color
	)


# Formats a numeric value as percentage text.
func _percent_text(
	value: float
) -> String:
	if value < 0.0:
		return "-"

	return "%d%%" % int(
		round(
			clampf(
				value,
				0.0,
				1.0
			)
			* 100.0
		)
	)


# Returns the growth progress.
func _get_growth_progress(
	plant: Node,
	data: PlantData
) -> float:
	if data.max_stage <= 0:
		return 1.0

	var stage: int = clampi(
		int(plant.get("stage")),
		0,
		data.max_stage
	)

	if stage >= data.max_stage:
		return 1.0

	var total_hours: float = 0.0
	var completed_hours: float = 0.0

	for index: int in range(
		data.max_stage
	):
		var stage_days: float = 1.0

		if index < data.days_to_next_stage.size():
			stage_days = maxf(
				data.days_to_next_stage[index],
				0.001
			)

		var stage_hours: float = (
			stage_days * 24.0
		)

		total_hours += stage_hours

		if index < stage:
			completed_hours += stage_hours

	if stage < data.days_to_next_stage.size():
		var current_stage_hours: float = maxf(
			data.days_to_next_stage[stage]
			* 24.0,
			0.001
		)

		var current_accum: float = maxf(
			float(
				plant.get(
					"_growth_hours_accum"
				)
			),
			0.0
		)

		completed_hours += minf(
			current_accum,
			current_stage_hours
		)

	if total_hours <= 0.0:
		return 0.0

	return clampf(
		completed_hours / total_hours,
		0.0,
		1.0
	)


# ------------------------------------------------------------------
# Color classification
# ------------------------------------------------------------------

# Returns the display color for a value relative to a target range.
func _range_color(
	value: float,
	ideal_min: float,
	ideal_max: float,
	warning_margin: float
) -> Color:
	if value < 0.0:
		return COLOR_MUTED

	var low: float = minf(
		ideal_min,
		ideal_max
	)
	var high: float = maxf(
		ideal_min,
		ideal_max
	)

	if (
		value >= low
		and value <= high
	):
		return COLOR_GOOD

	var distance: float = 0.0

	if value < low:
		distance = low - value
	else:
		distance = value - high

	if distance <= warning_margin:
		return COLOR_WARNING

	return COLOR_BAD


# Returns the display color for the current plant health.
func _health_color(
	ratio: float
) -> Color:
	if ratio >= health_good_threshold:
		return COLOR_GOOD

	if ratio >= health_warning_threshold:
		return COLOR_WARNING

	return COLOR_BAD


# Returns a status color where lower values are better.
func _low_is_good_color(
	value: float
) -> Color:
	if value <= bio_good_max:
		return COLOR_GOOD

	if value <= bio_warning_max:
		return COLOR_WARNING

	return COLOR_BAD


# ------------------------------------------------------------------
# Position / visibility
# ------------------------------------------------------------------

# Positions the inspector card near the inspected plant.
func _position_card() -> void:
	var mouse: Vector2 = get_viewport().get_mouse_position()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var actual_size: Vector2 = _card.size

	if (
		actual_size.x <= 1.0
		or actual_size.y <= 1.0
	):
		actual_size = card_size

	var target: Vector2 = (
		mouse
		+ cursor_offset
	)

	if (
		target.x
		+ actual_size.x
		+ screen_edge_margin
		> viewport_size.x
	):
		target.x = (
			mouse.x
			- actual_size.x
			- cursor_offset.x
		)

	if (
		target.y
		+ actual_size.y
		+ screen_edge_margin
		> viewport_size.y
	):
		target.y = (
			mouse.y
			- actual_size.y
			- cursor_offset.y
		)

	target.x = clampf(
		target.x,
		screen_edge_margin,
		maxf(
			screen_edge_margin,
			viewport_size.x
			- actual_size.x
			- screen_edge_margin
		)
	)

	target.y = clampf(
		target.y,
		screen_edge_margin,
		maxf(
			screen_edge_margin,
			viewport_size.y
			- actual_size.y
			- screen_edge_margin
		)
	)

	_card.position = target


# Hides the card.
func _hide_card() -> void:
	if _card != null:
		_card.visible = false
