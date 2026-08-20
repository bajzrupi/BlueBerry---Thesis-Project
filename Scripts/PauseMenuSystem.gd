extends Node

# Alpha pause menu and user-facing Save/Load entry point.

@export_category("Debug Logging")
@export var debug_log: bool = false


var _is_open: bool = false
var _previous_mouse_mode: int = Input.MOUSE_MODE_HIDDEN

var _ui_layer: CanvasLayer
var _backdrop: ColorRect
var _panel: Panel
var _status_label: Label
var _save_button: Button
var _load_button: Button
var _main_menu_dialog: ConfirmationDialog
var _quit_dialog: ConfirmationDialog


# Initializes this system when the node becomes ready.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_ui()
	_connect_save_signals()

	if debug_log:
		print(
			"[PauseMenu] ready key=Esc save_exists=",
			SaveSystem.has_save()
		)


# Handles direct player input.
func _input(event: InputEvent) -> void:
	if not _is_escape_pressed(event):
		return

	if _is_open:
		close_menu()
		get_viewport().set_input_as_handled()
		return

	# The Pause Menu belongs to gameplay only. Do not let the global Autoload
	# open on the Main Menu / Character Select after returning from a Garden.
	if not _has_gameplay_world():
		return

	# Other systems deliberately pause the tree while their own UI is open.
	# Do not steal Escape from Build Mode, storage, repair dialogs, etc.
	if get_tree().paused:
		return

	if BuildSystem.is_active():
		return

	open_menu()
	get_viewport().set_input_as_handled()


# Opens the menu.
func open_menu() -> void:
	if _is_open:
		return

	_is_open = true
	_previous_mouse_mode = Input.get_mouse_mode()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_backdrop.visible = true
	_panel.visible = true
	_status_label.text = ""
	_refresh_buttons()

	if debug_log:
		print(
			"[PauseMenu] OPEN save_exists=",
			SaveSystem.has_save()
		)


# Closes the menu.
func close_menu() -> void:
	if not _is_open:
		return

	if _main_menu_dialog != null and _main_menu_dialog.visible:
		_main_menu_dialog.hide()

	if _quit_dialog != null and _quit_dialog.visible:
		_quit_dialog.hide()

	_is_open = false
	_backdrop.visible = false
	_panel.visible = false
	get_tree().paused = false
	Input.set_mouse_mode(_previous_mouse_mode)

	if debug_log:
		print("[PauseMenu] CLOSED")


# Checks whether this interface is currently open.
func is_open() -> bool:
	return _is_open


# Handles the resume pressed signal or callback.
func _on_resume_pressed() -> void:
	close_menu()


# Handles the save pressed signal or callback.
func _on_save_pressed() -> void:
	_status_label.text = "Saving..."
	_save_button.disabled = true

	var success: bool = SaveSystem.save_game()

	if success:
		_status_label.text = "GAME SAVED"
	else:
		_status_label.text = "SAVE FAILED"

	_refresh_buttons()


# Handles the load pressed signal or callback.
func _on_load_pressed() -> void:
	if not SaveSystem.has_save():
		_status_label.text = "NO SAVE FILE"
		_refresh_buttons()
		return

	_status_label.text = "Loading..."
	_save_button.disabled = true
	_load_button.disabled = true

	var success: bool = SaveSystem.load_game()

	if success:
		_status_label.text = "GAME LOADED"
	else:
		_status_label.text = "LOAD FAILED"

	# SaveSystem restores the tree to its previous paused state. Since load was
	# launched from this menu, the expected state is still paused.
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh_buttons()


# Handles the main menu pressed signal or callback.
func _on_main_menu_pressed() -> void:
	_main_menu_dialog.dialog_text = (
		"Return to the Main Menu?\n\n"
		+ "Unsaved progress will be lost."
	)
	_main_menu_dialog.popup_centered(
		Vector2i(390, 180)
	)


# Handles the main menu confirmed signal or callback.
func _on_main_menu_confirmed() -> void:
	_status_label.text = "Returning to Main Menu..."

	# Hide the pause UI before the gameplay scene is replaced.
	_is_open = false
	_backdrop.visible = false
	_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var success: bool = GameFlowSystem.return_to_main_menu()

	if success:
		return

	# If the scene transition fails, restore a usable paused gameplay state.
	_is_open = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_backdrop.visible = true
	_panel.visible = true
	_status_label.text = "MAIN MENU FAILED"


# Handles the quit pressed signal or callback.
func _on_quit_pressed() -> void:
	_quit_dialog.dialog_text = (
		"Quit the game?\n\n"
		+ "Unsaved progress will be lost."
	)
	_quit_dialog.popup_centered(
		Vector2i(360, 170)
	)


# Handles the quit confirmed signal or callback.
func _on_quit_confirmed() -> void:
	get_tree().quit()


# Handles the save completed signal or callback.
func _on_save_completed(_path: String) -> void:
	if not _is_open:
		return

	_status_label.text = "GAME SAVED"
	_refresh_buttons()


# Handles the load completed signal or callback.
func _on_load_completed(_path: String) -> void:
	if not _is_open:
		return

	_status_label.text = "GAME LOADED"
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh_buttons()


# Handles the save failed signal or callback.
func _on_save_failed(reason: String) -> void:
	if not _is_open:
		return

	_status_label.text = "SAVE FAILED: %s" % reason
	_refresh_buttons()


# Handles the load failed signal or callback.
func _on_load_failed(reason: String) -> void:
	if not _is_open:
		return

	_status_label.text = "LOAD FAILED: %s" % reason
	_refresh_buttons()


# Refreshes the buttons.
func _refresh_buttons() -> void:
	if _save_button == null or _load_button == null:
		return

	_save_button.disabled = false
	_load_button.disabled = not SaveSystem.has_save()

	if _load_button.disabled:
		_load_button.tooltip_text = "No save file exists yet."
	else:
		_load_button.tooltip_text = "Load the current save slot."


# Connects the save signals signals and callbacks.
func _connect_save_signals() -> void:
	if not SaveSystem.save_completed.is_connected(
		_on_save_completed
	):
		SaveSystem.save_completed.connect(
			_on_save_completed
		)

	if not SaveSystem.load_completed.is_connected(
		_on_load_completed
	):
		SaveSystem.load_completed.connect(
			_on_load_completed
		)

	if not SaveSystem.save_failed.is_connected(
		_on_save_failed
	):
		SaveSystem.save_failed.connect(
			_on_save_failed
		)

	if not SaveSystem.load_failed.is_connected(
		_on_load_failed
	):
		SaveSystem.load_failed.connect(
			_on_load_failed
		)


# Checks whether the Escape key was pressed.
func _is_escape_pressed(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		return true

	if event is InputEventKey:
		var key_event := event as InputEventKey
		return (
			key_event.pressed
			and not key_event.echo
			and key_event.keycode == KEY_ESCAPE
		)

	return false


# Creates the UI.
func _create_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "PauseMenuUI"
	_ui_layer.layer = 90
	add_child(_ui_layer)

	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_backdrop.color = Color(
		0.0,
		0.0,
		0.0,
		0.68
	)
	_backdrop.mouse_filter = (
		Control.MOUSE_FILTER_STOP
	)
	_backdrop.visible = false
	_ui_layer.add_child(_backdrop)

	_panel = Panel.new()
	_panel.name = "PausePanel"
	_panel.set_anchors_preset(
		Control.PRESET_CENTER
	)
	_panel.position = Vector2(
		-190.0,
		-250.0
	)
	_panel.size = Vector2(
		380.0,
		500.0
	)
	_panel.mouse_filter = (
		Control.MOUSE_FILTER_STOP
	)
	_panel.add_theme_stylebox_override(
		"panel",
		_create_panel_style()
	)
	_panel.visible = false
	_ui_layer.add_child(_panel)

	var title := Label.new()
	title.position = Vector2(
		24.0,
		24.0
	)
	title.size = Vector2(
		332.0,
		36.0
	)
	title.text = "PAUSED"
	title.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	title.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	title.add_theme_font_size_override(
		"font_size",
		24
	)
	title.add_theme_color_override(
		"font_color",
		Color(0.90, 0.94, 0.88, 1.0)
	)
	_panel.add_child(title)

	var subtitle := Label.new()
	subtitle.position = Vector2(
		24.0,
		62.0
	)
	subtitle.size = Vector2(
		332.0,
		22.0
	)
	subtitle.text = "BlueBerry Farm"
	subtitle.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	subtitle.add_theme_font_size_override(
		"font_size",
		11
	)
	subtitle.add_theme_color_override(
		"font_color",
		Color(0.58, 0.64, 0.57, 1.0)
	)
	_panel.add_child(subtitle)

	var button_column := VBoxContainer.new()
	button_column.position = Vector2(
		52.0,
		112.0
	)
	button_column.size = Vector2(
		276.0,
		272.0
	)
	button_column.add_theme_constant_override(
		"separation",
		10
	)
	_panel.add_child(button_column)

	var resume_button := _create_menu_button(
		"RESUME"
	)
	resume_button.pressed.connect(
		_on_resume_pressed
	)
	button_column.add_child(resume_button)

	_save_button = _create_menu_button(
		"SAVE GAME"
	)
	_save_button.pressed.connect(
		_on_save_pressed
	)
	button_column.add_child(_save_button)

	_load_button = _create_menu_button(
		"LOAD GAME"
	)
	_load_button.pressed.connect(
		_on_load_pressed
	)
	button_column.add_child(_load_button)

	var main_menu_button := _create_menu_button(
		"MAIN MENU"
	)
	main_menu_button.pressed.connect(
		_on_main_menu_pressed
	)
	button_column.add_child(main_menu_button)

	var quit_button := _create_menu_button(
		"QUIT GAME"
	)
	quit_button.pressed.connect(
		_on_quit_pressed
	)
	button_column.add_child(quit_button)

	_status_label = Label.new()
	_status_label.position = Vector2(
		32.0,
		416.0
	)
	_status_label.size = Vector2(
		316.0,
		28.0
	)
	_status_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_status_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	_status_label.add_theme_font_size_override(
		"font_size",
		11
	)
	_status_label.add_theme_color_override(
		"font_color",
		Color(0.72, 0.78, 0.70, 1.0)
	)
	_panel.add_child(_status_label)

	var hint := Label.new()
	hint.position = Vector2(
		32.0,
		456.0
	)
	hint.size = Vector2(
		316.0,
		20.0
	)
	hint.text = "ESC  Resume"
	hint.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	hint.add_theme_font_size_override(
		"font_size",
		10
	)
	hint.add_theme_color_override(
		"font_color",
		Color(0.46, 0.51, 0.46, 1.0)
	)
	_panel.add_child(hint)

	_main_menu_dialog = ConfirmationDialog.new()
	_main_menu_dialog.name = "MainMenuConfirmation"
	_main_menu_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_main_menu_dialog.unresizable = true
	_main_menu_dialog.exclusive = true
	_main_menu_dialog.always_on_top = true
	_main_menu_dialog.title = "Return to Main Menu"
	_main_menu_dialog.get_ok_button().text = "Main Menu"
	_main_menu_dialog.get_cancel_button().text = "Cancel"
	_main_menu_dialog.confirmed.connect(
		_on_main_menu_confirmed
	)
	add_child(_main_menu_dialog)

	_quit_dialog = ConfirmationDialog.new()
	_quit_dialog.name = "QuitConfirmation"
	_quit_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_quit_dialog.unresizable = true
	_quit_dialog.exclusive = true
	_quit_dialog.always_on_top = true
	_quit_dialog.title = "Quit Game"
	_quit_dialog.get_ok_button().text = "Quit"
	_quit_dialog.get_cancel_button().text = "Cancel"
	_quit_dialog.confirmed.connect(
		_on_quit_confirmed
	)
	add_child(_quit_dialog)


# Checks whether gameplay world exists or is available.
func _has_gameplay_world() -> bool:
	var tilemap_variant: Variant = SaveSystem.get(
		"_tilemap"
	)
	var player_variant: Variant = SaveSystem.get(
		"_player"
	)

	# Scene replacement can leave SaveSystem with stale freed Object
	# references for a frame. Validate Objects before any `is Type` checks.
	return (
		is_instance_valid(tilemap_variant)
		and tilemap_variant is TileMap
		and is_instance_valid(player_variant)
		and player_variant is CharacterBody2D
	)


# Creates the menu button.
func _create_menu_button(text_value: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(
		276.0,
		46.0
	)
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = (
		Control.CURSOR_POINTING_HAND
	)
	button.add_theme_font_size_override(
		"font_size",
		14
	)
	button.add_theme_stylebox_override(
		"normal",
		_create_button_style(false)
	)
	button.add_theme_stylebox_override(
		"hover",
		_create_button_style(true)
	)
	button.add_theme_stylebox_override(
		"pressed",
		_create_button_style(true)
	)
	button.add_theme_stylebox_override(
		"disabled",
		_create_button_style(false, true)
	)
	return button


# Creates the panel style.
func _create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(
		0.035,
		0.050,
		0.055,
		0.985
	)
	style.border_color = Color(
		0.18,
		0.22,
		0.17,
		1.0
	)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	return style


# Creates the button style.
func _create_button_style(
	hovered: bool,
	disabled: bool = false
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	if disabled:
		style.bg_color = Color(
			0.06,
			0.065,
			0.06,
			0.80
		)
		style.border_color = Color(
			0.13,
			0.14,
			0.13,
			0.75
		)
	elif hovered:
		style.bg_color = Color(
			0.16,
			0.18,
			0.15,
			0.98
		)
		style.border_color = Color(
			0.58,
			0.66,
			0.52,
			1.0
		)
	else:
		style.bg_color = Color(
			0.09,
			0.105,
			0.09,
			0.95
		)
		style.border_color = Color(
			0.28,
			0.32,
			0.27,
			1.0
		)

	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style
