extends Node2D

signal died(plant: Node2D)

# Plant runtime state, tuning parameters, and optional logging
@export var data: PlantData
@export var start_stage: int = 0
@export var anchor_cell: Vector2i = Vector2i.ZERO
@export var occupied_cells: Array[Vector2i] = []

@onready var sprite: Sprite2D = $Sprite2D

var stage: int = 0
var health: float = 100.0
var _growth_hours_accum: float = 0.0


var pest_level: float = 0.0
var disease_level: float = 0.0


var is_dead: bool = false
@export var debug_death: bool = true


@export var debug_log: bool = true
@export var debug_log_every_minutes: int = 60


@export var status_marker_enabled: bool = true
@export var status_marker_y_offset: float = -18.0
@export var status_dry_margin: float = 0.08
@export var status_wet_margin: float = 0.08
@export var status_ph_margin: float = 0.50
@export var status_pest_threshold: float = 0.25
@export var status_disease_threshold: float = 0.25
@export var debug_status_log: bool = false

var status_label: Label



# Infection parameters
@export var pest_seed_per_hour: float = 0.03
@export var disease_seed_per_hour: float = 0.02
@export var pest_growth_per_hour: float = 0.08
@export var disease_growth_per_hour: float = 0.06
@export var pest_natural_recovery_per_hour: float = 0.01
@export var disease_natural_recovery_per_hour: float = 0.006



# Spread parameters
@export var enable_spread: bool = true
@export var pest_spread_threshold: float = 0.40
@export var disease_spread_threshold: float = 0.35
@export var pest_spread_per_hour: float = 0.08
@export var disease_spread_per_hour: float = 0.06
@export var pest_spread_seed_amount: float = 0.10
@export var disease_spread_seed_amount: float = 0.08
@export var max_spread_targets_per_tick: int = 3
@export var debug_spread: bool = false


# Sprite alignment const
const BASE_H: float = 32.0


# Initialize plant state and connect to world tick
func _ready() -> void:
	stage = start_stage
	if data != null:
		health = data.max_health

	_apply_stage()
	_create_status_label()

	# Update visuals, markers, and periodic logging
	_update_visual()
	_update_status_marker(0.5, 0.5, 7.0)

	Clock.world_tick.connect(_on_world_tick)


# Disconnect signals and unregister occupied cells
func _exit_tree() -> void:
	if Clock.world_tick.is_connected(_on_world_tick):
		Clock.world_tick.disconnect(_on_world_tick)


	for c in occupied_cells:
		PlantRegistry.unregister(c)


# Remove plant and free its occupied cells
func despawn() -> void:
	for c in occupied_cells:
		PlantRegistry.unregister(c)
	queue_free()


# Reduce pest level by tool effect
func apply_pesticide(amount: float) -> void:
	if is_dead:
		return
	pest_level = max(0.0, pest_level - amount)

# Reduce disease level by tool effect
func apply_fungicide(amount: float) -> void:
	if is_dead:
		return
	disease_level = max(0.0, disease_level - amount)


# Apply incoming pest infection seed
func receive_pest_seed(amount: float) -> void:
	if is_dead:
		return
	pest_level = clamp(pest_level + amount, 0.0, 1.0)

# Apply incoming disease infection seed
func receive_disease_seed(amount: float) -> void:
	if is_dead:
		return
	disease_level = clamp(disease_level + amount, 0.0, 1.0)


# Update infection, environment response, growth, death, visuals, and status marker
func _on_world_tick(day: int, minute_of_day: int, delta_minutes: int) -> void:
	if data == null:
		return


	if is_dead:
		_update_visual()
		_update_status_marker(0.0, 0.0, 7.0)
		return

	var hours := float(delta_minutes) / 60.0

	# Read zone and climate stats


	var moisture := BiomeSystem.get_moisture(anchor_cell)
	var nutrients := BiomeSystem.get_nutrients(anchor_cell)
	var ph := BiomeSystem.get_ph(anchor_cell)
	var pest_pressure := BiomeSystem.get_pest_pressure(anchor_cell)
	var disease_pressure := BiomeSystem.get_disease_pressure(anchor_cell)

	var zst: Dictionary = BiomeSystem.get_zone_stats(anchor_cell)
	var humidity := float(zst.get("humidity", 0.5))
	var temperature := float(zst.get("temperature", 20.0))
	var light := float(zst.get("light", 0.7))

	if moisture < 0.0:
		moisture = 0.5
	if nutrients < 0.0:
		nutrients = 0.5
	if ph < 0.0:
		ph = 7.0


	# Update infection from zone pressure
	var health_factor = clamp(health / data.max_health, 0.0, 1.0)
	var susceptibility = 0.35 + (1.0 - health_factor) * 0.65


	if pest_level <= 0.0001:
		var prob_p = pest_seed_per_hour * pest_pressure * susceptibility * (1.0 - data.pest_resistance) * hours
		if randf() < prob_p:
			pest_level = 0.10
	else:
		pest_level = clamp(
			pest_level + pest_growth_per_hour * pest_pressure * (1.0 - data.pest_resistance) * hours,
			0.0, 1.0
		)


	if disease_level <= 0.0001:
		var prob_d = disease_seed_per_hour * disease_pressure * susceptibility * (1.0 - data.disease_resistance) * hours
		if randf() < prob_d:
			disease_level = 0.08
	else:
		disease_level = clamp(
			disease_level + disease_growth_per_hour * disease_pressure * (1.0 - data.disease_resistance) * hours,
			0.0, 1.0
		)


	pest_level = max(0.0, pest_level - pest_natural_recovery_per_hour * hours)
	disease_level = max(0.0, disease_level - disease_natural_recovery_per_hour * hours)



	# Attempt local plant-to-plant spread
	if enable_spread:
		_try_spread(hours, humidity, temperature, light)



	# Evaluate optimal environmental ranges
	var moist_ok := (moisture >= data.optimal_moisture_min and moisture <= data.optimal_moisture_max)
	var nutr_ok := (nutrients >= data.optimal_nutrients_min and nutrients <= data.optimal_nutrients_max)
	var ph_ok := (ph >= data.optimal_ph_min and ph <= data.optimal_ph_max)

	var temp_ok := (temperature >= data.optimal_temp_min and temperature <= data.optimal_temp_max)
	var hum_ok := (humidity >= data.optimal_humidity_min and humidity <= data.optimal_humidity_max)
	var light_ok := (light >= data.optimal_light_min and light <= data.optimal_light_max)

	var env_good := moist_ok and nutr_ok and ph_ok and temp_ok and hum_ok and light_ok


	var bio_growth_mult := (1.0 - 0.50 * pest_level) * (1.0 - 0.70 * disease_level)
	var bio_extra_decay := (0.6 * pest_level + 1.2 * disease_level)



	# Update health from environment and infection
	if env_good:
		health = min(data.max_health, health + data.health_recover_per_hour * hours)
	else:
		var dist := 0.0

		if not moist_ok:
			dist += (data.optimal_moisture_min - moisture) if moisture < data.optimal_moisture_min else (moisture - data.optimal_moisture_max)

		if not nutr_ok:
			dist += (data.optimal_nutrients_min - nutrients) if nutrients < data.optimal_nutrients_min else (nutrients - data.optimal_nutrients_max)

		if not ph_ok:
			var ph_dist := (data.optimal_ph_min - ph) if ph < data.optimal_ph_min else (ph - data.optimal_ph_max)
			dist += ph_dist / 3.0

		if not temp_ok:
			var tdist := (data.optimal_temp_min - temperature) if temperature < data.optimal_temp_min else (temperature - data.optimal_temp_max)
			dist += tdist / 10.0

		if not hum_ok:
			dist += ((data.optimal_humidity_min - humidity) if humidity < data.optimal_humidity_min else (humidity - data.optimal_humidity_max)) * 0.75

		if not light_ok:
			dist += ((data.optimal_light_min - light) if light < data.optimal_light_min else (light - data.optimal_light_max)) * 0.50

		var decay := data.health_decay_per_hour * (1.0 + dist * 2.0)
		health = max(0.0, health - decay * hours)


	health = max(0.0, health - bio_extra_decay * hours)



	# Apply death rule
	if health <= 0.0 and not is_dead:
		health = 0.0
		is_dead = true


		pest_level = 0.0
		disease_level = 0.0
		enable_spread = false
		_growth_hours_accum = 0.0

		_update_visual()
		_update_status_marker(moisture, nutrients, ph)

		if debug_death:
			print("[Death] ", data.display_name, " cell=", anchor_cell, " stage=", stage, " day=", day, " time=", "%02d:%02d" % [minute_of_day / 60.0, minute_of_day % 60])

		died.emit(self)
		return



	# Update growth progression
	if stage < data.max_stage:
		var growth_factor := 1.0 if env_good else data.growth_factor_outside_range
		var health_mult = clamp(health / data.max_health, 0.0, 1.0)

		_growth_hours_accum += hours * growth_factor * health_mult * clamp(bio_growth_mult, 0.05, 1.0)

		while stage < data.max_stage:
			var need_hours := _hours_to_next_stage(stage, data)
			if _growth_hours_accum < need_hours:
				break
			_growth_hours_accum -= need_hours
			stage += 1
			_apply_stage()

	_update_visual()
	_update_status_marker(moisture, nutrients, ph)
	_debug_log(day, minute_of_day, moisture, nutrients, ph, temperature, humidity, light, pest_pressure, disease_pressure, env_good)


# Attempt local plant-to-plant spread based on infection and weather
func _try_spread(hours: float, humidity: float, temperature: float, light: float) -> void:
	var can_pest := pest_level >= pest_spread_threshold
	var can_dis := disease_level >= disease_spread_threshold
	if not can_pest and not can_dis:
		return

	var targets: Array[Node] = _collect_neighbor_plants()
	if targets.size() == 0:
		return

	var spread_count := 0

	var pest_weather_mult := 1.0
	pest_weather_mult += clamp((temperature - 22.0) / 10.0, 0.0, 1.0) * 0.50
	pest_weather_mult += clamp((light - 0.6) / 0.4, 0.0, 1.0) * 0.25

	var disease_weather_mult := 1.0
	disease_weather_mult += clamp((humidity - 0.60) / 0.40, 0.0, 1.0) * 1.00
	if WeatherSystem.current_weather == WeatherSystem.Weather.RAIN:
		disease_weather_mult += 0.50

	for t in targets:
		if spread_count >= max_spread_targets_per_tick:
			break
		if t == self:
			continue

		var tdata: PlantData = t.get("data")
		if tdata == null:
			continue

		if bool(t.get("is_dead")):
			continue

		var thealth: float = float(t.get("health"))
		var tmax: float = float(tdata.max_health)
		var t_health_factor = clamp(thealth / tmax, 0.0, 1.0)
		var t_sus = 0.50 + (1.0 - t_health_factor) * 0.50

		if can_pest:
			var res_p = clamp(tdata.pest_resistance, 0.0, 1.0)
			var prob_p = pest_spread_per_hour * pest_level * hours * pest_weather_mult * (1.0 - res_p) * t_sus
			if randf() < prob_p:
				t.call("receive_pest_seed", pest_spread_seed_amount)
				spread_count += 1
				if debug_spread:
					print("[Spread] PEST -> ", tdata.display_name, " prob=", snapped(prob_p, 0.001))

		if can_dis and spread_count < max_spread_targets_per_tick:
			var res_d = clamp(tdata.disease_resistance, 0.0, 1.0)
			var prob_d = disease_spread_per_hour * disease_level * hours * disease_weather_mult * (1.0 - res_d) * t_sus
			if randf() < prob_d:
				t.call("receive_disease_seed", disease_spread_seed_amount)
				spread_count += 1
				if debug_spread:
					print("[Spread] DIS -> ", tdata.display_name, " prob=", snapped(prob_d, 0.001))


# Collect uniqe neighbor plants around the footprint
func _collect_neighbor_plants() -> Array[Node]:
	var neighbor_cells: Array[Vector2i] = []
	if occupied_cells.size() == 0:
		occupied_cells = [anchor_cell]

	for c in occupied_cells:
		neighbor_cells.append(Vector2i(c.x + 1, c.y))
		neighbor_cells.append(Vector2i(c.x - 1, c.y))
		neighbor_cells.append(Vector2i(c.x, c.y + 1))
		neighbor_cells.append(Vector2i(c.x, c.y - 1))

	var seen := {}
	var out: Array[Node] = []
	for nc in neighbor_cells:
		var p = PlantRegistry.get_plant(nc)
		if p == null:
			continue
		var id := p.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		out.append(p)

	return out


# Convert growth stage timing into required in-game hours
func _hours_to_next_stage(current_stage: int, pd: PlantData) -> float:
	if current_stage >= pd.max_stage:
		return 999999.0

	var idx := current_stage
	var days := 1.0
	if pd.days_to_next_stage.size() > 0:
		days = pd.days_to_next_stage[idx] if idx < pd.days_to_next_stage.size() else pd.days_to_next_stage[pd.days_to_next_stage.size() - 1]

	return max(0.01, days) * 24.0


# Apply current stage texture/region and sprite alignment
func _apply_stage() -> void:
	if data == null:
		return
	if data.stage_textures.size() == 0 or data.stage_regions.size() == 0:
		return

	var max_idx = min(data.max_stage, min(data.stage_textures.size() - 1, data.stage_regions.size() - 1))
	stage = clamp(stage, 0, max_idx)

	sprite.texture = data.stage_textures[stage]
	sprite.region_enabled = true
	sprite.region_rect = data.stage_regions[stage]

	var h := sprite.region_rect.size.y
	sprite.position.y = data.base_sprite_offset_y - (h - BASE_H) * 0.5

	_position_status_label()


# Update sprite tint based on health and death state
func _update_visual() -> void:
	if sprite == null or data == null:
		return

	if is_dead:
		sprite.modulate = Color(0.55, 0.55, 0.55, 1.0)
		return

	var h = clamp(health / data.max_health, 0.0, 1.0)

	var healthy := Color(1, 1, 1, 1)
	var stressed := Color(1.0, 0.85, 0.55, 1.0)
	var very_bad := Color(0.55, 0.35, 0.20, 1.0)

	if h >= 0.5:
		var t = (1.0 - h) / 0.5
		sprite.modulate = healthy.lerp(stressed, t)
	else:
		var t2 = (0.5 - h) / 0.5
		sprite.modulate = stressed.lerp(very_bad, t2)


# Create in-world status label node
func _create_status_label() -> void:
	if not status_marker_enabled:
		return

	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.visible = false
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.size = Vector2(96, 18)
	status_label.z_index = 2000
	status_label.add_theme_font_size_override("font_size", 10)
	add_child(status_label)

	_position_status_label()


# Position status label above the sprite
func _position_status_label() -> void:
	if status_label == null or sprite == null:
		return

	var region_h := 32.0
	if sprite.region_enabled:
		region_h = sprite.region_rect.size.y

	status_label.position = Vector2(-48, sprite.position.y - region_h * 0.5 + status_marker_y_offset)


# Update status label contents from current plant and soil conditions
func _update_status_marker(moisture: float, nutrients: float, ph: float) -> void:
	if not status_marker_enabled or status_label == null or data == null:
		return

	_position_status_label()

	if is_dead:
		status_label.visible = true
		status_label.text = "DEAD"
		status_label.modulate = Color(0.75, 0.75, 0.75, 1.0)
		return

	var tags: Array[String] = []

	if moisture < (data.optimal_moisture_min - status_dry_margin):
		tags.append("DRY")
	elif moisture > (data.optimal_moisture_max + status_wet_margin):
		tags.append("WET")

	if ph < (data.optimal_ph_min - status_ph_margin) or ph > (data.optimal_ph_max + status_ph_margin):
		tags.append("PH")

	if pest_level >= status_pest_threshold:
		tags.append("PEST")

	if disease_level >= status_disease_threshold:
		tags.append("DIS")

	if tags.is_empty():
		status_label.visible = false
		status_label.text = ""
		return

	status_label.visible = true
	status_label.text = " ".join(tags)

	if tags.has("DIS"):
		status_label.modulate = Color(0.7, 1.0, 0.7, 1.0)
	elif tags.has("PEST"):
		status_label.modulate = Color(1.0, 0.85, 0.4, 1.0)
	elif tags.has("PH"):
		status_label.modulate = Color(0.8, 0.7, 1.0, 1.0)
	elif tags.has("DRY") or tags.has("WET"):
		status_label.modulate = Color(1.0, 0.95, 0.6, 1.0)
	else:
		status_label.modulate = Color(1, 1, 1, 1)

	if debug_status_log:
		print("[StatusMarker] ", data.display_name, " cell=", anchor_cell, " tags=", tags)


# Emitt structured debug output at configured intervals
func _debug_log(day: int, minute_of_day: int,
	moisture: float, nutrients: float, ph: float,
	temperature: float, humidity: float, light: float,
	pest_pressure: float, disease_pressure: float, env_good: bool) -> void:

	if not debug_log:
		return

	var step = max(1, debug_log_every_minutes)
	if (minute_of_day % step) != 0:
		return

	var h := minute_of_day / 60.0
	var m := minute_of_day % 60

	print(data.display_name, " cell=", anchor_cell,
		" day=", day, " time=", "%02d:%02d" % [h, m],
		" stage=", stage,
		" health=", snapped(health, 0.1),
		" moist=", snapped(moisture, 0.01),
		" nutr=", snapped(nutrients, 0.01),
		" ph=", snapped(ph, 0.01),
		" temp=", snapped(temperature, 0.1),
		" hum=", snapped(humidity, 0.01),
		" light=", snapped(light, 0.01),
		" pest=", snapped(pest_level, 0.01),
		" dis=", snapped(disease_level, 0.01),
		" pPress=", snapped(pest_pressure, 0.01),
		" dPress=", snapped(disease_pressure, 0.01),
		" env=", env_good)
