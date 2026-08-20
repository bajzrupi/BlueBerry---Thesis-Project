extends "res://Scripts/AutomationMachineBase.gd"

# Level 20 automated nutrient-management machine.
#
# Same machine contract as the Field Sprinkler:
# - Build Mode placement on grass or biome outer edge
# - Level 1-3 range/effect upgrades
# - 1h / 3h / 6h / 12h interval
# - ON/OFF
# - individual configuration and Save/Load state
# - connected biome zones are treated once per cycle
#
# Unique behavior:
# - player selects a nutrient trigger threshold
# - zones at/above the threshold are skipped
# - only nutrient state is affected

signal fertilizer_applied(
	cell: Vector2i,
	zones_fertilized: int,
	nutrients_amount: float
)


const BUILD_ID: StringName = &"fertilizer_injector"

const TRIGGER_OPTIONS: Array[float] = [
	0.35,
	0.45,
	0.55,
	0.65
]

const REASON_INVALID_TRIGGER: String = "INVALID_TRIGGER"


@export_category("Fertilizer Level 1")

@export_range(0.01, 1.0, 0.01)
var level_1_nutrients_per_cycle: float = 0.10


@export_category("Fertilizer Level 2")

@export_range(0.01, 1.0, 0.01)
var level_2_nutrients_per_cycle: float = 0.14


@export_category("Fertilizer Level 3")

@export_range(0.01, 1.0, 0.01)
var level_3_nutrients_per_cycle: float = 0.18


@export_category("Fertilizer Configuration")

@export_range(0.0, 1.0, 0.05)
var default_trigger_nutrients: float = 0.55


var _machine_texture: Texture2D


# Returns the machine build ID.
func get_machine_build_id() -> StringName:
	return BUILD_ID


# Returns the machine display name.
func get_machine_display_name() -> String:
	return "Fertilizer Injector"


# Returns the effect amount for level.
func get_effect_amount_for_level(
	level: int
) -> float:
	var base_amount: float = 0.0

	match clampi(level, 1, MAX_MACHINE_LEVEL):
		2:
			base_amount = level_2_nutrients_per_cycle
		3:
			base_amount = level_3_nutrients_per_cycle
		_:
			base_amount = level_1_nutrients_per_cycle

	return clampf(
		base_amount
		* RandomEventSystem.get_fertilizer_injector_strength_multiplier(),
		0.0,
		1.0
	)


# Returns the trigger options.
func get_trigger_options() -> Array[float]:
	return TRIGGER_OPTIONS.duplicate()


# Returns the trigger threshold.
func get_trigger_threshold(
	cell: Vector2i
) -> float:
	if not has_machine(cell):
		return -1.0

	_ensure_default_state(cell)

	return clampf(
		float(
			_machine_states[cell].get(
				"trigger_nutrients",
				default_trigger_nutrients
			)
		),
		0.0,
		1.0
	)


# Sets the trigger threshold.
func set_trigger_threshold(
	cell: Vector2i,
	trigger_nutrients: float
) -> Dictionary:
	if not has_machine(cell):
		return {
			"ok": false,
			"reason": REASON_INVALID_MACHINE
		}

	var valid: bool = false

	for option: float in TRIGGER_OPTIONS:
		if is_equal_approx(
			option,
			trigger_nutrients
		):
			valid = true
			break

	if not valid:
		return {
			"ok": false,
			"reason": REASON_INVALID_TRIGGER,
			"allowed": get_trigger_options()
		}

	_ensure_default_state(cell)

	var state: Dictionary = _machine_states[cell]
	var previous: float = float(
		state.get(
			"trigger_nutrients",
			default_trigger_nutrients
		)
	)

	state["trigger_nutrients"] = trigger_nutrients
	_machine_states[cell] = state

	var public_state: Dictionary = get_machine_state(cell)
	machine_configuration_changed.emit(
		cell,
		public_state
	)
	machine_state_changed.emit(
		cell,
		public_state
	)

	return {
		"ok": true,
		"cell": cell,
		"previous_trigger": previous,
		"trigger_nutrients": trigger_nutrients,
		"state": public_state
	}


# Creates the custom default state.
func _make_custom_default_state() -> Dictionary:
	return {
		"trigger_nutrients": _normalized_default_trigger()
	}


# Adds machine-specific fields to the public machine state.
func _enrich_public_state(
	_cell: Vector2i,
	state: Dictionary,
	output: Dictionary
) -> void:
	output["nutrients_per_cycle"] = float(
		output.get("effect_amount", 0.0)
	)
	output["trigger_nutrients"] = clampf(
		float(
			state.get(
				"trigger_nutrients",
				_normalized_default_trigger()
			)
		),
		0.0,
		1.0
	)


# Sanitizes machine-specific data loaded from a save.
func _sanitize_loaded_custom_state(
	entry: Dictionary,
	state: Dictionary
) -> void:
	var loaded: float = float(
		entry.get(
			"trigger_nutrients",
			_normalized_default_trigger()
		)
	)

	var best: float = _nearest_trigger_option(loaded)
	state["trigger_nutrients"] = best


# Appends the custom save fields.
func _append_custom_save_fields(
	_cell: Vector2i,
	state: Dictionary,
	entry: Dictionary
) -> void:
	entry["trigger_nutrients"] = clampf(
		float(
			state.get(
				"trigger_nutrients",
				_normalized_default_trigger()
			)
		),
		0.0,
		1.0
	)


# Applies the machine cycle.
func _apply_machine_cycle(
	machine_cell: Vector2i,
	radius_cells: int,
	effect_amount: float
) -> int:
	var zones: Dictionary = collect_covered_zones(
		machine_cell,
		radius_cells
	)
	var trigger: float = get_trigger_threshold(
		machine_cell
	)
	var fertilized: int = 0

	for zone_variant: Variant in zones.keys():
		var representative: Vector2i = zones[zone_variant]
		var nutrients: float = BiomeSystem.get_nutrients(
			representative
		)

		if (
			nutrients < 0.0
			or nutrients >= trigger
		):
			continue

		BiomeSystem.add_nutrients(
			representative,
			effect_amount
		)
		fertilized += 1

	fertilizer_applied.emit(
		machine_cell,
		fertilized,
		effect_amount
	)

	return fertilized


# Handles the cycle visual signal or callback.
func _on_cycle_visual(
	machine_cell: Vector2i,
	affected_zones: int
) -> void:
	if (
		affected_zones <= 0
		or not is_instance_valid(_tilemap)
	):
		return

	var center: Vector2 = _tilemap.to_global(
		_tilemap.map_to_local(machine_cell)
	)
	var cell_pixels := Vector2(
		_tilemap.tile_set.tile_size
	)
	var radius: int = get_machine_radius(machine_cell)
	var diameter: float = float(
		maxi(radius * 2 + 1, 1)
	)

	ToolParticles.spawn_fertilize(
		center,
		cell_pixels,
		Vector2(diameter, diameter)
	)


# Creates the machine visual.
func _create_machine_visual(
	cell: Vector2i
) -> Node2D:
	if (
		not is_instance_valid(_tilemap)
		or not is_instance_valid(_visual_parent)
	):
		return null

	if _machine_texture == null:
		_machine_texture = _make_machine_texture()

	var holder := Node2D.new()
	holder.name = "FertilizerInjector_%d_%d" % [
		cell.x,
		cell.y
	]
	_visual_parent.add_child(holder)

	var sprite := Sprite2D.new()
	sprite.texture = _machine_texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	holder.add_child(sprite)

	position_machine_visual_for_y_sort(
		holder,
		sprite,
		cell
	)

	return holder


# Creates the machine texture.
func _make_machine_texture() -> Texture2D:
	var image := Image.create(
		32,
		32,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	var outline := Color(0.06, 0.10, 0.06, 1.0)
	var tank_dark := Color(0.16, 0.34, 0.18, 1.0)
	var tank_light := Color(0.36, 0.70, 0.30, 1.0)
	var nutrient := Color(0.76, 0.91, 0.24, 1.0)
	var metal := Color(0.55, 0.62, 0.53, 1.0)

	_fill_rect(image, Rect2i(8, 7, 16, 19), outline)
	_fill_rect(image, Rect2i(9, 8, 14, 17), tank_dark)
	_fill_rect(image, Rect2i(11, 9, 10, 15), tank_light)
	_fill_rect(image, Rect2i(9, 15, 14, 3), nutrient)

	_fill_rect(image, Rect2i(13, 3, 6, 5), outline)
	_fill_rect(image, Rect2i(14, 4, 4, 4), metal)

	# Right-side injector pipe: short outlet, then a vertical leg that
	# visibly disappears into the soil instead of floating horizontally.
	_fill_rect(image, Rect2i(23, 17, 5, 4), outline)
	_fill_rect(image, Rect2i(24, 18, 3, 2), metal)
	_fill_rect(image, Rect2i(25, 20, 3, 7), outline)
	_fill_rect(image, Rect2i(26, 20, 1, 6), metal)

	# Lower machine foot/base so the sprite reads as planted in the ground.
	_fill_rect(image, Rect2i(6, 25, 20, 3), outline)
	_fill_rect(image, Rect2i(8, 26, 16, 1), metal)

	return ImageTexture.create_from_image(image)


# Fills the rectangle.
func _fill_rect(
	image: Image,
	rect: Rect2i,
	color: Color
) -> void:
	for y: int in range(
		rect.position.y,
		rect.position.y + rect.size.y
	):
		for x: int in range(
			rect.position.x,
			rect.position.x + rect.size.x
		):
			if (
				x >= 0
				and y >= 0
				and x < image.get_width()
				and y < image.get_height()
			):
				image.set_pixel(x, y, color)


# Returns the nearest valid default trigger threshold.
func _normalized_default_trigger() -> float:
	return _nearest_trigger_option(
		default_trigger_nutrients
	)


# Returns the valid trigger option closest to a value.
func _nearest_trigger_option(value: float) -> float:
	var best: float = TRIGGER_OPTIONS[0]
	var best_distance: float = absf(
		value - best
	)

	for option: float in TRIGGER_OPTIONS:
		var distance: float = absf(
			value - option
		)

		if distance < best_distance:
			best = option
			best_distance = distance

	return best
