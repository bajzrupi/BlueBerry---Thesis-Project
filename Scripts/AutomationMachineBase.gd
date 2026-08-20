extends Node
class_name AutomationMachineBase

# Shared backend for every player-built automation machine.
#
# Field Sprinkler, Fertilizer Injector, Soil Neutralizer, and Plant Protection
# Station all use this state/scheduling/upgrade/save architecture. Subclasses
# only keep the behavior that is unique to their own treatment/effect.
#
# Subclasses override:
# - get_machine_build_id()
# - get_machine_display_name()
# - get_effect_amount_for_level()
# - _apply_machine_cycle()
# - optional schedule/event/state/save/visual hooks.

signal machine_state_changed(
	cell: Vector2i,
	state: Dictionary
)

signal machine_upgraded(
	cell: Vector2i,
	previous_level: int,
	new_level: int,
	cost: int
)

signal machine_configuration_changed(
	cell: Vector2i,
	state: Dictionary
)

signal machine_cycle_completed(
	cell: Vector2i,
	affected_zones: int,
	effect_amount: float
)


const MAX_MACHINE_LEVEL: int = 3

const INTERVAL_OPTIONS_MINUTES: Array[int] = [
	60,
	180,
	360,
	720
]

const REASON_INVALID_MACHINE: String = "INVALID_MACHINE"
const REASON_MAX_LEVEL: String = "MAX_LEVEL"
const REASON_INSUFFICIENT_MONEY: String = "INSUFFICIENT_MONEY"
const REASON_INVALID_INTERVAL: String = "INVALID_INTERVAL"


@export_category("Automation Level 1")

@export_range(1, 6, 1)
var level_1_radius_cells: int = 2


@export_category("Automation Level 2")

@export_range(1, 8, 1)
var level_2_radius_cells: int = 3

@export_range(0, 100000, 10)
var upgrade_to_level_2_cost: int = 250


@export_category("Automation Level 3")

@export_range(1, 10, 1)
var level_3_radius_cells: int = 4

@export_range(0, 100000, 10)
var upgrade_to_level_3_cost: int = 600


@export_category("Automation Configuration")

@export_range(60, 1440, 60)
var default_interval_minutes: int = 180


@export_category("Debug Logging")

@export var debug_log: bool = false


var _tilemap: TileMap
var _configured: bool = false

# Authoritative live machine cells rebuilt from BuildSystem.
var _machine_cells: Dictionary = {}

# cell -> per-machine runtime state
var _machine_states: Dictionary = {}

# Optional subclass-created world visuals.
var _machine_nodes: Dictionary = {}

# Runtime visuals must be siblings of Player inside the same Y-sort container.
# A fixed z_index/root under TileMap makes machines render over Player
# regardless of where the Player is standing.
var _visual_parent: Node2D
var _owned_fallback_visual_parent: Node2D


# Initializes this system when the node becomes ready.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	if not BuildSystem.build_cell_placed.is_connected(
		_on_build_cell_placed
	):
		BuildSystem.build_cell_placed.connect(
			_on_build_cell_placed
		)

	if not BuildSystem.build_cell_removed.is_connected(
		_on_build_cell_removed
	):
		BuildSystem.build_cell_removed.connect(
			_on_build_cell_removed
		)

	if not Clock.world_tick.is_connected(
		_on_world_tick
	):
		Clock.world_tick.connect(
			_on_world_tick
		)


# ------------------------------------------------------------
# World binding
# ------------------------------------------------------------

# Connects this system to the current world references.
func configure(tilemap: TileMap) -> void:
	if tilemap == null:
		push_error(
			"[%s] configure received missing TileMap."
			% get_machine_display_name()
		)
		return

	if (
		is_instance_valid(_tilemap)
		and _tilemap != tilemap
	):
		unconfigure(_tilemap)

	_tilemap = tilemap
	_configured = true

	# A newly instanced gameplay world never inherits another Garden's
	# per-machine state. SaveSystem restores it after BuildSystem + Clock.
	_machine_states.clear()

	_create_visual_parent()
	rebuild_from_build_state()

	if debug_log:
		print(
			"[",
			get_machine_display_name(),
			"] configured count=",
			_machine_cells.size()
		)


# Disconnects this system from the current world references.
func unconfigure(tilemap: TileMap) -> void:
	if not is_instance_valid(_tilemap):
		_clear_runtime()
		return

	if _tilemap != tilemap:
		return

	_clear_runtime()

	if debug_log:
		print(
			"[",
			get_machine_display_name(),
			"] unconfigured"
		)


# Clears the runtime.
func _clear_runtime() -> void:
	_clear_visuals()
	_machine_cells.clear()
	_machine_states.clear()

	# Only free the fallback node created by this system. Never free the
	# gameplay scene's shared Entities container.
	if is_instance_valid(_owned_fallback_visual_parent):
		_owned_fallback_visual_parent.queue_free()

	_owned_fallback_visual_parent = null
	_visual_parent = null
	_tilemap = null
	_configured = false


# Rebuilds the from build state.
func rebuild_from_build_state() -> void:
	if (
		not _configured
		or not is_instance_valid(_tilemap)
	):
		return

	_clear_visuals()
	_machine_cells.clear()

	var built_cells: Dictionary = (
		BuildSystem.get_player_built_cells()
	)
	var live_cells: Dictionary = {}
	var build_id: StringName = get_machine_build_id()

	for cell_variant: Variant in built_cells.keys():
		var cell: Vector2i = cell_variant
		var record_variant: Variant = built_cells[cell]

		if typeof(record_variant) != TYPE_DICTIONARY:
			continue

		var record: Dictionary = record_variant
		var object_id := StringName(
			record.get("object_build_id", &"")
		)

		if object_id != build_id:
			continue

		live_cells[cell] = true
		_machine_cells[cell] = true
		_ensure_default_state(cell)

		var visual: Node2D = _create_machine_visual(cell)

		if is_instance_valid(visual):
			_machine_nodes[cell] = visual

	# Remove state belonging to machines that no longer exist.
	for state_cell_variant: Variant in _machine_states.keys():
		var state_cell: Vector2i = state_cell_variant

		if not live_cells.has(state_cell):
			_machine_states.erase(state_cell)

	if debug_log:
		print(
			"[",
			get_machine_display_name(),
			"] rebuilt count=",
			_machine_cells.size(),
			" states=",
			_machine_states.size()
		)


# ------------------------------------------------------------
# Subclass identity / effect hooks
# ------------------------------------------------------------

# Returns the machine build ID.
func get_machine_build_id() -> StringName:
	return &""


# Returns the machine display name.
func get_machine_display_name() -> String:
	return "Automation Machine"


# Returns the effect amount for level.
func get_effect_amount_for_level(
	_level: int
) -> float:
	return 0.0


# Returns the actual cycle effect after temporary modifiers are applied.
func _get_cycle_effect_amount(
	cell: Vector2i
) -> float:
	return get_machine_effect_amount(cell)


# Returns the effective schedule interval after temporary modifiers.
func _get_effective_interval_minutes(
	base_interval_minutes: int
) -> int:
	return maxi(base_interval_minutes, 1)


# Allows a subclass to temporarily block automatic cycles without turning
# the player's machine OFF or advancing its stored schedule.
func _is_machine_cycle_blocked(
	_cell: Vector2i
) -> bool:
	return false


# Returns the serialized key used for the next scheduled cycle timestamp.
# Sprinkler keeps its legacy save key so existing Gardens remain compatible.
func _get_persistence_next_cycle_key() -> String:
	return "next_cycle_total_minutes"


# Allows a subclass to sanitize common schedule data after loading.
func _sanitize_loaded_schedule(
	_entry: Dictionary,
	_state: Dictionary,
	_current_total_minutes: int
) -> void:
	pass


# Apply one cycle to all relevant zones.
# Return the number of zones actually affected.
func _apply_machine_cycle(
	_machine_cell: Vector2i,
	_radius_cells: int,
	_effect_amount: float
) -> int:
	return 0


# Creates the custom default state.
func _make_custom_default_state() -> Dictionary:
	return {}


# Adds machine-specific fields to the public machine state.
func _enrich_public_state(
	_cell: Vector2i,
	_state: Dictionary,
	_output: Dictionary
) -> void:
	pass


# Sanitizes machine-specific data loaded from a save.
func _sanitize_loaded_custom_state(
	_entry: Dictionary,
	_state: Dictionary
) -> void:
	pass


# Appends the custom save fields.
func _append_custom_save_fields(
	_cell: Vector2i,
	_state: Dictionary,
	_entry: Dictionary
) -> void:
	pass


# Creates the machine visual.
func _create_machine_visual(
	_cell: Vector2i
) -> Node2D:
	return null


# Handles the cycle visual signal or callback.
func _on_cycle_visual(
	_machine_cell: Vector2i,
	_affected_zones: int
) -> void:
	pass


# ------------------------------------------------------------
# Public machine API
# ------------------------------------------------------------

# Returns the machine cells.
func get_machine_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	for cell_variant: Variant in _machine_cells.keys():
		result.append(cell_variant)

	return result


# Checks whether machine exists or is available.
func has_machine(cell: Vector2i) -> bool:
	return _machine_cells.has(cell)


# Returns the machine world position.
func get_machine_world_position(
	cell: Vector2i
) -> Vector2:
	if (
		not _configured
		or not is_instance_valid(_tilemap)
		or not has_machine(cell)
	):
		return Vector2.INF

	return _tilemap.to_global(
		_tilemap.map_to_local(cell)
	)


# Returns the nearest machine cell.
func get_nearest_machine_cell(
	world_position: Vector2,
	max_distance_pixels: float
) -> Variant:
	if (
		not _configured
		or not is_instance_valid(_tilemap)
		or max_distance_pixels < 0.0
	):
		return null

	var best_cell: Variant = null
	var best_distance: float = max_distance_pixels

	for cell_variant: Variant in _machine_cells.keys():
		var cell: Vector2i = cell_variant
		var machine_world: Vector2 = get_machine_world_position(
			cell
		)

		if machine_world == Vector2.INF:
			continue

		var distance: float = world_position.distance_to(
			machine_world
		)

		if distance <= best_distance:
			best_distance = distance
			best_cell = cell

	return best_cell


# Returns the interval options.
func get_interval_options() -> Array[int]:
	return INTERVAL_OPTIONS_MINUTES.duplicate()


# Returns the level definition.
func get_level_definition(
	level: int
) -> Dictionary:
	var safe_level: int = clampi(
		level,
		1,
		MAX_MACHINE_LEVEL
	)

	match safe_level:
		2:
			return {
				"level": 2,
				"radius": level_2_radius_cells,
				"effect_amount": get_effect_amount_for_level(2),
				"cost_to_reach": upgrade_to_level_2_cost
			}
		3:
			return {
				"level": 3,
				"radius": level_3_radius_cells,
				"effect_amount": get_effect_amount_for_level(3),
				"cost_to_reach": upgrade_to_level_3_cost
			}
		_:
			return {
				"level": 1,
				"radius": level_1_radius_cells,
				"effect_amount": get_effect_amount_for_level(1),
				"cost_to_reach": 0
			}


# Returns the machine state.
func get_machine_state(
	cell: Vector2i
) -> Dictionary:
	if not has_machine(cell):
		return {}

	_ensure_default_state(cell)

	var state: Dictionary = _machine_states[cell]
	var level: int = clampi(
		int(state.get("level", 1)),
		1,
		MAX_MACHINE_LEVEL
	)
	var definition: Dictionary = get_level_definition(level)
	var output: Dictionary = state.duplicate(true)

	output["cell"] = cell
	output["level"] = level
	output["max_level"] = MAX_MACHINE_LEVEL
	output["radius"] = int(
		definition.get("radius", level_1_radius_cells)
	)
	output["effect_amount"] = float(
		definition.get("effect_amount", 0.0)
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
	output["cycle_blocked"] = _is_machine_cycle_blocked(
		cell
	)
	output["upgrade_cost"] = get_upgrade_cost(cell)
	output["minutes_until_next"] = get_minutes_until_next_cycle(
		cell
	)

	_enrich_public_state(cell, state, output)
	return output


# Returns the machine level.
func get_machine_level(cell: Vector2i) -> int:
	if not has_machine(cell):
		return 0

	_ensure_default_state(cell)

	return clampi(
		int(_machine_states[cell].get("level", 1)),
		1,
		MAX_MACHINE_LEVEL
	)


# Returns the machine radius.
func get_machine_radius(cell: Vector2i) -> int:
	var level: int = get_machine_level(cell)

	if level <= 0:
		return 0

	return int(
		get_level_definition(level).get(
			"radius",
			level_1_radius_cells
		)
	)


# Returns the machine effect amount.
func get_machine_effect_amount(cell: Vector2i) -> float:
	var level: int = get_machine_level(cell)

	if level <= 0:
		return 0.0

	return float(
		get_level_definition(level).get(
			"effect_amount",
			0.0
		)
	)


# Checks whether the machine is enabled.
func is_machine_enabled(cell: Vector2i) -> bool:
	if not has_machine(cell):
		return false

	_ensure_default_state(cell)
	return bool(_machine_states[cell].get("enabled", true))


# Returns the machine interval minutes.
func get_machine_interval_minutes(cell: Vector2i) -> int:
	if not has_machine(cell):
		return 0

	_ensure_default_state(cell)
	return int(
		_machine_states[cell].get(
			"interval_minutes",
			_get_default_interval_minutes()
		)
	)


# Returns the minutes until next cycle.
func get_minutes_until_next_cycle(cell: Vector2i) -> int:
	if not has_machine(cell):
		return -1

	if not is_machine_enabled(cell):
		return -1

	if _is_machine_cycle_blocked(cell):
		return -1

	_ensure_default_state(cell)

	var state: Dictionary = _machine_states[cell]
	var next_total: int = int(
		state.get(
			"next_cycle_total_minutes",
			_get_current_total_minutes()
			+ get_machine_interval_minutes(cell)
		)
	)

	return maxi(
		next_total - _get_current_total_minutes(),
		0
	)


# ------------------------------------------------------------
# Upgrade / configuration
# ------------------------------------------------------------

# Returns the upgrade cost.
func get_upgrade_cost(cell: Vector2i) -> int:
	var current_level: int = get_machine_level(cell)

	if (
		current_level <= 0
		or current_level >= MAX_MACHINE_LEVEL
	):
		return 0

	return maxi(
		int(
			get_level_definition(
				current_level + 1
			).get(
				"cost_to_reach",
				0
			)
		),
		0
	)


# Returns the current get upgrade status result.
func get_upgrade_status(cell: Vector2i) -> Dictionary:
	if not has_machine(cell):
		return {
			"ok": false,
			"reason": REASON_INVALID_MACHINE
		}

	var current_level: int = get_machine_level(cell)

	if current_level >= MAX_MACHINE_LEVEL:
		return {
			"ok": false,
			"reason": REASON_MAX_LEVEL,
			"level": current_level,
			"max_level": MAX_MACHINE_LEVEL,
			"cost": 0
		}

	var next_level: int = current_level + 1
	var definition: Dictionary = get_level_definition(next_level)
	var cost: int = get_upgrade_cost(cell)

	if not EconomySystem.can_afford(cost):
		return {
			"ok": false,
			"reason": REASON_INSUFFICIENT_MONEY,
			"level": current_level,
			"next_level": next_level,
			"cost": cost,
			"available_money": EconomySystem.get_money(),
			"next_radius": int(definition.get("radius", 0)),
			"next_effect_amount": float(
				definition.get("effect_amount", 0.0)
			)
		}

	return {
		"ok": true,
		"reason": "",
		"level": current_level,
		"next_level": next_level,
		"cost": cost,
		"available_money": EconomySystem.get_money(),
		"next_radius": int(definition.get("radius", 0)),
		"next_effect_amount": float(
			definition.get("effect_amount", 0.0)
		)
	}


# Upgrades the machine.
func upgrade_machine(cell: Vector2i) -> Dictionary:
	var status: Dictionary = get_upgrade_status(cell)

	if not bool(status.get("ok", false)):
		return status

	var previous_level: int = get_machine_level(cell)
	var new_level: int = previous_level + 1
	var cost: int = int(status.get("cost", 0))

	if not EconomySystem.spend_money(
		cost,
		"%s_UPGRADE_%d_%d_L%d"
		% [
			String(get_machine_build_id()).to_upper(),
			cell.x,
			cell.y,
			new_level
		]
	):
		return {
			"ok": false,
			"reason": REASON_INSUFFICIENT_MONEY,
			"level": previous_level,
			"cost": cost,
			"available_money": EconomySystem.get_money()
		}

	var state: Dictionary = _machine_states[cell]
	state["level"] = new_level
	_machine_states[cell] = state

	var public_state: Dictionary = get_machine_state(cell)

	machine_upgraded.emit(
		cell,
		previous_level,
		new_level,
		cost
	)
	machine_state_changed.emit(cell, public_state)

	return {
		"ok": true,
		"cell": cell,
		"previous_level": previous_level,
		"new_level": new_level,
		"cost": cost,
		"state": public_state
	}


# Sets the machine interval.
func set_machine_interval(
	cell: Vector2i,
	interval_minutes: int
) -> Dictionary:
	if not has_machine(cell):
		return {
			"ok": false,
			"reason": REASON_INVALID_MACHINE
		}

	if not INTERVAL_OPTIONS_MINUTES.has(interval_minutes):
		return {
			"ok": false,
			"reason": REASON_INVALID_INTERVAL,
			"allowed": get_interval_options()
		}

	_ensure_default_state(cell)

	var state: Dictionary = _machine_states[cell]
	var previous_interval: int = int(
		state.get(
			"interval_minutes",
			_get_default_interval_minutes()
		)
	)

	state["interval_minutes"] = interval_minutes

	if bool(state.get("enabled", true)):
		state["next_cycle_total_minutes"] = (
			_get_current_total_minutes()
			+ _get_effective_interval_minutes(
				interval_minutes
			)
		)

	_machine_states[cell] = state

	var public_state: Dictionary = get_machine_state(cell)
	machine_configuration_changed.emit(cell, public_state)
	machine_state_changed.emit(cell, public_state)

	return {
		"ok": true,
		"cell": cell,
		"previous_interval": previous_interval,
		"interval_minutes": interval_minutes,
		"state": public_state
	}


# Sets the machine enabled.
func set_machine_enabled(
	cell: Vector2i,
	enabled: bool
) -> Dictionary:
	if not has_machine(cell):
		return {
			"ok": false,
			"reason": REASON_INVALID_MACHINE
		}

	_ensure_default_state(cell)

	var state: Dictionary = _machine_states[cell]
	var previous_enabled: bool = bool(
		state.get("enabled", true)
	)

	state["enabled"] = enabled

	if enabled and not previous_enabled:
		var base_interval: int = int(
			state.get(
				"interval_minutes",
				_get_default_interval_minutes()
			)
		)
		state["next_cycle_total_minutes"] = (
			_get_current_total_minutes()
			+ _get_effective_interval_minutes(
				base_interval
			)
		)

	_machine_states[cell] = state

	var public_state: Dictionary = get_machine_state(cell)
	machine_configuration_changed.emit(cell, public_state)
	machine_state_changed.emit(cell, public_state)

	return {
		"ok": true,
		"cell": cell,
		"previous_enabled": previous_enabled,
		"enabled": enabled,
		"state": public_state
	}


# Reschedules all machine cycles from the current game time.
func reschedule_all_from_now() -> void:
	if not _configured:
		return

	var current_total: int = _get_current_total_minutes()

	for cell_variant: Variant in _machine_states.keys():
		var cell: Vector2i = cell_variant
		var state: Dictionary = _machine_states[cell]

		if not bool(state.get("enabled", true)):
			continue

		var base_interval: int = maxi(
			int(
				state.get(
					"interval_minutes",
					_get_default_interval_minutes()
				)
			),
			1
		)
		state["next_cycle_total_minutes"] = (
			current_total
			+ _get_effective_interval_minutes(
				base_interval
			)
		)
		_machine_states[cell] = state

		machine_state_changed.emit(
			cell,
			get_machine_state(cell)
		)


# ------------------------------------------------------------
# Persistence
# ------------------------------------------------------------

# Returns the serializable state of this system.
func get_save_state() -> Array[Dictionary]:
	var result: Array[Dictionary] = []

	for cell_variant: Variant in _machine_cells.keys():
		var cell: Vector2i = cell_variant
		_ensure_default_state(cell)

		var state: Dictionary = _machine_states[cell]
		var interval: int = int(
			state.get(
				"interval_minutes",
				_get_default_interval_minutes()
			)
		)
		var entry: Dictionary = {
			"x": cell.x,
			"y": cell.y,
			"level": clampi(
				int(state.get("level", 1)),
				1,
				MAX_MACHINE_LEVEL
			),
			"interval_minutes": interval,
			"enabled": bool(
				state.get("enabled", true)
			)
		}

		entry[_get_persistence_next_cycle_key()] = int(
			state.get(
				"next_cycle_total_minutes",
				_get_current_total_minutes()
				+ _get_effective_interval_minutes(
					interval
				)
			)
		)

		_append_custom_save_fields(
			cell,
			state,
			entry
		)
		result.append(entry)

	return result


# Restores this system from saved data.
func load_save_state(entries: Array) -> bool:
	if (
		not _configured
		or not is_instance_valid(_tilemap)
	):
		push_warning(
			"[%s] load_save_state rejected: world is not configured."
			% get_machine_display_name()
		)
		return false

	# BuildSystem has already restored the authoritative object cells.
	rebuild_from_build_state()

	var saved_by_cell: Dictionary = {}

	for entry_variant: Variant in entries:
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue

		var entry: Dictionary = entry_variant
		var cell := Vector2i(
			int(entry.get("x", 0)),
			int(entry.get("y", 0))
		)
		saved_by_cell[cell] = entry

	for cell_variant: Variant in _machine_cells.keys():
		var cell: Vector2i = cell_variant

		if not saved_by_cell.has(cell):
			_ensure_default_state(cell)
			continue

		var entry: Dictionary = saved_by_cell[cell]
		var interval: int = int(
			entry.get(
				"interval_minutes",
				_get_default_interval_minutes()
			)
		)

		if not INTERVAL_OPTIONS_MINUTES.has(interval):
			interval = _get_default_interval_minutes()

		var state: Dictionary = _make_default_state()
		var current_total: int = _get_current_total_minutes()

		state["level"] = clampi(
			int(entry.get("level", 1)),
			1,
			MAX_MACHINE_LEVEL
		)
		state["interval_minutes"] = interval
		state["enabled"] = bool(
			entry.get("enabled", true)
		)
		state["next_cycle_total_minutes"] = maxi(
			int(
				entry.get(
					_get_persistence_next_cycle_key(),
					current_total
					+ _get_effective_interval_minutes(
						interval
					)
				)
			),
			0
		)

		_sanitize_loaded_schedule(
			entry,
			state,
			current_total
		)
		_sanitize_loaded_custom_state(
			entry,
			state
		)
		_machine_states[cell] = state

		machine_state_changed.emit(
			cell,
			get_machine_state(cell)
		)

	return true


# ------------------------------------------------------------
# Clock simulation
# ------------------------------------------------------------

# Processes one world simulation tick.
func _on_world_tick(
	day: int,
	minute_of_day: int,
	delta_minutes: int
) -> void:
	if (
		not _configured
		or delta_minutes <= 0
		or _machine_cells.is_empty()
	):
		return

	var current_total: int = _total_minutes(
		day,
		minute_of_day
	)

	for cell_variant: Variant in _machine_cells.keys():
		var cell: Vector2i = cell_variant

		if not is_machine_enabled(cell):
			continue

		if _is_machine_cycle_blocked(cell):
			continue

		_ensure_default_state(cell)

		var state: Dictionary = _machine_states[cell]
		var base_interval: int = maxi(
			int(
				state.get(
					"interval_minutes",
					_get_default_interval_minutes()
				)
			),
			1
		)
		var interval: int = _get_effective_interval_minutes(
			base_interval
		)
		var next_total: int = int(
			state.get(
				"next_cycle_total_minutes",
				current_total + interval
			)
		)

		if next_total <= 0:
			next_total = current_total + interval

		if current_total < next_total:
			continue

		var cycles_due: int = (
			floori(
				float(current_total - next_total)
				/ float(interval)
			)
			+ 1
		)

		for _cycle_index: int in range(
			maxi(cycles_due, 1)
		):
			_run_single_cycle(cell)

		state = _machine_states[cell]
		state["next_cycle_total_minutes"] = (
			next_total
			+ maxi(cycles_due, 1) * interval
		)
		_machine_states[cell] = state

		machine_state_changed.emit(
			cell,
			get_machine_state(cell)
		)


# Executes one automation machine cycle.
func _run_single_cycle(cell: Vector2i) -> void:
	if not has_machine(cell):
		return

	if _is_machine_cycle_blocked(cell):
		return

	var radius: int = get_machine_radius(cell)
	var effect_amount: float = _get_cycle_effect_amount(
		cell
	)
	var affected_zones: int = _apply_machine_cycle(
		cell,
		radius,
		effect_amount
	)

	if affected_zones > 0:
		_on_cycle_visual(
			cell,
			affected_zones
		)

	machine_cycle_completed.emit(
		cell,
		affected_zones,
		effect_amount
	)

	if debug_log:
		print(
			"[",
			get_machine_display_name(),
			"] cycle cell=",
			cell,
			" L",
			get_machine_level(cell),
			" radius=",
			radius,
			" effect=",
			effect_amount,
			" zones=",
			affected_zones
		)


# Connected biome zones are collected at most once per machine cycle.
func collect_covered_zones(
	center_cell: Vector2i,
	radius_cells: int
) -> Dictionary:
	var result: Dictionary = {}
	var safe_radius: int = maxi(
		radius_cells,
		0
	)

	for y_offset: int in range(
		-safe_radius,
		safe_radius + 1
	):
		for x_offset: int in range(
			-safe_radius,
			safe_radius + 1
		):
			var cell := center_cell + Vector2i(
				x_offset,
				y_offset
			)
			var zone_id: int = BiomeSystem.get_zone_id(
				cell
			)

			if zone_id < 0:
				continue

			if not result.has(zone_id):
				result[zone_id] = cell

	return result


# ------------------------------------------------------------
# State / time helpers
# ------------------------------------------------------------

# Ensures the default state exists and is ready to use.
func _ensure_default_state(cell: Vector2i) -> void:
	if _machine_states.has(cell):
		return

	_machine_states[cell] = _make_default_state()


# Creates the default state.
func _make_default_state() -> Dictionary:
	var interval: int = _get_default_interval_minutes()
	var state: Dictionary = {
		"level": 1,
		"interval_minutes": interval,
		"enabled": true,
		"next_cycle_total_minutes": (
			_get_current_total_minutes()
			+ _get_effective_interval_minutes(
				interval
			)
		)
	}

	var custom: Dictionary = _make_custom_default_state()

	for key_variant: Variant in custom.keys():
		state[key_variant] = custom[key_variant]

	return state


# Returns the default interval minutes.
func _get_default_interval_minutes() -> int:
	if INTERVAL_OPTIONS_MINUTES.has(
		default_interval_minutes
	):
		return default_interval_minutes

	return 180


# Returns the current total minutes.
func _get_current_total_minutes() -> int:
	return _total_minutes(
		Clock.day,
		Clock.minute_of_day
	)


# Returns the current game time as total minutes.
func _total_minutes(
	day: int,
	minute_of_day: int
) -> int:
	return maxi(day - 1, 0) * 1440 + clampi(
		minute_of_day,
		0,
		1439
	)


# ------------------------------------------------------------
# Build / visuals
# ------------------------------------------------------------

# Creates the visual parent.
func _create_visual_parent() -> void:
	if not is_instance_valid(_tilemap):
		return

	if is_instance_valid(_visual_parent):
		return

	_visual_parent = null
	_owned_fallback_visual_parent = null

	var current_scene: Node = get_tree().current_scene

	# Preferred path: Player already lives here in test_level.tscn.
	if current_scene != null:
		var entities_node: Node = current_scene.get_node_or_null(
			"WorldObjects/Entities"
		)

		if (
			is_instance_valid(entities_node)
			and entities_node is Node2D
		):
			_visual_parent = entities_node as Node2D

	# Fallback: find Player and use its Node2D parent.
	if _visual_parent == null and current_scene != null:
		var player_node: Node = current_scene.find_child(
			"Player",
			true,
			false
		)

		if (
			is_instance_valid(player_node)
			and is_instance_valid(player_node.get_parent())
			and player_node.get_parent() is Node2D
		):
			_visual_parent = player_node.get_parent() as Node2D

	if is_instance_valid(_visual_parent):
		_visual_parent.y_sort_enabled = true

		if debug_log:
			print(
				"[",
				get_machine_display_name(),
				"] visual parent=",
				_visual_parent.get_path(),
				" y_sort=",
				_visual_parent.y_sort_enabled
			)
		return

	# Last-resort fallback for unusual test scenes.
	var fallback := Node2D.new()
	fallback.name = (
		"%sRuntimeVisuals"
		% String(get_machine_build_id()).to_pascal_case()
	)
	fallback.y_sort_enabled = true

	var parent_candidate: Node = _tilemap.get_parent()

	if (
		is_instance_valid(parent_candidate)
		and parent_candidate is Node
	):
		parent_candidate.add_child(fallback)
	else:
		_tilemap.add_child(fallback)

	_visual_parent = fallback
	_owned_fallback_visual_parent = fallback

	push_warning(
		"[%s] Player Y-sort parent was not found; using fallback visual parent."
		% get_machine_display_name()
	)


# Positions a machine so its visible sprite remains centered on its build cell,
# while the Y-sort origin is at the BOTTOM of that cell. This matches the
# Player's feet-based sort origin and gives correct front/behind ordering.
func position_machine_visual_for_y_sort(
	holder: Node2D,
	sprite: CanvasItem,
	cell: Vector2i
) -> void:
	if (
		not is_instance_valid(_tilemap)
		or not is_instance_valid(_visual_parent)
		or not is_instance_valid(holder)
		or not is_instance_valid(sprite)
	):
		return

	var tile_size := Vector2(
		_tilemap.tile_set.tile_size
	)
	var target_world_position: Vector2 = _tilemap.to_global(
		_tilemap.map_to_local(cell)
	)
	var sort_offset := Vector2(
		0.0,
		tile_size.y * 0.5
	)

	holder.global_position = (
		target_world_position
		+ sort_offset
	)

	if sprite is Node2D:
		(sprite as Node2D).position = -sort_offset


# Clears the visuals.
func _clear_visuals() -> void:
	for node_variant: Variant in _machine_nodes.values():
		# Scene changes may leave a freed Object in this Variant for a frame.
		# Validate first; using `is` on a freed instance raises a runtime error.
		if (
			is_instance_valid(node_variant)
			and node_variant is Node
		):
			(node_variant as Node).queue_free()

	_machine_nodes.clear()


# Handles the build cell placed signal or callback.
func _on_build_cell_placed(
	cell: Vector2i,
	build_id: StringName,
	_cost: int
) -> void:
	if build_id != get_machine_build_id():
		return

	# A newly placed machine always starts from its own default state.
	_machine_states[cell] = _make_default_state()
	call_deferred("rebuild_from_build_state")


# Handles the build cell removed signal or callback.
func _on_build_cell_removed(
	cell: Vector2i,
	build_id: StringName,
	_refund: int
) -> void:
	if build_id != get_machine_build_id():
		return

	_machine_states.erase(cell)
	call_deferred("rebuild_from_build_state")
