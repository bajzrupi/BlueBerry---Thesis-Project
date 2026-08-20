extends CanvasLayer

# Screen-space weather particle effect configuration
@onready var rain: CPUParticles2D = $Rain
@onready var snow: CPUParticles2D = $Snow


@export var vfx_layer: int = 1

@export var debug_log: bool = false
@export var debug_log_every_seconds: float = 2.0
var _log_accum := 0.0


var _rain_tex: Texture2D
var _snow_tex: Texture2D


# Initialize rain/snow particle systems and generated textures
func _ready() -> void:
	layer = vfx_layer

	_rain_tex = _make_rain_streak_texture(2, 14)
	_snow_tex = _make_dot_texture(6)

	_setup_rain()
	_setup_snow()
	_update_emit_rects()


	_apply_weather()

	if debug_log:
		print("[WeatherVFX] ready. layer=", layer)


# Keep emitters aligned to viewport and toggle precipitation by weater
func _process(delta: float) -> void:
	_update_emit_rects()
	_apply_weather()

	if debug_log:
		_log_accum += delta
		if _log_accum >= debug_log_every_seconds:
			_log_accum = 0.0
			print("[WeatherVFX] weather=", _weather_name(),
				" rain=", rain.emitting,
				" snow=", snow.emitting)


# Enable the correct particle emitter for the current weather
func _apply_weather() -> void:

	match WeatherSystem.current_weather:
		WeatherSystem.Weather.RAIN:
			rain.emitting = true
			snow.emitting = false
		WeatherSystem.Weather.COLDSNAP:
			rain.emitting = false
			snow.emitting = true
		_:
			rain.emitting = false
			snow.emitting = false


# Convert weather enum to display name
func _weather_name() -> String:
	match WeatherSystem.current_weather:
		WeatherSystem.Weather.CLEAR: return "CLEAR"
		WeatherSystem.Weather.CLOUDY: return "CLOUDY"
		WeatherSystem.Weather.RAIN: return "RAIN"
		WeatherSystem.Weather.HEATWAVE: return "HEATWAVE"
		WeatherSystem.Weather.COLDSNAP: return "COLDSNAP"
	return "?"


# Configure rain particle parameters
func _setup_rain() -> void:
	rain.texture = _rain_tex
	rain.one_shot = false
	rain.emitting = false
	rain.amount = 450
	rain.lifetime = 0.9
	rain.direction = Vector2(0.15, 1).normalized()
	rain.spread = 6.0
	rain.initial_velocity_min = 520.0
	rain.initial_velocity_max = 760.0
	rain.gravity = Vector2(0, 0)
	rain.color = Color(0.55, 0.70, 1.0, 0.55)


	rain.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE


# Configure snow particle parameters
func _setup_snow() -> void:
	snow.texture = _snow_tex
	snow.one_shot = false
	snow.emitting = false
	snow.amount = 180
	snow.lifetime = 3.0
	snow.direction = Vector2(0.05, 1).normalized()
	snow.spread = 22.0
	snow.initial_velocity_min = 35.0
	snow.initial_velocity_max = 90.0
	snow.gravity = Vector2(0, 25)
	snow.color = Color(1, 1, 1, 0.75)
	snow.scale_amount_min = 0.6
	snow.scale_amount_max = 1.2

	snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE


# Resize emission rectangles to match the current viewport
func _update_emit_rects() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var size: Vector2 = vp.get_visible_rect().size


	var ext := Vector2(size.x * 0.5, size.y * 0.5)
	rain.emission_rect_extents = ext
	snow.emission_rect_extents = ext


	var center := size * 0.5
	rain.position = Vector2(center.x, -40)
	snow.position = Vector2(center.x, -40)


# Generate a small soft dot texture for particles
func _make_dot_texture(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var c := Vector2((size - 1) * 0.5, (size - 1) * 0.5)
	var r := (size * 0.5) - 0.5
	for y in range(size):
		for x in range(size):
			var d := c.distance_to(Vector2(x, y))
			if d <= r:
				var a := 1.0 - (d / r) * 0.6
				img.set_pixel(x, y, Color(1, 1, 1, clamp(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


# Generate a vertical streak texture for rain particles
func _make_rain_streak_texture(w: int, h: int) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	for y in range(h):
		var a := 1.0 - float(y) / float(h)
		for x in range(w):
			img.set_pixel(x, y, Color(1, 1, 1, clamp(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)
