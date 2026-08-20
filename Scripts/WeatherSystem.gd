extends Node

enum Weather { CLEAR, CLOUDY, RAIN, HEATWAVE, COLDSNAP }


# ------------------------------------------------------------------
# Weather configuration, climate baselines, and runtime state
# ------------------------------------------------------------------

# A weighted roll still happens once per in-game day.
# CLEAR means the day stays clear.
# Non-clear results start immediately and expire back to CLEAR after their
# configured duration instead of occupying the entire day.
@export_category("Daily Weather Weights")

@export var weight_clear: int = 45
@export var weight_cloudy: int = 25
@export var weight_rain: int = 20
@export var weight_heatwave: int = 7
@export var weight_coldsnap: int = 2


@export_category("Weather Episode Duration")

# Durations are expressed in in-game hours.
# With the current 3-minute day:
# 1 in-game hour = 7.5 real seconds.
@export_range(1, 24, 1)
var cloudy_duration_min_hours: int = 4

@export_range(1, 24, 1)
var cloudy_duration_max_hours: int = 10

@export_range(1, 24, 1)
var rain_duration_min_hours: int = 4

@export_range(1, 24, 1)
var rain_duration_max_hours: int = 8

@export_range(1, 24, 1)
var heatwave_duration_min_hours: int = 6

@export_range(1, 24, 1)
var heatwave_duration_max_hours: int = 10

@export_range(1, 24, 1)
var coldsnap_duration_min_hours: int = 6

@export_range(1, 24, 1)
var coldsnap_duration_max_hours: int = 10


@export_category("Climate Baselines")

@export var base_temp_c: float = 20.0
@export var base_humidity: float = 0.50


@export_category("Day / Night Light")

@export var sunrise_minute: int = 6 * 60
@export var sunset_minute: int = 20 * 60
@export var night_light: float = 0.10
@export var day_light: float = 1.00


@export_category("Weather Climate Modifiers")

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


@export_category("Weather Gameplay Effects")

@export var rain_moisture_gain_per_hour: float = 0.035


@export_category("Diagnostics")

@export var debug_print_daily: bool = false


signal weather_changed(
	weather: int,
	remaining_minutes: int
)


var current_weather: int = Weather.CLEAR

# Remaining active episode time.
# CLEAR always uses 0.
var weather_remaining_minutes: int = 0


# ------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------

# Initializes this system when the node becomes ready.
func _ready() -> void:
	randomize()

	# Day 1 begins at the configured Clock start time, so the first episode
	# begins there. Later daily rolls happen on Clock.day_changed.
	roll_daily_weather()


# Roll one weather result at the beginning of each new day.
func on_day_changed(_new_day: int) -> void:
	roll_daily_weather()


# Compute climate values for the current time, apply gameplay effects,
# and advance the active weather episode timer.
func on_world_tick(
	_day: int,
	minute_of_day: int,
	delta_minutes: int
) -> void:
	_publish_current_climate(
		minute_of_day,
		delta_minutes
	)

	_advance_weather_duration(
		delta_minutes,
		minute_of_day
	)


# ------------------------------------------------------------------
# Daily weather roll / episode duration
# ------------------------------------------------------------------

# Kept under the original public function name so GameFlowSystem and the
# existing scene wiring do not need any changes.
func roll_daily_weather() -> void:
	var rolled_weather: int = _weighted_roll()

	if rolled_weather == Weather.CLEAR:
		_set_weather(
			Weather.CLEAR,
			0
		)
	else:
		_set_weather(
			rolled_weather,
			_roll_duration_minutes(
				rolled_weather
			)
		)

	if debug_print_daily:
		print(
			"[Weather] rolled ",
			_weather_name(current_weather),
			" duration=",
			weather_remaining_minutes,
			"m"
		)


# Handles advance weather duration.
func _advance_weather_duration(
	delta_minutes: int,
	minute_of_day: int
) -> void:
	if current_weather == Weather.CLEAR:
		weather_remaining_minutes = 0
		return

	if delta_minutes <= 0:
		return

	weather_remaining_minutes = maxi(
		0,
		weather_remaining_minutes - delta_minutes
	)

	if weather_remaining_minutes > 0:
		return

	# The episode has ended. Return to normal clear weather for the remainder
	# of the day. Re-publish climate immediately so biome/global climate does
	# not retain the expired weather modifiers until the next world tick.
	_set_weather(
		Weather.CLEAR,
		0
	)

	_publish_current_climate(
		minute_of_day,
		0
	)

	if debug_print_daily:
		print(
			"[Weather] episode ended -> CLEAR"
		)


# Sets the weather.
func _set_weather(
	weather_value: int,
	remaining_minutes: int
) -> void:
	current_weather = clampi(
		weather_value,
		Weather.CLEAR,
		Weather.COLDSNAP
	)

	if current_weather == Weather.CLEAR:
		weather_remaining_minutes = 0
	else:
		weather_remaining_minutes = maxi(
			0,
			remaining_minutes
		)

	weather_changed.emit(
		current_weather,
		weather_remaining_minutes
	)


# Randomly selects duration minutes using the configured probabilities.
func _roll_duration_minutes(
	weather_value: int
) -> int:
	var bounds: Vector2i = _duration_bounds_hours(
		weather_value
	)

	if bounds.x <= 0 or bounds.y <= 0:
		return 0

	var min_hours: int = mini(
		bounds.x,
		bounds.y
	)
	var max_hours: int = maxi(
		bounds.x,
		bounds.y
	)

	return randi_range(
		min_hours,
		max_hours
	) * 60


# Handles duration bounds hours.
func _duration_bounds_hours(
	weather_value: int
) -> Vector2i:
	match weather_value:
		Weather.CLOUDY:
			return Vector2i(
				cloudy_duration_min_hours,
				cloudy_duration_max_hours
			)
		Weather.RAIN:
			return Vector2i(
				rain_duration_min_hours,
				rain_duration_max_hours
			)
		Weather.HEATWAVE:
			return Vector2i(
				heatwave_duration_min_hours,
				heatwave_duration_max_hours
			)
		Weather.COLDSNAP:
			return Vector2i(
				coldsnap_duration_min_hours,
				coldsnap_duration_max_hours
			)
		_:
			return Vector2i.ZERO


# Handles default loaded duration minutes.
func _default_loaded_duration_minutes(
	weather_value: int
) -> int:
	var bounds: Vector2i = _duration_bounds_hours(
		weather_value
	)

	if bounds == Vector2i.ZERO:
		return 0

	var min_hours: int = mini(
		bounds.x,
		bounds.y
	)
	var max_hours: int = maxi(
		bounds.x,
		bounds.y
	)
	var midpoint_hours: int = int(
		round(
			(
				float(min_hours)
				+ float(max_hours)
			)
			* 0.5
		)
	)

	return maxi(
		1,
		midpoint_hours
	) * 60


# ------------------------------------------------------------------
# Climate / gameplay effect publication
# ------------------------------------------------------------------

# Handles publish current climate.
func _publish_current_climate(
	minute_of_day: int,
	delta_minutes: int
) -> void:
	var light: float = _compute_light(
		minute_of_day
	)

	var temp: float = base_temp_c
	var hum: float = base_humidity
	var light_mult: float = 1.0

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

	light = clampf(
		light * light_mult,
		0.0,
		1.0
	)
	hum = clampf(
		hum,
		0.0,
		1.0
	)

	BiomeSystem.set_global_climate(
		temp,
		hum,
		light
	)

	if (
		current_weather == Weather.RAIN
		and delta_minutes > 0
	):
		var hours: float = (
			float(delta_minutes) / 60.0
		)

		BiomeSystem.add_moisture_to_all_zones(
			rain_moisture_gain_per_hour
			* hours
		)


# ------------------------------------------------------------------
# Save / Load
# ------------------------------------------------------------------

# Returns the serializable state of this system.
func get_save_state() -> Dictionary:
	return {
		"current_weather": current_weather,
		"remaining_minutes": weather_remaining_minutes
	}


# Restores this system from saved data.
func load_save_state(
	state: Dictionary
) -> bool:
	var weather_value: int = clampi(
		int(
			state.get(
				"current_weather",
				Weather.CLEAR
			)
		),
		Weather.CLEAR,
		Weather.COLDSNAP
	)

	var remaining_default: int = (
		_default_loaded_duration_minutes(
			weather_value
		)
	)

	var remaining_minutes: int = maxi(
		0,
		int(
			state.get(
				"remaining_minutes",
				remaining_default
			)
		)
	)

	if weather_value == Weather.CLEAR:
		remaining_minutes = 0
	elif remaining_minutes <= 0:
		# A legacy save only stored current_weather. Give its non-clear weather
		# one sensible finite episode instead of restoring an infinite state.
		remaining_minutes = remaining_default

	_set_weather(
		weather_value,
		remaining_minutes
	)

	return true


# ------------------------------------------------------------------
# Weighted roll / light curve / display
# ------------------------------------------------------------------

# Handles weighted roll.
func _weighted_roll() -> int:
	var weights: Array[int] = [
		weight_clear,
		weight_cloudy,
		weight_rain,
		weight_heatwave,
		weight_coldsnap
	]

	var total: int = 0

	for weight: int in weights:
		total += maxi(
			0,
			weight
		)

	if total <= 0:
		return Weather.CLEAR

	var roll: int = randi() % total
	var accumulated: int = 0

	accumulated += maxi(
		0,
		weight_clear
	)

	if roll < accumulated:
		return Weather.CLEAR

	accumulated += maxi(
		0,
		weight_cloudy
	)

	if roll < accumulated:
		return Weather.CLOUDY

	accumulated += maxi(
		0,
		weight_rain
	)

	if roll < accumulated:
		return Weather.RAIN

	accumulated += maxi(
		0,
		weight_heatwave
	)

	if roll < accumulated:
		return Weather.HEATWAVE

	return Weather.COLDSNAP


# Calculates the light.
func _compute_light(
	minute_of_day: int
) -> float:
	if (
		minute_of_day < sunrise_minute
		or minute_of_day > sunset_minute
	):
		return night_light

	var day_length: float = float(
		sunset_minute - sunrise_minute
	)
	var t: float = (
		float(
			minute_of_day
			- sunrise_minute
		)
		/ day_length
	)

	var triangle: float = (
		1.0
		- absf(
			2.0 * t
			- 1.0
		)
	)

	return lerpf(
		night_light,
		day_light,
		triangle
	)


# Handles weather name.
func _weather_name(
	weather_value: int
) -> String:
	match weather_value:
		Weather.CLEAR:
			return "CLEAR"
		Weather.CLOUDY:
			return "CLOUDY"
		Weather.RAIN:
			return "RAIN"
		Weather.HEATWAVE:
			return "HEATWAVE"
		Weather.COLDSNAP:
			return "COLDSNAP"

	return "?"
