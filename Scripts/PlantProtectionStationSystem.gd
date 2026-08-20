extends "res://Scripts/AutomationMachineBase.gd"

# Level 40 automated biological-protection machine.
#
# Machine-family behavior:
# - Build Mode placement on grass or biome outer edge
# - Level 1-3 range / treatment upgrades
# - 1h / 3h / 6h / 12h interval
# - ON/OFF
# - per-machine configuration
# - Save/Load
# - if range touches a connected biome zone, living plants in that zone are
#   eligible for treatment once per cycle
#
# Unique behavior:
# - AUTO: independently treats pests and fungus only when each threshold is met
# - PEST: pesticide channel only
# - FUNGUS: fungicide channel only
# - BOTH: both treatment channels are enabled, still threshold-aware
#
# This is intentionally plant-level treatment rather than reducing the
# environmental biome pressure itself. The machine treats infected plants;
# weather/soil can still create future biological pressure.

signal protection_applied(
	cell: Vector2i,
	plants_treated: int,
	pest_treatments: int,
	fungus_treatments: int,
	pesticide_amount: float,
	fungicide_amount: float
)


const BUILD_ID: StringName = &"plant_protection_station"

const MODE_AUTO: StringName = &"auto"
const MODE_PEST: StringName = &"pest"
const MODE_FUNGUS: StringName = &"fungus"
const MODE_BOTH: StringName = &"both"

const MODE_OPTIONS: Array[StringName] = [
	MODE_AUTO,
	MODE_PEST,
	MODE_FUNGUS,
	MODE_BOTH
]

const TRIGGER_OPTIONS: Array[float] = [
	0.10,
	0.15,
	0.20,
	0.30
]

const REASON_INVALID_MODE: String = "INVALID_MODE"
const REASON_INVALID_TRIGGER: String = "INVALID_TRIGGER"


@export_category("Protection Level 1")

@export_range(0.01, 1.0, 0.01)
var level_1_pesticide_amount: float = 0.20

@export_range(0.01, 1.0, 0.01)
var level_1_fungicide_amount: float = 0.18


@export_category("Protection Level 2")

@export_range(0.01, 1.0, 0.01)
var level_2_pesticide_amount: float = 0.28

@export_range(0.01, 1.0, 0.01)
var level_2_fungicide_amount: float = 0.25


@export_category("Protection Level 3")

@export_range(0.01, 1.0, 0.01)
var level_3_pesticide_amount: float = 0.36

@export_range(0.01, 1.0, 0.01)
var level_3_fungicide_amount: float = 0.32


@export_category("Configuration")

@export var default_mode: StringName = MODE_AUTO

@export_range(0.0, 1.0, 0.05)
var default_pest_trigger: float = 0.15

@export_range(0.0, 1.0, 0.05)
var default_fungus_trigger: float = 0.15


var _machine_texture: Texture2D

# Cycle-local effect counters.
var _last_cycle_pest_treatments: int = 0
var _last_cycle_fungus_treatments: int = 0


# Initializes this system when the node becomes ready.
func _ready() -> void:
	# Later-tier economy while retaining the shared range / scheduling model.
	upgrade_to_level_2_cost = 500
	upgrade_to_level_3_cost = 1100
	super._ready()


# Returns the machine build ID.
func get_machine_build_id() -> StringName:
	return BUILD_ID


# Returns the machine display name.
func get_machine_display_name() -> String:
	return "Plant Protection Station"


# The shared base exposes one generic "effect amount". For this dual-channel
# machine it represents pesticide strength; public state separately exposes
# fungicide strength.
func get_effect_amount_for_level(
	level: int
) -> float:
	return get_pesticide_amount_for_level(level)


# Returns the pesticide amount for level.
func get_pesticide_amount_for_level(
	level: int
) -> float:
	var base_amount: float = 0.0

	match clampi(level, 1, MAX_MACHINE_LEVEL):
		2:
			base_amount = level_2_pesticide_amount
		3:
			base_amount = level_3_pesticide_amount
		_:
			base_amount = level_1_pesticide_amount

	return clampf(
		base_amount
		* RandomEventSystem.get_plant_protection_strength_multiplier(),
		0.0,
		1.0
	)


# Returns the fungicide amount for level.
func get_fungicide_amount_for_level(
	level: int
) -> float:
	var base_amount: float = 0.0

	match clampi(level, 1, MAX_MACHINE_LEVEL):
		2:
			base_amount = level_2_fungicide_amount
		3:
			base_amount = level_3_fungicide_amount
		_:
			base_amount = level_1_fungicide_amount

	return clampf(
		base_amount
		* RandomEventSystem.get_plant_protection_strength_multiplier(),
		0.0,
		1.0
	)


# Returns the mode options.
func get_mode_options() -> Array[StringName]:
	return MODE_OPTIONS.duplicate()


# Returns the trigger options.
func get_trigger_options() -> Array[float]:
	return TRIGGER_OPTIONS.duplicate()


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


# Returns the pest trigger.
func get_pest_trigger(
	cell: Vector2i
) -> float:
	if not has_machine(cell):
		return -1.0

	_ensure_default_state(cell)

	return _nearest_trigger_option(
		float(
			_machine_states[cell].get(
				"pest_trigger",
				default_pest_trigger
			)
		)
	)


# Returns the fungus trigger.
func get_fungus_trigger(
	cell: Vector2i
) -> float:
	if not has_machine(cell):
		return -1.0

	_ensure_default_state(cell)

	return _nearest_trigger_option(
		float(
			_machine_states[cell].get(
				"fungus_trigger",
				default_fungus_trigger
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
	var previous: StringName = _sanitize_mode(
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

	machine_configuration_changed.emit(cell, public_state)
	machine_state_changed.emit(cell, public_state)

	return {
		"ok": true,
		"cell": cell,
		"previous_mode": previous,
		"mode": safe_mode,
		"state": public_state
	}


# Sets the pest trigger.
func set_pest_trigger(
	cell: Vector2i,
	trigger: float
) -> Dictionary:
	return _set_trigger(
		cell,
		"pest_trigger",
		trigger
	)


# Sets the fungus trigger.
func set_fungus_trigger(
	cell: Vector2i,
	trigger: float
) -> Dictionary:
	return _set_trigger(
		cell,
		"fungus_trigger",
		trigger
	)


# Sets the trigger.
func _set_trigger(
	cell: Vector2i,
	state_key: String,
	trigger: float
) -> Dictionary:
	if not has_machine(cell):
		return {
			"ok": false,
			"reason": REASON_INVALID_MACHINE
		}

	if not _is_valid_trigger(trigger):
		return {
			"ok": false,
			"reason": REASON_INVALID_TRIGGER,
			"allowed": get_trigger_options()
		}

	_ensure_default_state(cell)

	var state: Dictionary = _machine_states[cell]
	var previous: float = float(
		state.get(
			state_key,
			0.15
		)
	)

	state[state_key] = trigger
	_machine_states[cell] = state

	var public_state: Dictionary = get_machine_state(cell)

	machine_configuration_changed.emit(cell, public_state)
	machine_state_changed.emit(cell, public_state)

	return {
		"ok": true,
		"cell": cell,
		"previous_trigger": previous,
		"trigger": trigger,
		"state": public_state
	}


# ------------------------------------------------------------
# Shared base hooks
# ------------------------------------------------------------

# Creates the custom default state.
func _make_custom_default_state() -> Dictionary:
	return {
		"mode": _sanitize_mode(default_mode),
		"pest_trigger": _nearest_trigger_option(
			default_pest_trigger
		),
		"fungus_trigger": _nearest_trigger_option(
			default_fungus_trigger
		)
	}


# Adds machine-specific fields to the public machine state.
func _enrich_public_state(
	_cell: Vector2i,
	state: Dictionary,
	output: Dictionary
) -> void:
	var level: int = clampi(
		int(state.get("level", 1)),
		1,
		MAX_MACHINE_LEVEL
	)

	output["mode"] = _sanitize_mode(
		StringName(
			state.get(
				"mode",
				default_mode
			)
		)
	)
	output["pest_trigger"] = _nearest_trigger_option(
		float(
			state.get(
				"pest_trigger",
				default_pest_trigger
			)
		)
	)
	output["fungus_trigger"] = _nearest_trigger_option(
		float(
			state.get(
				"fungus_trigger",
				default_fungus_trigger
			)
		)
	)
	output["pesticide_amount"] = get_pesticide_amount_for_level(
		level
	)
	output["fungicide_amount"] = get_fungicide_amount_for_level(
		level
	)


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
	state["pest_trigger"] = _nearest_trigger_option(
		float(
			entry.get(
				"pest_trigger",
				default_pest_trigger
			)
		)
	)
	state["fungus_trigger"] = _nearest_trigger_option(
		float(
			entry.get(
				"fungus_trigger",
				default_fungus_trigger
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
	entry["pest_trigger"] = _nearest_trigger_option(
		float(
			state.get(
				"pest_trigger",
				default_pest_trigger
			)
		)
	)
	entry["fungus_trigger"] = _nearest_trigger_option(
		float(
			state.get(
				"fungus_trigger",
				default_fungus_trigger
			)
		)
	)


# Applies the machine cycle.
func _apply_machine_cycle(
	machine_cell: Vector2i,
	radius_cells: int,
	_effect_amount: float
) -> int:
	var covered_zones: Dictionary = collect_covered_zones(
		machine_cell,
		radius_cells
	)

	if covered_zones.is_empty():
		_last_cycle_pest_treatments = 0
		_last_cycle_fungus_treatments = 0
		return 0

	var mode: StringName = get_machine_mode(machine_cell)
	var pest_trigger: float = get_pest_trigger(machine_cell)
	var fungus_trigger: float = get_fungus_trigger(machine_cell)
	var level: int = get_machine_level(machine_cell)

	var pesticide_amount: float = get_pesticide_amount_for_level(
		level
	)
	var fungicide_amount: float = get_fungicide_amount_for_level(
		level
	)

	var covered_zone_ids: Dictionary = {}

	for zone_variant: Variant in covered_zones.keys():
		covered_zone_ids[int(zone_variant)] = true

	var seen_plants: Dictionary = {}
	var treated_plants: int = 0
	var pest_treatments: int = 0
	var fungus_treatments: int = 0

	for plant_cell_variant: Variant in PlantRegistry.plants_by_cell.keys():
		var plant_cell: Vector2i = plant_cell_variant
		var zone_id: int = BiomeSystem.get_zone_id(plant_cell)

		if (
			zone_id < 0
			or not covered_zone_ids.has(zone_id)
		):
			continue

		var plant_variant: Variant = PlantRegistry.get_plant(
			plant_cell
		)

		# Registry entries may briefly point to a freed plant during scene
		# replacement, so validity must be checked before type inspection.
		if not is_instance_valid(plant_variant):
			continue

		if not plant_variant is Node:
			continue

		var plant := plant_variant as Node
		var instance_id: int = plant.get_instance_id()

		if seen_plants.has(instance_id):
			continue

		seen_plants[instance_id] = true

		var dead_variant: Variant = plant.get("is_dead")

		if (
			typeof(dead_variant) == TYPE_BOOL
			and bool(dead_variant)
		):
			continue

		var pest_level: float = clampf(
			float(plant.get("pest_level")),
			0.0,
			1.0
		)
		var fungus_level: float = clampf(
			float(plant.get("disease_level")),
			0.0,
			1.0
		)

		var pest_channel_enabled: bool = (
			mode == MODE_AUTO
			or mode == MODE_PEST
			or mode == MODE_BOTH
		)
		var fungus_channel_enabled: bool = (
			mode == MODE_AUTO
			or mode == MODE_FUNGUS
			or mode == MODE_BOTH
		)

		var did_treat: bool = false

		if (
			pest_channel_enabled
			and pest_level >= pest_trigger
			and plant.has_method("apply_pesticide")
		):
			plant.call(
				"apply_pesticide",
				pesticide_amount
			)
			pest_treatments += 1
			did_treat = true

		if (
			fungus_channel_enabled
			and fungus_level >= fungus_trigger
			and plant.has_method("apply_fungicide")
		):
			plant.call(
				"apply_fungicide",
				fungicide_amount
			)
			fungus_treatments += 1
			did_treat = true

		if did_treat:
			treated_plants += 1

	_last_cycle_pest_treatments = pest_treatments
	_last_cycle_fungus_treatments = fungus_treatments

	protection_applied.emit(
		machine_cell,
		treated_plants,
		pest_treatments,
		fungus_treatments,
		pesticide_amount,
		fungicide_amount
	)

	return treated_plants


# Handles the cycle visual signal or callback.
func _on_cycle_visual(
	machine_cell: Vector2i,
	affected_plants: int
) -> void:
	if (
		affected_plants <= 0
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
		maxi(
			radius * 2 + 1,
			1
		)
	)
	var scale_cells := Vector2(
		diameter,
		diameter
	)

	if _last_cycle_pest_treatments > 0:
		ToolParticles.spawn_pesticide(
			center + Vector2(-4.0, 0.0),
			cell_pixels,
			scale_cells
		)

	if _last_cycle_fungus_treatments > 0:
		ToolParticles.spawn_fungicide(
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
	holder.name = "PlantProtection_%d_%d" % [
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


# ------------------------------------------------------------
# Configuration helpers
# ------------------------------------------------------------

# Sanitizes the mode.
func _sanitize_mode(
	mode: StringName
) -> StringName:
	if MODE_OPTIONS.has(mode):
		return mode

	return MODE_AUTO


# Checks whether the trigger is valid.
func _is_valid_trigger(
	value: float
) -> bool:
	for option: float in TRIGGER_OPTIONS:
		if is_equal_approx(
			option,
			value
		):
			return true

	return false


# Returns the valid trigger option closest to a value.
func _nearest_trigger_option(
	value: float
) -> float:
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

	var outline := Color(0.08, 0.08, 0.07, 1.0)
	var body_dark := Color(0.29, 0.25, 0.18, 1.0)
	var body_light := Color(0.58, 0.48, 0.26, 1.0)
	var pesticide := Color(0.72, 0.86, 0.25, 1.0)
	var fungicide := Color(0.33, 0.78, 0.72, 1.0)
	var shield := Color(0.82, 0.85, 0.72, 1.0)
	var metal := Color(0.54, 0.57, 0.51, 1.0)

	# Main cabinet.
	_fill_rect(image, Rect2i(7, 8, 18, 17), outline)
	_fill_rect(image, Rect2i(8, 9, 16, 15), body_dark)
	_fill_rect(image, Rect2i(10, 10, 12, 12), body_light)

	# Dual biological-treatment reservoirs.
	_fill_rect(image, Rect2i(9, 16, 6, 5), outline)
	_fill_rect(image, Rect2i(10, 17, 4, 3), pesticide)
	_fill_rect(image, Rect2i(17, 16, 6, 5), outline)
	_fill_rect(image, Rect2i(18, 17, 4, 3), fungicide)

	# Small shield emblem.
	_fill_rect(image, Rect2i(13, 11, 6, 2), shield)
	_fill_rect(image, Rect2i(12, 12, 8, 3), shield)
	_fill_rect(image, Rect2i(14, 15, 4, 2), shield)
	_fill_rect(image, Rect2i(15, 17, 2, 1), shield)

	# Top sensor.
	_fill_rect(image, Rect2i(13, 4, 6, 5), outline)
	_fill_rect(image, Rect2i(14, 5, 4, 3), metal)

	# Side application pipe bends into the ground.
	_fill_rect(image, Rect2i(24, 17, 5, 4), outline)
	_fill_rect(image, Rect2i(25, 18, 3, 2), metal)
	_fill_rect(image, Rect2i(26, 20, 3, 8), outline)
	_fill_rect(image, Rect2i(27, 20, 1, 7), metal)

	# Ground foot.
	_fill_rect(image, Rect2i(6, 24, 20, 4), outline)
	_fill_rect(image, Rect2i(8, 25, 16, 2), metal)

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
