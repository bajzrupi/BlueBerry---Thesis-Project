extends Node

# Game time configuration, signals, and runtime state

# Time scaling configuration
@export var day_length_seconds: float = 30.0
@export var tick_step_minutes: int = 60
@export var time_scale: float = 1.0

@export var start_day: int = 1
@export var start_minute_of_day: int = 8 * 60


# Time progression signals
signal time_changed(day: int, minute_of_day: int, time_of_day_0_1: float)
signal world_tick(day: int, minute_of_day: int, delta_minutes: int)
signal day_changed(new_day: int)
signal hour_changed(new_hour: int)


# Runtime clock state
var day: int
var minute_of_day: int

var _game_seconds_accum: float = 0.0
var _paused: bool = false

const MINUTES_PER_DAY := 24 * 60
const SECONDS_PER_GAME_DAY := 24 * 60 * 60

# Initialize clock state
func _ready() -> void:
	_reset()

# Advance game time based on real time and emit signals
func _process(delta: float) -> void:
	if _paused:
		return
	if day_length_seconds <= 0.0:
		return

	# Convert real time into in-game seconds
	var game_seconds_per_real_second := float(SECONDS_PER_GAME_DAY) / day_length_seconds
	_game_seconds_accum += delta * time_scale * game_seconds_per_real_second

	var step_game_seconds = max(1, tick_step_minutes) * 60

	# Emitt fixed-step world ticks
	while _game_seconds_accum >= step_game_seconds:
		_game_seconds_accum -= step_game_seconds
		_advance_minutes(max(1, tick_step_minutes))

	emit_signal("time_changed", day, minute_of_day, get_time_of_day())

# Apply minute advancement and emitt tick/day/hour events
func _advance_minutes(delta_minutes: int) -> void:
	var prev_hour := get_hour()

	# Advance minutes and handle day rolloover
	minute_of_day += delta_minutes
	while minute_of_day >= MINUTES_PER_DAY:
		minute_of_day -= MINUTES_PER_DAY
		day += 1
		emit_signal("day_changed", day)

	emit_signal("world_tick", day, minute_of_day, delta_minutes)

	var new_hour := get_hour()
	if new_hour != prev_hour:
		emit_signal("hour_changed", new_hour)

# Reset clock to configured start time
func _reset() -> void:
	day = start_day
	minute_of_day = clamp(start_minute_of_day, 0, MINUTES_PER_DAY - 1)
	_game_seconds_accum = 0.0

# Pause or resume time progression
func set_paused(v: bool) -> void:
	_paused = v

# Current in-game hour
func get_hour() -> int:
	return int(minute_of_day / 60.0)

# Current in-game minute
func get_minute() -> int:
	return minute_of_day % 60

# Normalized time-of-day in range 0..1
func get_time_of_day() -> float:
	return float(minute_of_day) / float(MINUTES_PER_DAY)

# Format current time as HH:MM
func format_time() -> String:
	return "%02d:%02d" % [get_hour(), get_minute()]
