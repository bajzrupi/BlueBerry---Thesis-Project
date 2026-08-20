extends Node2D

# Scene references and runtime setup
@onready var tilemap: TileMap = $Biome/GroundTileMap
@onready var cam: Camera2D = $WorldObjects/Entities/Player/Camera2D
@onready var player: CharacterBody2D = $WorldObjects/Entities/Player


@export_category("Debug Logging")
@export var debug_clock_logs: bool = false


# Initialize camera limits, input mode, and connect global systems
func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


	Clock.world_tick.connect(_on_world_tick)
	Clock.day_changed.connect(_on_day_changed)
	Clock.hour_changed.connect(_on_hour_changed)

	if debug_clock_logs:
		print("[Clock] Start: Day ", Clock.day, " ", Clock.format_time())
	BiomeSystem.init_from_tilemap(tilemap, "Plantable")
	BuildSystem.configure(tilemap, player, cam)
	WorldBoundsSystem.configure(tilemap, player, cam)
	SaveSystem.configure(tilemap, player)
	SprinklerSystem.configure(tilemap)
	FertilizerInjectorSystem.configure(tilemap)
	SoilNeutralizerSystem.configure(tilemap)
	PlantProtectionStationSystem.configure(tilemap)
	ChestSystem.configure(tilemap, player)
	RepairSystem.configure(tilemap, player)
	MinimapSystem.configure(tilemap, player)
	Clock.world_tick.connect(BiomeSystem.on_world_tick)

	Clock.day_changed.connect(WeatherSystem.on_day_changed)
	Clock.world_tick.connect(WeatherSystem.on_world_tick)

	# Apply the Main Menu launch request only after every world-bound system
	# above has been configured.
	GameFlowSystem.on_world_ready()

# Toggle mouse visibility based on aim mode
func _process(_delta: float) -> void:
	if BuildSystem.is_active():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	elif Input.is_action_pressed("aim_mode"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


# Releases transient BuildSystem world references on scene exit.
func _exit_tree() -> void:
	MinimapSystem.unconfigure(tilemap)
	RepairSystem.unconfigure(tilemap)
	ChestSystem.unconfigure(tilemap)
	PlantProtectionStationSystem.unconfigure(tilemap)
	SoilNeutralizerSystem.unconfigure(tilemap)
	FertilizerInjectorSystem.unconfigure(tilemap)
	SprinklerSystem.unconfigure(tilemap)
	SaveSystem.unconfigure(tilemap)
	WorldBoundsSystem.unconfigure(tilemap)
	BuildSystem.unconfigure(tilemap)


# Tick callback for time progression logging
func _on_world_tick(day: int, _minute_of_day: int, delta_minutes: int) -> void:
	if debug_clock_logs:
		print("[Tick] Day ", day, " ", Clock.format_time(), " (+", delta_minutes, "m)")

# Day change callback logging
func _on_day_changed(new_day: int) -> void:
	if debug_clock_logs:
		print("=== New Day: ", new_day, " ===")

# Hour change callback logging
func _on_hour_changed(new_hour: int) -> void:
	if debug_clock_logs:
		print("[Hour] ", new_hour, ":00")
