extends Node

# Biome zone simulation parameters and runtime zone state

# Zone default values
@export var default_moisture_loamy: float = 0.55
@export var default_moisture_sandy: float = 0.30
@export var default_nutrients_loamy: float = 0.60
@export var default_nutrients_sandy: float = 0.35


@export var water_retention_loamy: float = 0.85
@export var water_retention_sandy: float = 0.45
@export var nutrient_retention_loamy: float = 0.80
@export var nutrient_retention_sandy: float = 0.40


@export var base_moisture_loss_per_hour: float = 0.05
@export var base_nutrients_loss_per_hour: float = 0.01


@export var default_ph_loamy: float = 6.8
@export var default_ph_sandy: float = 7.4
@export var ph_buffer_loamy: float = 0.80
@export var ph_buffer_sandy: float = 0.40
@export var base_ph_drift_per_day: float = 0.10


@export var pressure_adjust_per_day: float = 0.35


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


# Update zone soil stats and pressure over time
func on_world_tick(_day: int, _minute_of_day: int, delta_minutes: int) -> void:
	if _zone_stats.size() == 0:
		return

	var hours := float(delta_minutes) / 60.0
	var days := float(delta_minutes) / (24.0 * 60.0)

	for zid in _zone_stats.keys():
		var st: Dictionary = _zone_stats[zid]
		var soil: String = st.get("soil_type", "")

		var wret := _water_retention_for_soil(soil)
		var nret := _nutrient_retention_for_soil(soil)


		var moisture_loss := base_moisture_loss_per_hour * (1.0 - wret)
		var nutrients_loss := base_nutrients_loss_per_hour * (1.0 - nret)

		# Apply soil retention losses
		st["moisture"] = clamp(float(st.get("moisture", 0.5)) - moisture_loss * hours, MOISTURE_MIN, MOISTURE_MAX)
		st["nutrients"] = clamp(float(st.get("nutrients", 0.5)) - nutrients_loss * hours, NUTRIENTS_MIN, NUTRIENTS_MAX)



		# Drift pH toward baseline
		var ph := float(st.get("ph", 7.0))
		var baseline := _ph_baseline_for_soil(soil)
		var buffer := _ph_buffer_for_soil(soil)
		var sensitivity = (1.0 - clamp(buffer, 0.0, 0.95))

		var step = base_ph_drift_per_day * sensitivity * days
		if ph < baseline:
			ph = min(baseline, ph + step)
		elif ph > baseline:
			ph = max(baseline, ph - step)
		st["ph"] = clamp(ph, PH_MIN, PH_MAX)



		# Move pressure toward climate-driven targets
		var pest_target := _compute_pest_target(st)
		var disease_target := _compute_disease_target(st)

		var k = clamp(pressure_adjust_per_day * days, 0.0, 1.0)
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
		var wret := _water_retention_for_soil(soil)
		st["moisture"] = clamp(float(st.get("moisture", 0.5)) + amount * wret, MOISTURE_MIN, MOISTURE_MAX)
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
	var wret := _water_retention_for_soil(soil)
	st["moisture"] = clamp(float(st.get("moisture", 0.5)) + amount * wret, MOISTURE_MIN, MOISTURE_MAX)
	_zone_stats[zid] = st

# Add nutrients to the zone containing the cell
func add_nutrients(cell: Vector2i, amount: float) -> void:
	var zid := get_zone_id(cell)
	if zid == -1:
		return
	var st: Dictionary = _zone_stats[zid]
	var soil: String = st.get("soil_type", "")
	var nret := _nutrient_retention_for_soil(soil)
	st["nutrients"] = clamp(float(st.get("nutrients", 0.5)) + amount * nret, NUTRIENTS_MIN, NUTRIENTS_MAX)
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

			var soil := _get_soil_type(td)
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
				"humidity": 0.5,
				"temperature": 20.0,
				"light": 0.7,
				"pest_pressure": 0.0,
				"disease_pressure": 0.0,
			}

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
			var s := _get_soil_type(td)
			if s == "":
				s = "unknown"
			if s != soil:
				continue
			visited[n] = true
			q.append(n)

# Read soil type from TileData custom data
func _get_soil_type(td: TileData) -> String:
	var v = td.get_custom_data("soil_type")
	return "" if v == null else str(v)

# Water retention factor lookup by soil type
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
