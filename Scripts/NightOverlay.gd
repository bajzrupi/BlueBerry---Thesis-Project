extends CanvasLayer

# Night overlay configuration and logging settings
@onready var fade: ColorRect = $Fade



# Overlay intensity settings
@export var max_dark_alpha: float = 0.70


@export var night_threshold: float = 0.25


@export var smooth_speed: float = 6.0



# Overlay runtime logging
@export var debug_log: bool = false
@export var debug_log_every_minutes: int = 60

var _last_logged_minute: int = -999999


# Initialize overlay alpha from current global light
func _ready() -> void:

	_apply_alpha(_target_alpha(BiomeSystem.global_light), true)


# Update overlay alpha every frame (and optionally print status)
func _process(delta: float) -> void:
	var light = BiomeSystem.global_light
	var target := _target_alpha(light)


	var current := fade.color.a
	var a = lerp(current, target, 1.0 - exp(-smooth_speed * delta))
	_apply_alpha(a, false)


	if debug_log and Clock != null:
		var m := Clock.minute_of_day
		var step = max(1, debug_log_every_minutes)
		if (m % step) == 0 and m != _last_logged_minute:
			_last_logged_minute = m
			print("[NightOverlay] day=", Clock.day,
				" time=", "%02d:%02d" % [m / 60.0, m % 60],
				" light=", snapped(light, 0.01),
				" alpha=", snapped(fade.color.a, 0.01))


# Convert global light value into target overlay alpha
func _target_alpha(light: float) -> float:

	var l = clamp(light, 0.0, 1.0)


	if l >= night_threshold:
		return 0.0


	var t = 1.0 - (l / night_threshold)
	t = clamp(t, 0.0, 1.0)

	return t * max_dark_alpha


# Apply computed alpha to the ColorRect
func _apply_alpha(a: float, immediate: bool) -> void:
	var c := fade.color
	c.a = clamp(a, 0.0, 1.0)
	fade.color = c
