extends Node

enum Weather { CLEAR, CLOUDY, RAIN, HEATWAVE, COLDSNAP }


# Weather configuration, climate baselines, and runtime state

# Daily weather weights
@export var weight_clear: int = 45
@export var weight_cloudy: int = 25
@export var weight_rain: int = 20
@export var weight_heatwave: int = 7
@export var weight_coldsnap: int = 3



# Climate baselines
@export var base_temp_c: float = 20.0
@export var base_humidity: float = 0.50



# Day-night light curve settings
@export var sunrise_minute: int = 6 * 60
@export var sunset_minute: int = 20 * 60
@export var night_light: float = 0.10
@export var day_light: float = 1.00



# Weather state modifiers
@export var cloudy_light_mult: float = 0.75
@export var rain_light_mult: float = 0.60
@export var heat_light_mult: float = 1.00
@export var cold_light_mult: float = 0.90

@export var cloudy_temp_offset: float = -1.0
@export var rain_temp_offset: float = -2.0
@export var heat_temp_offset: float = 6.0
@export var cold_temp_offset: float = -6.0

@export var cloudy_humidity_offset: float = 0.10
@export var rain_humidity_offset: float = 0.25
@export var heat_humidity_offset: float = -0.10
@export var cold_humidity_offset: float = -0.05



# Weather gameplay effects
@export var rain_moisture_gain_per_hour: float = 0.10

@export var debug_print_daily: bool = true

var current_weather: int = Weather.CLEAR


# Initialize RNG and roll initial daily weather
func _ready() -> void:
	randomize()

	roll_daily_weather()


# Roll a new daily weather state on day change
func on_day_changed(_new_day: int) -> void:
	roll_daily_weather()


# Compute climate values for the current time and apply gameplay effects
func on_world_tick(_day: int, minute_of_day: int, delta_minutes: int) -> void:

	# Compute base light from day-night curve
	var light := _compute_light(minute_of_day)


	var temp := base_temp_c
	var hum := base_humidity
	var light_mult := 1.0


	# Apply per-weather climate offsets
	match current_weather:
		Weather.CLEAR:
			pass
		Weather.CLOUDY:
			temp += cloudy_temp_offset
			hum += cloudy_humidity_offset
			light_mult *= cloudy_light_mult
		Weather.RAIN:
			temp += rain_temp_offset
			hum += rain_humidity_offset
			light_mult *= rain_light_mult
		Weather.HEATWAVE:
			temp += heat_temp_offset
			hum += heat_humidity_offset
			light_mult *= heat_light_mult
		Weather.COLDSNAP:
			temp += cold_temp_offset
			hum += cold_humidity_offset
			light_mult *= cold_light_mult

	light = clamp(light * light_mult, 0.0, 1.0)
	hum = clamp(hum, 0.0, 1.0)



	# Publish climate to biome system
	BiomeSystem.set_global_climate(temp, hum, light)



	# Apply rain moisture increase to all zones
	if current_weather == Weather.RAIN:
		var hours := float(delta_minutes) / 60.0
		BiomeSystem.add_moisture_to_all_zones(rain_moisture_gain_per_hour * hours)


# Select weather for the current day using weighted roll
func roll_daily_weather() -> void:
	current_weather = _weighted_roll()
	if debug_print_daily:
		print("[Weather] ", _weather_name(current_weather))


# Weighted random selection for daily weather
func _weighted_roll() -> int:
	var weights := [
		weight_clear,
		weight_cloudy,
		weight_rain,
		weight_heatwave,
		weight_coldsnap
	]
	var total := 0
	for w in weights:
		total += max(0, w)

	if total <= 0:
		return Weather.CLEAR

	var r := randi() % total
	var acc := 0

	acc += max(0, weight_clear)
	if r < acc: return Weather.CLEAR

	acc += max(0, weight_cloudy)
	if r < acc: return Weather.CLOUDY

	acc += max(0, weight_rain)
	if r < acc: return Weather.RAIN

	acc += max(0, weight_heatwave)
	if r < acc: return Weather.HEATWAVE

	return Weather.COLDSNAP


# Compute day-night light curve from minute-of-day
func _compute_light(minute_of_day: int) -> float:

	if minute_of_day < sunrise_minute or minute_of_day > sunset_minute:
		return night_light

	var day_len := float(sunset_minute - sunrise_minute)
	var t := (float(minute_of_day - sunrise_minute) / day_len)


	var tri = 1.0 - abs(2.0 * t - 1.0)
	return lerp(night_light, day_light, tri)


# Convert weather enum value to display name
func _weather_name(w: int) -> String:
	match w:
		Weather.CLEAR: return "CLEAR"
		Weather.CLOUDY: return "CLOUDY"
		Weather.RAIN: return "RAIN"
		Weather.HEATWAVE: return "HEATWAVE"
		Weather.COLDSNAP: return "COLDSNAP"
	return "?"
