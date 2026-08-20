extends "res://Scripts/AutomationMachineBase.gd"

# Field Sprinkler implementation built on the shared automation-machine backend.
#
# AutomationMachineBase now owns the same common behavior as the other machines:
# - placement tracking and Y-sort visuals
# - Level 1-3 range / upgrade state
# - 1h / 3h / 6h / 12h scheduling
# - ON/OFF configuration
# - Save/Load state
#
# This script only keeps sprinkler-specific moisture, random-event behavior,
# water particles, and compatibility aliases used by older game systems.

# Legacy signals remain available so existing UI/audio/event integrations do not
# need to change at the same time as the backend refactor.
signal sprinkler_state_changed(
	cell: Vector2i,
	state: Dictionary
)

signal sprinkler_upgraded(
	cell: Vector2i,
	previous_level: int,
	new_level: int,
	cost: int
)

signal sprinkler_configuration_changed(
	cell: Vector2i,
	state: Dictionary
)

signal sprinkler_watered(
	cell: Vector2i,
	zones_watered: int,
	moisture_amount: float
)


const BUILD_ID: StringName = &"sprinkler"

# Backward-compatible names used by existing tests/UI code.
const BUILD_ID_SPRINKLER: StringName = BUILD_ID
const MAX_SPRINKLER_LEVEL: int = 3
const WATERING_INTERVAL_OPTIONS_MINUTES: Array[int] = [
	60,
	180,
	360,
	720
]

const REASON_INVALID_SPRINKLER: String = "INVALID_SPRINKLER"


@export_category("Sprinkler Level 1")

@export_range(0.01, 1.0, 0.01)
var level_1_moisture_per_cycle: float = 0.12


@export_category("Sprinkler Level 2")

@export_range(0.01, 1.0, 0.01)
var level_2_moisture_per_cycle: float = 0.16


@export_category("Sprinkler Level 3")

@export_range(0.01, 1.0, 0.01)
var level_3_moisture_per_cycle: float = 0.20


@export_category("Sprinkler Configuration")

# Already-wet biome zones are skipped to avoid repeated saturation.
@export_range(0.0, 1.0, 0.01)
var skip_zone_at_moisture: float = 0.80


@export_category("Visual Animation")

# Cosmetic spray animation. Gameplay watering still follows in-game time.
@export_range(2.0, 60.0, 0.5)
var visual_cycle_seconds: float = 10.0

@export_range(0.5, 5.0, 0.1)
var visual_burst_seconds: float = 2.0

@export_range(0.08, 1.0, 0.02)
var visual_pulse_interval_seconds: float = 0.16

@export_range(4, 24, 1)
var visual_direction_count: int = 12

@export_range(0.0, 16.0, 0.5)
var visual_nozzle_radius_pixels: float = 6.0


var _visual_cycle_timer: Timer
var _visual_burst_remaining: float = 0.0
var _visual_pulse_accumulator: float = 0.0
var _visual_pulse_index: int = 0


# Applies sprinkler-specific defaults, then starts the shared backend.
func _ready() -> void:
	upgrade_to_level_2_cost = 150
	upgrade_to_level_3_cost = 350

	super._ready()

	_create_visual_cycle_timer()
	_connect_legacy_signal_relays()

	if debug_log:
		print(
			"[Sprinkler] shared automation backend ready ",
			"L1=(r",
			level_1_radius_cells,
			",+",
			level_1_moisture_per_cycle,
			") L2=(r",
			level_2_radius_cells,
			",+",
			level_2_moisture_per_cycle,
			") L3=(r",
			level_3_radius_cells,
			",+",
			level_3_moisture_per_cycle,
			") default_interval=",
			default_interval_minutes
		)


# Resets cosmetic spray state before binding a gameplay world.
func configure(tilemap: TileMap) -> void:
	_reset_visual_burst()

	if is_instance_valid(_visual_cycle_timer):
		_visual_cycle_timer.wait_time = maxf(
			visual_cycle_seconds,
			2.0
		)

		if _visual_cycle_timer.is_stopped():
			_visual_cycle_timer.start()

	super.configure(tilemap)


# Clears cosmetic spray state when the active gameplay world is removed.
func unconfigure(tilemap: TileMap) -> void:
	super.unconfigure(tilemap)

	if not _configured:
		_reset_visual_burst()


# Advances the real-time cosmetic sprinkler spray animation.
func _process(delta: float) -> void:
	if (
		not _configured
		or _machine_nodes.is_empty()
		or get_tree().paused
		or _visual_burst_remaining <= 0.0
	):
		return

	_visual_burst_remaining = maxf(
		_visual_burst_remaining - delta,
		0.0
	)
	_visual_pulse_accumulator += delta

	while (
		_visual_pulse_accumulator
		>= visual_pulse_interval_seconds
	):
		_visual_pulse_accumulator -= (
			visual_pulse_interval_seconds
		)
		_emit_visual_spray_pulse()


# ------------------------------------------------------------
# Shared machine hooks
# ------------------------------------------------------------

# Identifies the BuildSystem object represented by this backend.
func get_machine_build_id() -> StringName:
	return BUILD_ID


# Returns the user-facing machine name.
func get_machine_display_name() -> String:
	return "Field Sprinkler"


# Returns the base moisture added by each level before temporary events.
func get_effect_amount_for_level(
	level: int
) -> float:
	match clampi(level, 1, MAX_MACHINE_LEVEL):
		2:
			return level_2_moisture_per_cycle
		3:
			return level_3_moisture_per_cycle
		_:
			return level_1_moisture_per_cycle


# Keeps the legacy moisture field in level definitions used by older UI/tests.
func get_level_definition(
	level: int
) -> Dictionary:
	var definition: Dictionary = super.get_level_definition(
		level
	)

	definition["moisture_per_cycle"] = float(
		definition.get("effect_amount", 0.0)
	)

	return definition


# Applies Efficient Irrigation or other temporary sprinkler-strength modifiers.
func _get_cycle_effect_amount(
	cell: Vector2i
) -> float:
	return clampf(
		get_machine_effect_amount(cell)
		* _get_event_sprinkler_strength_multiplier(),
		0.0,
		1.0
	)


# Applies Water Shortage or other temporary interval modifiers.
func _get_effective_interval_minutes(
	base_interval_minutes: int
) -> int:
	return maxi(
		int(round(
			float(maxi(base_interval_minutes, 1))
			* _get_event_sprinkler_interval_multiplier()
		)),
		1
	)


# Sprinkler Breakdown blocks cycles without changing the player's ON/OFF state.
func _is_machine_cycle_blocked(
	_cell: Vector2i
) -> bool:
	return _are_sprinklers_disabled_by_event()


# Keeps existing Garden save files compatible with the old sprinkler backend.
func _get_persistence_next_cycle_key() -> String:
	return "next_watering_total_minutes"


# Prevents a stale legacy timestamp from causing a large catch-up burst on load.
func _sanitize_loaded_schedule(
	_entry: Dictionary,
	state: Dictionary,
	current_total_minutes: int
) -> void:
	if not bool(state.get("enabled", true)):
		return

	var next_total: int = int(
		state.get(
			"next_cycle_total_minutes",
			current_total_minutes
		)
	)

	if next_total > current_total_minutes:
		return

	var base_interval: int = int(
		state.get(
			"interval_minutes",
			_get_default_interval_minutes()
		)
	)

	state["next_cycle_total_minutes"] = (
		current_total_minutes
		+ _get_effective_interval_minutes(
			base_interval
		)
	)


# Adds sprinkler-specific fields to the generic machine state.
func _enrich_public_state(
	cell: Vector2i,
	state: Dictionary,
	output: Dictionary
) -> void:
	output["moisture_per_cycle"] = float(
		output.get("effect_amount", 0.0)
	)
	output["event_disabled"] = _is_machine_cycle_blocked(
		cell
	)
	output["effective_interval_minutes"] = (
		_get_effective_interval_minutes(
			int(
				state.get(
					"interval_minutes",
					_get_default_interval_minutes()
				)
			)
		)
	)


# Waters each connected biome zone at most once per machine cycle.
func _apply_machine_cycle(
	machine_cell: Vector2i,
	radius_cells: int,
	effect_amount: float
) -> int:
	var zones: Dictionary = collect_covered_zones(
		machine_cell,
		radius_cells
	)
	var watered_zones: int = 0

	for zone_variant: Variant in zones.keys():
		var representative: Vector2i = zones[zone_variant]
		var moisture: float = BiomeSystem.get_moisture(
			representative
		)

		if (
			moisture < 0.0
			or moisture >= skip_zone_at_moisture
		):
			continue

		BiomeSystem.add_moisture(
			representative,
			effect_amount
		)
		watered_zones += 1

	return watered_zones


# Starts water feedback when a gameplay watering cycle affected a zone.
func _on_cycle_visual(
	machine_cell: Vector2i,
	_affected_zones: int
) -> void:
	_spawn_water_effect(machine_cell)
	_start_visual_burst()


# Creates the runtime sprinkler sprite inside the shared Y-sort container.
func _create_machine_visual(
	cell: Vector2i
) -> Node2D:
	if not is_instance_valid(_visual_parent):
		return null

	var holder := Node2D.new()
	holder.name = "Sprinkler_%d_%d" % [
		cell.x,
		cell.y
	]

	var sprite := Sprite2D.new()
	sprite.name = "Visual"
	sprite.texture = BuildSystem.get_build_icon(
		BUILD_ID
	)
	sprite.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
	)

	holder.add_child(sprite)
	_visual_parent.add_child(holder)

	position_machine_visual_for_y_sort(
		holder,
		sprite,
		cell
	)

	return holder


# ------------------------------------------------------------
# Cosmetic water animation
# ------------------------------------------------------------

# Creates the repeating real-time timer used only for visible spray pulses.
func _create_visual_cycle_timer() -> void:
	if is_instance_valid(_visual_cycle_timer):
		return

	_visual_cycle_timer = Timer.new()
	_visual_cycle_timer.name = "VisualCycleTimer"
	_visual_cycle_timer.wait_time = maxf(
		visual_cycle_seconds,
		2.0
	)
	_visual_cycle_timer.one_shot = false
	_visual_cycle_timer.autostart = true
	_visual_cycle_timer.process_mode = (
		Node.PROCESS_MODE_PAUSABLE
	)
	_visual_cycle_timer.timeout.connect(
		_on_visual_cycle_timeout
	)
	add_child(_visual_cycle_timer)


# Starts a cosmetic spray burst while at least one sprinkler can operate.
func _on_visual_cycle_timeout() -> void:
	if (
		not _configured
		or _get_enabled_sprinkler_count() <= 0
		or get_tree().paused
		or _are_sprinklers_disabled_by_event()
	):
		return

	_start_visual_burst()


# Initializes one visible spray burst.
func _start_visual_burst() -> void:
	_visual_burst_remaining = maxf(
		visual_burst_seconds,
		0.1
	)
	_visual_pulse_accumulator = (
		visual_pulse_interval_seconds
	)
	_visual_pulse_index = 0


# Clears the current cosmetic spray burst.
func _reset_visual_burst() -> void:
	_visual_burst_remaining = 0.0
	_visual_pulse_accumulator = 0.0
	_visual_pulse_index = 0


# Emits one directional spray pulse from every enabled sprinkler.
func _emit_visual_spray_pulse() -> void:
	if (
		not is_instance_valid(_tilemap)
		or _are_sprinklers_disabled_by_event()
	):
		return

	var cell_pixels := Vector2(
		_tilemap.tile_set.tile_size
	)
	var direction_count: int = maxi(
		visual_direction_count,
		4
	)
	var angle_step: float = TAU / float(
		direction_count
	)
	var angle: float = (
		-PI * 0.5
		+ angle_step * float(
			_visual_pulse_index % direction_count
		)
	)
	var direction := Vector2(
		cos(angle),
		sin(angle)
	)
	var nozzle_offset: Vector2 = (
		direction
		* visual_nozzle_radius_pixels
	)

	for cell_variant: Variant in _machine_nodes.keys():
		var cell: Vector2i = cell_variant

		if not is_machine_enabled(cell):
			continue

		var center: Vector2 = _tilemap.to_global(
			_tilemap.map_to_local(cell)
		)

		ToolParticles.spawn_sprinkler_water(
			center + nozzle_offset,
			cell_pixels,
			Vector2.ONE,
			direction
		)

	_visual_pulse_index += 1


# Spawns the short central water feedback used by an actual watering cycle.
func _spawn_water_effect(
	cell: Vector2i
) -> void:
	if not is_instance_valid(_tilemap):
		return

	var world_position: Vector2 = _tilemap.to_global(
		_tilemap.map_to_local(cell)
	)
	var cell_pixels := Vector2(
		_tilemap.tile_set.tile_size
	)

	ToolParticles.spawn_water(
		world_position,
		cell_pixels,
		Vector2.ONE
	)


# Counts enabled sprinkler machines for the cosmetic animation.
func _get_enabled_sprinkler_count() -> int:
	var count: int = 0

	for cell: Vector2i in get_machine_cells():
		if is_machine_enabled(cell):
			count += 1

	return count


# ------------------------------------------------------------
# Random Event integration
# ------------------------------------------------------------

# Returns RandomEventSystem without creating a hard initialization dependency.
func _get_random_event_system() -> Node:
	return get_node_or_null(
		"/root/RandomEventSystem"
	)


# Returns the current global sprinkler interval multiplier.
func _get_event_sprinkler_interval_multiplier() -> float:
	var event_system: Node = _get_random_event_system()

	if (
		event_system != null
		and event_system.has_method(
			"get_sprinkler_interval_multiplier"
		)
	):
		return clampf(
			float(event_system.call(
				"get_sprinkler_interval_multiplier"
			)),
			0.5,
			4.0
		)

	return 1.0


# Returns the current global sprinkler strength multiplier.
func _get_event_sprinkler_strength_multiplier() -> float:
	var event_system: Node = _get_random_event_system()

	if (
		event_system != null
		and event_system.has_method(
			"get_sprinkler_strength_multiplier"
		)
	):
		return clampf(
			float(event_system.call(
				"get_sprinkler_strength_multiplier"
			)),
			0.25,
			3.0
		)

	return 1.0


# Checks whether a temporary event has disabled the sprinkler network.
func _are_sprinklers_disabled_by_event() -> bool:
	var event_system: Node = _get_random_event_system()

	if (
		event_system != null
		and event_system.has_method(
			"are_sprinklers_disabled"
		)
	):
		return bool(event_system.call(
			"are_sprinklers_disabled"
		))

	return false


# ------------------------------------------------------------
# Backward-compatible sprinkler API
# ------------------------------------------------------------

# Returns sprinkler cells through the shared machine registry.
func get_sprinkler_cells() -> Array[Vector2i]:
	return get_machine_cells()


# Checks whether the requested cell contains a sprinkler.
func has_sprinkler(cell: Vector2i) -> bool:
	return has_machine(cell)


# Returns the sprinkler center in world coordinates.
func get_sprinkler_world_position(
	cell: Vector2i
) -> Vector2:
	return get_machine_world_position(cell)


# Finds the nearest sprinkler using the shared machine lookup.
func get_nearest_sprinkler_cell(
	world_position: Vector2,
	max_distance_pixels: float
) -> Variant:
	return get_nearest_machine_cell(
		world_position,
		max_distance_pixels
	)


# Returns the same interval options used by every automation machine.
func get_watering_interval_options() -> Array[int]:
	return get_interval_options()


# Returns the legacy sprinkler-shaped public state.
func get_sprinkler_state(
	cell: Vector2i
) -> Dictionary:
	var output: Dictionary = get_machine_state(cell)

	if output.is_empty():
		return output

	output["next_watering_total_minutes"] = int(
		output.get(
			"next_cycle_total_minutes",
			0
		)
	)
	output.erase("next_cycle_total_minutes")
	output.erase("effect_amount")
	output.erase("cycle_blocked")

	return output


# Returns the current sprinkler level.
func get_sprinkler_level(
	cell: Vector2i
) -> int:
	return get_machine_level(cell)


# Returns the current sprinkler coverage radius.
func get_sprinkler_radius(
	cell: Vector2i
) -> int:
	return get_machine_radius(cell)


# Returns base moisture output before temporary event modifiers.
func get_sprinkler_moisture_per_cycle(
	cell: Vector2i
) -> float:
	return get_machine_effect_amount(cell)


# Checks whether the player has switched this sprinkler ON.
func is_sprinkler_enabled(
	cell: Vector2i
) -> bool:
	return is_machine_enabled(cell)


# Returns the player's selected base watering interval.
func get_sprinkler_interval_minutes(
	cell: Vector2i
) -> int:
	return get_machine_interval_minutes(cell)


# Returns time until the next watering, or -1 when unavailable.
func get_minutes_until_next_watering(
	cell: Vector2i
) -> int:
	return get_minutes_until_next_cycle(cell)


# Returns the cost of the next sprinkler level.
func get_sprinkler_upgrade_cost(
	cell: Vector2i
) -> int:
	return get_upgrade_cost(cell)


# Returns upgrade information in the legacy sprinkler field shape.
func get_sprinkler_upgrade_status(
	cell: Vector2i
) -> Dictionary:
	var result: Dictionary = get_upgrade_status(cell)

	_convert_invalid_reason(result)

	if result.has("next_effect_amount"):
		result["next_moisture_per_cycle"] = float(
			result.get(
				"next_effect_amount",
				0.0
			)
		)
		result.erase("next_effect_amount")

	return result


# Upgrades through the shared automation-machine economy path.
func upgrade_sprinkler(
	cell: Vector2i
) -> Dictionary:
	var result: Dictionary = upgrade_machine(cell)
	_convert_legacy_result_state(
		result,
		cell
	)
	return result


# Changes interval through the shared automation-machine scheduler.
func set_sprinkler_interval(
	cell: Vector2i,
	interval_minutes: int
) -> Dictionary:
	var result: Dictionary = set_machine_interval(
		cell,
		interval_minutes
	)
	_convert_legacy_result_state(
		result,
		cell
	)
	return result


# Changes ON/OFF state through the shared automation-machine scheduler.
func set_sprinkler_enabled(
	cell: Vector2i,
	enabled: bool
) -> Dictionary:
	var result: Dictionary = set_machine_enabled(
		cell,
		enabled
	)
	_convert_legacy_result_state(
		result,
		cell
	)
	return result


# Converts generic invalid-machine errors to the historical sprinkler reason.
func _convert_invalid_reason(
	result: Dictionary
) -> void:
	if String(
		result.get("reason", "")
	) == REASON_INVALID_MACHINE:
		result["reason"] = REASON_INVALID_SPRINKLER


# Keeps mutation result dictionaries compatible with the previous API.
func _convert_legacy_result_state(
	result: Dictionary,
	cell: Vector2i
) -> void:
	_convert_invalid_reason(result)

	if (
		bool(result.get("ok", false))
		and has_machine(cell)
	):
		result["state"] = get_sprinkler_state(
			cell
		)


# ------------------------------------------------------------
# Legacy signal relays
# ------------------------------------------------------------

# Relays shared machine signals to the old sprinkler-specific signal names.
func _connect_legacy_signal_relays() -> void:
	if not machine_state_changed.is_connected(
		_relay_machine_state_changed
	):
		machine_state_changed.connect(
			_relay_machine_state_changed
		)

	if not machine_upgraded.is_connected(
		_relay_machine_upgraded
	):
		machine_upgraded.connect(
			_relay_machine_upgraded
		)

	if not machine_configuration_changed.is_connected(
		_relay_machine_configuration_changed
	):
		machine_configuration_changed.connect(
			_relay_machine_configuration_changed
		)

	if not machine_cycle_completed.is_connected(
		_relay_machine_cycle_completed
	):
		machine_cycle_completed.connect(
			_relay_machine_cycle_completed
		)


# Emits the legacy state signal with legacy field names.
func _relay_machine_state_changed(
	cell: Vector2i,
	_state: Dictionary
) -> void:
	sprinkler_state_changed.emit(
		cell,
		get_sprinkler_state(cell)
	)


# Emits the legacy upgrade signal.
func _relay_machine_upgraded(
	cell: Vector2i,
	previous_level: int,
	new_level: int,
	cost: int
) -> void:
	sprinkler_upgraded.emit(
		cell,
		previous_level,
		new_level,
		cost
	)


# Emits the legacy configuration signal with legacy field names.
func _relay_machine_configuration_changed(
	cell: Vector2i,
	_state: Dictionary
) -> void:
	sprinkler_configuration_changed.emit(
		cell,
		get_sprinkler_state(cell)
	)


# Emits the legacy watering signal after the shared cycle completes.
func _relay_machine_cycle_completed(
	cell: Vector2i,
	affected_zones: int,
	effect_amount: float
) -> void:
	sprinkler_watered.emit(
		cell,
		affected_zones,
		effect_amount
	)
