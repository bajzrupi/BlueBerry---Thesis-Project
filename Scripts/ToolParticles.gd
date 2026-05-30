extends Node

# Tool particle generator and effect presets
@export var debug_log: bool = true

var _dot_tex: Texture2D


# Build reusable particle texture
func _ready() -> void:
	_dot_tex = _make_dot_texture(8)
	if debug_log:
		print("[Particles] ToolParticles ready, dot_tex OK")


# Generate a soft dot texture used by all tool particles
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


# Spawn a one-shot particle burst with the given parameters
func _spawn_particles(
	world_pos: Vector2,
	color: Color,
	cell_px: Vector2,
	scale_cells: Vector2,
	amount: int,
	lifetime: float,
	direction: Vector2,
	spread_deg: float,
	vel_min: float,
	vel_max: float,
	gravity: Vector2,
	scale_min: float,
	scale_max: float
) -> void:
	var n := Node2D.new()
	n.global_position = world_pos
	n.z_index = 1100

	var p := CPUParticles2D.new()
	p.texture = _dot_tex
	p.one_shot = true
	p.emitting = false
	p.amount = max(1, amount)
	p.lifetime = lifetime
	p.direction = direction
	p.spread = spread_deg
	p.initial_velocity_min = vel_min
	p.initial_velocity_max = vel_max
	p.gravity = gravity
	p.color = color
	p.scale_amount_min = scale_min
	p.scale_amount_max = scale_max


	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(cell_px.x * 0.35 * scale_cells.x, cell_px.y * 0.20 * scale_cells.y)

	n.add_child(p)
	get_tree().current_scene.add_child(n)

	p.emitting = true


	var t := Timer.new()
	t.one_shot = true
	t.wait_time = lifetime + 0.2
	t.timeout.connect(func(): n.queue_free())
	n.add_child(t)
	t.start()

	if debug_log:
		print("[Particles] spawn pos=", world_pos,
			" amount=", p.amount,
			" life=", lifetime,
			" dir=", direction,
			" color=", color,
			" scale_cells=", scale_cells)


# Spawn watering particle effect
func spawn_water(world_pos: Vector2, cell_px: Vector2, scale_cells: Vector2) -> void:
	_spawn_particles(
		world_pos,
		Color(0.3, 0.6, 1.0, 0.85),
		cell_px, scale_cells,
		int(18 * scale_cells.x * scale_cells.y),
		0.45,
		Vector2(0, 1),
		22.0,
		80.0, 160.0,
		Vector2(0, 650),
		0.5, 0.9
	)

# Spawn fertilizing particle effect
func spawn_fertilize(world_pos: Vector2, cell_px: Vector2, scale_cells: Vector2) -> void:
	_spawn_particles(
		world_pos,
		Color(0.3, 1.0, 0.4, 0.85),
		cell_px, scale_cells,
		int(16 * scale_cells.x * scale_cells.y),
		0.50,
		Vector2(0, -1),
		85.0,
		40.0, 120.0,
		Vector2(0, 520),
		0.6, 1.0
	)

# Spawn lime particle effect
func spawn_lime(world_pos: Vector2, cell_px: Vector2, scale_cells: Vector2) -> void:
	_spawn_particles(
		world_pos,
		Color(0.95, 0.95, 0.95, 0.90),
		cell_px, scale_cells,
		int(14 * scale_cells.x * scale_cells.y),
		0.45,
		Vector2(0, -1),
		70.0,
		30.0, 100.0,
		Vector2(0, 450),
		0.55, 0.95
	)

# Spawn acid particle effect
func spawn_acid(world_pos: Vector2, cell_px: Vector2, scale_cells: Vector2) -> void:
	_spawn_particles(
		world_pos,
		Color(0.7, 0.3, 1.0, 0.85),
		cell_px, scale_cells,
		int(14 * scale_cells.x * scale_cells.y),
		0.50,
		Vector2(0, -1),
		55.0,
		25.0, 90.0,
		Vector2(0, 260),
		0.7, 1.1
	)

# Spawn pesticide particle effect
func spawn_pesticide(world_pos: Vector2, cell_px: Vector2, scale_cells: Vector2) -> void:
	_spawn_particles(
		world_pos,
		Color(1.0, 0.6, 0.2, 0.85),
		cell_px, scale_cells,
		int(16 * scale_cells.x * scale_cells.y),
		0.40,
		Vector2(0, -1),
		35.0,
		90.0, 180.0,
		Vector2(0, 120),
		0.5, 0.9
	)

# Spawn fungicide particle effect
func spawn_fungicide(world_pos: Vector2, cell_px: Vector2, scale_cells: Vector2) -> void:
	_spawn_particles(
		world_pos,
		Color(0.2, 1.0, 1.0, 0.85),
		cell_px, scale_cells,
		int(16 * scale_cells.x * scale_cells.y),
		0.40,
		Vector2(0, -1),
		35.0,
		90.0, 180.0,
		Vector2(0, 120),
		0.5, 0.9
	)

# Spawn shovel dirt particle effect
func spawn_shovel(world_pos: Vector2, cell_px: Vector2, scale_cells: Vector2) -> void:
	_spawn_particles(
		world_pos,
		Color(0.45, 0.30, 0.15, 0.90),
		cell_px, scale_cells,
		int(18 * scale_cells.x * scale_cells.y),
		0.55,
		Vector2(0, -1),
		95.0,
		60.0, 180.0,
		Vector2(0, 780),
		0.6, 1.1
	)
