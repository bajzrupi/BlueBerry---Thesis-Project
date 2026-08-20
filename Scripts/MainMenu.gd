extends Control

# Startup Main Menu with three independent Garden save slots.
# New Game -> choose Garden slot -> required Character Select -> gameplay.
# Continue -> most recently used existing Garden.
# Gardens -> play, create, overwrite or delete individual Garden slots.

@export_category("Debug Logging")
@export var debug_log: bool = false


enum SlotScreenMode {
	NONE,
	NEW_GAME,
	GARDENS
}


var _new_game_button: Button
var _continue_button: Button
var _gardens_button: Button
var _quit_button: Button
var _status_label: Label

var _slot_overlay: ColorRect
var _slot_panel: PanelContainer
var _slot_title: Label
var _slot_rows: VBoxContainer
var _slot_back_button: Button
var _slot_screen_mode: int = SlotScreenMode.NONE

var _overwrite_dialog: ConfirmationDialog
var _delete_dialog: ConfirmationDialog
var _quit_dialog: ConfirmationDialog

var _pending_new_game_slot: int = -1
var _pending_delete_slot: int = -1


# Initializes this system when the node becomes ready.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameFlowSystem.prepare_main_menu()

	_build_ui()
	_connect_signals()
	_refresh_main_menu()

	if debug_log:
		print(
			"[MainMenu] ready saves=",
			SaveSystem.get_existing_slots(),
			" preferred_continue=",
			SaveSystem.get_preferred_continue_slot()
		)


# Connects the signals signals and callbacks.
func _connect_signals() -> void:
	if not CharacterSelectSystem.character_confirmed.is_connected(
		_on_character_confirmed
	):
		CharacterSelectSystem.character_confirmed.connect(
			_on_character_confirmed
		)

	if not GameFlowSystem.game_launch_failed.is_connected(
		_on_game_launch_failed
	):
		GameFlowSystem.game_launch_failed.connect(
			_on_game_launch_failed
		)

	if not SaveSystem.save_deleted.is_connected(
		_on_save_deleted
	):
		SaveSystem.save_deleted.connect(
			_on_save_deleted
		)


# -----------------------------------------------------------------------------
# Main buttons
# -----------------------------------------------------------------------------

# Handles the new game pressed signal or callback.
func _on_new_game_pressed() -> void:
	_open_slot_screen(SlotScreenMode.NEW_GAME)


# Handles the continue pressed signal or callback.
func _on_continue_pressed() -> void:
	var slot: int = SaveSystem.get_preferred_continue_slot()

	if slot == -1:
		_refresh_main_menu()
		return

	_launch_continue(slot)


# Handles the gardens pressed signal or callback.
func _on_gardens_pressed() -> void:
	_open_slot_screen(SlotScreenMode.GARDENS)


# Handles the quit pressed signal or callback.
func _on_quit_pressed() -> void:
	_quit_dialog.dialog_text = (
		"Are you sure you want to quit the game?"
	)
	_quit_dialog.popup_centered(
		Vector2i(390, 150)
	)


# Handles the quit confirmed signal or callback.
func _on_quit_confirmed() -> void:
	get_tree().quit()


# -----------------------------------------------------------------------------
# Garden slot screen
# -----------------------------------------------------------------------------

# Opens the slot screen.
func _open_slot_screen(mode: int) -> void:
	_slot_screen_mode = mode
	_slot_overlay.visible = true
	_slot_panel.visible = true

	if mode == SlotScreenMode.NEW_GAME:
		_slot_title.text = "SELECT A GARDEN SLOT"
	else:
		_slot_title.text = "GARDENS"

	_refresh_slot_rows()

	if debug_log:
		print(
			"[MainMenu] slot screen mode=",
			mode,
			" saves=",
			SaveSystem.get_existing_slots()
		)


# Closes the slot screen.
func _close_slot_screen() -> void:
	_slot_screen_mode = SlotScreenMode.NONE
	_slot_overlay.visible = false
	_slot_panel.visible = false
	_pending_new_game_slot = -1
	_pending_delete_slot = -1
	_refresh_main_menu()


# Refreshes the slot rows.
func _refresh_slot_rows() -> void:
	for child in _slot_rows.get_children():
		_slot_rows.remove_child(child)
		child.queue_free()

	for slot in range(1, SaveSystem.MAX_SAVE_SLOTS + 1):
		_slot_rows.add_child(
			_create_slot_row(slot)
		)


# Creates the slot row.
func _create_slot_row(slot: int) -> Control:
	var metadata: Dictionary = SaveSystem.get_slot_metadata(slot)
	var exists: bool = bool(metadata.get("exists", false))
	var valid: bool = bool(metadata.get("valid", false))

	var card := PanelContainer.new()
	card.name = "GardenSlot%d" % slot
	card.custom_minimum_size = Vector2(560.0, 84.0)
	card.add_theme_stylebox_override(
		"panel",
		_create_slot_style(
			slot == SaveSystem.get_active_slot()
		)
	)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	row.add_child(info)

	var title := Label.new()
	title.text = "GARDEN %d" % slot
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override(
		"font_color",
		Color(0.86, 0.95, 0.82, 1.0)
	)
	info.add_child(title)

	var details := Label.new()
	details.add_theme_font_size_override("font_size", 11)
	details.add_theme_color_override(
		"font_color",
		Color(0.65, 0.75, 0.70, 1.0)
	)

	if not exists:
		details.text = "EMPTY GARDEN"
	elif not valid:
		details.text = "UNREADABLE / INCOMPATIBLE SAVE"
	else:
		details.text = _format_slot_metadata(metadata)

	info.add_child(details)

	var primary := Button.new()
	primary.custom_minimum_size = Vector2(108.0, 38.0)
	primary.add_theme_font_size_override("font_size", 11)
	primary.pressed.connect(
		_on_slot_primary_pressed.bind(slot)
	)
	row.add_child(primary)

	var delete_button := Button.new()
	delete_button.custom_minimum_size = Vector2(82.0, 38.0)
	delete_button.text = "DELETE"
	delete_button.add_theme_font_size_override("font_size", 10)
	delete_button.pressed.connect(
		_on_slot_delete_pressed.bind(slot)
	)
	row.add_child(delete_button)

	if _slot_screen_mode == SlotScreenMode.NEW_GAME:
		primary.text = "OVERWRITE" if exists else "START"
		primary.disabled = false
		delete_button.visible = false
	else:
		if exists:
			primary.text = "PLAY"
			primary.disabled = not valid
			delete_button.visible = true
		else:
			primary.text = "NEW GAME"
			primary.disabled = false
			delete_button.visible = false

	return card


# Formats the slot metadata for display.
func _format_slot_metadata(metadata: Dictionary) -> String:
	var character_text: String = String(
		metadata.get("character_id", "male")
	).capitalize()
	var player_level: int = int(
		metadata.get("player_level", 0)
	)
	var day: int = int(metadata.get("day", 1))
	var money: int = int(metadata.get("money", 0))

	return (
		"%s  •  Player Lv. %d  •  Day %d  •  $%d"
		% [character_text, player_level, day, money]
	)


# Handles the slot primary pressed signal or callback.
func _on_slot_primary_pressed(slot: int) -> void:
	var metadata := SaveSystem.get_slot_metadata(slot)
	var exists: bool = bool(metadata.get("exists", false))

	if _slot_screen_mode == SlotScreenMode.NEW_GAME:
		_request_new_game(slot, exists)
		return

	if _slot_screen_mode == SlotScreenMode.GARDENS:
		if exists:
			if bool(metadata.get("valid", false)):
				_launch_continue(slot)
		else:
			_request_new_game(slot, false)


# Requests the new game.
func _request_new_game(slot: int, occupied: bool) -> void:
	_pending_new_game_slot = slot

	if occupied:
		_overwrite_dialog.dialog_text = (
			"Garden %d already contains a save.\n\n"
			+ "Starting a new garden here will permanently replace it "
			+ "after you confirm your character.\n\n"
			+ "Continue?"
		) % slot
		_overwrite_dialog.popup_centered(
			Vector2i(470, 210)
		)
		return

	_begin_character_select_for_slot(slot)


# Handles the overwrite confirmed signal or callback.
func _on_overwrite_confirmed() -> void:
	if not SaveSystem.is_valid_slot(_pending_new_game_slot):
		return

	_begin_character_select_for_slot(
		_pending_new_game_slot
	)


# Handles begin character select for slot.
func _begin_character_select_for_slot(slot: int) -> void:
	_pending_new_game_slot = slot

	if not SaveSystem.set_active_slot(slot):
		_status_label.text = "Could not select Garden %d." % slot
		return

	_slot_overlay.visible = false
	_slot_panel.visible = false
	_set_main_buttons_enabled(false)

	_status_label.text = (
		"Garden %d selected. Choose your character."
		% slot
	)

	CharacterSelectSystem.open_selector(true)

	if debug_log:
		print(
			"[MainMenu] NEW GAME slot=",
			slot,
			" -> Character Select"
		)


# Handles the character confirmed signal or callback.
func _on_character_confirmed(
	character_id: StringName
) -> void:
	if not SaveSystem.is_valid_slot(_pending_new_game_slot):
		return

	var slot := _pending_new_game_slot

	_status_label.text = (
		"Starting Garden %d as %s..."
		% [slot, String(character_id).capitalize()]
	)

	call_deferred("_launch_new_game", slot)


# Handles launch new game.
func _launch_new_game(slot: int) -> void:
	if not GameFlowSystem.start_new_game(slot):
		_set_main_buttons_enabled(true)
		_open_slot_screen(SlotScreenMode.NEW_GAME)
		return

	_pending_new_game_slot = -1


# Handles launch continue.
func _launch_continue(slot: int) -> void:
	if not SaveSystem.has_save(slot):
		_refresh_main_menu()
		_refresh_slot_rows_if_open()
		return

	_set_main_buttons_enabled(false)
	_slot_overlay.visible = false
	_slot_panel.visible = false
	_status_label.text = "Loading Garden %d..." % slot

	if not GameFlowSystem.continue_game(slot):
		_set_main_buttons_enabled(true)
		_refresh_main_menu()
		_refresh_slot_rows_if_open()


# -----------------------------------------------------------------------------
# Delete Garden
# -----------------------------------------------------------------------------

# Handles the slot delete pressed signal or callback.
func _on_slot_delete_pressed(slot: int) -> void:
	if not SaveSystem.has_save(slot):
		_refresh_slot_rows()
		return

	_pending_delete_slot = slot
	_delete_dialog.dialog_text = (
		"Delete Garden %d?\n\n"
		+ "This permanently removes this save file.\n"
		+ "This action cannot be undone."
	) % slot
	_delete_dialog.popup_centered(
		Vector2i(430, 190)
	)


# Handles the delete confirmed signal or callback.
func _on_delete_confirmed() -> void:
	if not SaveSystem.is_valid_slot(_pending_delete_slot):
		return

	var slot := _pending_delete_slot
	_pending_delete_slot = -1

	if SaveSystem.delete_save(slot):
		_status_label.text = "Garden %d deleted." % slot
	else:
		_status_label.text = "Could not delete Garden %d." % slot

	_refresh_main_menu()
	_refresh_slot_rows_if_open()


# Handles the save deleted signal or callback.
func _on_save_deleted(slot: int) -> void:
	if debug_log:
		print("[MainMenu] Garden deleted slot=", slot)


# -----------------------------------------------------------------------------
# Refresh / failures
# -----------------------------------------------------------------------------

# Handles the game launch failed signal or callback.
func _on_game_launch_failed(reason: String) -> void:
	_status_label.text = (
		"Could not start the game: %s" % reason
	)
	_set_main_buttons_enabled(true)
	_refresh_main_menu()
	_refresh_slot_rows_if_open()


# Refreshes the main menu.
func _refresh_main_menu() -> void:
	if _continue_button == null:
		return

	var continue_slot: int = (
		SaveSystem.get_preferred_continue_slot()
	)
	var has_any: bool = continue_slot != -1

	_continue_button.disabled = not has_any

	if has_any:
		_continue_button.text = (
			"CONTINUE • GARDEN %d" % continue_slot
		)
		_continue_button.tooltip_text = (
			"Continue the most recently used Garden."
		)
		_status_label.text = (
			"%d / %d garden slots are in use."
			% [
				SaveSystem.get_existing_slots().size(),
				SaveSystem.MAX_SAVE_SLOTS
			]
		)
	else:
		_continue_button.text = "CONTINUE"
		_continue_button.tooltip_text = (
			"No saved garden exists yet."
		)
		_status_label.text = (
			"No saved gardens yet. Start a new one."
		)


# Refreshes the slot rows if open.
func _refresh_slot_rows_if_open() -> void:
	if _slot_screen_mode == SlotScreenMode.NONE:
		return

	if not _slot_panel.visible:
		return

	_refresh_slot_rows()


# Sets the main buttons enabled.
func _set_main_buttons_enabled(enabled: bool) -> void:
	_new_game_button.disabled = not enabled
	_gardens_button.disabled = not enabled
	_quit_button.disabled = not enabled

	if enabled:
		_continue_button.disabled = (
			not SaveSystem.has_any_save()
		)
	else:
		_continue_button.disabled = true


# -----------------------------------------------------------------------------
# UI construction
# -----------------------------------------------------------------------------

# Builds the UI.
func _build_ui() -> void:
	var background := ColorRect.new()
	background.name = "Background"
	background.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	background.color = Color(0.025, 0.045, 0.038, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var glow := ColorRect.new()
	glow.name = "CenterGlow"
	glow.set_anchors_preset(Control.PRESET_CENTER)
	glow.position = Vector2(-300.0, -260.0)
	glow.size = Vector2(600.0, 520.0)
	glow.color = Color(0.08, 0.16, 0.12, 0.55)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var panel := PanelContainer.new()
	panel.name = "MenuPanel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-240.0, -245.0)
	panel.size = Vector2(480.0, 490.0)
	panel.add_theme_stylebox_override(
		"panel",
		_create_panel_style()
	)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)

	var title := Label.new()
	title.text = "BLUEBERRY"
	title.custom_minimum_size = Vector2(0.0, 58.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override(
		"font_color",
		Color(0.78, 0.96, 0.72, 1.0)
	)
	title.add_theme_color_override(
		"font_outline_color",
		Color(0.01, 0.02, 0.015, 1.0)
	)
	title.add_theme_constant_override("outline_size", 4)
	content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "BOTANICAL GARDEN • ALPHA"
	subtitle.custom_minimum_size = Vector2(0.0, 28.0)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override(
		"font_color",
		Color(0.56, 0.72, 0.66, 1.0)
	)
	content.add_child(subtitle)

	var separator := HSeparator.new()
	separator.custom_minimum_size = Vector2(0.0, 10.0)
	content.add_child(separator)

	_new_game_button = _create_menu_button("NEW GAME")
	_new_game_button.pressed.connect(_on_new_game_pressed)
	content.add_child(_new_game_button)

	_continue_button = _create_menu_button("CONTINUE")
	_continue_button.pressed.connect(_on_continue_pressed)
	content.add_child(_continue_button)

	_gardens_button = _create_menu_button("GARDENS")
	_gardens_button.pressed.connect(_on_gardens_pressed)
	content.add_child(_gardens_button)

	_quit_button = _create_menu_button("QUIT")
	_quit_button.pressed.connect(_on_quit_pressed)
	content.add_child(_quit_button)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.custom_minimum_size = Vector2(0.0, 46.0)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override(
		"font_color",
		Color(0.64, 0.74, 0.70, 1.0)
	)
	content.add_child(_status_label)

	_build_slot_overlay()
	_build_dialogs()


# Builds the slot overlay.
func _build_slot_overlay() -> void:
	_slot_overlay = ColorRect.new()
	_slot_overlay.name = "SlotBackdrop"
	_slot_overlay.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_slot_overlay.color = Color(0.0, 0.0, 0.0, 0.72)
	_slot_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_slot_overlay.visible = false
	add_child(_slot_overlay)

	_slot_panel = PanelContainer.new()
	_slot_panel.name = "GardenSlotsPanel"
	_slot_panel.set_anchors_preset(Control.PRESET_CENTER)
	_slot_panel.position = Vector2(-330.0, -250.0)
	_slot_panel.size = Vector2(660.0, 500.0)
	_slot_panel.add_theme_stylebox_override(
		"panel",
		_create_panel_style()
	)
	_slot_panel.visible = false
	add_child(_slot_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_bottom", 24)
	_slot_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)

	_slot_title = Label.new()
	_slot_title.text = "GARDENS"
	_slot_title.custom_minimum_size = Vector2(0.0, 42.0)
	_slot_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slot_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_slot_title.add_theme_font_size_override("font_size", 23)
	_slot_title.add_theme_color_override(
		"font_color",
		Color(0.88, 0.96, 0.84, 1.0)
	)
	content.add_child(_slot_title)

	var explanation := Label.new()
	explanation.text = (
		"Each Garden is an independent save file."
	)
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	explanation.add_theme_font_size_override("font_size", 11)
	explanation.add_theme_color_override(
		"font_color",
		Color(0.62, 0.72, 0.68, 1.0)
	)
	content.add_child(explanation)

	_slot_rows = VBoxContainer.new()
	_slot_rows.add_theme_constant_override("separation", 10)
	content.add_child(_slot_rows)

	_slot_back_button = Button.new()
	_slot_back_button.text = "BACK"
	_slot_back_button.custom_minimum_size = Vector2(0.0, 38.0)
	_slot_back_button.pressed.connect(_close_slot_screen)
	content.add_child(_slot_back_button)


# Builds the dialogs.
func _build_dialogs() -> void:
	_overwrite_dialog = ConfirmationDialog.new()
	_overwrite_dialog.name = "OverwriteGardenDialog"
	_overwrite_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_overwrite_dialog.title = "Overwrite Garden"
	_overwrite_dialog.get_ok_button().text = "Continue"
	_overwrite_dialog.get_cancel_button().text = "Cancel"
	_overwrite_dialog.confirmed.connect(
		_on_overwrite_confirmed
	)
	add_child(_overwrite_dialog)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.name = "DeleteGardenDialog"
	_delete_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_delete_dialog.title = "Delete Garden"
	_delete_dialog.get_ok_button().text = "Delete"
	_delete_dialog.get_cancel_button().text = "Cancel"
	_delete_dialog.confirmed.connect(
		_on_delete_confirmed
	)
	add_child(_delete_dialog)

	_quit_dialog = ConfirmationDialog.new()
	_quit_dialog.name = "QuitGameDialog"
	_quit_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_quit_dialog.unresizable = true
	_quit_dialog.exclusive = true
	_quit_dialog.always_on_top = true
	_quit_dialog.title = "Quit Game"
	_quit_dialog.get_ok_button().text = "Quit Game"
	_quit_dialog.get_cancel_button().text = "Cancel"
	_quit_dialog.confirmed.connect(
		_on_quit_confirmed
	)
	add_child(_quit_dialog)


# Creates the menu button.
func _create_menu_button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0.0, 50.0)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 15)

	button.add_theme_stylebox_override(
		"normal",
		_create_button_style(false, false)
	)
	button.add_theme_stylebox_override(
		"hover",
		_create_button_style(true, false)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_create_button_style(true, true)
	)
	button.add_theme_stylebox_override(
		"disabled",
		_create_disabled_button_style()
	)

	return button


# Creates the panel style.
func _create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.060, 0.050, 0.97)
	style.border_color = Color(0.30, 0.56, 0.50, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 12
	return style


# Creates the slot style.
func _create_slot_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.082, 0.068, 0.98)

	if active:
		style.border_color = Color(0.60, 0.84, 0.48, 1.0)
		style.border_width_left = 2
		style.border_width_top = 2
		style.border_width_right = 2
		style.border_width_bottom = 2
	else:
		style.border_color = Color(0.20, 0.34, 0.29, 1.0)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1

	style.corner_radius_top_left = 7
	style.corner_radius_top_right = 7
	style.corner_radius_bottom_left = 7
	style.corner_radius_bottom_right = 7
	return style


# Creates the button style.
func _create_button_style(
	hovered: bool,
	pressed: bool
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	if pressed:
		style.bg_color = Color(0.12, 0.28, 0.21, 1.0)
	elif hovered:
		style.bg_color = Color(0.10, 0.23, 0.18, 1.0)
	else:
		style.bg_color = Color(0.065, 0.12, 0.095, 1.0)

	style.border_color = (
		Color(0.56, 0.82, 0.50, 1.0)
		if hovered
		else Color(0.22, 0.38, 0.33, 1.0)
	)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


# Creates the disabled button style.
func _create_disabled_button_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.065, 0.058, 0.90)
	style.border_color = Color(0.14, 0.19, 0.17, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style
