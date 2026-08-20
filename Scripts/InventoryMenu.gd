extends CanvasLayer

# Full-screen plant inventory with two-way drag and drop.
signal inventory_opened()
signal inventory_closed()


const GRID_COLUMNS: int = 4
const INVENTORY_SLOT_SIZE: Vector2 = Vector2(88.0, 88.0)
const HOTBAR_SLOT_SIZE: Vector2 = Vector2(64.0, 64.0)


@export_category("Inventory Menu")

# Controls the CanvasLayer drawing order.
@export var menu_layer: int = 20

# Size of plant icons inside inventory slots.
@export var item_icon_size: Vector2 = Vector2(58.0, 58.0)

# Pauses world simulation while the inventory is open.
@export var pause_game_while_open: bool = true


@export_category("Debug Logging")

# Enables inventory menu interaction logging.
@export var debug_log: bool = false


# Stores the full-screen menu root.
var _menu_root: Control

# Stores inventory slot controls.
var _inventory_buttons: Array[Button] = []
var _inventory_icons: Array[TextureRect] = []
var _inventory_amount_labels: Array[Label] = []

# Stores editable hotbar controls.
var _hotbar_buttons: Array[Button] = []
var _hotbar_icons: Array[TextureRect] = []
var _hotbar_amount_labels: Array[Label] = []

# Stores the editable hotbar panel.
var _hotbar_editor_panel: PanelContainer

# Displays hotbar instructions and capacity errors.
var _hotbar_status_label: Label

# Stores the active hotbar error animation.
var _hotbar_error_tween: Tween

# Displays focused plant details.
var _details_name_label: Label
var _details_amount_label: Label
var _details_level_label: Label
var _details_xp_label: Label
var _details_reward_label: Label

# Selects or deselects the focused plant.
var _selection_button: Button

# Stores the focused plant independently from its slot.
var _focused_plant: PlantData = null

# Tracks whether the menu is open.
var _is_open: bool = false

# Preserves gameplay state while the menu is open.
var _previous_pause_state: bool = false
var _previous_mouse_mode: Input.MouseMode = (
	Input.MOUSE_MODE_VISIBLE
)


# Builds the menu and connects inventory systems.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = menu_layer
	add_to_group("modal_menu")

	_build_menu()
	_connect_system_signals()
	_initialize_focus()
	_set_menu_open(false, false)
	_refresh_all()

	if debug_log:
		print(
			"[InventoryMenu] ready inventory_slots=",
			InventoryLayoutSystem.get_slot_count(),
			" hotbar_slots=",
			HotbarSystem.get_slot_count()
		)


# Handles inventory opening and closing.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		toggle_inventory()
		get_viewport().set_input_as_handled()
		return

	if _is_open and event.is_action_pressed("ui_cancel"):
		close_inventory()
		get_viewport().set_input_as_handled()


# Opens or closes the inventory.
func toggle_inventory() -> void:
	_set_menu_open(not _is_open, true)


# Opens the inventory.
func open_inventory() -> void:
	_set_menu_open(true, true)


# Allows other modal menus to close this inventory.
func close_modal_menu() -> void:
	close_inventory()


# Returns whether this modal menu is open.
func is_modal_menu_open() -> bool:
	return _is_open


# Closes the inventory.
func close_inventory() -> void:
	_set_menu_open(false, true)


# Returns whether the inventory is currently open.
func is_inventory_open() -> bool:
	return _is_open


# Applies menu visibility, cursor, and pause behavior.
func _set_menu_open(
	should_open: bool,
	should_emit_signal: bool
) -> void:
	if should_open == _is_open and _menu_root != null:
		_menu_root.visible = should_open
		return

	if should_open:
		_close_other_modal_menus()

	_is_open = should_open
	_menu_root.visible = _is_open

	if _is_open:
		_previous_pause_state = get_tree().paused
		_previous_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

		if pause_game_while_open:
			get_tree().paused = true

		_refresh_all()

		if should_emit_signal:
			inventory_opened.emit()

		if debug_log:
			print("[InventoryMenu] opened")
	else:
		if pause_game_while_open:
			get_tree().paused = _previous_pause_state

		Input.mouse_mode = _previous_mouse_mode

		if should_emit_signal:
			inventory_closed.emit()

		if debug_log:
			print("[InventoryMenu] closed")


# Closes any other open modal menu.
func _close_other_modal_menus() -> void:
	for menu: Node in get_tree().get_nodes_in_group(
		"modal_menu"
	):
		if menu == self:
			continue

		if (
			menu.has_method("is_modal_menu_open")
			and bool(menu.call("is_modal_menu_open"))
			and menu.has_method("close_modal_menu")
		):
			menu.call("close_modal_menu")


# Creates the full-screen inventory layout.
func _build_menu() -> void:
	_menu_root = Control.new()
	_menu_root.name = "InventoryMenuRoot"
	_menu_root.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_menu_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_menu_root)

	var dim_background := ColorRect.new()
	dim_background.name = "DimBackground"
	dim_background.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	dim_background.color = Color(0.0, 0.0, 0.0, 0.58)
	dim_background.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_root.add_child(dim_background)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "InventoryPanel"
	panel.custom_minimum_size = Vector2(760.0, 560.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override(
		"panel",
		_create_main_panel_style()
	)
	center.add_child(panel)

	var outer_margin := MarginContainer.new()
	outer_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer_margin.add_theme_constant_override("margin_left", 20)
	outer_margin.add_theme_constant_override("margin_top", 16)
	outer_margin.add_theme_constant_override("margin_right", 20)
	outer_margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(outer_margin)

	var main_column := VBoxContainer.new()
	main_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_column.add_theme_constant_override("separation", 12)
	outer_margin.add_child(main_column)

	main_column.add_child(_create_header())

	var content_row := HBoxContainer.new()
	content_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_row.add_theme_constant_override("separation", 18)
	main_column.add_child(content_row)

	content_row.add_child(_create_inventory_grid())
	content_row.add_child(_create_details_panel())
	main_column.add_child(_create_hotbar_editor())


# Creates the inventory title and close button.
func _create_header() -> Control:
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var title := Label.new()
	title.text = "INVENTORY"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override(
		"font_color",
		Color(0.82, 1.0, 0.68, 1.0)
	)
	title.add_theme_color_override(
		"font_outline_color",
		Color(0.02, 0.03, 0.02, 1.0)
	)
	title.add_theme_constant_override("outline_size", 3)
	header.add_child(title)

	var close_button := Button.new()
	close_button.text = "Close  [I / Esc]"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	close_button.pressed.connect(close_inventory)
	close_button.add_theme_stylebox_override(
		"normal",
		_create_action_button_style(false, false)
	)
	close_button.add_theme_stylebox_override(
		"hover",
		_create_action_button_style(false, true)
	)
	close_button.add_theme_stylebox_override(
		"pressed",
		_create_action_button_style(true, true)
	)
	header.add_child(close_button)

	return header


# Creates the movable inventory grid.
func _create_inventory_grid() -> Control:
	var grid_panel := PanelContainer.new()
	grid_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid_panel.add_theme_stylebox_override(
		"panel",
		_create_inner_panel_style()
	)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	grid_panel.add_child(margin)

	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	margin.add_child(grid)

	for index in range(
		InventoryLayoutSystem.get_slot_count()
	):
		grid.add_child(_create_inventory_slot(index))

	return grid_panel


# Creates one inventory slot with two-way drag support.
func _create_inventory_slot(index: int) -> Button:
	var button := Button.new()
	button.name = "InventorySlot%d" % (index + 1)
	button.custom_minimum_size = INVENTORY_SLOT_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.text = ""
	button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	button.pressed.connect(
		_on_inventory_slot_pressed.bind(index)
	)
	button.gui_input.connect(
		_on_inventory_slot_gui_input.bind(index)
	)
	button.set_drag_forwarding(
		_get_inventory_drag_data.bind(index),
		_can_drop_on_inventory.bind(index),
		_drop_on_inventory.bind(index)
	)

	var icon := TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_CENTER)
	icon.custom_minimum_size = item_icon_size
	icon.position = -item_icon_size * 0.5
	icon.size = item_icon_size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)

	var amount_label := Label.new()
	amount_label.set_anchors_preset(
		Control.PRESET_BOTTOM_RIGHT
	)
	amount_label.offset_left = -38.0
	amount_label.offset_top = -27.0
	amount_label.offset_right = -6.0
	amount_label.offset_bottom = -4.0
	amount_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	amount_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_BOTTOM
	)
	amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	amount_label.add_theme_font_size_override(
		"font_size",
		16
	)
	amount_label.add_theme_color_override(
		"font_outline_color",
		Color(0.02, 0.02, 0.02, 1.0)
	)
	amount_label.add_theme_constant_override(
		"outline_size",
		4
	)
	button.add_child(amount_label)

	_inventory_buttons.append(button)
	_inventory_icons.append(icon)
	_inventory_amount_labels.append(amount_label)

	return button


# Creates the focused-plant details panel.
func _create_details_panel() -> Control:
	var details_panel := PanelContainer.new()
	details_panel.custom_minimum_size = Vector2(270.0, 0.0)
	details_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details_panel.add_theme_stylebox_override(
		"panel",
		_create_inner_panel_style()
	)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	details_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	_details_name_label = _create_detail_label(
		"No plant focused",
		20,
		Color(0.82, 1.0, 0.68, 1.0)
	)
	content.add_child(_details_name_label)

	content.add_child(HSeparator.new())

	_details_amount_label = _create_detail_label(
		"Seeds: 0",
		14,
		Color(1.0, 0.90, 0.45, 1.0)
	)
	content.add_child(_details_amount_label)

	_details_level_label = _create_detail_label(
		"Plant Level: 0",
		14,
		Color(0.75, 0.90, 1.0, 1.0)
	)
	content.add_child(_details_level_label)

	_details_xp_label = _create_detail_label(
		"Plant XP: 0/0",
		14,
		Color(0.75, 0.90, 1.0, 1.0)
	)
	content.add_child(_details_xp_label)

	content.add_child(HSeparator.new())

	_details_reward_label = _create_detail_label(
		"Harvest reward unavailable",
		13,
		Color(0.84, 0.84, 0.82, 1.0)
	)
	_details_reward_label.autowrap_mode = (
		TextServer.AUTOWRAP_WORD_SMART
	)
	content.add_child(_details_reward_label)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(spacer)

	_selection_button = Button.new()
	_selection_button.text = "Select"
	_selection_button.custom_minimum_size = Vector2(0.0, 42.0)
	_selection_button.focus_mode = Control.FOCUS_NONE
	_selection_button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	_selection_button.pressed.connect(
		_on_selection_button_pressed
	)
	content.add_child(_selection_button)

	var hint := Label.new()
	hint.text = (
		"Single click: inspect\n"
		+ "Double-click: add/remove from hotbar\n"
		+ "Drag inventory ↔ inventory: move or swap\n"
		+ "Drag hotbar → chosen inventory slot: remove"
	)
	hint.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override(
		"font_color",
		Color(0.66, 0.70, 0.65, 1.0)
	)
	content.add_child(hint)

	return details_panel


# Creates the editable hotbar.
func _create_hotbar_editor() -> Control:
	var wrapper := VBoxContainer.new()
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_theme_constant_override("separation", 6)

	_hotbar_status_label = Label.new()
	_hotbar_status_label.text = (
		"HOTBAR — drag plants to empty slots"
	)
	_hotbar_status_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_hotbar_status_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_hotbar_status_label.add_theme_font_size_override(
		"font_size",
		13
	)
	_hotbar_status_label.add_theme_color_override(
		"font_color",
		Color(0.78, 0.84, 0.76, 1.0)
	)
	wrapper.add_child(_hotbar_status_label)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(center)

	_hotbar_editor_panel = PanelContainer.new()
	_hotbar_editor_panel.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_hotbar_editor_panel.add_theme_stylebox_override(
		"panel",
		_create_inner_panel_style()
	)
	center.add_child(_hotbar_editor_panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 7)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 7)
	margin.add_theme_constant_override("margin_bottom", 7)
	_hotbar_editor_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation", 5)
	margin.add_child(row)

	for index in range(HotbarSystem.get_slot_count()):
		row.add_child(_create_hotbar_slot(index))

	return wrapper


# Creates one hotbar drag source and drop target.
func _create_hotbar_slot(index: int) -> Button:
	var button := Button.new()
	button.name = "HotbarSlot%d" % (index + 1)
	button.custom_minimum_size = HOTBAR_SLOT_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.text = ""
	button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	button.pressed.connect(
		_on_hotbar_slot_pressed.bind(index)
	)
	button.gui_input.connect(
		_on_hotbar_slot_gui_input.bind(index)
	)
	button.set_drag_forwarding(
		_get_hotbar_drag_data.bind(index),
		_can_drop_on_hotbar.bind(index),
		_drop_on_hotbar.bind(index)
	)

	var icon := TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_CENTER)
	icon.custom_minimum_size = Vector2(44.0, 44.0)
	icon.position = Vector2(-22.0, -22.0)
	icon.size = Vector2(44.0, 44.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)

	var amount_label := Label.new()
	amount_label.set_anchors_preset(
		Control.PRESET_BOTTOM_RIGHT
	)
	amount_label.offset_left = -34.0
	amount_label.offset_top = -25.0
	amount_label.offset_right = -5.0
	amount_label.offset_bottom = -3.0
	amount_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT
	)
	amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	amount_label.add_theme_font_size_override("font_size", 14)
	amount_label.add_theme_color_override(
		"font_outline_color",
		Color(0.02, 0.02, 0.02, 1.0)
	)
	amount_label.add_theme_constant_override(
		"outline_size",
		3
	)
	button.add_child(amount_label)

	var number_label := Label.new()
	number_label.text = str(index + 1)
	number_label.position = Vector2(5.0, 2.0)
	number_label.size = Vector2(18.0, 16.0)
	number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number_label.add_theme_font_size_override("font_size", 9)
	number_label.add_theme_color_override(
		"font_color",
		Color(0.70, 0.74, 0.68, 1.0)
	)
	button.add_child(number_label)

	_hotbar_buttons.append(button)
	_hotbar_icons.append(icon)
	_hotbar_amount_labels.append(amount_label)

	return button


# Creates one details label.
func _create_detail_label(
	text_value: String,
	font_size: int,
	color: Color
) -> Label:
	var label := Label.new()
	label.text = text_value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override(
		"font_outline_color",
		Color(0.02, 0.03, 0.02, 1.0)
	)
	label.add_theme_constant_override("outline_size", 2)
	return label


# Initializes the focused plant.
func _initialize_focus() -> void:
	var selected: PlantData = PlantSelectionSystem.get_current_plant()

	if selected != null:
		_focused_plant = selected
		return

	for index in range(
		InventoryLayoutSystem.get_slot_count()
	):
		var plant_data: PlantData = InventoryLayoutSystem.get_plant(index)

		if plant_data != null:
			_focused_plant = plant_data
			return


# Connects inventory, layout, hotbar, and progression signals.
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

	if not InventoryLayoutSystem.slot_changed.is_connected(
		_on_inventory_layout_slot_changed
	):
		InventoryLayoutSystem.slot_changed.connect(
			_on_inventory_layout_slot_changed
		)

	if not InventoryLayoutSystem.layout_reset.is_connected(
		_on_inventory_layout_reset
	):
		InventoryLayoutSystem.layout_reset.connect(
			_on_inventory_layout_reset
		)

	if not ProgressionSystem.plant_progress_changed.is_connected(
		_on_plant_progress_changed
	):
		ProgressionSystem.plant_progress_changed.connect(
			_on_plant_progress_changed
		)

	if not HotbarSystem.slot_changed.is_connected(
		_on_hotbar_slot_changed
	):
		HotbarSystem.slot_changed.connect(
			_on_hotbar_slot_changed
		)

	if not HotbarSystem.hotbar_reset.is_connected(
		_on_hotbar_reset
	):
		HotbarSystem.hotbar_reset.connect(
			_on_hotbar_reset
		)

	if not HotbarSystem.assignment_failed.is_connected(
		_on_hotbar_assignment_failed
	):
		HotbarSystem.assignment_failed.connect(
			_on_hotbar_assignment_failed
		)

	if not PlantSelectionSystem.selection_changed.is_connected(
		_on_plant_selection_changed
	):
		PlantSelectionSystem.selection_changed.connect(
			_on_plant_selection_changed
		)


# Refreshes the complete menu.
func _refresh_all() -> void:
	for index in range(_inventory_buttons.size()):
		_refresh_inventory_slot(index)

	for index in range(_hotbar_buttons.size()):
		_refresh_hotbar_slot(index)

	_refresh_details()
	_refresh_selection_button()


# Refreshes one dynamic inventory slot.
func _refresh_inventory_slot(index: int) -> void:
	if index < 0 or index >= _inventory_buttons.size():
		return

	var plant_data: PlantData = InventoryLayoutSystem.get_plant(index)
	var button := _inventory_buttons[index]
	var icon := _inventory_icons[index]
	var amount_label := _inventory_amount_labels[index]

	if plant_data == null:
		button.tooltip_text = (
			"Empty inventory slot"
			+ "\nDrop an inventory or hotbar plant here"
		)
		icon.texture = null
		icon.modulate = Color.WHITE
		amount_label.text = ""
	else:
		button.tooltip_text = (
			plant_data.display_name
			+ "\nClick: inspect"
			+ "\nDouble-click: add/remove from hotbar"
			+ "\nDrag: move or swap"
		)
		icon.texture = _create_plant_icon(plant_data)

		var amount := InventorySystem.get_amount(
			plant_data.seed_item_id
		)
		amount_label.text = str(amount)

		if amount > 0:
			amount_label.add_theme_color_override(
				"font_color",
				Color.WHITE
			)
			icon.modulate = Color.WHITE
		else:
			amount_label.add_theme_color_override(
				"font_color",
				Color(1.0, 0.38, 0.34, 1.0)
			)
			icon.modulate = Color(0.55, 0.55, 0.55, 0.72)

	_apply_inventory_slot_style(index)


# Refreshes one editable hotbar slot.
func _refresh_hotbar_slot(index: int) -> void:
	if index < 0 or index >= _hotbar_buttons.size():
		return

	var plant_data: PlantData = HotbarSystem.get_plant(index)
	var button := _hotbar_buttons[index]
	var icon := _hotbar_icons[index]
	var amount_label := _hotbar_amount_labels[index]

	if plant_data == null:
		button.tooltip_text = "Empty hotbar slot"
		icon.texture = null
		icon.modulate = Color.WHITE
		amount_label.text = ""
	else:
		button.tooltip_text = (
			plant_data.display_name
			+ "\nClick: select"
			+ "\nDrag to inventory: remove and place"
		)
		icon.texture = _create_plant_icon(plant_data)
		amount_label.text = str(
			InventorySystem.get_amount(
				plant_data.seed_item_id
			)
		)

	_apply_hotbar_slot_style(index)


# Applies one inventory slot state.
func _apply_inventory_slot_style(index: int) -> void:
	var plant_data: PlantData = InventoryLayoutSystem.get_plant(index)
	var focused: bool = (
		plant_data != null
		and _focused_plant != null
		and plant_data.seed_item_id
		== _focused_plant.seed_item_id
	)
	var in_hotbar: bool = (
		plant_data != null
		and HotbarSystem.contains_plant(plant_data)
	)
	var active: bool = (
		plant_data != null
		and PlantSelectionSystem.is_selected(plant_data)
	)
	var empty: bool = plant_data == null
	var button := _inventory_buttons[index]

	button.add_theme_stylebox_override(
		"normal",
		_create_inventory_slot_style(
			focused,
			in_hotbar,
			active,
			false,
			empty
		)
	)
	button.add_theme_stylebox_override(
		"hover",
		_create_inventory_slot_style(
			focused,
			in_hotbar,
			active,
			true,
			empty
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_create_inventory_slot_style(
			true,
			in_hotbar,
			active,
			true,
			false
		)
	)


# Applies one hotbar slot state.
func _apply_hotbar_slot_style(index: int) -> void:
	var plant_data: PlantData = HotbarSystem.get_plant(index)
	var selected: bool = (
		plant_data != null
		and PlantSelectionSystem.is_selected(plant_data)
	)
	var empty: bool = plant_data == null
	var button := _hotbar_buttons[index]

	button.add_theme_stylebox_override(
		"normal",
		_create_hotbar_slot_style(
			selected,
			false,
			empty
		)
	)
	button.add_theme_stylebox_override(
		"hover",
		_create_hotbar_slot_style(
			selected,
			true,
			empty
		)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_create_hotbar_slot_style(
			true,
			true,
			false
		)
	)


# Refreshes focused plant details.
func _refresh_details() -> void:
	if _focused_plant == null:
		_details_name_label.text = "No plant focused"
		_details_amount_label.text = "Seeds: 0"
		_details_level_label.text = "Plant Level: 0"
		_details_xp_label.text = "Plant XP: 0/0"
		_details_reward_label.text = (
			"Harvest reward unavailable"
		)
		return

	var item_id := _focused_plant.seed_item_id
	var progress := (
		ProgressionSystem.get_plant_progress(item_id)
	)
	var rewards := (
		ProgressionSystem.get_harvest_rewards(item_id)
	)
	var level := int(progress.get("level", 0))
	var xp := int(progress.get("xp", 0))
	var xp_to_next := int(
		progress.get("xp_to_next", 0)
	)

	_details_name_label.text = _focused_plant.display_name
	_details_amount_label.text = "Seeds: %d" % (
		InventorySystem.get_amount(item_id)
	)
	_details_level_label.text = (
		"Plant Level: %d" % level
	)

	if xp_to_next <= 0:
		_details_xp_label.text = "Plant XP: MAX"
	else:
		_details_xp_label.text = (
			"Plant XP: %d/%d" % [
				xp,
				xp_to_next
			]
		)

	_details_reward_label.text = (
		"Current harvest reward\n"
		+ "Seeds: %d\nMoney: %d\nPlayer XP: %d" % [
			int(rewards.get("seed_gain", 0)),
			int(rewards.get("money_gain", 0)),
			int(rewards.get("player_xp_gain", 0))
		]
	)


# Refreshes the Select or Deselect button.
func _refresh_selection_button() -> void:
	if _focused_plant == null:
		_selection_button.text = "Select"
		_selection_button.disabled = true
		return

	_selection_button.disabled = false
	var in_hotbar: bool = HotbarSystem.contains_plant(
		_focused_plant
	)

	_selection_button.text = (
		"Deselect" if in_hotbar else "Select"
	)

	_selection_button.add_theme_stylebox_override(
		"normal",
		_create_action_button_style(in_hotbar, false)
	)
	_selection_button.add_theme_stylebox_override(
		"hover",
		_create_action_button_style(in_hotbar, true)
	)
	_selection_button.add_theme_stylebox_override(
		"pressed",
		_create_action_button_style(not in_hotbar, true)
	)


# Focuses the plant stored in one inventory slot.
func _focus_inventory_slot(index: int) -> void:
	var plant_data: PlantData = InventoryLayoutSystem.get_plant(index)

	if plant_data == null:
		return

	_focused_plant = plant_data
	_refresh_all()


# Handles one inventory-slot click.
func _on_inventory_slot_pressed(index: int) -> void:
	_focus_inventory_slot(index)

	if debug_log:
		var plant_data: PlantData = InventoryLayoutSystem.get_plant(index)

		if plant_data != null:
			print(
				"[InventoryMenu] focused slot=",
				index,
				" plant=",
				plant_data.display_name
			)


# Handles a double-click hotbar toggle.
func _on_inventory_slot_gui_input(
	event: InputEvent,
	index: int
) -> void:
	if not event is InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton

	if (
		mouse_event.button_index != MOUSE_BUTTON_LEFT
		or not mouse_event.pressed
		or not mouse_event.double_click
	):
		return

	var plant_data: PlantData = InventoryLayoutSystem.get_plant(index)

	if plant_data == null:
		return

	_focused_plant = plant_data
	_toggle_focused_plant_hotbar()
	_inventory_buttons[index].accept_event()


# Adds or removes the focused plant from the hotbar.
func _on_selection_button_pressed() -> void:
	_toggle_focused_plant_hotbar()


# Toggles the focused plant's hotbar membership.
func _toggle_focused_plant_hotbar() -> bool:
	if _focused_plant == null:
		return false

	if HotbarSystem.contains_plant(_focused_plant):
		return HotbarSystem.remove_plant(_focused_plant)

	var assigned_slot := HotbarSystem.add_plant(
		_focused_plant
	)

	if assigned_slot < 0:
		return false

	PlantSelectionSystem.set_plant(_focused_plant)
	return true


# Selects a plant from the editable hotbar.
func _on_hotbar_slot_pressed(index: int) -> void:
	var plant_data: PlantData = HotbarSystem.get_plant(index)

	if plant_data == null:
		return

	_focused_plant = plant_data
	PlantSelectionSystem.set_plant(plant_data)
	_refresh_all()


# Removes a hotbar item with a left-button double-click.
func _on_hotbar_slot_gui_input(
	event: InputEvent,
	index: int
) -> void:
	if not event is InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton

	if (
		mouse_event.button_index != MOUSE_BUTTON_LEFT
		or not mouse_event.pressed
		or not mouse_event.double_click
	):
		return

	var plant_data: PlantData = HotbarSystem.get_plant(index)

	if plant_data == null:
		return

	_focused_plant = plant_data

	if not HotbarSystem.clear_slot(index):
		return

	_refresh_all()
	_hotbar_buttons[index].accept_event()

	if debug_log:
		print(
			"[InventoryMenu] hotbar double-click removed plant=",
			plant_data.display_name,
			" slot=",
			index
		)


# Creates inventory drag data.
func _get_inventory_drag_data(
	_at_position: Vector2,
	source_index: int
) -> Variant:
	var plant_data: PlantData = InventoryLayoutSystem.get_plant(
		source_index
	)

	if plant_data == null:
		return null

	_focused_plant = plant_data
	_inventory_buttons[source_index].set_drag_preview(
		_create_drag_preview(plant_data)
	)

	return {
		"type": "inventory_plant",
		"plant_data": plant_data,
		"source_inventory_slot": source_index
	}


# Creates hotbar drag data.
func _get_hotbar_drag_data(
	_at_position: Vector2,
	source_index: int
) -> Variant:
	var plant_data: PlantData = HotbarSystem.get_plant(source_index)

	if plant_data == null:
		return null

	_focused_plant = plant_data
	_hotbar_buttons[source_index].set_drag_preview(
		_create_drag_preview(plant_data)
	)

	return {
		"type": "hotbar_plant",
		"plant_data": plant_data,
		"source_hotbar_slot": source_index
	}


# Accepts inventory or hotbar plants on inventory slots.
func _can_drop_on_inventory(
	_at_position: Vector2,
	data: Variant,
	_target_index: int
) -> bool:
	if not data is Dictionary:
		return false

	var drag_data: Dictionary = data
	var drag_type := String(drag_data.get("type", ""))

	return (
		drag_type == "inventory_plant"
		or drag_type == "hotbar_plant"
	)


# Moves or returns a plant to the exact inventory slot.
func _drop_on_inventory(
	_at_position: Vector2,
	data: Variant,
	target_index: int
) -> void:
	if not _can_drop_on_inventory(
		Vector2.ZERO,
		data,
		target_index
	):
		return

	var drag_data: Dictionary = data
	var drag_type := String(drag_data.get("type", ""))
	var plant_data: PlantData = drag_data.get(
		"plant_data",
		null
	)

	if plant_data == null:
		return

	var moved := false

	if drag_type == "inventory_plant":
		var source_index := int(
			drag_data.get("source_inventory_slot", -1)
		)
		moved = InventoryLayoutSystem.move_slot(
			source_index,
			target_index
		)
	elif drag_type == "hotbar_plant":
		var source_hotbar_slot := int(
			drag_data.get("source_hotbar_slot", -1)
		)

		if source_hotbar_slot < 0:
			return

		if not HotbarSystem.clear_slot(source_hotbar_slot):
			return

		moved = InventoryLayoutSystem.move_plant_to_slot(
			plant_data,
			target_index
		)

	if not moved:
		return

	_focused_plant = plant_data
	_refresh_all()

	if debug_log:
		print(
			"[InventoryMenu] inventory drop type=",
			drag_type,
			" plant=",
			plant_data.display_name,
			" target=",
			target_index
		)


# Accepts inventory or hotbar plants on hotbar slots.
func _can_drop_on_hotbar(
	_at_position: Vector2,
	data: Variant,
	_target_index: int
) -> bool:
	if not data is Dictionary:
		return false

	var drag_data: Dictionary = data
	var drag_type := String(drag_data.get("type", ""))

	return (
		drag_type == "inventory_plant"
		or drag_type == "hotbar_plant"
	)


# Adds or moves one plant to a requested hotbar slot.
func _drop_on_hotbar(
	_at_position: Vector2,
	data: Variant,
	target_index: int
) -> void:
	if not _can_drop_on_hotbar(
		Vector2.ZERO,
		data,
		target_index
	):
		return

	var drag_data: Dictionary = data
	var plant_data: PlantData = drag_data.get(
		"plant_data",
		null
	)

	if plant_data == null:
		return

	var assigned: bool = HotbarSystem.assign_plant(
		target_index,
		plant_data
	)

	if not assigned:
		return

	_focused_plant = plant_data
	PlantSelectionSystem.set_plant(plant_data)
	_refresh_all()


# Creates a plant drag preview.
func _create_drag_preview(
	plant_data: PlantData
) -> Control:
	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(68.0, 68.0)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_theme_stylebox_override(
		"panel",
		_create_drag_preview_style()
	)

	var icon := TextureRect.new()
	icon.texture = _create_plant_icon(plant_data)
	icon.custom_minimum_size = Vector2(58.0, 58.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_child(icon)

	return preview


# Creates a cropped icon from the plant's final stage.
func _create_plant_icon(
	plant_data: PlantData
) -> Texture2D:
	if plant_data == null:
		return null

	if plant_data.stage_textures.is_empty():
		return null

	var stage_index := clampi(
		plant_data.max_stage,
		0,
		plant_data.stage_textures.size() - 1
	)
	var source_texture := (
		plant_data.stage_textures[stage_index]
	)

	if source_texture == null:
		return null

	if stage_index >= plant_data.stage_regions.size():
		return source_texture

	var region := plant_data.stage_regions[stage_index]

	if region.size.x <= 0.0 or region.size.y <= 0.0:
		return source_texture

	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = source_texture
	atlas_texture.region = region
	return atlas_texture


# Handles one inventory layout change.
func _on_inventory_layout_slot_changed(
	slot_index: int,
	_plant_data: PlantData
) -> void:
	_refresh_inventory_slot(slot_index)


# Handles a complete inventory layout reset.
func _on_inventory_layout_reset() -> void:
	_initialize_focus()
	_refresh_all()


# Handles inventory quantity changes.
func _on_item_amount_changed(
	item_id: StringName,
	_previous_amount: int,
	_new_amount: int
) -> void:
	for index in range(_inventory_buttons.size()):
		var plant_data: PlantData = InventoryLayoutSystem.get_plant(index)

		if (
			plant_data != null
			and plant_data.seed_item_id == item_id
		):
			_refresh_inventory_slot(index)

	for index in range(_hotbar_buttons.size()):
		var plant_data: PlantData = HotbarSystem.get_plant(index)

		if (
			plant_data != null
			and plant_data.seed_item_id == item_id
		):
			_refresh_hotbar_slot(index)

	_refresh_details()


# Handles a complete inventory quantity reset.
func _on_inventory_reset(_items: Dictionary) -> void:
	_refresh_all()


# Handles plant mastery changes.
func _on_plant_progress_changed(
	plant_id: StringName,
	_level: int,
	_xp: int,
	_xp_to_next: int
) -> void:
	if (
		_focused_plant != null
		and _focused_plant.seed_item_id == plant_id
	):
		_refresh_details()


# Handles one hotbar assignment change.
func _on_hotbar_slot_changed(
	slot_index: int,
	_plant_data: PlantData
) -> void:
	_refresh_hotbar_slot(slot_index)

	for index in range(_inventory_buttons.size()):
		_apply_inventory_slot_style(index)

	_refresh_selection_button()


# Handles a complete hotbar reset.
func _on_hotbar_reset() -> void:
	_refresh_all()


# Handles rejected hotbar assignments.
func _on_hotbar_assignment_failed(
	reason: String,
	_plant_data: PlantData,
	_slot_index: int
) -> void:
	_flash_hotbar_error(reason)


# Handles active plant selection changes.
func _on_plant_selection_changed(
	_plant_data: PlantData,
	_index: int
) -> void:
	_refresh_all()


# Flashes the hotbar editor in red.
func _flash_hotbar_error(reason: String) -> void:
	if _hotbar_editor_panel == null:
		return

	if _hotbar_error_tween != null and _hotbar_error_tween.is_valid():
		_hotbar_error_tween.kill()

	var error_text := "HOTBAR ERROR"

	match reason:
		HotbarSystem.REASON_HOTBAR_FULL:
			error_text = "HOTBAR FULL — remove an item first"
		HotbarSystem.REASON_SLOT_OCCUPIED:
			error_text = "SLOT OCCUPIED — use an empty slot"
		HotbarSystem.REASON_INVALID_SLOT:
			error_text = "INVALID HOTBAR SLOT"
		HotbarSystem.REASON_INVALID_PLANT:
			error_text = "INVALID PLANT"

	_hotbar_status_label.text = error_text
	_hotbar_status_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.35, 0.30, 1.0)
	)
	_hotbar_editor_panel.modulate = Color(
		1.35,
		0.35,
		0.35,
		1.0
	)

	_hotbar_error_tween = create_tween()
	_hotbar_error_tween.tween_property(
		_hotbar_editor_panel,
		"modulate",
		Color.WHITE,
		0.45
	)
	_hotbar_error_tween.tween_interval(0.45)
	_hotbar_error_tween.tween_callback(
		_restore_hotbar_status
	)


# Restores the normal hotbar instruction.
func _restore_hotbar_status() -> void:
	_hotbar_status_label.text = (
		"HOTBAR — drag plants to empty slots"
	)
	_hotbar_status_label.add_theme_color_override(
		"font_color",
		Color(0.78, 0.84, 0.76, 1.0)
	)


# Creates the main inventory panel style.
func _create_main_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.038, 0.98)
	style.border_color = Color(0.43, 0.63, 0.34, 1.0)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_left = 9
	style.corner_radius_bottom_right = 9
	return style


# Creates a secondary panel style.
func _create_inner_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.072, 0.96)
	style.border_color = Color(0.20, 0.24, 0.20, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style


# Creates inventory focus, membership, and active states.
func _create_inventory_slot_style(
	focused: bool,
	in_hotbar: bool,
	active: bool,
	hovered: bool,
	empty: bool
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	if empty:
		style.bg_color = Color(0.045, 0.05, 0.046, 0.90)
		style.border_color = Color(0.13, 0.15, 0.13, 1.0)
	elif active:
		style.bg_color = Color(0.16, 0.23, 0.11, 0.98)
		style.border_color = Color(0.78, 1.0, 0.38, 1.0)
	elif in_hotbar:
		style.bg_color = Color(0.18, 0.15, 0.08, 0.98)
		style.border_color = Color(1.0, 0.78, 0.28, 1.0)
	elif focused:
		style.bg_color = Color(0.12, 0.16, 0.12, 0.98)
		style.border_color = Color(0.38, 0.76, 1.0, 1.0)
	elif hovered:
		style.bg_color = Color(0.15, 0.17, 0.15, 0.98)
		style.border_color = Color(0.57, 0.65, 0.53, 1.0)
	else:
		style.bg_color = Color(0.09, 0.10, 0.09, 0.98)
		style.border_color = Color(0.30, 0.34, 0.30, 1.0)

	var width := 2

	if focused or in_hotbar:
		width = 3

	if active:
		width = 4

	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style


# Creates one hotbar slot state.
func _create_hotbar_slot_style(
	selected: bool,
	hovered: bool,
	empty: bool
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	if selected:
		style.bg_color = Color(0.17, 0.24, 0.11, 0.98)
		style.border_color = Color(0.78, 1.0, 0.38, 1.0)
	elif hovered:
		style.bg_color = Color(0.16, 0.18, 0.15, 0.98)
		style.border_color = Color(0.62, 0.70, 0.58, 1.0)
	elif empty:
		style.bg_color = Color(0.05, 0.055, 0.05, 0.94)
		style.border_color = Color(0.16, 0.18, 0.16, 1.0)
	else:
		style.bg_color = Color(0.09, 0.10, 0.09, 0.98)
		style.border_color = Color(0.30, 0.34, 0.30, 1.0)

	var width := 4 if selected else 2
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


# Creates Select, Deselect, and close button states.
func _create_action_button_style(
	destructive: bool,
	hovered: bool
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	if destructive:
		style.bg_color = Color(0.20, 0.10, 0.09, 0.98)
		style.border_color = Color(1.0, 0.46, 0.36, 1.0)
	elif hovered:
		style.bg_color = Color(0.18, 0.25, 0.12, 0.98)
		style.border_color = Color(0.78, 1.0, 0.38, 1.0)
	else:
		style.bg_color = Color(0.10, 0.12, 0.09, 0.98)
		style.border_color = Color(0.45, 0.64, 0.34, 1.0)

	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style


# Creates the drag preview border.
func _create_drag_preview_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.08, 0.94)
	style.border_color = Color(0.78, 1.0, 0.38, 1.0)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style
