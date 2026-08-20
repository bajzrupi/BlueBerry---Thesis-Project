extends CanvasLayer

# Minecraft-style bottom hotbar for assigned plant items.
const SLOT_SIZE: Vector2 = Vector2(58.0, 58.0)


@export_category("Inventory Hotbar")

# Controls the CanvasLayer drawing order.
@export var hud_layer: int = 6

# Distance between the hotbar and the bottom screen edge.
@export var bottom_margin: float = 14.0

# Space between adjacent slots.
@export var slot_separation: int = 4

# Size of the item icon inside each slot.
@export var item_icon_size: Vector2 = Vector2(42.0, 42.0)


@export_category("Debug Logging")

# Enables hotbar initialization and update logs.
@export var debug_log: bool = false


# Stores slot buttons by slot index.
var _slot_buttons: Array[Button] = []

# Stores item icons by slot index.
var _slot_icons: Array[TextureRect] = []

# Stores amount labels by slot index.
var _slot_amount_labels: Array[Label] = []

# Stores number labels by slot index.
var _slot_number_labels: Array[Label] = []

# Stores the visible hotbar panel.
var _hotbar_panel: PanelContainer

# Stores the active capacity warning animation.
var _capacity_tween: Tween


# Builds the hotbar and connects system signals.
func _ready() -> void:
	layer = hud_layer

	_build_hotbar()
	_connect_system_signals()
	_refresh_all_slots()
	_refresh_selection()

	if debug_log:
		print(
			"[InventoryHotbar] ready slots=",
			HotbarSystem.get_slot_count()
		)


# Cycles through occupied hotbar slots with the mouse wheel.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return

	var mouse_event := event as InputEventMouseButton

	if not mouse_event.pressed:
		return

	match mouse_event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			_cycle_hotbar_selection(-1)
			get_viewport().set_input_as_handled()

		MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_hotbar_selection(1)
			get_viewport().set_input_as_handled()


# Selects the previous or next occupied hotbar slot.
func _cycle_hotbar_selection(direction: int) -> void:
	if direction == 0:
		return

	var occupied_slots: Array[int] = []

	for slot_index in range(HotbarSystem.get_slot_count()):
		if HotbarSystem.get_plant(slot_index) != null:
			occupied_slots.append(slot_index)

	if occupied_slots.is_empty():
		if debug_log:
			print("[InventoryHotbar] wheel ignored: no assigned plants")

		return

	var selected_plant: PlantData = PlantSelectionSystem.get_current_plant()
	var selected_slot: int = HotbarSystem.find_plant_slot(selected_plant)
	var occupied_index: int = occupied_slots.find(selected_slot)
	var target_occupied_index: int

	if occupied_index < 0:
		target_occupied_index = (
			0 if direction > 0 else occupied_slots.size() - 1
		)
	else:
		target_occupied_index = posmod(
			occupied_index + direction,
			occupied_slots.size()
		)

	var target_slot: int = occupied_slots[target_occupied_index]
	var target_plant: PlantData = HotbarSystem.get_plant(target_slot)

	if target_plant == null:
		return

	PlantSelectionSystem.set_plant(target_plant)

	if debug_log:
		print(
			"[InventoryHotbar] wheel selected slot=",
			target_slot,
			" plant=",
			target_plant.display_name,
			" direction=",
			direction
		)


# Creates the bottom-centered hotbar.
func _build_hotbar() -> void:
	var bottom_anchor := CenterContainer.new()
	bottom_anchor.name = "BottomAnchor"
	bottom_anchor.set_anchors_preset(
		Control.PRESET_BOTTOM_WIDE
	)
	bottom_anchor.offset_top = -(SLOT_SIZE.y + 28.0)
	bottom_anchor.offset_bottom = -bottom_margin
	bottom_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bottom_anchor)

	_hotbar_panel = PanelContainer.new()
	_hotbar_panel.name = "HotbarPanel"
	_hotbar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hotbar_panel.add_theme_stylebox_override(
		"panel",
		_create_hotbar_background()
	)
	bottom_anchor.add_child(_hotbar_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_hotbar_panel.add_child(margin)

	var slots := HBoxContainer.new()
	slots.name = "Slots"
	slots.mouse_filter = Control.MOUSE_FILTER_PASS
	slots.add_theme_constant_override(
		"separation",
		slot_separation
	)
	margin.add_child(slots)

	for index in range(HotbarSystem.get_slot_count()):
		slots.add_child(_create_slot(index))


# Creates one fixed hotbar slot.
func _create_slot(index: int) -> Button:
	var button := Button.new()
	button.name = "Slot%d" % (index + 1)
	button.custom_minimum_size = SLOT_SIZE
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	button.text = ""
	button.pressed.connect(
		_on_slot_pressed.bind(index)
	)

	var icon := TextureRect.new()
	icon.name = "ItemIcon"
	icon.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	icon.offset_left = (
		(SLOT_SIZE.x - item_icon_size.x) * 0.5
	)
	icon.offset_top = (
		(SLOT_SIZE.y - item_icon_size.y) * 0.5
	)
	icon.offset_right = -icon.offset_left
	icon.offset_bottom = -icon.offset_top
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)

	var amount_label := Label.new()
	amount_label.name = "Amount"
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
	amount_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_BOTTOM
	)
	amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	amount_label.add_theme_font_size_override(
		"font_size",
		15
	)
	amount_label.add_theme_color_override(
		"font_outline_color",
		Color(0.03, 0.03, 0.03, 1.0)
	)
	amount_label.add_theme_constant_override(
		"outline_size",
		4
	)
	button.add_child(amount_label)

	var number_label := Label.new()
	number_label.name = "SlotNumber"
	number_label.text = str(index + 1)
	number_label.position = Vector2(5.0, 2.0)
	number_label.size = Vector2(18.0, 16.0)
	number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number_label.add_theme_font_size_override(
		"font_size",
		9
	)
	number_label.add_theme_color_override(
		"font_color",
		Color(0.68, 0.72, 0.67, 1.0)
	)
	number_label.add_theme_color_override(
		"font_outline_color",
		Color(0.02, 0.02, 0.02, 1.0)
	)
	number_label.add_theme_constant_override(
		"outline_size",
		2
	)
	button.add_child(number_label)

	_slot_buttons.append(button)
	_slot_icons.append(icon)
	_slot_amount_labels.append(amount_label)
	_slot_number_labels.append(number_label)

	_apply_slot_style(index)
	return button


# Connects the hotbar to inventory, assignments, and selection.
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


# Refreshes every hotbar slot.
func _refresh_all_slots() -> void:
	for index in range(_slot_buttons.size()):
		_refresh_slot(index)


# Refreshes one slot assignment, icon, and amount.
func _refresh_slot(index: int) -> void:
	if index < 0 or index >= _slot_buttons.size():
		return

	var plant_data := HotbarSystem.get_plant(index)
	var button := _slot_buttons[index]
	var icon := _slot_icons[index]
	var amount_label := _slot_amount_labels[index]

	if plant_data == null:
		button.disabled = true
		button.tooltip_text = "Empty slot"
		icon.texture = null
		icon.modulate = Color.WHITE
		amount_label.text = ""
	else:
		button.disabled = false
		button.tooltip_text = plant_data.display_name
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

	_apply_slot_style(index)


# Creates a cropped icon from the plant's final visual stage.
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


# Refreshes the selected slot highlight.
func _refresh_selection() -> void:
	for index in range(_slot_buttons.size()):
		_apply_slot_style(index)


# Applies visual states to one slot.
func _apply_slot_style(index: int) -> void:
	if index < 0 or index >= _slot_buttons.size():
		return

	var plant_data := HotbarSystem.get_plant(index)
	var selected := (
		plant_data != null
		and PlantSelectionSystem.is_selected(plant_data)
	)
	var empty := plant_data == null
	var button := _slot_buttons[index]

	button.add_theme_stylebox_override(
		"normal",
		_create_slot_style(selected, false, empty)
	)
	button.add_theme_stylebox_override(
		"hover",
		_create_slot_style(selected, true, empty)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_create_slot_style(true, true, false)
	)
	button.add_theme_stylebox_override(
		"focus",
		_create_slot_style(selected, false, empty)
	)
	button.add_theme_stylebox_override(
		"disabled",
		_create_slot_style(false, false, true)
	)


# Creates the hotbar outer background.
func _create_hotbar_background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.035, 0.88)
	style.border_color = Color(0.12, 0.15, 0.12, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style


# Creates one slot state style.
func _create_slot_style(
	selected: bool,
	hovered: bool,
	empty: bool
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	if empty:
		style.bg_color = Color(0.07, 0.075, 0.07, 0.72)
		style.border_color = Color(0.17, 0.18, 0.17, 0.75)
	elif selected:
		style.bg_color = Color(0.17, 0.23, 0.12, 0.96)
		style.border_color = Color(0.78, 1.0, 0.42, 1.0)
	elif hovered:
		style.bg_color = Color(0.16, 0.17, 0.15, 0.96)
		style.border_color = Color(0.62, 0.68, 0.58, 1.0)
	else:
		style.bg_color = Color(0.10, 0.11, 0.10, 0.94)
		style.border_color = Color(0.34, 0.37, 0.33, 1.0)

	var border_width := 2

	if selected:
		border_width = 4

	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


# Selects the plant assigned to a clicked slot.
func _on_slot_pressed(index: int) -> void:
	var plant_data := HotbarSystem.get_plant(index)

	if plant_data == null:
		return

	PlantSelectionSystem.set_plant(plant_data)

	if debug_log:
		print(
			"[InventoryHotbar] clicked slot=",
			index,
			" plant=",
			plant_data.display_name
		)


# Handles one inventory amount change.
func _on_item_amount_changed(
	item_id: StringName,
	previous_amount: int,
	new_amount: int
) -> void:
	for index in range(_slot_buttons.size()):
		var plant_data := HotbarSystem.get_plant(index)

		if (
			plant_data != null
			and plant_data.seed_item_id == item_id
		):
			_refresh_slot(index)

	if debug_log:
		print(
			"[InventoryHotbar] amount item=",
			String(item_id),
			" old=",
			previous_amount,
			" new=",
			new_amount
		)


# Handles a complete inventory reset.
func _on_inventory_reset(_items: Dictionary) -> void:
	_refresh_all_slots()

	if debug_log:
		print("[InventoryHotbar] inventory reset")


# Handles one changed hotbar assignment.
func _on_hotbar_slot_changed(
	slot_index: int,
	_plant_data: PlantData
) -> void:
	_refresh_slot(slot_index)
	_refresh_selection()


# Handles a complete hotbar reset.
func _on_hotbar_reset() -> void:
	_refresh_all_slots()
	_refresh_selection()


# Handles a selected or deselected plant.
func _on_plant_selection_changed(
	plant_data: PlantData,
	index: int
) -> void:
	_refresh_selection()

	if not debug_log:
		return

	if plant_data == null:
		print("[InventoryHotbar] selection cleared")
	else:
		print(
			"[InventoryHotbar] selected plant=",
			plant_data.display_name,
			" plant_index=",
			index,
			" hotbar_slot=",
			HotbarSystem.find_plant_slot(plant_data)
		)


# Handles rejected assignments with a red capacity flash.
func _on_hotbar_assignment_failed(
	reason: String,
	_plant_data: PlantData,
	_slot_index: int
) -> void:
	_flash_capacity_error(reason)


# Flashes the complete hotbar when an assignment cannot be completed.
func _flash_capacity_error(reason: String) -> void:
	if _hotbar_panel == null:
		return

	if _capacity_tween != null and _capacity_tween.is_valid():
		_capacity_tween.kill()

	_hotbar_panel.modulate = Color(1.35, 0.35, 0.35, 1.0)
	_capacity_tween = create_tween()
	_capacity_tween.tween_property(
		_hotbar_panel,
		"modulate",
		Color.WHITE,
		0.38
	)

	if debug_log:
		print(
			"[InventoryHotbar] blocked reason=",
			reason
		)
