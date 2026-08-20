extends CanvasLayer

# Temporary screen-space progression and seed display.
const ITEM_LILY_SEED: StringName = &"lily_seed"
const ITEM_CACTUS_SEED: StringName = &"cactus_seed"

# Display order for tracked seed types.
const TRACKED_ITEMS: Array[StringName] = [
	ITEM_LILY_SEED,
	ITEM_CACTUS_SEED
]

# Display names for tracked seed types.
const ITEM_DISPLAY_NAMES: Dictionary = {
	ITEM_LILY_SEED: "Lily",
	ITEM_CACTUS_SEED: "Cactus"
}

# Default row presentation.
const DEFAULT_FONT_SIZE: int = 13
const SELECTED_FONT_SIZE: int = 15
const DEFAULT_NAME_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const DEFAULT_AMOUNT_COLOR: Color = Color(1.0, 0.9, 0.45, 1.0)
const SELECTED_COLOR: Color = Color(0.78, 1.0, 0.42, 1.0)
const SELECTED_OUTLINE_COLOR: Color = Color(0.08, 0.16, 0.04, 1.0)


@export_category("Inventory HUD")

# Controls the CanvasLayer drawing order.
@export var hud_layer: int = 4

# Positions the panel from the top-left corner.
@export var screen_offset: Vector2 = Vector2(16.0, 70.0)

# Controls the minimum width of the inventory panel.
@export var panel_width: float = 250.0


@export_category("Debug Logging")

# Enables HUD initialization and update logging.
@export var debug_log: bool = false


# Stores amount labels by inventory item identifier.
var _amount_labels: Dictionary = {}

# Stores item name labels by inventory item identifier.
var _name_labels: Dictionary = {}

# Displays player progression.
var _player_progress_label: Label

# Displays the currently selected plant type.
var _selection_label: Label

# Displays the selected plant mastery progression.
var _plant_progress_label: Label

# Stores the generated inventory panel.
var _panel: PanelContainer


# Builds the HUD and connects system signals.
func _ready() -> void:
	layer = hud_layer

	_build_ui()
	_connect_system_signals()
	_refresh_all()

	if debug_log:
		print(
			"[InventoryHUD] ready layer=",
			layer,
			" offset=",
			screen_offset
		)


# Creates the complete HUD panel.
func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "GardenStatusPanel"
	_panel.position = screen_offset
	_panel.custom_minimum_size = Vector2(panel_width, 0.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override(
		"panel",
		_create_panel_style()
	)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 4)
	margin.add_child(content)

	var title := Label.new()
	title.name = "Title"
	title.text = "GARDEN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override(
		"font_color",
		Color(0.82, 1.0, 0.68, 1.0)
	)
	content.add_child(title)

	_player_progress_label = _create_center_label(
		"Player Lv. 0   XP 0/100",
		13,
		Color(0.72, 0.88, 1.0, 1.0)
	)
	content.add_child(_player_progress_label)

	content.add_child(_create_separator("ProgressSeparator"))

	var seed_title := Label.new()
	seed_title.name = "SeedTitle"
	seed_title.text = "SEEDS"
	seed_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	seed_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seed_title.add_theme_font_size_override("font_size", 14)
	seed_title.add_theme_color_override(
		"font_color",
		Color(0.82, 1.0, 0.68, 1.0)
	)
	content.add_child(seed_title)

	_selection_label = _create_center_label(
		"-",
		16,
		Color(1.0, 0.9, 0.45, 1.0)
	)
	_selection_label.add_theme_color_override(
		"font_outline_color",
		SELECTED_OUTLINE_COLOR
	)
	_selection_label.add_theme_constant_override(
		"outline_size",
		3
	)
	content.add_child(_selection_label)

	_plant_progress_label = _create_center_label(
		"Plant Lv. 0   XP 0/5",
		12,
		Color(0.78, 1.0, 0.62, 1.0)
	)
	content.add_child(_plant_progress_label)

	content.add_child(_create_separator("SeedSeparator"))

	for item_id: StringName in TRACKED_ITEMS:
		content.add_child(_create_item_row(item_id))


# Creates a centered informational label.
func _create_center_label(
	text_value: String,
	font_size: int,
	color: Color
) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(
		"font_size",
		font_size
	)
	label.add_theme_color_override(
		"font_color",
		color
	)
	return label


# Creates a named horizontal separator.
func _create_separator(node_name: String) -> HSeparator:
	var separator := HSeparator.new()
	separator.name = node_name
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return separator


# Creates one inventory item row.
func _create_item_row(item_id: StringName) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = String(item_id)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)

	var name_label := Label.new()
	name_label.text = String(
		ITEM_DISPLAY_NAMES.get(
			item_id,
			String(item_id)
		)
	)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override(
		"font_size",
		DEFAULT_FONT_SIZE
	)
	name_label.add_theme_color_override(
		"font_color",
		DEFAULT_NAME_COLOR
	)
	row.add_child(name_label)
	_name_labels[item_id] = name_label

	var amount_label := Label.new()
	amount_label.name = "Amount"
	amount_label.text = "0"
	amount_label.custom_minimum_size = Vector2(42.0, 0.0)
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	amount_label.add_theme_font_size_override(
		"font_size",
		DEFAULT_FONT_SIZE
	)
	amount_label.add_theme_color_override(
		"font_color",
		DEFAULT_AMOUNT_COLOR
	)
	row.add_child(amount_label)

	_amount_labels[item_id] = amount_label
	return row


# Creates the panel background style.
func _create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.05, 0.86)
	style.border_color = Color(0.48, 0.76, 0.34, 0.92)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style


# Connects HUD updates to inventory, economy, and progression.
func _connect_system_signals() -> void:
	if not InventorySystem.item_amount_changed.is_connected(
		_on_item_amount_changed
	):
		InventorySystem.item_amount_changed.connect(
			_on_item_amount_changed
		)

	if not InventorySystem.inventory_reset.is_connected(
		_on_inventory_reset
	):
		InventorySystem.inventory_reset.connect(
			_on_inventory_reset
		)

	if not ProgressionSystem.player_progress_changed.is_connected(
		_on_player_progress_changed
	):
		ProgressionSystem.player_progress_changed.connect(
			_on_player_progress_changed
		)

	if not ProgressionSystem.plant_progress_changed.is_connected(
		_on_plant_progress_changed
	):
		ProgressionSystem.plant_progress_changed.connect(
			_on_plant_progress_changed
		)

	if not PlantSelectionSystem.selection_changed.is_connected(
		_on_plant_selection_changed
	):
		PlantSelectionSystem.selection_changed.connect(
			_on_plant_selection_changed
		)


# Refreshes every displayed value.
func _refresh_all() -> void:
	for item_id: StringName in TRACKED_ITEMS:
		_refresh_item(item_id)

	_refresh_player_progress()
	_refresh_selection()


# Refreshes one tracked inventory amount.
func _refresh_item(item_id: StringName) -> void:
	var amount_label: Label = _amount_labels.get(item_id)

	if amount_label == null:
		return

	amount_label.text = str(
		InventorySystem.get_amount(item_id)
	)


# Refreshes player XP and milestone currencies.
func _refresh_player_progress() -> void:
	var progress := ProgressionSystem.get_player_progress()
	var level := int(progress.get("level", 0))
	var xp := int(progress.get("xp", 0))
	var xp_to_next := int(progress.get("xp_to_next", 0))
	if level >= ProgressionSystem.MAX_PLAYER_LEVEL:
		_player_progress_label.text = (
			"Player Lv. %d   MAX" % level
		)
	else:
		_player_progress_label.text = (
			"Player Lv. %d   XP %d/%d" % [
				level,
				xp,
				xp_to_next
			]
		)


# Refreshes the selected plant and its mastery progress.
func _refresh_selection() -> void:
	var selected_data := (
		PlantSelectionSystem.get_current_plant()
	)
	var selected_seed_id: StringName = &""

	if selected_data != null:
		selected_seed_id = selected_data.seed_item_id
		_selection_label.text = selected_data.display_name
	else:
		_selection_label.text = "None"

	for item_id: StringName in TRACKED_ITEMS:
		_apply_row_selection(
			item_id,
			item_id == selected_seed_id
		)

	_refresh_selected_plant_progress()


# Refreshes the selected plant mastery label.
func _refresh_selected_plant_progress() -> void:
	var selected_data := (
		PlantSelectionSystem.get_current_plant()
	)

	if selected_data == null:
		_plant_progress_label.text = "Plant progress unavailable"
		return

	var progress := ProgressionSystem.get_plant_progress(
		selected_data.seed_item_id
	)
	var level := int(progress.get("level", 0))
	var xp := int(progress.get("xp", 0))
	var xp_to_next := int(progress.get("xp_to_next", 0))

	if level >= ProgressionSystem.MAX_PLANT_LEVEL:
		_plant_progress_label.text = (
			"Plant Lv. %d   MAX" % level
		)
	else:
		_plant_progress_label.text = (
			"Plant Lv. %d   XP %d/%d" % [
				level,
				xp,
				xp_to_next
			]
		)


# Applies a stronger visual state to the selected plant row.
func _apply_row_selection(
	item_id: StringName,
	is_selected: bool
) -> void:
	var name_label: Label = _name_labels.get(item_id)
	var amount_label: Label = _amount_labels.get(item_id)

	if name_label == null or amount_label == null:
		return

	var display_name := String(
		ITEM_DISPLAY_NAMES.get(
			item_id,
			String(item_id)
		)
	)

	if is_selected:
		name_label.text = "▶ " + display_name

		name_label.add_theme_font_size_override(
			"font_size",
			SELECTED_FONT_SIZE
		)
		amount_label.add_theme_font_size_override(
			"font_size",
			SELECTED_FONT_SIZE
		)

		name_label.add_theme_color_override(
			"font_color",
			SELECTED_COLOR
		)
		amount_label.add_theme_color_override(
			"font_color",
			SELECTED_COLOR
		)

		name_label.add_theme_color_override(
			"font_outline_color",
			SELECTED_OUTLINE_COLOR
		)
		amount_label.add_theme_color_override(
			"font_outline_color",
			SELECTED_OUTLINE_COLOR
		)

		name_label.add_theme_constant_override(
			"outline_size",
			2
		)
		amount_label.add_theme_constant_override(
			"outline_size",
			2
		)
	else:
		name_label.text = display_name

		name_label.add_theme_font_size_override(
			"font_size",
			DEFAULT_FONT_SIZE
		)
		amount_label.add_theme_font_size_override(
			"font_size",
			DEFAULT_FONT_SIZE
		)

		name_label.add_theme_color_override(
			"font_color",
			DEFAULT_NAME_COLOR
		)
		amount_label.add_theme_color_override(
			"font_color",
			DEFAULT_AMOUNT_COLOR
		)

		name_label.remove_theme_color_override(
			"font_outline_color"
		)
		amount_label.remove_theme_color_override(
			"font_outline_color"
		)

		name_label.remove_theme_constant_override(
			"outline_size"
		)
		amount_label.remove_theme_constant_override(
			"outline_size"
		)


# Handles an individual inventory amount change.
func _on_item_amount_changed(
	item_id: StringName,
	previous_amount: int,
	new_amount: int
) -> void:
	if not _amount_labels.has(item_id):
		return

	_refresh_item(item_id)

	if debug_log:
		print(
			"[InventoryHUD] update item=",
			String(item_id),
			" old=",
			previous_amount,
			" new=",
			new_amount
		)


# Handles a complete inventory reset.
func _on_inventory_reset(_items: Dictionary) -> void:
	for item_id: StringName in TRACKED_ITEMS:
		_refresh_item(item_id)

	if debug_log:
		print("[InventoryHUD] inventory reset")


# Handles global player progression changes.
func _on_player_progress_changed(
	_level: int,
	_xp: int,
	_xp_to_next: int
) -> void:
	_refresh_player_progress()


# Handles plant mastery progression changes.
func _on_plant_progress_changed(
	plant_id: StringName,
	_level: int,
	_xp: int,
	_xp_to_next: int
) -> void:
	var selected_data := (
		PlantSelectionSystem.get_current_plant()
	)

	if (
		selected_data != null
		and selected_data.seed_item_id == plant_id
	):
		_refresh_selected_plant_progress()


# Handles a changed plant selection.
func _on_plant_selection_changed(
	plant_data: PlantData,
	index: int
) -> void:
	_refresh_selection()

	if debug_log:
		print(
			"[InventoryHUD] selection plant=",
			plant_data.display_name,
			" index=",
			index
		)
