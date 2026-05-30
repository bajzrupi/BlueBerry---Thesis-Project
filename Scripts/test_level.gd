extends Node2D

# Scene references and runtime setup
@onready var tilemap: TileMap = $Biome/GroundTileMap
@onready var cam: Camera2D = $WorldObjects/Entities/Player/Camera2D


@export var debug_clock_logs: bool = true


# Initialize camera limits, input mode, and connect global systems
func _ready() -> void:
	_apply_camera_limits_from_tilemap()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


	Clock.world_tick.connect(_on_world_tick)
	Clock.day_changed.connect(_on_day_changed)
	Clock.hour_changed.connect(_on_hour_changed)

	print("[Clock] Start: Day ", Clock.day, " ", Clock.format_time())
	BiomeSystem.init_from_tilemap(tilemap, "Plantable")
	Clock.world_tick.connect(BiomeSystem.on_world_tick)

	Clock.day_changed.connect(WeatherSystem.on_day_changed)
	Clock.world_tick.connect(WeatherSystem.on_world_tick)


# Derive camera limits from placed tiles
func _apply_camera_limits_from_tilemap() -> void:
	var used: Rect2i = tilemap.get_used_rect()
	if used.size == Vector2i.ZERO:
		push_warning("TileMap used_rect üres (nincs lerakott tile?)")
		return

	var cell: Vector2i = tilemap.tile_set.tile_size

	var top_left_local: Vector2 = Vector2(used.position.x * cell.x, used.position.y * cell.y)
	var bottom_right_local: Vector2 = Vector2(
		(used.position.x + used.size.x) * cell.x,
		(used.position.y + used.size.y) * cell.y
	)

	var top_left_global: Vector2 = tilemap.to_global(top_left_local)
	var bottom_right_global: Vector2 = tilemap.to_global(bottom_right_local)

	cam.limit_left = int(top_left_global.x)
	cam.limit_top = int(top_left_global.y)
	cam.limit_right = int(bottom_right_global.x)
	cam.limit_bottom = int(bottom_right_global.y)


# Toggle mouse visibility based on aim mode
func _process(_delta: float) -> void:

	if Input.is_action_pressed("aim_mode"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


# Tick callback for time progression logging
func _on_world_tick(day: int, _minute_of_day: int, delta_minutes: int) -> void:
	print("[Tick] Day ", day, " ", Clock.format_time(), " (+", delta_minutes, "m)")

# Day change callback logging
func _on_day_changed(new_day: int) -> void:
	print("=== New Day: ", new_day, " ===")

# Hour change callback logging
func _on_hour_changed(new_hour: int) -> void:
	print("[Hour] ", new_hour, ":00")
