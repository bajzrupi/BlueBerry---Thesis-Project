extends CanvasLayer

# Mouse-operated shop with Seeds, Terrain, and Equipment progression.
signal shop_opened()
signal shop_closed()


const PAGE_SEEDS: StringName = &"seeds"
const PAGE_TERRAIN: StringName = &"terrain"
const PAGE_EQUIPMENT: StringName = &"equipment"

const QUANTITY_OPTIONS: Array[int] = [
	1,
	5,
	10
]


@export_category("Shop Menu")

# Controls the CanvasLayer drawing order.
@export var menu_layer: int = 21

# Size of the plant icon in each seed row.
@export var item_icon_size: Vector2 = Vector2(54.0, 54.0)

# Pauses world simulation while the shop is open.
@export var pause_game_while_open: bool = true


@export_category("Debug Logging")

# Enables shop menu initialization and interaction logs.
@export var debug_log: bool = false


# Stores the full-screen menu root.
var _menu_root: Control

# Displays the current money balance.
var _money_label: Label

# Displays available milestone Plant Unlock Tokens.
var _plant_unlock_token_label: Label

# Displays transaction feedback.
var _status_label: Label

# Stores each shop page.
var _pages: Dictionary = {}

# Stores each shop tab button.
var _tab_buttons: Dictionary = {}

# Stores the currently visible shop page.
var _active_page: StringName = PAGE_SEEDS

# Stores selected seed quantities.
var _selected_quantities: Dictionary = {}

# Stores seed plant definitions.
var _plants: Dictionary = {}

# Stores seed row panels.
var _seed_row_panels: Dictionary = {}

# Stores seed stock labels.
var _stock_labels: Dictionary = {}

# Stores seed total price labels.
var _total_labels: Dictionary = {}

# Stores seed purchase buttons.
var _buy_buttons: Dictionary = {}

# Stores seed selling buttons.
var _sell_buttons: Dictionary = {}

# Stores permanent plant unlock buttons.
var _plant_unlock_buttons: Dictionary = {}

# Stores seed quantity buttons.
var _quantity_buttons: Dictionary = {}

# Stores terrain row panels.
var _terrain_row_panels: Dictionary = {}

# Stores terrain level labels.
var _terrain_level_labels: Dictionary = {}

# Stores terrain requirement labels.
var _terrain_requirement_labels: Dictionary = {}

# Stores terrain gameplay-effect labels.
var _terrain_effect_labels: Dictionary = {}

# Stores terrain upgrade buttons.
var _terrain_upgrade_buttons: Dictionary = {}

# Stores equipment row panels.
var _equipment_row_panels: Dictionary = {}

# Stores equipment level labels.
var _equipment_level_labels: Dictionary = {}

# Stores equipment gameplay-effect labels.
var _equipment_effect_labels: Dictionary = {}

# Stores equipment requirement labels.
var _equipment_requirement_labels: Dictionary = {}

# Stores equipment upgrade buttons.
var _equipment_upgrade_buttons: Dictionary = {}

# Stores active row flash tweens.
var _row_tweens: Dictionary = {}

# Tracks whether the shop is currently open.
var _is_open: bool = false

# Preserves gameplay state while the shop is open.
var _previous_pause_state: bool = false
var _previous_mouse_mode: Input.MouseMode = (
	Input.MOUSE_MODE_VISIBLE
)


# Builds the shop and connects transaction systems.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = menu_layer
	add_to_group("modal_menu")

	_build_menu()
	_connect_system_signals()
	_set_active_page(PAGE_SEEDS)
	_set_shop_open(false, false)
	_refresh_all()

	if debug_log:
		print(
			"[ShopMenu] ready layer=",
			layer,
			" seed_catalog=",
			ShopSystem.get_all_plant_catalog().size(),
			" unlocked_seeds=",
			ShopSystem.get_catalog().size(),
			" terrain_catalog=",
			ShopSystem.get_terrain_catalog().size(),
			" equipment_catalog=",
			ShopSystem.get_equipment_catalog().size()
		)


# Handles shop opening and closing.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_shop"):
		toggle_shop()
		get_viewport().set_input_as_handled()
		return

	if _is_open and event.is_action_pressed("ui_cancel"):
		close_shop()
		get_viewport().set_input_as_handled()


# Opens or closes the shop.
func toggle_shop() -> void:
	_set_shop_open(not _is_open, true)


# Opens the shop.
func open_shop() -> void:
	_set_shop_open(true, true)


# Closes the shop.
func close_shop() -> void:
	_set_shop_open(false, true)


# Allows another modal menu to close this shop.
func close_modal_menu() -> void:
	close_shop()


# Returns whether this modal menu is open.
func is_modal_menu_open() -> bool:
	return _is_open


# Applies visibility, cursor, pause, and modal behavior.
func _set_shop_open(
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
		_set_status(
			"Choose a shop category.",
			false
		)

		if should_emit_signal:
			shop_opened.emit()

		if debug_log:
			print(
				"[ShopMenu] opened page=",
				String(_active_page)
			)
	else:
		if pause_game_while_open:
			get_tree().paused = _previous_pause_state

		Input.mouse_mode = _previous_mouse_mode

		if should_emit_signal:
			shop_closed.emit()

		if debug_log:
			print("[ShopMenu] closed")


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


# Creates the complete full-screen shop UI.
func _build_menu() -> void:
	_menu_root = Control.new()
	_menu_root.name = "ShopMenuRoot"
	_menu_root.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_menu_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_menu_root)

	var dim_background := ColorRect.new()
	dim_background.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	dim_background.color = Color(0.0, 0.0, 0.0, 0.58)
	dim_background.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu_root.add_child(dim_background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_root.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "ShopPanel"
	panel.custom_minimum_size = Vector2(900.0, 620.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override(
		"panel",
		_create_main_panel_style()
	)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	content.add_child(_create_header())
	content.add_child(_create_tabs())
	content.add_child(HSeparator.new())
	content.add_child(_create_page_host())

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.add_theme_font_size_override("font_size", 13)
	content.add_child(_status_label)


# Creates the title, money display, and close button.
func _create_header() -> Control:
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "SHOP"
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

	_money_label = Label.new()
	_money_label.text = "Money: 0"
	_money_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_money_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_money_label.add_theme_font_size_override("font_size", 16)
	_money_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.86, 0.32, 1.0)
	)
	header.add_child(_money_label)

	var close_button := Button.new()
	close_button.text = "Close  [P / Esc]"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	close_button.pressed.connect(close_shop)
	_apply_button_style(close_button, false)
	header.add_child(close_button)

	return header


# Creates the shop category tabs.
func _create_tabs() -> Control:
	var tabs := HBoxContainer.new()
	tabs.mouse_filter = Control.MOUSE_FILTER_PASS
	tabs.add_theme_constant_override("separation", 6)

	_add_tab_button(
		tabs,
		PAGE_SEEDS,
		"Seeds"
	)
	_add_tab_button(
		tabs,
		PAGE_TERRAIN,
		"Terrain"
	)
	_add_tab_button(
		tabs,
		PAGE_EQUIPMENT,
		"Equipment"
	)

	return tabs


# Adds one clickable shop category tab.
func _add_tab_button(
	parent: HBoxContainer,
	page_id: StringName,
	label_text: String
) -> void:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = Vector2(150.0, 38.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	button.pressed.connect(
		_on_tab_pressed.bind(page_id)
	)
	parent.add_child(button)
	_tab_buttons[page_id] = button


# Creates and stores all shop pages.
func _create_page_host() -> Control:
	var host := VBoxContainer.new()
	host.name = "PageHost"
	host.custom_minimum_size = Vector2(0.0, 445.0)
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var seeds_page := _create_seeds_page()
	host.add_child(seeds_page)
	_pages[PAGE_SEEDS] = seeds_page

	var terrain_page := _create_terrain_page()
	host.add_child(terrain_page)
	_pages[PAGE_TERRAIN] = terrain_page

	var equipment_page := _create_equipment_page()
	host.add_child(equipment_page)
	_pages[PAGE_EQUIPMENT] = equipment_page

	return host


# Creates the existing seed trading page.
func _create_seeds_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "SeedsPage"
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_theme_constant_override("separation", 8)

	var description := Label.new()
	description.text = (
		"Buy or sell unlocked seeds. Milestone tokens permanently "
		+ "unlock new plant types."
	)
	description.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description.add_theme_color_override(
		"font_color",
		Color(0.72, 0.78, 0.70, 1.0)
	)
	page.add_child(description)

	_plant_unlock_token_label = Label.new()
	_plant_unlock_token_label.text = "Plant Unlock Tokens: 0"
	_plant_unlock_token_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_plant_unlock_token_label.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	_plant_unlock_token_label.add_theme_font_size_override(
		"font_size",
		13
	)
	_plant_unlock_token_label.add_theme_color_override(
		"font_color",
		Color(0.90, 0.82, 0.42, 1.0)
	)
	page.add_child(_plant_unlock_token_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	page.add_child(scroll)

	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 10)
	scroll.add_child(rows)

	for plant_data: PlantData in (
		ShopSystem.get_all_plant_catalog()
	):
		rows.add_child(_create_seed_row(plant_data))

	return page


# Creates one seed trading row.
func _create_seed_row(
	plant_data: PlantData
) -> Control:
	var item_id: StringName = plant_data.seed_item_id
	_plants[item_id] = plant_data
	_selected_quantities[item_id] = 1

	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size = Vector2(0.0, 156.0)
	row_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_panel.add_theme_stylebox_override(
		"panel",
		_create_row_style()
	)
	_seed_row_panels[item_id] = row_panel

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	row_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	row.add_child(_create_item_icon(plant_data))
	row.add_child(_create_item_information(plant_data))
	row.add_child(_create_quantity_selector(plant_data))
	row.add_child(_create_transaction_controls(plant_data))

	return row_panel


# Creates one framed plant icon.
func _create_item_icon(
	plant_data: PlantData
) -> Control:
	var icon_frame := PanelContainer.new()
	icon_frame.custom_minimum_size = Vector2(78.0, 78.0)
	icon_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_frame.add_theme_stylebox_override(
		"panel",
		_create_icon_style()
	)

	var icon_center := CenterContainer.new()
	icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_frame.add_child(icon_center)

	var icon := TextureRect.new()
	icon.texture = _create_plant_icon(plant_data)
	icon.custom_minimum_size = item_icon_size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_center.add_child(icon)

	return icon_frame


# Creates the seed name, stock, and unit prices.
func _create_item_information(
	plant_data: PlantData
) -> Control:
	var information := VBoxContainer.new()
	information.custom_minimum_size = Vector2(190.0, 0.0)
	information.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	information.mouse_filter = Control.MOUSE_FILTER_IGNORE
	information.add_theme_constant_override("separation", 5)

	var name_label := Label.new()
	name_label.text = plant_data.display_name
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override(
		"font_color",
		Color(0.88, 0.96, 0.84, 1.0)
	)
	information.add_child(name_label)

	var stock_label := Label.new()
	stock_label.text = "Owned: 0"
	stock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stock_label.add_theme_font_size_override("font_size", 13)
	stock_label.add_theme_color_override(
		"font_color",
		Color(0.76, 0.82, 0.74, 1.0)
	)
	information.add_child(stock_label)
	_stock_labels[plant_data.seed_item_id] = stock_label

	var price_label := Label.new()
	price_label.text = "Unit buy: %d\nUnit sell: %d" % [
		plant_data.seed_buy_price,
		plant_data.seed_sell_price
	]
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_label.add_theme_font_size_override("font_size", 13)
	price_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.86, 0.38, 1.0)
	)
	information.add_child(price_label)

	return information


# Creates the 1, 5, and 10 quantity buttons.
func _create_quantity_selector(
	plant_data: PlantData
) -> Control:
	var selector := VBoxContainer.new()
	selector.custom_minimum_size = Vector2(155.0, 0.0)
	selector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selector.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "QUANTITY"
	title.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override(
		"font_color",
		Color(0.72, 0.78, 0.70, 1.0)
	)
	selector.add_child(title)

	var button_row := HBoxContainer.new()
	button_row.mouse_filter = Control.MOUSE_FILTER_PASS
	button_row.add_theme_constant_override("separation", 4)
	selector.add_child(button_row)

	var item_id: StringName = plant_data.seed_item_id
	var buttons: Array[Button] = []

	for quantity: int in QUANTITY_OPTIONS:
		var quantity_button := Button.new()
		quantity_button.text = str(quantity)
		quantity_button.custom_minimum_size = Vector2(46.0, 34.0)
		quantity_button.focus_mode = Control.FOCUS_NONE
		quantity_button.toggle_mode = true
		quantity_button.mouse_default_cursor_shape = (
			Control.CURSOR_POINTING_HAND
		)
		quantity_button.pressed.connect(
			_on_quantity_pressed.bind(
				item_id,
				quantity
			)
		)
		button_row.add_child(quantity_button)
		buttons.append(quantity_button)

	_quantity_buttons[item_id] = buttons

	var total_label := Label.new()
	total_label.text = "Buy: 0\nSell: 0"
	total_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	total_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	total_label.add_theme_font_size_override("font_size", 13)
	total_label.add_theme_color_override(
		"font_color",
		Color(0.82, 0.86, 0.80, 1.0)
	)
	selector.add_child(total_label)
	_total_labels[item_id] = total_label

	return selector


# Creates the seed buy and sell controls.
func _create_transaction_controls(
	plant_data: PlantData
) -> Control:
	var controls := VBoxContainer.new()
	controls.custom_minimum_size = Vector2(170.0, 0.0)
	controls.mouse_filter = Control.MOUSE_FILTER_PASS
	controls.add_theme_constant_override("separation", 8)

	var buy_button := Button.new()
	buy_button.text = "BUY 1"
	buy_button.custom_minimum_size = Vector2(170.0, 48.0)
	buy_button.focus_mode = Control.FOCUS_NONE
	buy_button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	buy_button.pressed.connect(
		_on_buy_pressed.bind(plant_data)
	)
	_apply_button_style(buy_button, false)
	controls.add_child(buy_button)
	_buy_buttons[plant_data.seed_item_id] = buy_button

	var sell_button := Button.new()
	sell_button.text = "SELL 1"
	sell_button.custom_minimum_size = Vector2(170.0, 48.0)
	sell_button.focus_mode = Control.FOCUS_NONE
	sell_button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	sell_button.pressed.connect(
		_on_sell_pressed.bind(plant_data)
	)
	_apply_button_style(sell_button, true)
	controls.add_child(sell_button)
	_sell_buttons[plant_data.seed_item_id] = sell_button

	var unlock_button := Button.new()
	unlock_button.text = "UNLOCK  •  1 TOKEN"
	unlock_button.custom_minimum_size = Vector2(170.0, 48.0)
	unlock_button.focus_mode = Control.FOCUS_NONE
	unlock_button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	unlock_button.pressed.connect(
		_on_plant_unlock_pressed.bind(plant_data)
	)
	_apply_button_style(unlock_button, false)
	controls.add_child(unlock_button)
	_plant_unlock_buttons[
		plant_data.seed_item_id
	] = unlock_button

	return controls


# Creates the terrain upgrade page.
func _create_terrain_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "TerrainPage"
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_theme_constant_override("separation", 10)

	var description := Label.new()
	description.text = (
		"Terrain upgrades are permanent progression for each soil type."
	)
	description.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description.add_theme_color_override(
		"font_color",
		Color(0.72, 0.78, 0.70, 1.0)
	)
	page.add_child(description)

	for terrain_entry: Dictionary in (
		ShopSystem.get_terrain_catalog()
	):
		page.add_child(
			_create_terrain_row(terrain_entry)
		)

	var note := Label.new()
	note.text = (
		"Terrain upgrades apply immediately. They improve maintenance "
		+ "without changing the underlying soil type."
	)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override(
		"font_color",
		Color(0.66, 0.70, 0.65, 1.0)
	)
	page.add_child(note)

	return page


# Creates one terrain upgrade row.
func _create_terrain_row(
	terrain_entry: Dictionary
) -> Control:
	var terrain_id: StringName = StringName(
		terrain_entry.get("id", &"")
	)
	var display_name: String = String(
		terrain_entry.get(
			"display_name",
			String(terrain_id)
		)
	)
	var description_text: String = String(
		terrain_entry.get("description", "")
	)

	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size = Vector2(0.0, 178.0)
	row_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_panel.add_theme_stylebox_override(
		"panel",
		_create_row_style()
	)
	_terrain_row_panels[terrain_id] = row_panel

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	row_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)

	var information := VBoxContainer.new()
	information.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	information.mouse_filter = Control.MOUSE_FILTER_IGNORE
	information.add_theme_constant_override("separation", 5)
	row.add_child(information)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override(
		"font_color",
		Color(0.88, 0.96, 0.84, 1.0)
	)
	information.add_child(name_label)

	var terrain_description := Label.new()
	terrain_description.text = description_text
	terrain_description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	terrain_description.add_theme_font_size_override(
		"font_size",
		13
	)
	terrain_description.add_theme_color_override(
		"font_color",
		Color(0.72, 0.78, 0.70, 1.0)
	)
	information.add_child(terrain_description)

	var level_label := Label.new()
	level_label.text = "Terrain Level: 1 / 5"
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_label.add_theme_font_size_override("font_size", 15)
	level_label.add_theme_color_override(
		"font_color",
		Color(0.74, 0.90, 1.0, 1.0)
	)
	information.add_child(level_label)
	_terrain_level_labels[terrain_id] = level_label

	var effect_label := Label.new()
	effect_label.text = ""
	effect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect_label.add_theme_font_size_override("font_size", 12)
	effect_label.add_theme_color_override(
		"font_color",
		Color(0.68, 0.84, 0.66, 1.0)
	)
	information.add_child(effect_label)
	_terrain_effect_labels[terrain_id] = effect_label

	var requirement_label := Label.new()
	requirement_label.text = ""
	requirement_label.custom_minimum_size = Vector2(260.0, 0.0)
	requirement_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	requirement_label.add_theme_font_size_override(
		"font_size",
		13
	)
	requirement_label.add_theme_color_override(
		"font_color",
		Color(0.82, 0.86, 0.80, 1.0)
	)
	row.add_child(requirement_label)
	_terrain_requirement_labels[
		terrain_id
	] = requirement_label

	var upgrade_button := Button.new()
	upgrade_button.text = "UPGRADE"
	upgrade_button.custom_minimum_size = Vector2(190.0, 54.0)
	upgrade_button.focus_mode = Control.FOCUS_NONE
	upgrade_button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	upgrade_button.pressed.connect(
		_on_terrain_upgrade_pressed.bind(
			terrain_id
		)
	)
	_apply_button_style(upgrade_button, false)
	row.add_child(upgrade_button)
	_terrain_upgrade_buttons[terrain_id] = upgrade_button

	return row_panel


# Creates the equipment progression page.
func _create_equipment_page() -> Control:
	var page := VBoxContainer.new()
	page.name = "EquipmentPage"
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_theme_constant_override("separation", 8)

	var description := Label.new()
	description.text = (
		"Upgrade each tool independently. Higher levels improve "
		+ "effectiveness and interaction range."
	)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description.add_theme_color_override(
		"font_color",
		Color(0.72, 0.78, 0.70, 1.0)
	)
	page.add_child(description)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	page.add_child(scroll)

	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 9)
	scroll.add_child(rows)

	for equipment_entry: Dictionary in (
		ShopSystem.get_equipment_catalog()
	):
		rows.add_child(
			_create_equipment_row(equipment_entry)
		)

	return page


# Creates one equipment upgrade row.
func _create_equipment_row(
	equipment_entry: Dictionary
) -> Control:
	var equipment_id: StringName = StringName(
		equipment_entry.get("id", &"")
	)
	var display_name: String = String(
		equipment_entry.get(
			"display_name",
			String(equipment_id)
		)
	)
	var description_text: String = String(
		equipment_entry.get("description", "")
	)

	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size = Vector2(0.0, 150.0)
	row_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_panel.add_theme_stylebox_override(
		"panel",
		_create_row_style()
	)
	_equipment_row_panels[equipment_id] = row_panel

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 10)
	row_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)

	var information := VBoxContainer.new()
	information.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	information.mouse_filter = Control.MOUSE_FILTER_IGNORE
	information.add_theme_constant_override("separation", 4)
	row.add_child(information)

	var name_label := Label.new()
	name_label.text = display_name
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override(
		"font_color",
		Color(0.88, 0.96, 0.84, 1.0)
	)
	information.add_child(name_label)

	var description_label := Label.new()
	description_label.text = description_text
	description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	description_label.add_theme_font_size_override(
		"font_size",
		12
	)
	description_label.add_theme_color_override(
		"font_color",
		Color(0.72, 0.78, 0.70, 1.0)
	)
	information.add_child(description_label)

	var level_label := Label.new()
	level_label.text = "Equipment Level: 1 / 5"
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_label.add_theme_font_size_override("font_size", 14)
	level_label.add_theme_color_override(
		"font_color",
		Color(0.74, 0.90, 1.0, 1.0)
	)
	information.add_child(level_label)
	_equipment_level_labels[equipment_id] = level_label

	var effect_label := Label.new()
	effect_label.text = ""
	effect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	effect_label.add_theme_font_size_override("font_size", 12)
	effect_label.add_theme_color_override(
		"font_color",
		Color(0.68, 0.84, 0.66, 1.0)
	)
	information.add_child(effect_label)
	_equipment_effect_labels[equipment_id] = effect_label

	var requirement_label := Label.new()
	requirement_label.text = ""
	requirement_label.custom_minimum_size = Vector2(235.0, 0.0)
	requirement_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	requirement_label.add_theme_font_size_override(
		"font_size",
		12
	)
	requirement_label.add_theme_color_override(
		"font_color",
		Color(0.82, 0.86, 0.80, 1.0)
	)
	row.add_child(requirement_label)
	_equipment_requirement_labels[
		equipment_id
	] = requirement_label

	var upgrade_button := Button.new()
	upgrade_button.text = "UPGRADE"
	upgrade_button.custom_minimum_size = Vector2(195.0, 52.0)
	upgrade_button.focus_mode = Control.FOCUS_NONE
	upgrade_button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	upgrade_button.pressed.connect(
		_on_equipment_upgrade_pressed.bind(
			equipment_id
		)
	)
	_apply_button_style(upgrade_button, false)
	row.add_child(upgrade_button)
	_equipment_upgrade_buttons[equipment_id] = upgrade_button

	return row_panel


# Connects the shop to economy, inventory, and progression.
func _connect_system_signals() -> void:
	if not EconomySystem.money_changed.is_connected(
		_on_money_changed
	):
		EconomySystem.money_changed.connect(
			_on_money_changed
		)

	if not EconomySystem.economy_reset.is_connected(
		_on_economy_reset
	):
		EconomySystem.economy_reset.connect(
			_on_economy_reset
		)

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

	if not ShopSystem.transaction_completed.is_connected(
		_on_transaction_completed
	):
		ShopSystem.transaction_completed.connect(
			_on_transaction_completed
		)

	if not ShopSystem.transaction_failed.is_connected(
		_on_transaction_failed
	):
		ShopSystem.transaction_failed.connect(
			_on_transaction_failed
		)

	if not ShopSystem.plant_unlock_completed.is_connected(
		_on_plant_unlock_completed
	):
		ShopSystem.plant_unlock_completed.connect(
			_on_plant_unlock_completed
		)

	if not ShopSystem.plant_unlock_failed.is_connected(
		_on_plant_unlock_failed
	):
		ShopSystem.plant_unlock_failed.connect(
			_on_plant_unlock_failed
		)

	if not ProgressionSystem.plant_unlock_tokens_changed.is_connected(
		_on_plant_unlock_tokens_changed
	):
		ProgressionSystem.plant_unlock_tokens_changed.connect(
			_on_plant_unlock_tokens_changed
		)

	if not ProgressionSystem.plant_unlock_changed.is_connected(
		_on_plant_unlock_changed
	):
		ProgressionSystem.plant_unlock_changed.connect(
			_on_plant_unlock_changed
		)

	if not ShopSystem.terrain_upgrade_completed.is_connected(
		_on_terrain_upgrade_completed
	):
		ShopSystem.terrain_upgrade_completed.connect(
			_on_terrain_upgrade_completed
		)

	if not ShopSystem.terrain_upgrade_failed.is_connected(
		_on_terrain_upgrade_failed
	):
		ShopSystem.terrain_upgrade_failed.connect(
			_on_terrain_upgrade_failed
		)

	if not ProgressionSystem.terrain_level_changed.is_connected(
		_on_terrain_level_changed
	):
		ProgressionSystem.terrain_level_changed.connect(
			_on_terrain_level_changed
		)

	if not ProgressionSystem.player_progress_changed.is_connected(
		_on_player_progress_changed
	):
		ProgressionSystem.player_progress_changed.connect(
			_on_player_progress_changed
		)


	if not ShopSystem.equipment_upgrade_completed.is_connected(
		_on_equipment_upgrade_completed
	):
		ShopSystem.equipment_upgrade_completed.connect(
			_on_equipment_upgrade_completed
		)

	if not ShopSystem.equipment_upgrade_failed.is_connected(
		_on_equipment_upgrade_failed
	):
		ShopSystem.equipment_upgrade_failed.connect(
			_on_equipment_upgrade_failed
		)

	if not ProgressionSystem.equipment_level_changed.is_connected(
		_on_equipment_level_changed
	):
		ProgressionSystem.equipment_level_changed.connect(
			_on_equipment_level_changed
		)


# Changes the visible shop category.
func _on_tab_pressed(page_id: StringName) -> void:
	_set_active_page(page_id)

	if page_id == PAGE_SEEDS:
		_set_status(
			"Choose a quantity, then buy or sell.",
			false
		)
	elif page_id == PAGE_TERRAIN:
		_set_status(
			"Terrain upgrades require money and Player Level.",
			false
		)
	else:
		_set_status(
			"Equipment upgrades improve tools immediately.",
			false
		)

	if debug_log:
		print(
			"[ShopMenu] page=",
			String(page_id)
		)


# Shows one page and hides the others.
func _set_active_page(page_id: StringName) -> void:
	if not _pages.has(page_id):
		return

	_active_page = page_id

	for stored_page_id: Variant in _pages.keys():
		var page: Control = _pages.get(
			stored_page_id
		) as Control

		if page != null:
			page.visible = (
				StringName(stored_page_id)
				== _active_page
			)

	for stored_button_id: Variant in _tab_buttons.keys():
		var button: Button = _tab_buttons.get(
			stored_button_id
		) as Button

		if button == null:
			continue

		var selected: bool = (
			StringName(stored_button_id)
			== _active_page
		)
		button.button_pressed = selected
		button.add_theme_stylebox_override(
			"normal",
			_create_tab_style(selected, false)
		)
		button.add_theme_stylebox_override(
			"hover",
			_create_tab_style(selected, true)
		)
		button.add_theme_stylebox_override(
			"pressed",
			_create_tab_style(true, true)
		)


# Refreshes all visible shop values.
func _refresh_all() -> void:
	_refresh_money()
	_refresh_plant_unlock_tokens()

	for plant_data: PlantData in (
		ShopSystem.get_all_plant_catalog()
	):
		_refresh_seed_row(plant_data)

	for terrain_entry: Dictionary in (
		ShopSystem.get_terrain_catalog()
	):
		var terrain_id: StringName = StringName(
			terrain_entry.get("id", &"")
		)
		_refresh_terrain_row(terrain_id)


	for equipment_entry: Dictionary in (
		ShopSystem.get_equipment_catalog()
	):
		var equipment_id: StringName = StringName(
			equipment_entry.get("id", &"")
		)
		_refresh_equipment_row(equipment_id)


# Refreshes the money balance.
func _refresh_money() -> void:
	_money_label.text = "Money: %d" % (
		EconomySystem.get_money()
	)


# Refreshes the milestone token balance shown on the Seeds page.
func _refresh_plant_unlock_tokens() -> void:
	if _plant_unlock_token_label == null:
		return

	_plant_unlock_token_label.text = (
		"Plant Unlock Tokens: %d"
		% ProgressionSystem.plant_unlock_tokens
	)


# Refreshes one complete seed row.
func _refresh_seed_row(
	plant_data: PlantData
) -> void:
	var item_id: StringName = plant_data.seed_item_id
	var unlocked: bool = ProgressionSystem.is_plant_unlocked(
		item_id
	)
	var quantity: int = int(
		_selected_quantities.get(item_id, 1)
	)
	var stock: int = InventorySystem.get_amount(item_id)
	var buy_total: int = ShopSystem.get_buy_price(
		plant_data,
		quantity
	)
	var sell_total: int = ShopSystem.get_sell_price(
		plant_data,
		quantity
	)
	var buy_status: Dictionary = ShopSystem.get_buy_status(
		plant_data,
		quantity
	)
	var sell_status: Dictionary = ShopSystem.get_sell_status(
		plant_data,
		quantity
	)
	var unlock_status: Dictionary = (
		ShopSystem.get_plant_unlock_status(
			plant_data
		)
	)

	var stock_label: Label = _stock_labels.get(
		item_id
	) as Label
	var total_label: Label = _total_labels.get(
		item_id
	) as Label
	var buy_button: Button = _buy_buttons.get(
		item_id
	) as Button
	var sell_button: Button = _sell_buttons.get(
		item_id
	) as Button
	var unlock_button: Button = (
		_plant_unlock_buttons.get(
			item_id
		) as Button
	)

	if stock_label != null:
		stock_label.text = (
			"Owned: %d" % stock
			if unlocked
			else "LOCKED"
		)

	if total_label != null:
		if unlocked:
			total_label.text = "Buy total: %d\nSell total: %d" % [
				buy_total,
				sell_total
			]
		else:
			total_label.text = (
				"Requires 1\nPlant Unlock Token"
			)

	if buy_button != null:
		buy_button.visible = unlocked
		buy_button.text = "BUY %d  •  %d" % [
			quantity,
			buy_total
		]
		buy_button.disabled = not bool(
			buy_status.get("ok", false)
		)
		buy_button.tooltip_text = _get_seed_status_tooltip(
			ShopSystem.ACTION_BUY,
			buy_status
		)

	if sell_button != null:
		sell_button.visible = unlocked
		sell_button.text = "SELL %d  •  %d" % [
			quantity,
			sell_total
		]
		sell_button.disabled = not bool(
			sell_status.get("ok", false)
		)
		sell_button.tooltip_text = _get_seed_status_tooltip(
			ShopSystem.ACTION_SELL,
			sell_status
		)

	if unlock_button != null:
		unlock_button.visible = not unlocked
		unlock_button.disabled = not bool(
			unlock_status.get("ok", false)
		)
		unlock_button.tooltip_text = (
			_get_plant_unlock_tooltip(
				unlock_status
			)
		)

	_refresh_quantity_buttons(item_id, quantity)

	var quantity_buttons: Array = _quantity_buttons.get(
		item_id,
		[]
	)

	for stored_button: Variant in quantity_buttons:
		var quantity_button: Button = stored_button as Button

		if quantity_button != null:
			quantity_button.disabled = not unlocked




# Refreshes one terrain row.
func _refresh_terrain_row(
	terrain_id: StringName
) -> void:
	var status: Dictionary = (
		ShopSystem.get_terrain_upgrade_status(
			terrain_id
		)
	)
	var current_level: int = int(
		status.get(
			"current_level",
			ProgressionSystem.get_terrain_level(
				terrain_id
			)
		)
	)
	var max_level: int = int(
		status.get(
			"max_level",
			ProgressionSystem.MAX_TERRAIN_LEVEL
		)
	)
	var next_level: int = int(
		status.get("next_level", current_level)
	)
	var cost: int = int(status.get("cost", 0))
	var required_level: int = int(
		status.get("required_player_level", 0)
	)
	var reason: String = String(
		status.get("reason", "")
	)

	var level_label: Label = _terrain_level_labels.get(
		terrain_id
	) as Label
	var requirement_label: Label = (
		_terrain_requirement_labels.get(
			terrain_id
		) as Label
	)
	var effect_label: Label = (
		_terrain_effect_labels.get(
			terrain_id
		) as Label
	)
	var upgrade_button: Button = (
		_terrain_upgrade_buttons.get(
			terrain_id
		) as Button
	)

	if level_label != null:
		level_label.text = "Terrain Level: %d / %d" % [
			current_level,
			max_level
		]

	if effect_label != null:
		var effects: Dictionary = BiomeSystem.get_terrain_effects(
			String(terrain_id),
			current_level
		)
		effect_label.text = _format_terrain_effects(effects)

	if requirement_label != null:
		if current_level >= max_level:
			requirement_label.text = (
				"Maximum terrain level reached."
			)
			requirement_label.add_theme_color_override(
				"font_color",
				Color(0.72, 1.0, 0.62, 1.0)
			)
		else:
			requirement_label.text = (
				"Next: Lv. %d\nCost: %d\nRequired Player Lv.: %d" % [
					next_level,
					cost,
					required_level
				]
			)

			if reason == ShopSystem.REASON_PLAYER_LEVEL_TOO_LOW:
				requirement_label.add_theme_color_override(
					"font_color",
					Color(1.0, 0.56, 0.34, 1.0)
				)
			elif reason == ShopSystem.REASON_INSUFFICIENT_MONEY:
				requirement_label.add_theme_color_override(
					"font_color",
					Color(1.0, 0.76, 0.30, 1.0)
				)
			else:
				requirement_label.add_theme_color_override(
					"font_color",
					Color(0.82, 0.86, 0.80, 1.0)
				)

	if upgrade_button != null:
		if current_level >= max_level:
			upgrade_button.text = "MAX LEVEL"
			upgrade_button.disabled = true
			upgrade_button.tooltip_text = (
				"Maximum terrain level reached."
			)
		else:
			upgrade_button.text = "UPGRADE TO LV. %d  •  %d" % [
				next_level,
				cost
			]
			upgrade_button.disabled = not bool(
				status.get("ok", false)
			)
			upgrade_button.tooltip_text = (
				_get_terrain_status_tooltip(status)
			)


# Refreshes one equipment upgrade row.
func _refresh_equipment_row(
	equipment_id: StringName
) -> void:
	var status: Dictionary = (
		ShopSystem.get_equipment_upgrade_status(
			equipment_id
		)
	)
	var current_level: int = int(
		status.get(
			"current_level",
			ProgressionSystem.get_equipment_level(
				equipment_id
			)
		)
	)
	var max_level: int = int(
		status.get(
			"max_level",
			ProgressionSystem.MAX_EQUIPMENT_LEVEL
		)
	)
	var next_level: int = int(
		status.get("next_level", current_level)
	)
	var cost: int = int(status.get("cost", 0))
	var required_level: int = int(
		status.get("required_player_level", 0)
	)
	var reason: String = String(
		status.get("reason", "")
	)

	var level_label: Label = _equipment_level_labels.get(
		equipment_id
	) as Label
	var effect_label: Label = _equipment_effect_labels.get(
		equipment_id
	) as Label
	var requirement_label: Label = (
		_equipment_requirement_labels.get(
			equipment_id
		) as Label
	)
	var upgrade_button: Button = (
		_equipment_upgrade_buttons.get(
			equipment_id
		) as Button
	)

	if level_label != null:
		level_label.text = "Equipment Level: %d / %d" % [
			current_level,
			max_level
		]

	if effect_label != null:
		var effects: Dictionary = (
			ProgressionSystem.get_equipment_effects(
				equipment_id,
				current_level
			)
		)
		effect_label.text = _format_equipment_effects(
			equipment_id,
			effects
		)

	if requirement_label != null:
		if current_level >= max_level:
			requirement_label.text = (
				"Maximum equipment level reached."
			)
			requirement_label.add_theme_color_override(
				"font_color",
				Color(0.72, 1.0, 0.62, 1.0)
			)
		else:
			requirement_label.text = (
				"Next: Lv. %d\nCost: %d\nRequired Player Lv.: %d" % [
					next_level,
					cost,
					required_level
				]
			)

			if reason == ShopSystem.REASON_PLAYER_LEVEL_TOO_LOW:
				requirement_label.add_theme_color_override(
					"font_color",
					Color(1.0, 0.56, 0.34, 1.0)
				)
			elif reason == ShopSystem.REASON_INSUFFICIENT_MONEY:
				requirement_label.add_theme_color_override(
					"font_color",
					Color(1.0, 0.76, 0.30, 1.0)
				)
			else:
				requirement_label.add_theme_color_override(
					"font_color",
					Color(0.82, 0.86, 0.80, 1.0)
				)

	if upgrade_button != null:
		if current_level >= max_level:
			upgrade_button.text = "MAX LEVEL"
			upgrade_button.disabled = true
			upgrade_button.tooltip_text = (
				"Maximum equipment level reached."
			)
		else:
			upgrade_button.text = "UPGRADE TO LV. %d  •  %d" % [
				next_level,
				cost
			]
			upgrade_button.disabled = not bool(
				status.get("ok", false)
			)
			upgrade_button.tooltip_text = (
				_get_equipment_status_tooltip(status)
			)


# Refreshes the selected seed quantity highlight.
func _refresh_quantity_buttons(
	item_id: StringName,
	selected_quantity: int
) -> void:
	var buttons: Array = _quantity_buttons.get(
		item_id,
		[]
	)

	for index in range(buttons.size()):
		var button: Button = buttons[index] as Button

		if button == null:
			continue

		var quantity: int = QUANTITY_OPTIONS[index]
		var selected: bool = quantity == selected_quantity

		button.button_pressed = selected
		button.add_theme_stylebox_override(
			"normal",
			_create_quantity_style(selected, false)
		)
		button.add_theme_stylebox_override(
			"hover",
			_create_quantity_style(selected, true)
		)
		button.add_theme_stylebox_override(
			"pressed",
			_create_quantity_style(true, true)
		)


# Returns a clear disabled seed-button explanation.
func _get_seed_status_tooltip(
	action: String,
	status: Dictionary
) -> String:
	if bool(status.get("ok", false)):
		return (
			"Purchase selected quantity."
			if action == ShopSystem.ACTION_BUY
			else "Sell selected quantity."
		)

	var reason: String = String(
		status.get("reason", "")
	)

	match reason:
		ShopSystem.REASON_INSUFFICIENT_MONEY:
			return "Not enough money for this quantity."
		ShopSystem.REASON_INSUFFICIENT_STOCK:
			return "Not enough seeds for this quantity."
		ShopSystem.REASON_NOT_FOR_SALE:
			return "This item is not available for trading."
		ShopSystem.REASON_INVALID_PRICE:
			return "This item has no valid shop price."
		ShopSystem.REASON_PLANT_LOCKED:
			return "Unlock this plant before trading its seeds."

	return "Transaction unavailable."


# Returns a clear permanent plant-unlock explanation.
func _get_plant_unlock_tooltip(
	status: Dictionary
) -> String:
	if bool(status.get("ok", false)):
		return "Spend 1 Plant Unlock Token to unlock this plant permanently."

	var reason: String = String(
		status.get("reason", "")
	)

	match reason:
		ShopSystem.REASON_ALREADY_UNLOCKED:
			return "This plant is already unlocked."
		ShopSystem.REASON_INSUFFICIENT_UNLOCK_TOKENS:
			return "Reach a Player Level milestone to earn an unlock token."
		ShopSystem.REASON_INVALID_PLANT:
			return "Invalid plant unlock."

	return "Plant unlock unavailable."


# Returns a clear disabled terrain-button explanation.
func _get_terrain_status_tooltip(
	status: Dictionary
) -> String:
	if bool(status.get("ok", false)):
		return "Purchase the next terrain level."

	var reason: String = String(
		status.get("reason", "")
	)

	match reason:
		ShopSystem.REASON_PLAYER_LEVEL_TOO_LOW:
			return "Your Player Level is too low."
		ShopSystem.REASON_INSUFFICIENT_MONEY:
			return "Not enough money for this terrain upgrade."
		ShopSystem.REASON_MAX_TERRAIN_LEVEL:
			return "Maximum terrain level reached."
		ShopSystem.REASON_INVALID_TERRAIN:
			return "Invalid terrain upgrade."

	return "Terrain upgrade unavailable."


# Returns a clear disabled equipment-button explanation.
func _get_equipment_status_tooltip(
	status: Dictionary
) -> String:
	if bool(status.get("ok", false)):
		return "Purchase the next equipment level."

	var reason: String = String(
		status.get("reason", "")
	)

	match reason:
		ShopSystem.REASON_PLAYER_LEVEL_TOO_LOW:
			return "Your Player Level is too low."
		ShopSystem.REASON_INSUFFICIENT_MONEY:
			return "Not enough money for this equipment upgrade."
		ShopSystem.REASON_MAX_EQUIPMENT_LEVEL:
			return "Maximum equipment level reached."
		ShopSystem.REASON_INVALID_EQUIPMENT:
			return "Invalid equipment upgrade."

	return "Equipment upgrade unavailable."


# Changes the selected seed quantity.
func _on_quantity_pressed(
	item_id: StringName,
	quantity: int
) -> void:
	_selected_quantities[item_id] = quantity

	var plant_data: PlantData = _plants.get(
		item_id
	) as PlantData

	if plant_data == null:
		return

	_refresh_seed_row(plant_data)
	_set_status(
		"%s quantity set to %d." % [
			plant_data.display_name,
			quantity
		],
		false
	)


# Purchases the selected seed quantity.
func _on_buy_pressed(
	plant_data: PlantData
) -> void:
	var quantity: int = int(
		_selected_quantities.get(
			plant_data.seed_item_id,
			1
		)
	)

	ShopSystem.buy_seed(
		plant_data,
		quantity
	)


# Sells the selected seed quantity.
func _on_sell_pressed(
	plant_data: PlantData
) -> void:
	var quantity: int = int(
		_selected_quantities.get(
			plant_data.seed_item_id,
			1
		)
	)

	ShopSystem.sell_seed(
		plant_data,
		quantity
	)


# Spends one milestone token to permanently unlock a plant.
func _on_plant_unlock_pressed(
	plant_data: PlantData
) -> void:
	ShopSystem.unlock_plant(plant_data)


# Purchases the next terrain level.
func _on_terrain_upgrade_pressed(
	terrain_id: StringName
) -> void:
	ShopSystem.buy_terrain_upgrade(terrain_id)


# Purchases the next equipment level.
func _on_equipment_upgrade_pressed(
	equipment_id: StringName
) -> void:
	ShopSystem.buy_equipment_upgrade(equipment_id)


# Handles a completed seed transaction.
func _on_transaction_completed(
	action: String,
	plant_data: PlantData,
	quantity: int,
	total_price: int
) -> void:
	var verb: String = "Bought"

	if action == ShopSystem.ACTION_SELL:
		verb = "Sold"

	_set_status(
		"%s %d %s seed%s for %d." % [
			verb,
			quantity,
			plant_data.display_name,
			"" if quantity == 1 else "s",
			total_price
		],
		false
	)
	_flash_seed_row(
		plant_data.seed_item_id,
		Color(0.62, 1.18, 0.62, 1.0)
	)
	_refresh_all()


# Handles a rejected seed transaction.
func _on_transaction_failed(
	action: String,
	plant_data: PlantData,
	_quantity: int,
	reason: String
) -> void:
	var message: String = "Transaction failed."

	match reason:
		ShopSystem.REASON_INSUFFICIENT_MONEY:
			message = "Not enough money."
		ShopSystem.REASON_INSUFFICIENT_STOCK:
			message = "Not enough seeds to sell."
		ShopSystem.REASON_INVALID_PRICE:
			message = "This item has no valid shop price."
		ShopSystem.REASON_NOT_FOR_SALE:
			message = "This item is not available in the shop."

	_set_status(message, true)

	if plant_data != null:
		_flash_seed_row(
			plant_data.seed_item_id,
			Color(1.28, 0.42, 0.42, 1.0)
		)

	if debug_log:
		print(
			"[ShopMenu] failed action=",
			action,
			" reason=",
			reason
		)


# Handles a completed permanent plant unlock.
func _on_plant_unlock_completed(
	plant_data: PlantData,
	token_cost: int
) -> void:
	_set_status(
		"%s unlocked permanently for %d token." % [
			plant_data.display_name,
			token_cost
		],
		false
	)
	_flash_seed_row(
		plant_data.seed_item_id,
		Color(0.62, 1.18, 0.62, 1.0)
	)
	_refresh_all()


# Handles a rejected permanent plant unlock.
func _on_plant_unlock_failed(
	plant_data: PlantData,
	reason: String
) -> void:
	var message: String = "Plant unlock failed."

	match reason:
		ShopSystem.REASON_INSUFFICIENT_UNLOCK_TOKENS:
			message = "No Plant Unlock Token is available."
		ShopSystem.REASON_ALREADY_UNLOCKED:
			message = "This plant is already unlocked."

	_set_status(message, true)

	if plant_data != null:
		_flash_seed_row(
			plant_data.seed_item_id,
			Color(1.28, 0.42, 0.42, 1.0)
		)


# Refreshes unlock controls when the token balance changes.
func _on_plant_unlock_tokens_changed(
	_previous_amount: int,
	_new_amount: int,
	_delta: int,
	_reason: String
) -> void:
	_refresh_all()


# Refreshes seed rows after one plant becomes available.
func _on_plant_unlock_changed(
	_plant_id: StringName,
	_unlocked: bool
) -> void:
	_refresh_all()


# Handles a completed terrain purchase.
func _on_terrain_upgrade_completed(
	terrain_id: StringName,
	previous_level: int,
	new_level: int,
	cost: int
) -> void:
	_set_status(
		"%s upgraded: Lv. %d → %d for %d." % [
			_get_terrain_display_name(terrain_id),
			previous_level,
			new_level,
			cost
		],
		false
	)
	_flash_terrain_row(
		terrain_id,
		Color(0.62, 1.18, 0.62, 1.0)
	)
	_refresh_all()


# Handles a rejected terrain purchase.
func _on_terrain_upgrade_failed(
	terrain_id: StringName,
	reason: String
) -> void:
	var message: String = "Terrain upgrade failed."

	match reason:
		ShopSystem.REASON_PLAYER_LEVEL_TOO_LOW:
			message = "Player Level is too low."
		ShopSystem.REASON_INSUFFICIENT_MONEY:
			message = "Not enough money."
		ShopSystem.REASON_MAX_TERRAIN_LEVEL:
			message = "Terrain is already at maximum level."

	_set_status(message, true)
	_flash_terrain_row(
		terrain_id,
		Color(1.28, 0.42, 0.42, 1.0)
	)


# Refreshes one terrain after its progression signal.
func _on_terrain_level_changed(
	terrain_id: StringName,
	_previous_level: int,
	_new_level: int
) -> void:
	_refresh_terrain_row(terrain_id)


# Refreshes terrain requirements after Player Level changes.
func _on_player_progress_changed(
	_level: int,
	_xp: int,
	_xp_to_next: int
) -> void:
	for terrain_entry: Dictionary in (
		ShopSystem.get_terrain_catalog()
	):
		var terrain_id: StringName = StringName(
			terrain_entry.get("id", &"")
		)
		_refresh_terrain_row(terrain_id)


	for equipment_entry: Dictionary in (
		ShopSystem.get_equipment_catalog()
	):
		var equipment_id: StringName = StringName(
			equipment_entry.get("id", &"")
		)
		_refresh_equipment_row(equipment_id)


# Handles a completed equipment purchase.
func _on_equipment_upgrade_completed(
	equipment_id: StringName,
	previous_level: int,
	new_level: int,
	cost: int
) -> void:
	_set_status(
		"%s upgraded: Lv. %d → %d for %d." % [
			_get_equipment_display_name(equipment_id),
			previous_level,
			new_level,
			cost
		],
		false
	)
	_flash_equipment_row(
		equipment_id,
		Color(0.62, 1.18, 0.62, 1.0)
	)
	_refresh_all()


# Handles a rejected equipment purchase.
func _on_equipment_upgrade_failed(
	equipment_id: StringName,
	reason: String
) -> void:
	var message: String = "Equipment upgrade failed."

	match reason:
		ShopSystem.REASON_PLAYER_LEVEL_TOO_LOW:
			message = "Player Level is too low."
		ShopSystem.REASON_INSUFFICIENT_MONEY:
			message = "Not enough money."
		ShopSystem.REASON_MAX_EQUIPMENT_LEVEL:
			message = "Equipment is already at maximum level."

	_set_status(message, true)
	_flash_equipment_row(
		equipment_id,
		Color(1.28, 0.42, 0.42, 1.0)
	)


# Refreshes one equipment row after progression changes.
func _on_equipment_level_changed(
	equipment_id: StringName,
	_previous_level: int,
	_new_level: int
) -> void:
	_refresh_equipment_row(equipment_id)


# Displays transaction feedback.
func _set_status(
	message: String,
	is_error: bool
) -> void:
	_status_label.text = message

	if is_error:
		_status_label.add_theme_color_override(
			"font_color",
			Color(1.0, 0.42, 0.36, 1.0)
		)
	else:
		_status_label.add_theme_color_override(
			"font_color",
			Color(0.72, 1.0, 0.62, 1.0)
		)


# Flashes one seed row after a transaction.
func _flash_seed_row(
	item_id: StringName,
	flash_color: Color
) -> void:
	var row_panel: PanelContainer = _seed_row_panels.get(
		item_id
	) as PanelContainer

	_flash_row_control(
		"seed_%s" % String(item_id),
		row_panel,
		flash_color
	)


# Flashes one terrain row after an upgrade.
func _flash_terrain_row(
	terrain_id: StringName,
	flash_color: Color
) -> void:
	var row_panel: PanelContainer = (
		_terrain_row_panels.get(
			terrain_id
		) as PanelContainer
	)

	_flash_row_control(
		"terrain_%s" % String(terrain_id),
		row_panel,
		flash_color
	)


# Flashes one equipment row after an upgrade.
func _flash_equipment_row(
	equipment_id: StringName,
	flash_color: Color
) -> void:
	var row_panel: PanelContainer = (
		_equipment_row_panels.get(
			equipment_id
		) as PanelContainer
	)

	_flash_row_control(
		"equipment_%s" % String(equipment_id),
		row_panel,
		flash_color
	)


# Flashes a row control using one managed tween.
func _flash_row_control(
	tween_key: String,
	row_panel: PanelContainer,
	flash_color: Color
) -> void:
	if row_panel == null:
		return

	var old_tween: Tween = _row_tweens.get(
		tween_key
	) as Tween

	if old_tween != null and old_tween.is_valid():
		old_tween.kill()

	row_panel.modulate = flash_color

	var tween: Tween = create_tween()
	tween.tween_property(
		row_panel,
		"modulate",
		Color.WHITE,
		0.34
	)
	_row_tweens[tween_key] = tween


# Handles a changed money balance.
func _on_money_changed(
	_previous_amount: int,
	_new_amount: int,
	_delta: int,
	_reason: String
) -> void:
	_refresh_all()


# Handles an economy reset.
func _on_economy_reset(
	_current_amount: int
) -> void:
	_refresh_all()


# Handles a changed seed inventory quantity.
func _on_item_amount_changed(
	item_id: StringName,
	_previous_amount: int,
	_new_amount: int
) -> void:
	var plant_data: PlantData = _plants.get(
		item_id
	) as PlantData

	if plant_data != null:
		_refresh_seed_row(plant_data)


# Handles an inventory reset.
func _on_inventory_reset(
	_items: Dictionary
) -> void:
	_refresh_all()


# Formats the active maintenance bonuses for a terrain row.
func _format_terrain_effects(effects: Dictionary) -> String:
	var moisture_reduction: int = int(round(
		float(effects.get("moisture_loss_reduction", 0.0)) * 100.0
	))
	var nutrient_reduction: int = int(round(
		float(effects.get("nutrient_loss_reduction", 0.0)) * 100.0
	))
	var treatment_bonus: int = int(round(
		float(effects.get("treatment_bonus", 0.0)) * 100.0
	))
	var ph_reduction: int = int(round(
		float(effects.get("ph_drift_reduction", 0.0)) * 100.0
	))
	var pressure_reduction: int = int(round(
		float(effects.get("bio_pressure_reduction", 0.0)) * 100.0
	))

	return (
		"Moisture loss -%d%% | Nutrient loss -%d%% | Treatment +%d%%\n"
		+ "pH drift -%d%% | Pest/Disease pressure -%d%%"
	) % [
		moisture_reduction,
		nutrient_reduction,
		treatment_bonus,
		ph_reduction,
		pressure_reduction
	]


# Formats the active gameplay bonus for one equipment item.
func _format_equipment_effects(
	equipment_id: StringName,
	effects: Dictionary
) -> String:
	var range_bonus: int = int(
		effects.get("range_bonus", 0)
	)
	var effect_bonus: int = int(round(
		float(effects.get("effect_bonus", 0.0))
		* 100.0
	))
	var recovery_chance: int = int(round(
		float(
			effects.get(
				"seed_recovery_chance",
				0.0
			)
		) * 100.0
	))

	if equipment_id == ProgressionSystem.EQUIPMENT_SHOVEL:
		return "Seed recovery %d%% | Range +%d cells" % [
			recovery_chance,
			range_bonus
		]

	if equipment_id == ProgressionSystem.EQUIPMENT_HARVEST:
		return "Harvest money +%d%% | Range +%d cells" % [
			effect_bonus,
			range_bonus
		]

	return "Tool effect +%d%% | Range +%d cells" % [
		effect_bonus,
		range_bonus
	]


# Returns one equipment display name.
func _get_equipment_display_name(
	equipment_id: StringName
) -> String:
	for equipment_entry: Dictionary in (
		ShopSystem.get_equipment_catalog()
	):
		if StringName(
			equipment_entry.get("id", &"")
		) == equipment_id:
			return String(
				equipment_entry.get(
					"display_name",
					String(equipment_id)
				)
			)

	return String(equipment_id)


# Returns one terrain display name.
func _get_terrain_display_name(
	terrain_id: StringName
) -> String:
	for terrain_entry: Dictionary in (
		ShopSystem.get_terrain_catalog()
	):
		if StringName(
			terrain_entry.get("id", &"")
		) == terrain_id:
			return String(
				terrain_entry.get(
					"display_name",
					String(terrain_id)
				)
			)

	return String(terrain_id)


# Creates a cropped plant icon from its final visual stage.
func _create_plant_icon(
	plant_data: PlantData
) -> Texture2D:
	if plant_data == null:
		return null

	if plant_data.stage_textures.is_empty():
		return null

	var stage_index: int = clampi(
		plant_data.max_stage,
		0,
		plant_data.stage_textures.size() - 1
	)
	var source_texture: Texture2D = (
		plant_data.stage_textures[stage_index]
	)

	if source_texture == null:
		return null

	if stage_index >= plant_data.stage_regions.size():
		return source_texture

	var region: Rect2 = plant_data.stage_regions[
		stage_index
	]

	if region.size.x <= 0.0 or region.size.y <= 0.0:
		return source_texture

	var atlas_texture := AtlasTexture.new()
	atlas_texture.atlas = source_texture
	atlas_texture.region = region
	return atlas_texture


# Applies normal and destructive button styles.
func _apply_button_style(
	button: Button,
	destructive: bool
) -> void:
	button.add_theme_stylebox_override(
		"normal",
		_create_button_style(destructive, false)
	)
	button.add_theme_stylebox_override(
		"hover",
		_create_button_style(destructive, true)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_create_button_style(destructive, true)
	)
	button.add_theme_stylebox_override(
		"disabled",
		_create_disabled_button_style()
	)


# Creates the main shop panel style.
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


# Creates one shop row style.
func _create_row_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.072, 0.96)
	style.border_color = Color(0.20, 0.24, 0.20, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


# Creates the shop icon frame style.
func _create_icon_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.09, 0.98)
	style.border_color = Color(0.48, 0.66, 0.38, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style


# Creates buy, sell, upgrade, and close button states.
func _create_button_style(
	destructive: bool,
	hovered: bool
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	if destructive:
		style.bg_color = Color(0.18, 0.10, 0.08, 0.98)
		style.border_color = Color(0.94, 0.46, 0.34, 1.0)
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


# Creates disabled transaction and upgrade states.
func _create_disabled_button_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.065, 0.068, 0.064, 0.94)
	style.border_color = Color(0.19, 0.20, 0.18, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style


# Creates selected and unselected quantity button states.
func _create_quantity_style(
	selected: bool,
	hovered: bool
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	if selected:
		style.bg_color = Color(0.18, 0.25, 0.12, 0.98)
		style.border_color = Color(0.78, 1.0, 0.38, 1.0)
	elif hovered:
		style.bg_color = Color(0.14, 0.16, 0.14, 0.98)
		style.border_color = Color(0.54, 0.62, 0.50, 1.0)
	else:
		style.bg_color = Color(0.085, 0.095, 0.085, 0.98)
		style.border_color = Color(0.28, 0.32, 0.28, 1.0)

	var width: int = 3 if selected else 2
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style


# Creates selected and unselected tab button states.
func _create_tab_style(
	selected: bool,
	hovered: bool
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	if selected:
		style.bg_color = Color(0.16, 0.23, 0.11, 0.98)
		style.border_color = Color(0.78, 1.0, 0.38, 1.0)
	elif hovered:
		style.bg_color = Color(0.13, 0.15, 0.13, 0.98)
		style.border_color = Color(0.50, 0.58, 0.47, 1.0)
	else:
		style.bg_color = Color(0.075, 0.085, 0.075, 0.98)
		style.border_color = Color(0.24, 0.28, 0.24, 1.0)

	var width: int = 3 if selected else 2
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style
