extends Node

# Announces runtime zone topology changes after map building.
signal zones_rebuilt(zone_count: int)

# Biome zone simulation parameters and runtime zone state

# Zone default values
const ZONE_NUMERIC_KEYS: Array[String] = [
	"moisture",
	"nutrients",
	"ph",
	"humidity",
	"temperature",
	"light",
	"pest_pressure",
	"disease_pressure"
]

@export var default_moisture_loamy: float = 0.70
@export var default_moisture_sandy: float = 0.30
@export var default_nutrients_loamy: float = 0.65
@export var default_nutrients_sandy: float = 0.40


@export var water_retention_loamy: float = 0.85
@export var water_retention_sandy: float = 0.70
@export var nutrient_retention_loamy: float = 0.80
@export var nutrient_retention_sandy: float = 0.40


@export var base_moisture_loss_per_hour: float = 0.025
@export var base_nutrients_loss_per_hour: float = 0.008


@export var default_ph_loamy: float = 6.8
@export var default_ph_sandy: float = 7.4

# Long-term natural soil chemistry targets.
# Loamy slowly acidifies; Sandy slowly becomes more alkaline.
@export var ph_drift_target_loamy: float = 5.4
@export var ph_drift_target_sandy: float = 8.6

@export var ph_buffer_loamy: float = 0.80
@export var ph_buffer_sandy: float = 0.40

# Autonomous pH movement per in-game day before buffering and Terrain effects.
@export var base_ph_drift_per_day: float = 0.25


@export var pressure_adjust_per_day: float = 0.60


@export_category("Terrain Progression Effects")

# Maximum reduction to natural moisture loss at Terrain Level 5.
@export_range(0.0, 0.90, 0.01)
var terrain_moisture_loss_reduction_at_max: float = 0.40

# Maximum reduction to natural nutrient loss at Terrain Level 5.
@export_range(0.0, 0.90, 0.01)
var terrain_nutrient_loss_reduction_at_max: float = 0.40

# Maximum bonus to watering and fertilizing efficiency at Terrain Level 5.
@export_range(0.0, 1.00, 0.01)
var terrain_treatment_bonus_at_max: float = 0.20

# Maximum reduction to autonomous pH drift at Terrain Level 5.
@export_range(0.0, 0.90, 0.01)
var terrain_ph_drift_reduction_at_max: float = 0.40

# Maximum reduction to climate-driven pest and disease pressure at Terrain Level 5.
@export_range(0.0, 0.90, 0.01)
var terrain_bio_pressure_reduction_at_max: float = 0.30


# Zone stat bounds
const MOISTURE_MIN := 0.0
const MOISTURE_MAX := 1.0
const NUTRIENTS_MIN := 0.0
const NUTRIENTS_MAX := 1.0
const PH_MIN := 0.0
const PH_MAX := 14.0


# Zone maps and runtime state
var _tilemap: TileMap
var _plantable_layer: int = -1

var _cell_to_zone := {}
var _zone_stats := {}
var _next_zone_id: int = 1


# Global climate cache
var global_temperature: float = 20.0
var global_humidity: float = 0.5
var global_light: float = 1.0

# Build zone data from the TileMap plantable layer
func init_from_tilemap(tilemap: TileMap, plantable_layer_name: String = "Plantable") -> void:
	_tilemap = tilemap
	_plantable_layer = _find_layer_by_name(_tilemap, plantable_layer_name)
	if _plantable_layer == -1:
		push_warning("BiomeSystem: Plantable layer not found: %s" % plantable_layer_name)
		return
	_build_zones()


# Rebuilds soil zones after runtime TileMap edits while preserving existing stats.
func refresh_from_tilemap_preserving_stats() -> void:
	if _tilemap == null or _plantable_layer == -1:
		return

	var cell_snapshot: Dictionary = _capture_cell_zone_stats()
	_build_zones()
	_restore_zone_stats_from_cells(cell_snapshot)
	zones_rebuilt.emit(_zone_stats.size())


# Update zone soil stats and pressure over time
func on_world_tick(_day: int, _minute_of_day: int, delta_minutes: int) -> void:
	if _zone_stats.size() == 0:
		return

	var hours := float(delta_minutes) / 60.0
	var days := float(delta_minutes) / (24.0 * 60.0)
	var random_event_drying_multiplier: float = (
		_get_random_event_drying_multiplier()
	)

	for zid in _zone_stats.keys():
		var st: Dictionary = _zone_stats[zid]
		var soil: String = st.get("soil_type", "")

		var wret := _water_retention_for_soil(soil)
		var nret := _nutrient_retention_for_soil(soil)


		var moisture_loss_multiplier: float = _terrain_loss_multiplier(
			soil,
			terrain_moisture_loss_reduction_at_max
		)
		var nutrient_loss_multiplier: float = _terrain_loss_multiplier(
			soil,
			terrain_nutrient_loss_reduction_at_max
		)

		var moisture_loss: float = (
			base_moisture_loss_per_hour
			* (1.0 - wret)
			* moisture_loss_multiplier
			* random_event_drying_multiplier
		)
		var nutrients_loss: float = (
			base_nutrients_loss_per_hour
			* (1.0 - nret)
			* nutrient_loss_multiplier
		)

		# Terrain upgrades reduce natural soil-stat decay without changing soil type.
		st["moisture"] = clamp(
			float(st.get("moisture", 0.5)) - moisture_loss * hours,
			MOISTURE_MIN,
			MOISTURE_MAX
		)
		st["nutrients"] = clamp(
			float(st.get("nutrients", 0.5)) - nutrients_loss * hours,
			NUTRIENTS_MIN,
			NUTRIENTS_MAX
		)



		# Natural pH stress:
		# - Loamy zones slowly acidify.
		# - Sandy zones slowly become more alkaline.
		#
		# The previous implementation drifted back toward the safe starting
		# baseline, so normal play almost never required Lime or Acid.
		var ph := float(st.get("ph", 7.0))
		var drift_target := _ph_drift_target_for_soil(soil)
		var buffer := _ph_buffer_for_soil(soil)

		# Buffering still helps, but does not almost completely suppress
		# natural pH movement.
		var sensitivity: float = (
			1.0
			- 0.5 * clamp(buffer, 0.0, 0.95)
		)

		var ph_drift_multiplier: float = _terrain_loss_multiplier(
			soil,
			terrain_ph_drift_reduction_at_max
		)
		var step: float = (
			base_ph_drift_per_day
			* sensitivity
			* days
			* ph_drift_multiplier
		)

		if ph < drift_target:
			ph = min(drift_target, ph + step)
		elif ph > drift_target:
			ph = max(drift_target, ph - step)

		st["ph"] = clamp(ph, PH_MIN, PH_MAX)



		# Move pressure toward climate-driven targets
		var pressure_multiplier: float = _terrain_loss_multiplier(
			soil,
			terrain_bio_pressure_reduction_at_max
		)
		var pest_target: float = _compute_pest_target(st) * pressure_multiplier
		var disease_target: float = _compute_disease_target(st) * pressure_multiplier

		var k: float = clamp(pressure_adjust_per_day * days, 0.0, 1.0)
		st["pest_pressure"] = lerp(float(st.get("pest_pressure", 0.0)), pest_target, k)
		st["disease_pressure"] = lerp(float(st.get("disease_pressure", 0.0)), disease_target, k)

		_zone_stats[zid] = st


# Apply global climate values to all zones
func set_global_climate(temp_c: float, humidity_0_1: float, light_0_1: float) -> void:
	# Store global climate and propagate to zones
	global_temperature = temp_c
	global_humidity = clamp(humidity_0_1, 0.0, 1.0)
	global_light = clamp(light_0_1, 0.0, 1.0)

	if _zone_stats.size() == 0:
		return
	for zid in _zone_stats.keys():
		var st: Dictionary = _zone_stats[zid]
		st["temperature"] = temp_c
		st["humidity"] = clamp(humidity_0_1, 0.0, 1.0)
		st["light"] = clamp(light_0_1, 0.0, 1.0)
		_zone_stats[zid] = st

# Apply moisture delta to every zone
func add_moisture_to_all_zones(amount: float) -> void:
	if _zone_stats.size() == 0:
		return
	for zid in _zone_stats.keys():
		var st: Dictionary = _zone_stats[zid]
		var soil: String = st.get("soil_type", "")
		var wret: float = _water_retention_for_soil(soil)
		var treatment_multiplier: float = _terrain_treatment_multiplier(soil)
		st["moisture"] = clamp(
			float(st.get("moisture", 0.5))
			+ amount * wret * treatment_multiplier,
			MOISTURE_MIN,
			MOISTURE_MAX
		)
		_zone_stats[zid] = st


# Map a cell to its zone id
func get_zone_id(cell: Vector2i) -> int:
	return int(_cell_to_zone.get(cell, -1))

# Get the zone stats dictionary for a cell
func get_zone_stats(cell: Vector2i) -> Dictionary:
	var zid := get_zone_id(cell)
	return {} if zid == -1 else _zone_stats.get(zid, {})

# Get zone moisture value for a cell
func get_moisture(cell: Vector2i) -> float:
	var st := get_zone_stats(cell)
	return float(st.get("moisture", -1.0)) if not st.is_empty() else -1.0

# Get zone nutrient value for a cell
func get_nutrients(cell: Vector2i) -> float:
	var st := get_zone_stats(cell)
	return float(st.get("nutrients", -1.0)) if not st.is_empty() else -1.0

# Get zone pH value for a cell
func get_ph(cell: Vector2i) -> float:
	var st := get_zone_stats(cell)
	return float(st.get("ph", -1.0)) if not st.is_empty() else -1.0

# Get pest pressure value for a cell
func get_pest_pressure(cell: Vector2i) -> float:
	var st := get_zone_stats(cell)
	return float(st.get("pest_pressure", 0.0)) if not st.is_empty() else 0.0

# Get disease pressure value for a cell
func get_disease_pressure(cell: Vector2i) -> float:
	var st := get_zone_stats(cell)
	return float(st.get("disease_pressure", 0.0)) if not st.is_empty() else 0.0

# Add moisture to the zone containing the cell
func add_moisture(cell: Vector2i, amount: float) -> void:
	var zid := get_zone_id(cell)
	if zid == -1:
		return
	var st: Dictionary = _zone_stats[zid]
	var soil: String = st.get("soil_type", "")
	var wret: float = _water_retention_for_soil(soil)
	var treatment_multiplier: float = _terrain_treatment_multiplier(soil)
	st["moisture"] = clamp(
		float(st.get("moisture", 0.5))
		+ amount * wret * treatment_multiplier,
		MOISTURE_MIN,
		MOISTURE_MAX
	)
	_zone_stats[zid] = st

# Add nutrients to the zone containing the cell
func add_nutrients(cell: Vector2i, amount: float) -> void:
	var zid := get_zone_id(cell)
	if zid == -1:
		return
	var st: Dictionary = _zone_stats[zid]
	var soil: String = st.get("soil_type", "")
	var nret: float = _nutrient_retention_for_soil(soil)
	var treatment_multiplier: float = _terrain_treatment_multiplier(soil)
	st["nutrients"] = clamp(
		float(st.get("nutrients", 0.5))
		+ amount * nret * treatment_multiplier,
		NUTRIENTS_MIN,
		NUTRIENTS_MAX
	)
	_zone_stats[zid] = st

# Add pH delta to the zone containing the cell with buffering
func add_ph(cell: Vector2i, delta_pH: float) -> void:
	var zid := get_zone_id(cell)
	if zid == -1:
		return
	var st: Dictionary = _zone_stats[zid]
	var soil: String = st.get("soil_type", "")
	var buffer := _ph_buffer_for_soil(soil)
	var applied = delta_pH * (1.0 - clamp(buffer, 0.0, 0.95))
	st["ph"] = clamp(float(st.get("ph", 7.0)) + applied, PH_MIN, PH_MAX)
	_zone_stats[zid] = st


# Compute target pest pressure from climate and soil stats
func _compute_pest_target(st: Dictionary) -> float:

	var temp := float(st.get("temperature", 20.0))
	var light := float(st.get("light", 0.7))
	var nutr := float(st.get("nutrients", 0.5))
	var hum := float(st.get("humidity", 0.5))

	var t := 0.0
	t += clamp((temp - 22.0) / 10.0, 0.0, 1.0) * 0.35
	t += clamp((light - 0.6) / 0.4, 0.0, 1.0) * 0.25
	t += clamp((nutr - 0.5) / 0.5, 0.0, 1.0) * 0.30
	t += clamp((hum - 0.55) / 0.45, 0.0, 1.0) * 0.10
	return clamp(t, 0.0, 1.0)

# Compute target disease pressure from climate and soil stats
func _compute_disease_target(st: Dictionary) -> float:

	var temp := float(st.get("temperature", 20.0))
	var hum := float(st.get("humidity", 0.5))
	var moist := float(st.get("moisture", 0.5))
	var light := float(st.get("light", 0.7))

	var t := 0.0
	t += clamp((hum - 0.60) / 0.40, 0.0, 1.0) * 0.40
	t += clamp((moist - 0.70) / 0.30, 0.0, 1.0) * 0.40

	var temp_score = 1.0 - clamp(abs(temp - 22.0) / 10.0, 0.0, 1.0)
	t += temp_score * 0.15

	t += clamp((0.6 - light) / 0.6, 0.0, 1.0) * 0.05
	return clamp(t, 0.0, 1.0)


# Flood-fill connected plantable cells into soil zones
func _build_zones() -> void:
	# Flood-fill plantable cells into connected soil zones
	_cell_to_zone.clear()
	_zone_stats.clear()
	_next_zone_id = 1

	var used: Rect2i = _tilemap.get_used_rect()
	if used.size == Vector2i.ZERO:
		push_warning("BiomeSystem: TileMap used_rect empty.")
		return

	var visited := {}

	for y in range(used.position.y, used.position.y + used.size.y):
		for x in range(used.position.x, used.position.x + used.size.x):
			var c := Vector2i(x, y)
			if visited.has(c):
				continue

			var td: TileData = _tilemap.get_cell_tile_data(_plantable_layer, c)
			if td == null:
				continue

			var soil: String = get_soil_type_at_cell(c)
			if soil == "":
				soil = "unknown"

			var zid := _next_zone_id
			_next_zone_id += 1
			_flood_fill_zone(c, soil, zid, visited)

			_zone_stats[zid] = {
				"soil_type": soil,
				"moisture": (default_moisture_loamy if soil == "loamy" else default_moisture_sandy),
				"nutrients": (default_nutrients_loamy if soil == "loamy" else default_nutrients_sandy),
				"ph": _ph_baseline_for_soil(soil),
				"humidity": global_humidity,
				"temperature": global_temperature,
				"light": global_light,
				"pest_pressure": 0.0,
				"disease_pressure": 0.0,
			}

# Captures effective cell stats before rebuilding zone topology.
func _capture_cell_zone_stats() -> Dictionary:
	var snapshot: Dictionary = {}

	for cell_variant: Variant in _cell_to_zone.keys():
		var cell: Vector2i = cell_variant
		var zid: int = int(
			_cell_to_zone.get(cell, -1)
		)
		var stats: Dictionary = _zone_stats.get(
			zid,
			{}
		)

		if not stats.is_empty():
			snapshot[cell] = stats.duplicate(true)

	return snapshot


# Restores old conditions to rebuilt zones using area-weighted cell samples.
func _restore_zone_stats_from_cells(
	snapshot: Dictionary
) -> void:
	if snapshot.is_empty() or _zone_stats.is_empty():
		return

	var sums_by_zone: Dictionary = {}
	var counts_by_zone: Dictionary = {}

	for cell_variant: Variant in _cell_to_zone.keys():
		var cell: Vector2i = cell_variant

		if not snapshot.has(cell):
			continue

		var zid: int = int(
			_cell_to_zone.get(cell, -1)
		)
		var new_stats: Dictionary = _zone_stats.get(
			zid,
			{}
		)
		var old_stats: Dictionary = snapshot[cell]

		if (
			String(old_stats.get("soil_type", ""))
			!= String(new_stats.get("soil_type", ""))
		):
			continue

		if not sums_by_zone.has(zid):
			var sums: Dictionary = {}

			for key: String in ZONE_NUMERIC_KEYS:
				sums[key] = 0.0

			sums_by_zone[zid] = sums
			counts_by_zone[zid] = 0

		var zone_sums: Dictionary = sums_by_zone[zid]

		for key: String in ZONE_NUMERIC_KEYS:
			zone_sums[key] = (
				float(zone_sums.get(key, 0.0))
				+ float(old_stats.get(
					key,
					new_stats.get(key, 0.0)
				))
			)

		sums_by_zone[zid] = zone_sums
		counts_by_zone[zid] = (
			int(counts_by_zone.get(zid, 0))
			+ 1
		)

	for zid_variant: Variant in sums_by_zone.keys():
		var zid: int = int(zid_variant)
		var count: int = int(
			counts_by_zone.get(zid, 0)
		)

		if count <= 0:
			continue

		var stats: Dictionary = _zone_stats[zid]
		var sums: Dictionary = sums_by_zone[zid]

		for key: String in ZONE_NUMERIC_KEYS:
			stats[key] = (
				float(sums.get(key, 0.0))
				/ float(count)
			)

		_zone_stats[zid] = stats


# Flood-fill helper for zone construction
func _flood_fill_zone(start: Vector2i, soil: String, zid: int, visited: Dictionary) -> void:
	var q: Array[Vector2i] = [start]
	visited[start] = true

	while q.size() > 0:
		var c = q.pop_front()
		_cell_to_zone[c] = zid

		for n in [Vector2i(c.x+1, c.y), Vector2i(c.x-1, c.y), Vector2i(c.x, c.y+1), Vector2i(c.x, c.y-1)]:
			if visited.has(n):
				continue
			var td: TileData = _tilemap.get_cell_tile_data(_plantable_layer, n)
			if td == null:
				continue
			var s: String = get_soil_type_at_cell(n)
			if s == "":
				s = "unknown"
			if s != soil:
				continue
			visited[n] = true
			q.append(n)

# Returns the effective soil type for one cell.
# Player-built visual edge tiles use a BuildSystem override because the
# original atlas edge variants do not all contain TileData soil metadata.
func get_soil_type_at_cell(cell: Vector2i) -> String:
	if BuildSystem.has_method("get_built_soil_type"):
		var built_soil: String = BuildSystem.get_built_soil_type(cell)

		if built_soil != "":
			return built_soil

	if _tilemap == null or _plantable_layer < 0:
		return ""

	var td: TileData = _tilemap.get_cell_tile_data(
		_plantable_layer,
		cell
	)

	if td == null:
		return ""

	return _get_soil_type(td)


# Read soil type from TileData custom data
func _get_soil_type(td: TileData) -> String:
	var v = td.get_custom_data("soil_type")
	return "" if v == null else str(v)

# Returns the gameplay modifiers for one soil type and terrain level.
func get_terrain_effects(
	soil: String,
	level_override: int = -1
) -> Dictionary:
	var level: int = (
		_terrain_level_for_soil(soil)
		if level_override < 1
		else clampi(
			level_override,
			1,
			ProgressionSystem.MAX_TERRAIN_LEVEL
		)
	)
	var progress: float = _terrain_progress_for_level(level)

	return {
		"soil": soil,
		"level": level,
		"max_level": ProgressionSystem.MAX_TERRAIN_LEVEL,
		"moisture_loss_reduction": (
			terrain_moisture_loss_reduction_at_max * progress
		),
		"nutrient_loss_reduction": (
			terrain_nutrient_loss_reduction_at_max * progress
		),
		"treatment_bonus": (
			terrain_treatment_bonus_at_max * progress
		),
		"ph_drift_reduction": (
			terrain_ph_drift_reduction_at_max * progress
		),
		"bio_pressure_reduction": (
			terrain_bio_pressure_reduction_at_max * progress
		)
	}


# Returns terrain progress normalized from Level 1 to the maximum level.
func _terrain_progress_for_level(level: int) -> float:
	var max_level: int = ProgressionSystem.MAX_TERRAIN_LEVEL

	if max_level <= 1:
		return 0.0

	var safe_level: int = clampi(level, 1, max_level)
	return float(safe_level - 1) / float(max_level - 1)


# Resolves the progression level that belongs to a soil type.
func _terrain_level_for_soil(soil: String) -> int:
	if soil == "loamy":
		return ProgressionSystem.get_terrain_level(
			ProgressionSystem.TERRAIN_LOAMY
		)

	if soil == "sandy":
		return ProgressionSystem.get_terrain_level(
			ProgressionSystem.TERRAIN_SANDY
		)

	return 1


# Returns a reduction multiplier where Level 1 remains the base simulation.
func _terrain_loss_multiplier(
	soil: String,
	max_reduction: float
) -> float:
	var level: int = _terrain_level_for_soil(soil)
	var progress: float = _terrain_progress_for_level(level)
	var reduction: float = clamp(
		max_reduction * progress,
		0.0,
		0.95
	)
	return 1.0 - reduction


# Returns the watering/fertilizing efficiency multiplier.
func _terrain_treatment_multiplier(soil: String) -> float:
	var level: int = _terrain_level_for_soil(soil)
	var progress: float = _terrain_progress_for_level(level)
	return 1.0 + maxf(
		terrain_treatment_bonus_at_max,
		0.0
	) * progress


# Water retention factor lookup by soil type
func _get_random_event_drying_multiplier() -> float:
	var event_system: Node = get_node_or_null(
		"/root/RandomEventSystem"
	)

	if (
		event_system != null
		and event_system.has_method("get_soil_drying_multiplier")
	):
		return clampf(
			float(event_system.call("get_soil_drying_multiplier")),
			0.35,
			3.0
		)

	return 1.0


# Returns the water-retention multiplier for a soil type.
func _water_retention_for_soil(soil: String) -> float:
	if soil == "loamy": return water_retention_loamy
	if soil == "sandy": return water_retention_sandy
	return 0.65

# Nutrient retention factor lookup by soil type
func _nutrient_retention_for_soil(soil: String) -> float:
	if soil == "loamy": return nutrient_retention_loamy
	if soil == "sandy": return nutrient_retention_sandy
	return 0.55

# Baseline pH lookup by soil type
func _ph_baseline_for_soil(soil: String) -> float:
	if soil == "loamy": return default_ph_loamy
	if soil == "sandy": return default_ph_sandy
	return 7.0

# Long-term natural pH target used by autonomous soil chemistry drift
func _ph_drift_target_for_soil(soil: String) -> float:
	if soil == "loamy": return ph_drift_target_loamy
	if soil == "sandy": return ph_drift_target_sandy
	return 7.0

# pH buffering factor lookup by soil type
func _ph_buffer_for_soil(soil: String) -> float:
	if soil == "loamy": return ph_buffer_loamy
	if soil == "sandy": return ph_buffer_sandy
	return 0.60

# Resolve TileMap layer index by layer name
func _find_layer_by_name(map: TileMap, layer_name: String) -> int:
	for i in range(map.get_layers_count()):
		if map.get_layer_name(i) == layer_name:
			return i
	return -1
