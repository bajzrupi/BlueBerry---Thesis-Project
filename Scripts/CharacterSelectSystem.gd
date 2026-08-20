extends Node

# Character selection overlay used by the real New Game flow.

signal character_confirmed(character_id: StringName)

@export_category("Character Select")
@export var ui_layer: int = 95

@export_category("Debug Logging")
@export var debug_log: bool = false


const CHARACTER_MALE: StringName = &"male"
const CHARACTER_FEMALE: StringName = &"female"

const PORTRAIT_REGION: Rect2 = Rect2(80.0, 140.0, 32.0, 32.0)

const PORTRAIT_PATHS: Dictionary = {
	CHARACTER_MALE:
		"res://Assets/Sprites/Characters/Male/idle.png",
	CHARACTER_FEMALE:
		"res://Assets/Sprites/Characters/Female/idle.png"
}


var _is_open: bool = false
var _selection_required: bool = false

var _selected_character_id: StringName = CHARACTER_MALE

var _previous_paused: bool = false
var _previous_mouse_mode: int = Input.MOUSE_MODE_HIDDEN

var _ui: CanvasLayer
var _backdrop: ColorRect
var _panel: Panel

var _male_card: PanelContainer
var _female_card: PanelContainer

var _male_button: Button
var _female_button: Button
var _confirm_button: Button
var _status_label: Label


# Initializes this system when the node becomes ready.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_create_ui()

	if debug_log:
		print("[CharacterSelect] ready")


# Handles direct player input.
func _input(event: InputEvent) -> void:
	if not _is_open:
		return

	if _is_escape_pressed(event):
		if not _selection_required:
			close_selector()

		get_viewport().set_input_as_handled()


# Opens the character selection overlay.
#
# required_selection=false:
#   Escape may close the selector without changing the current character.
#
# required_selection=true:
#   Used later for a real first-start flow. Escape cannot close the selector.
func open_selector(required_selection: bool = false) -> void:
	if _is_open:
		return

	_is_open = true
	_selection_required = required_selection

	_previous_paused = get_tree().paused
	_previous_mouse_mode = Input.get_mouse_mode()

	_selected_character_id = (
		CharacterSystem.get_current_character_id()
	)

	_refresh_selection_visuals()

	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_backdrop.visible = true
	_panel.visible = true

	if debug_log:
		print(
			"[CharacterSelect] OPEN current=",
			_selected_character_id,
			" required=",
			_selection_required
		)


# Closes the selector without changing the selected character.
# In the final first-start flow this is not available while selection is required.
func close_selector() -> void:
	if not _is_open:
		return

	_is_open = false
	_selection_required = false

	_backdrop.visible = false
	_panel.visible = false

	get_tree().paused = _previous_paused
	Input.set_mouse_mode(_previous_mouse_mode)


	if debug_log:
		print("[CharacterSelect] CLOSED without change")


# Checks whether this interface is currently open.
func is_open() -> bool:
	return _is_open


# Returns the selected character ID.
func get_selected_character_id() -> StringName:
	return _selected_character_id


# Handles the male pressed signal or callback.
func _on_male_pressed() -> void:
	_select_character(CHARACTER_MALE)


# Handles the female pressed signal or callback.
func _on_female_pressed() -> void:
	_select_character(CHARACTER_FEMALE)


# Selects the character.
func _select_character(character_id: StringName) -> void:
	if not CharacterSystem.is_valid_character(character_id):
		push_warning(
			"[CharacterSelect] invalid selection=%s"
			% String(character_id)
		)
		return

	_selected_character_id = character_id
	_refresh_selection_visuals()

	if debug_log:
		print(
			"[CharacterSelect] selected=",
			_selected_character_id
		)


# Handles the confirm pressed signal or callback.
func _on_confirm_pressed() -> void:
	if not CharacterSystem.is_valid_character(
		_selected_character_id
	):
		return

	var applied: bool = CharacterSystem.set_character(
		_selected_character_id
	)

	if not applied:
		push_warning(
			"[CharacterSelect] failed to apply character=%s"
			% String(_selected_character_id)
		)
		return

	var confirmed_id := _selected_character_id

	_is_open = false
	_selection_required = false

	_backdrop.visible = false
	_panel.visible = false

	get_tree().paused = _previous_paused
	Input.set_mouse_mode(_previous_mouse_mode)

	character_confirmed.emit(confirmed_id)

	if debug_log:
		print(
			"[CharacterSelect] CONFIRMED character=",
			confirmed_id
		)


# Refreshes the selection visuals.
func _refresh_selection_visuals() -> void:
	if (
		_male_card == null
		or _female_card == null
		or _status_label == null
	):
		return

	var male_selected: bool = (
		_selected_character_id == CHARACTER_MALE
	)
	var female_selected: bool = (
		_selected_character_id == CHARACTER_FEMALE
	)

	_male_card.add_theme_stylebox_override(
		"panel",
		_create_character_card_style(male_selected)
	)
	_female_card.add_theme_stylebox_override(
		"panel",
		_create_character_card_style(female_selected)
	)

	_male_button.text = (
		"SELECTED" if male_selected else "CHOOSE MALE"
	)
	_female_button.text = (
		"SELECTED" if female_selected else "CHOOSE FEMALE"
	)

	_male_button.disabled = male_selected
	_female_button.disabled = female_selected

	_status_label.text = (
		"Selected: %s"
		% String(_selected_character_id).to_upper()
	)


# Creates the UI.
func _create_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "CharacterSelectUI"
	_ui.layer = ui_layer
	add_child(_ui)

	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT
	)
	_backdrop.color = Color(
		0.0,
		0.0,
		0.0,
		0.78
	)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.visible = false
	_ui.add_child(_backdrop)

	_panel = Panel.new()
	_panel.name = "CharacterSelectPanel"
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-330.0, -215.0)
	_panel.size = Vector2(660.0, 430.0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override(
		"panel",
		_create_main_panel_style()
	)
	_panel.visible = false
	_ui.add_child(_panel)

	var title := Label.new()
	title.name = "Title"
	title.position = Vector2(28.0, 22.0)
	title.size = Vector2(604.0, 38.0)
	title.text = "CHOOSE YOUR CHARACTER"
	title.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	title.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	title.add_theme_font_size_override(
		"font_size",
		25
	)
	title.add_theme_color_override(
		"font_color",
		Color(0.90, 0.96, 0.88, 1.0)
	)
	title.add_theme_color_override(
		"font_outline_color",
		Color(0.02, 0.03, 0.025, 1.0)
	)
	title.add_theme_constant_override(
		"outline_size",
		3
	)
	_panel.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.position = Vector2(40.0, 62.0)
	subtitle.size = Vector2(580.0, 28.0)
	subtitle.text = (
		"Choose the gardener you want to play."
	)
	subtitle.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	subtitle.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	subtitle.add_theme_font_size_override(
		"font_size",
		13
	)
	subtitle.add_theme_color_override(
		"font_color",
		Color(0.72, 0.80, 0.76, 1.0)
	)
	_panel.add_child(subtitle)

	_male_card = _create_character_card(
		CHARACTER_MALE,
		"MALE",
		Vector2(70.0, 108.0)
	)
	_panel.add_child(_male_card)

	_female_card = _create_character_card(
		CHARACTER_FEMALE,
		"FEMALE",
		Vector2(350.0, 108.0)
	)
	_panel.add_child(_female_card)

	_male_button = _male_card.get_node(
		"Margin/Content/ChooseButton"
	) as Button
	_female_button = _female_card.get_node(
		"Margin/Content/ChooseButton"
	) as Button

	_male_button.pressed.connect(_on_male_pressed)
	_female_button.pressed.connect(_on_female_pressed)

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.position = Vector2(80.0, 340.0)
	_status_label.size = Vector2(500.0, 24.0)
	_status_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_status_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	_status_label.add_theme_font_size_override(
		"font_size",
		13
	)
	_status_label.add_theme_color_override(
		"font_color",
		Color(0.76, 0.90, 0.68, 1.0)
	)
	_panel.add_child(_status_label)

	_confirm_button = Button.new()
	_confirm_button.name = "ConfirmButton"
	_confirm_button.position = Vector2(220.0, 374.0)
	_confirm_button.size = Vector2(220.0, 38.0)
	_confirm_button.text = "SELECT CHARACTER"
	_confirm_button.focus_mode = Control.FOCUS_ALL
	_confirm_button.add_theme_font_size_override(
		"font_size",
		14
	)
	_confirm_button.pressed.connect(
		_on_confirm_pressed
	)
	_panel.add_child(_confirm_button)

	_refresh_selection_visuals()


# Creates the character card.
func _create_character_card(
	character_id: StringName,
	display_name: String,
	card_position: Vector2
) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "%sCard" % display_name.capitalize()
	card.position = card_position
	card.size = Vector2(240.0, 220.0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override(
		"panel",
		_create_character_card_style(false)
	)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override(
		"margin_left",
		14
	)
	margin.add_theme_constant_override(
		"margin_top",
		14
	)
	margin.add_theme_constant_override(
		"margin_right",
		14
	)
	margin.add_theme_constant_override(
		"margin_bottom",
		14
	)
	card.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "Content"
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override(
		"separation",
		10
	)
	margin.add_child(content)

	var portrait_center := CenterContainer.new()
	portrait_center.custom_minimum_size = Vector2(
		200.0,
		112.0
	)
	content.add_child(portrait_center)

	var portrait := TextureRect.new()
	portrait.name = "Portrait"
	portrait.custom_minimum_size = Vector2(
		96.0,
		96.0
	)
	portrait.expand_mode = (
		TextureRect.EXPAND_IGNORE_SIZE
	)
	portrait.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	portrait.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
	)
	portrait.mouse_filter = (
		Control.MOUSE_FILTER_IGNORE
	)
	portrait.texture = _create_portrait_texture(
		character_id
	)
	portrait_center.add_child(portrait)

	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = display_name
	name_label.custom_minimum_size = Vector2(
		200.0,
		28.0
	)
	name_label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	name_label.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	name_label.add_theme_font_size_override(
		"font_size",
		17
	)
	name_label.add_theme_color_override(
		"font_color",
		Color(0.90, 0.94, 0.88, 1.0)
	)
	content.add_child(name_label)

	var choose_button := Button.new()
	choose_button.name = "ChooseButton"
	choose_button.custom_minimum_size = Vector2(
		200.0,
		34.0
	)
	choose_button.text = "CHOOSE"
	choose_button.add_theme_font_size_override(
		"font_size",
		12
	)
	content.add_child(choose_button)

	return card


# Creates the portrait texture.
func _create_portrait_texture(
	character_id: StringName
) -> Texture2D:
	if not PORTRAIT_PATHS.has(character_id):
		return null

	var path: String = String(
		PORTRAIT_PATHS[character_id]
	)

	var source := load(path) as Texture2D

	if source == null:
		push_warning(
			"[CharacterSelect] missing portrait character=%s path=%s"
			% [String(character_id), path]
		)
		return null

	var atlas := AtlasTexture.new()
	atlas.atlas = source
	atlas.region = PORTRAIT_REGION

	return atlas


# Creates the main panel style.
func _create_main_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	style.bg_color = Color(
		0.035,
		0.052,
		0.046,
		0.98
	)
	style.border_color = Color(
		0.34,
		0.58,
		0.56,
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


# Creates the character card style.
func _create_character_card_style(
	selected: bool
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()

	style.bg_color = Color(
		0.065,
		0.085,
		0.074,
		0.98
	)

	if selected:
		style.border_color = Color(
			0.66,
			0.92,
			0.44,
			1.0
		)
		style.border_width_left = 3
		style.border_width_top = 3
		style.border_width_right = 3
		style.border_width_bottom = 3
	else:
		style.border_color = Color(
			0.24,
			0.34,
			0.31,
			1.0
		)
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1

	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8

	return style


# Checks whether the Escape key was pressed.
func _is_escape_pressed(
	event: InputEvent
) -> bool:
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
