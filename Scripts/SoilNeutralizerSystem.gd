extends "res://Scripts/AutomationMachineBase.gd"

# Level 30 automated soil-pH management machine.
#
# Shared automation-machine behavior:
# - Build Mode placement on grass or biome outer edge
# - Level 1-3 range / dosage upgrades
# - 1h / 3h / 6h / 12h interval
# - ON/OFF
# - per-machine configuration
# - Save/Load
# - each connected biome zone is handled at most once per cycle
#
# Unique behavior:
# - AUTO reads the plants inside each covered biome zone and keeps the soil
#   inside their compatible pH range.
# - LIME forces upward correction toward the target midpoint.
# - ACID forces downward correction toward the target midpoint.
# - Empty zones use soil-appropriate fallback pH ranges so the machine can
#   prepare soil before planting.

signal neutralizer_applied(
	cell: Vector2i,
	zones_adjusted: int,
	lime_zones: int,
	acid_zones: int,
	ph_dosage: float
)


const BUILD_ID: StringName = &"soil_neutralizer"

const MODE_AUTO: StringName = &"auto"
const MODE_LIME: StringName = &"lime"
const MODE_ACID: StringName = &"acid"

const MODE_OPTIONS: Array[StringName] = [
	MODE_AUTO,
	MODE_LIME,
	MODE_ACID
]

const REASON_INVALID_MODE: String = "INVALID_MODE"


@export_category("Neutralizer Level 1")

# Raw tool-like pH dosage before BiomeSystem soil buffering.
@export_range(0.05, 3.0, 0.05)
var level_1_ph_dosage: float = 0.60


@export_category("Neutralizer Level 2")

@export_range(0.05, 3.0, 0.05)
var level_2_ph_dosage: float = 0.80


@export_category("Neutralizer Level 3")

@export_range(0.05, 3.0, 0.05)
var level_3_ph_dosage: float = 1.00


@export_category("Fallback Soil Targets")

# Used only when a covered biome zone currently contains no living plants.
@export var fallback_loamy_ph_min: float = 6.2
@export var fallback_loamy_ph_max: float = 7.2

@export var fallback_sandy_ph_min: float = 6.8
@export var fallback_sandy_ph_max: float = 7.9

@export var fallback_other_ph_min: float = 6.5
@export var fallback_other_ph_max: float = 7.5


@export_category("Configuration")

@export var default_mode: StringName = MODE_AUTO


var _machine_texture: Texture2D

# Cycle-local counters used only for choosing the appropriate particle effect.
var _last_cycle_lime_zones: int = 0
var _last_cycle_acid_zones: int = 0


# Initializes this system when the node becomes ready.
func _ready() -> void:
	# Later-tier machine economy while retaining the shared range model.
	upgrade_to_level_2_cost = 350
	upgrade_to_level_3_cost = 800
	super._ready()


# Returns the machine build ID.
func get_machine_build_id() -> StringName:
	return BUILD_ID


# Returns the machine display name.
func get_machine_display_name() -> String:
	return "Soil Neutralizer"


# Returns the effect amount for level.
func get_effect_amount_for_level(
	level: int
) -> float:
	var base_amount: float = 0.0

	match clampi(level, 1, MAX_MACHINE_LEVEL):
		2:
			base_amount = level_2_ph_dosage
		3:
			base_amount = level_3_ph_dosage
		_:
			base_amount = level_1_ph_dosage

	return clampf(
		base_amount
		* RandomEventSystem.get_soil_neutralizer_strength_multiplier(),
		0.0,
		3.0
	)


# Returns the mode options.
func get_mode_options() -> Array[StringName]:
	return MODE_OPTIONS.duplicate()


# Returns the machine mode.
func get_machine_mode(
	cell: Vector2i
) -> StringName:
	if not has_machine(cell):
		return &""

	_ensure_default_state(cell)

	return _sanitize_mode(
		StringName(
			_machine_states[cell].get(
				"mode",
				default_mode
			)
		)
	)


# Sets the machine mode.
func set_machine_mode(
	cell: Vector2i,
	mode: StringName
) -> Dictionary:
	if not has_machine(cell):
		return {
			"ok": false,
			"reason": REASON_INVALID_MACHINE
		}

	var safe_mode: StringName = _sanitize_mode(mode)

	if safe_mode != mode:
		return {
			"ok": false,
			"reason": REASON_INVALID_MODE,
			"allowed": get_mode_options()
		}

	_ensure_default_state(cell)

	var state: Dictionary = _machine_states[cell]
	var previous_mode: StringName = _sanitize_mode(
		StringName(
			state.get(
				"mode",
				default_mode
			)
		)
	)

	state["mode"] = safe_mode
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
		"previous_mode": previous_mode,
		"mode": safe_mode,
		"state": public_state
	}


# Returns the target range for zone cell.
func get_target_range_for_zone_cell(
	cell: Vector2i
) -> Vector2:
	var zone_id: int = BiomeSystem.get_zone_id(cell)

	if zone_id < 0:
		return Vector2(
			fallback_other_ph_min,
			fallback_other_ph_max
		)

	return _target_range_for_zone(
		zone_id,
		cell
	)


# ------------------------------------------------------------
# Shared base hooks
# ------------------------------------------------------------

# Creates the custom default state.
func _make_custom_default_state() -> Dictionary:
	return {
		"mode": _sanitize_mode(default_mode)
	}


# Adds machine-specific fields to the public machine state.
func _enrich_public_state(
	_cell: Vector2i,
	state: Dictionary,
	output: Dictionary
) -> void:
	output["ph_dosage"] = float(
		output.get(
			"effect_amount",
			0.0
		)
	)
	output["mode"] = _sanitize_mode(
		StringName(
			state.get(
				"mode",
				default_mode
			)
		)
	)
	output["target_strategy"] = "Plant-safe range"


# Sanitizes machine-specific data loaded from a save.
func _sanitize_loaded_custom_state(
	entry: Dictionary,
	state: Dictionary
) -> void:
	state["mode"] = _sanitize_mode(
		StringName(
			entry.get(
				"mode",
				default_mode
			)
		)
	)


# Appends the custom save fields.
func _append_custom_save_fields(
	_cell: Vector2i,
	state: Dictionary,
	entry: Dictionary
) -> void:
	entry["mode"] = String(
		_sanitize_mode(
			StringName(
				state.get(
					"mode",
					default_mode
				)
			)
		)
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
	var mode: StringName = get_machine_mode(
		machine_cell
	)

	var adjusted: int = 0
	var lime_zones: int = 0
	var acid_zones: int = 0

	for zone_variant: Variant in zones.keys():
		var zone_id: int = int(zone_variant)
		var representative: Vector2i = zones[zone_variant]
		var current_ph: float = BiomeSystem.get_ph(
			representative
		)

		if current_ph < 0.0:
			continue

		var target: Vector2 = _target_range_for_zone(
			zone_id,
			representative
		)
		var target_min: float = minf(
			target.x,
			target.y
		)
		var target_max: float = maxf(
			target.x,
			target.y
		)
		var target_mid: float = (
			target_min + target_max
		) * 0.5

		var direction: int = 0

		match mode:
			MODE_LIME:
				if current_ph < target_mid:
					direction = 1
			MODE_ACID:
				if current_ph > target_mid:
					direction = -1
			_:
				if current_ph < target_min:
					direction = 1
				elif current_ph > target_max:
					direction = -1

		if direction == 0:
			continue

		var before: float = current_ph
		var delta_ph: float = absf(effect_amount) * float(
			direction
		)

		BiomeSystem.add_ph(
			representative,
			delta_ph
		)

		var after: float = BiomeSystem.get_ph(
			representative
		)

		if is_equal_approx(before, after):
			continue

		adjusted += 1

		if direction > 0:
			lime_zones += 1
		else:
			acid_zones += 1

	_last_cycle_lime_zones = lime_zones
	_last_cycle_acid_zones = acid_zones

	neutralizer_applied.emit(
		machine_cell,
		adjusted,
		lime_zones,
		acid_zones,
		effect_amount
	)

	return adjusted


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
	var radius: int = get_machine_radius(
		machine_cell
	)
	var diameter: float = float(
		maxi(
			radius * 2 + 1,
			1
		)
	)
	var scale_cells := Vector2(
		diameter,
		diameter
	)

	if _last_cycle_lime_zones > 0:
		ToolParticles.spawn_lime(
			center + Vector2(-4.0, 0.0),
			cell_pixels,
			scale_cells
		)

	if _last_cycle_acid_zones > 0:
		ToolParticles.spawn_acid(
			center + Vector2(4.0, 0.0),
			cell_pixels,
			scale_cells
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
	holder.name = "SoilNeutralizer_%d_%d" % [
		cell.x,
		cell.y
	]
	_visual_parent.add_child(holder)

	var sprite := Sprite2D.new()
	sprite.texture = _machine_texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# Ground-fit: the body sits on the tile and the probe visibly enters soil.
	holder.add_child(sprite)

	position_machine_visual_for_y_sort(
		holder,
		sprite,
		cell
	)

	return holder


# ------------------------------------------------------------
# pH targeting
# ------------------------------------------------------------

# Handles target range for zone.
func _target_range_for_zone(
	zone_id: int,
	representative: Vector2i
) -> Vector2:
	var found_plant: bool = false
	var overlap_min: float = -INF
	var overlap_max: float = INF

	var midpoint_sum: float = 0.0
	var midpoint_count: int = 0
	var half_width_sum: float = 0.0

	var seen_instances: Dictionary = {}

	for cell_variant: Variant in PlantRegistry.plants_by_cell.keys():
		var plant_cell: Vector2i = cell_variant

		if BiomeSystem.get_zone_id(plant_cell) != zone_id:
			continue

		var plant_variant: Variant = PlantRegistry.get_plant(
			plant_cell
		)

		# PlantRegistry can briefly contain a freed instance during scene change.
		if not is_instance_valid(plant_variant):
			continue

		if not plant_variant is Node:
			continue

		var plant := plant_variant as Node
		var instance_id: int = plant.get_instance_id()

		if seen_instances.has(instance_id):
			continue

		seen_instances[instance_id] = true

		var dead_variant: Variant = plant.get("is_dead")

		if (
			typeof(dead_variant) == TYPE_BOOL
			and bool(dead_variant)
		):
			continue

		var data_variant: Variant = plant.get("data")

		if not is_instance_valid(data_variant):
			continue

		if not data_variant is PlantData:
			continue

		var data := data_variant as PlantData
		var plant_min: float = minf(
			data.optimal_ph_min,
			data.optimal_ph_max
		)
		var plant_max: float = maxf(
			data.optimal_ph_min,
			data.optimal_ph_max
		)

		if not found_plant:
			overlap_min = plant_min
			overlap_max = plant_max
			found_plant = true
		else:
			overlap_min = maxf(
				overlap_min,
				plant_min
			)
			overlap_max = minf(
				overlap_max,
				plant_max
			)

		midpoint_sum += (
			plant_min + plant_max
		) * 0.5
		half_width_sum += (
			plant_max - plant_min
		) * 0.5
		midpoint_count += 1

	if found_plant:
		# Compatible plant ranges overlap: use their shared safe band.
		if overlap_min <= overlap_max:
			return Vector2(
				overlap_min,
				overlap_max
			)

		# Future plant combinations may have no shared band. In that case,
		# use the average preferred midpoint with a conservative common width
		# instead of oscillating between incompatible extremes.
		var average_mid: float = (
			midpoint_sum
			/ float(maxi(midpoint_count, 1))
		)
		var average_half_width: float = maxf(
			half_width_sum
			/ float(maxi(midpoint_count, 1)),
			0.20
		)

		return Vector2(
			average_mid - average_half_width,
			average_mid + average_half_width
		)

	return _fallback_target_range(
		representative
	)


# Handles fallback target range.
func _fallback_target_range(
	cell: Vector2i
) -> Vector2:
	var soil: String = BiomeSystem.get_soil_type_at_cell(
		cell
	)

	match soil:
		"loamy":
			return Vector2(
				fallback_loamy_ph_min,
				fallback_loamy_ph_max
			)
		"sandy":
			return Vector2(
				fallback_sandy_ph_min,
				fallback_sandy_ph_max
			)
		_:
			return Vector2(
				fallback_other_ph_min,
				fallback_other_ph_max
			)


# Sanitizes the mode.
func _sanitize_mode(
	mode: StringName
) -> StringName:
	if MODE_OPTIONS.has(mode):
		return mode

	return MODE_AUTO


# ------------------------------------------------------------
# Runtime pixel-art visual
# ------------------------------------------------------------

# Creates the machine texture.
func _make_machine_texture() -> Texture2D:
	var image := Image.create(
		32,
		32,
		false,
		Image.FORMAT_RGBA8
	)
	image.fill(
		Color(
			0.0,
			0.0,
			0.0,
			0.0
		)
	)

	var outline := Color(0.07, 0.08, 0.12, 1.0)
	var body_dark := Color(0.22, 0.22, 0.38, 1.0)
	var body_light := Color(0.43, 0.42, 0.67, 1.0)
	var lime_color := Color(0.72, 0.90, 0.42, 1.0)
	var acid_color := Color(0.46, 0.76, 0.94, 1.0)
	var metal := Color(0.58, 0.61, 0.67, 1.0)

	# Main cabinet.
	_fill_rect(
		image,
		Rect2i(7, 8, 18, 17),
		outline
	)
	_fill_rect(
		image,
		Rect2i(8, 9, 16, 15),
		body_dark
	)
	_fill_rect(
		image,
		Rect2i(10, 10, 12, 12),
		body_light
	)

	# Dual reagent indicators: Lime / Acid.
	_fill_rect(
		image,
		Rect2i(10, 12, 5, 7),
		outline
	)
	_fill_rect(
		image,
		Rect2i(11, 13, 3, 5),
		lime_color
	)
	_fill_rect(
		image,
		Rect2i(17, 12, 5, 7),
		outline
	)
	_fill_rect(
		image,
		Rect2i(18, 13, 3, 5),
		acid_color
	)

	# Top gauge.
	_fill_rect(
		image,
		Rect2i(12, 4, 8, 5),
		outline
	)
	_fill_rect(
		image,
		Rect2i(13, 5, 6, 3),
		metal
	)
	image.set_pixel(
		16,
		6,
		Color(0.12, 0.14, 0.17, 1.0)
	)

	# Ground probe: short outlet bends down into the soil.
	_fill_rect(
		image,
		Rect2i(24, 17, 5, 4),
		outline
	)
	_fill_rect(
		image,
		Rect2i(25, 18, 3, 2),
		metal
	)
	_fill_rect(
		image,
		Rect2i(26, 20, 3, 8),
		outline
	)
	_fill_rect(
		image,
		Rect2i(27, 20, 1, 7),
		metal
	)

	# Foot/base.
	_fill_rect(
		image,
		Rect2i(6, 24, 20, 4),
		outline
	)
	_fill_rect(
		image,
		Rect2i(8, 25, 16, 2),
		metal
	)

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
				image.set_pixel(
					x,
					y,
					color
				)
