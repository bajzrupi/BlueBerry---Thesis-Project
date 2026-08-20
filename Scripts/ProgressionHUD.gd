extends CanvasLayer

# Compact upper-right player portrait and level display.
@export_category("Player HUD")

# Controls the CanvasLayer drawing order.
@export var hud_layer: int = 6

# Distance from the upper-right screen corner.
@export var screen_margin: Vector2 = Vector2(16.0, 16.0)

# Controls the minimum panel size.
@export var panel_size: Vector2 = Vector2(220.0, 76.0)

# Optional fallback character portrait texture.
# CharacterSystem-controlled portraits override this when available.
@export var portrait_texture: Texture2D

# Portrait sheet paths for each selectable character.
const CHARACTER_PORTRAIT_PATHS: Dictionary = {
	&"male": "res://Assets/Sprites/Characters/Male/idle.png",
	&"female": "res://Assets/Sprites/Characters/Female/idle.png"
}

# Optional source region used when the portrait is part of a sprite sheet.
@export var portrait_region: Rect2 = Rect2()

# Controls the visible portrait size.
@export var portrait_size: Vector2 = Vector2(48.0, 48.0)

# Controls whether the portrait uses nearest-neighbor filtering.
@export var pixel_art_filtering: bool = true


# Controls the visible XP progress bar height.
@export var xp_bar_height: float = 10.0


@export_category("Debug Logging")

# Enables player HUD initialization and progression logs.
@export var debug_log: bool = false


# Stores the portrait display.
var _portrait_rect: TextureRect

# Stores the fallback portrait symbol.
var _portrait_fallback: Label

# Displays the current player level.
var _player_level_label: Label

# Displays progress toward the next player level.
var _xp_bar: ProgressBar

# Displays the current and required XP values.
var _xp_label: Label


# Builds the HUD and connects progression signals.
func _ready() -> void:
	layer = hud_layer

	_build_ui()
	_connect_progression_signals()
	_connect_character_signals()
	_refresh_portrait()
	_refresh_player_progress()

	if debug_log:
		print(
			"[ProgressionHUD] ready portrait=",
			portrait_texture != null,
			" layer=",
			layer,
			" margin=",
			screen_margin
		)


# Creates the complete upper-right player HUD.
func _build_ui() -> void:
	var panel := PanelContainer.new()
	panel.name = "PlayerHudPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -(panel_size.x + screen_margin.x)
	panel.offset_top = screen_margin.y
	panel.offset_right = -screen_margin.x
	panel.offset_bottom = screen_margin.y + panel_size.y
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override(
		"panel",
		_create_panel_style()
	)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.name = "Content"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	row.add_child(_create_portrait_frame())

	var progression_column := VBoxContainer.new()
	progression_column.name = "Progression"
	progression_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progression_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	progression_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progression_column.add_theme_constant_override("separation", 2)
	row.add_child(progression_column)

	_player_level_label = Label.new()
	_player_level_label.name = "PlayerLevel"
	_player_level_label.text = "PLAYER LV 0"
	_player_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_player_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_level_label.add_theme_font_size_override("font_size", 15)
	_player_level_label.add_theme_color_override(
		"font_color",
		Color(0.74, 0.90, 1.0, 1.0)
	)
	_player_level_label.add_theme_color_override(
		"font_outline_color",
		Color(0.02, 0.03, 0.03, 1.0)
	)
	_player_level_label.add_theme_constant_override(
		"outline_size",
		3
	)
	progression_column.add_child(_player_level_label)

	_xp_bar = ProgressBar.new()
	_xp_bar.name = "PlayerXP"
	_xp_bar.custom_minimum_size = Vector2(0.0, xp_bar_height)
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_bar.min_value = 0.0
	_xp_bar.max_value = 100.0
	_xp_bar.value = 0.0
	_xp_bar.show_percentage = false
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_bar.add_theme_stylebox_override(
		"background",
		_create_xp_background_style()
	)
	_xp_bar.add_theme_stylebox_override(
		"fill",
		_create_xp_fill_style()
	)
	progression_column.add_child(_xp_bar)

	_xp_label = Label.new()
	_xp_label.name = "PlayerXPText"
	_xp_label.text = "0 / 100 XP"
	_xp_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_label.add_theme_font_size_override("font_size", 10)
	_xp_label.add_theme_color_override(
		"font_color",
		Color(0.78, 0.84, 0.82, 1.0)
	)
	progression_column.add_child(_xp_label)


# Creates the bordered portrait container.
func _create_portrait_frame() -> Control:
	var portrait_frame := PanelContainer.new()
	portrait_frame.name = "PortraitFrame"
	portrait_frame.custom_minimum_size = (
		portrait_size + Vector2(8.0, 8.0)
	)
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_theme_stylebox_override(
		"panel",
		_create_portrait_style()
	)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_child(center)

	_portrait_rect = TextureRect.new()
	_portrait_rect.name = "Portrait"
	_portrait_rect.custom_minimum_size = portrait_size
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = (
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	)
	_portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_portrait_rect)

	_portrait_fallback = Label.new()
	_portrait_fallback.name = "PortraitFallback"
	_portrait_fallback.text = "P"
	_portrait_fallback.custom_minimum_size = portrait_size
	_portrait_fallback.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_portrait_fallback.vertical_alignment = (
		VERTICAL_ALIGNMENT_CENTER
	)
	_portrait_fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_fallback.add_theme_font_size_override(
		"font_size",
		24
	)
	_portrait_fallback.add_theme_color_override(
		"font_color",
		Color(0.82, 1.0, 0.68, 1.0)
	)
	_portrait_fallback.add_theme_color_override(
		"font_outline_color",
		Color(0.02, 0.03, 0.02, 1.0)
	)
	_portrait_fallback.add_theme_constant_override(
		"outline_size",
		3
	)
	center.add_child(_portrait_fallback)

	return portrait_frame


# Connects the HUD to global player progression.
func _connect_progression_signals() -> void:
	if not ProgressionSystem.player_progress_changed.is_connected(
		_on_player_progress_changed
	):
		ProgressionSystem.player_progress_changed.connect(
			_on_player_progress_changed
		)

	if not ProgressionSystem.progression_reset.is_connected(
		_on_progression_reset
	):
		ProgressionSystem.progression_reset.connect(
			_on_progression_reset
		)


# Connects the HUD to character appearance changes.
func _connect_character_signals() -> void:
	if not CharacterSystem.character_changed.is_connected(
		_on_character_changed
	):
		CharacterSystem.character_changed.connect(
			_on_character_changed
		)


# Returns the portrait sheet for the currently selected character.
func _get_character_portrait_texture() -> Texture2D:
	var character_id: StringName = (
		CharacterSystem.get_current_character_id()
	)

	if not CHARACTER_PORTRAIT_PATHS.has(character_id):
		return portrait_texture

	var path: String = String(
		CHARACTER_PORTRAIT_PATHS[character_id]
	)
	var resource := load(path)

	if resource == null:
		push_warning(
			"[ProgressionHUD] Missing portrait texture character=%s path=%s"
			% [String(character_id), path]
		)
		return portrait_texture

	return resource as Texture2D


# Refreshes the portrait for the currently selected character.
func _refresh_portrait() -> void:
	var source_texture: Texture2D = _get_character_portrait_texture()

	if source_texture == null:
		_portrait_rect.texture = null
		_portrait_rect.visible = false
		_portrait_fallback.visible = true
		return

	var displayed_texture: Texture2D = source_texture

	if (
		portrait_region.size.x > 0.0
		and portrait_region.size.y > 0.0
	):
		var atlas_texture := AtlasTexture.new()
		atlas_texture.atlas = source_texture
		atlas_texture.region = portrait_region
		displayed_texture = atlas_texture

	_portrait_rect.texture = displayed_texture
	_portrait_rect.visible = true
	_portrait_fallback.visible = false

	if pixel_art_filtering:
		_portrait_rect.texture_filter = (
			CanvasItem.TEXTURE_FILTER_NEAREST
		)
	else:
		_portrait_rect.texture_filter = (
			CanvasItem.TEXTURE_FILTER_LINEAR
		)

	if debug_log:
		print(
			"[ProgressionHUD] portrait character=",
			CharacterSystem.get_current_character_id()
		)


# Refreshes the current player level and XP progress.
func _refresh_player_progress() -> void:
	var progress: Dictionary = ProgressionSystem.get_player_progress()
	var level: int = int(progress.get("level", 0))
	var xp: int = maxi(int(progress.get("xp", 0)), 0)
	var xp_to_next: int = maxi(
		int(progress.get("xp_to_next", 1)),
		1
	)

	_player_level_label.text = "PLAYER LV %d" % level

	_xp_bar.max_value = float(xp_to_next)
	_xp_bar.value = float(clampi(xp, 0, xp_to_next))
	_xp_label.text = "%d / %d XP" % [
		xp,
		xp_to_next
	]


# Creates the outer HUD panel style.
func _create_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.055, 0.05, 0.90)
	style.border_color = Color(0.34, 0.52, 0.62, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style


# Creates the XP bar background style.
func _create_xp_background_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.035, 0.035, 0.96)
	style.border_color = Color(0.20, 0.30, 0.31, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


# Creates the XP bar fill style.
func _create_xp_fill_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.36, 0.72, 0.92, 1.0)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


# Creates the portrait border style.
func _create_portrait_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.085, 0.98)
	style.border_color = Color(0.70, 0.88, 0.56, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	return style


# Handles global player progression changes.
func _on_player_progress_changed(
	_level: int,
	_xp: int,
	_xp_to_next: int
) -> void:
	_refresh_player_progress()

	if debug_log:
		print(
			"[ProgressionHUD] player level=",
			_level,
			" xp=",
			_xp,
			"/",
			_xp_to_next
		)


# Handles a complete progression reset.
func _on_progression_reset() -> void:
	_refresh_player_progress()

	if debug_log:
		print("[ProgressionHUD] progression reset")


# Handles a selected character appearance change.
func _on_character_changed(_character_id: StringName) -> void:
	_refresh_portrait()
