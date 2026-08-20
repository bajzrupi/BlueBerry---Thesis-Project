extends Node

# Stores the currently selected player appearance and builds
# matching SpriteFrames resources for the Player.

signal character_changed(character_id: StringName)

const CHARACTER_MALE: StringName = &"male"
const CHARACTER_FEMALE: StringName = &"female"

const DEFAULT_CHARACTER: StringName = CHARACTER_MALE

const FRAME_WIDTH: int = 64
const WALK_FRAME_COUNT: int = 9
const WALK_FPS: float = 10.0

@export_category("Debug Logging")
@export var debug_log: bool = false

const DIRECTIONS: Array[StringName] = [
	&"Down",
	&"Left",
	&"Right",
	&"Up"
]

const SHEET_PATHS: Dictionary = {
	CHARACTER_MALE: {
		&"Down": "res://Assets/Sprites/Characters/Male/walk_down_fixed.png",
		&"Left": "res://Assets/Sprites/Characters/Male/walk_left_fixed.png",
		&"Right": "res://Assets/Sprites/Characters/Male/walk_right_fixed.png",
		&"Up": "res://Assets/Sprites/Characters/Male/walk_up_fixed.png"
	},
	CHARACTER_FEMALE: {
		&"Down": "res://Assets/Sprites/Characters/Female/walk_down_fixed.png",
		&"Left": "res://Assets/Sprites/Characters/Female/walk_left_fixed.png",
		&"Right": "res://Assets/Sprites/Characters/Female/walk_right_fixed.png",
		&"Up": "res://Assets/Sprites/Characters/Female/walk_up_fixed.png"
	}
}

var current_character_id: StringName = DEFAULT_CHARACTER

var _frames_cache: Dictionary = {}


# Initializes this system when the node becomes ready.
func _ready() -> void:
	for character_id in get_available_character_ids():
		var frames := _build_sprite_frames(character_id)

		if frames != null:
			_frames_cache[character_id] = frames

	if debug_log:
		print(
			"[CharacterSystem] ready current=",
			current_character_id,
			" characters=",
			get_available_character_ids()
		)


# Returns the available character IDs.
func get_available_character_ids() -> Array[StringName]:
	return [
		CHARACTER_MALE,
		CHARACTER_FEMALE
	]


# Checks whether the character is valid.
func is_valid_character(character_id: StringName) -> bool:
	return SHEET_PATHS.has(character_id)


# Returns the current character ID.
func get_current_character_id() -> StringName:
	return current_character_id


# Sets the character.
func set_character(character_id: StringName) -> bool:
	if not is_valid_character(character_id):
		push_warning(
			"[CharacterSystem] Invalid character id: %s"
			% String(character_id)
		)
		return false

	if current_character_id == character_id:
		return true

	current_character_id = character_id

	character_changed.emit(current_character_id)

	if debug_log:
		print(
			"[CharacterSystem] character changed=",
			current_character_id
		)

	return true


# Returns the sprite frames.
func get_sprite_frames(
	character_id: StringName = current_character_id
) -> SpriteFrames:
	if not is_valid_character(character_id):
		push_warning(
			"[CharacterSystem] Cannot get frames for invalid character: %s"
			% String(character_id)
		)
		return null

	if _frames_cache.has(character_id):
		return _frames_cache[character_id] as SpriteFrames

	var frames := _build_sprite_frames(character_id)

	if frames != null:
		_frames_cache[character_id] = frames

	return frames


# Builds the sprite frames.
func _build_sprite_frames(
	character_id: StringName
) -> SpriteFrames:
	if not is_valid_character(character_id):
		return null

	var frames := SpriteFrames.new()

	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")

	for direction in DIRECTIONS:
		var texture := _load_direction_texture(
			character_id,
			direction
		)

		if texture == null:
			push_error(
				"[CharacterSystem] Missing texture character=%s direction=%s"
				% [
					String(character_id),
					String(direction)
				]
			)
			return null

		_add_idle_animation(
			frames,
			direction,
			texture
		)

		_add_walk_animation(
			frames,
			direction,
			texture
		)

	return frames


# Loads the direction texture.
func _load_direction_texture(
	character_id: StringName,
	direction: StringName
) -> Texture2D:
	var character_paths: Dictionary = SHEET_PATHS.get(
		character_id,
		{}
	)

	if not character_paths.has(direction):
		return null

	var path: String = String(
		character_paths[direction]
	)

	var resource := load(path)

	if resource == null:
		return null

	return resource as Texture2D


# Adds the idle animation.
func _add_idle_animation(
	frames: SpriteFrames,
	direction: StringName,
	texture: Texture2D
) -> void:
	var animation_name := StringName(
		"Idle_%s" % String(direction)
	)

	frames.add_animation(animation_name)
	frames.set_animation_loop_mode(
		animation_name,
		SpriteFrames.LOOP_LINEAR
	)
	frames.set_animation_speed(
		animation_name,
		WALK_FPS
	)

	var atlas := _create_atlas_frame(
		texture,
		0
	)

	frames.add_frame(
		animation_name,
		atlas
	)


# Adds the walk animation.
func _add_walk_animation(
	frames: SpriteFrames,
	direction: StringName,
	texture: Texture2D
) -> void:
	var animation_name := StringName(
		"Walk_%s" % String(direction)
	)

	frames.add_animation(animation_name)
	frames.set_animation_loop_mode(
		animation_name,
		SpriteFrames.LOOP_LINEAR
	)
	frames.set_animation_speed(
		animation_name,
		WALK_FPS
	)

	for frame_index in range(WALK_FRAME_COUNT):
		var atlas := _create_atlas_frame(
			texture,
			frame_index
		)

		frames.add_frame(
			animation_name,
			atlas
		)


# Creates the atlas frame.
func _create_atlas_frame(
	texture: Texture2D,
	frame_index: int
) -> AtlasTexture:
	var atlas := AtlasTexture.new()

	atlas.atlas = texture

	atlas.region = Rect2(
		frame_index * FRAME_WIDTH,
		0,
		FRAME_WIDTH,
		texture.get_height()
	)

	return atlas
