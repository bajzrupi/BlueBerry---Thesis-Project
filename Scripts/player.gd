extends CharacterBody2D

# Player movement, targeting, and tool interactions


# Movement parameters
@export var speed: float = 140.0


# Scene and node path references
@export var plant_scene: PackedScene
@export var tilemap_path: NodePath
@export var plants_parent_path: NodePath


# Highlight node paths
@export var cell_highlight_1x1_path: NodePath
@export var cell_highlight_2x1_path: NodePath


# Placement and interaction targeting
@export var plantable_layer_name: String = "Plantable"
@export var plant_range_cells: int = 2
@export var plant_y_offset: float = 0.0

@export var selected_data: PlantData

# Zone tool parameters
@export var water_amount: float = 0.20
@export var fertilizer_amount: float = 0.15
@export var lime_amount: float = 0.6
@export var acid_amount: float = -0.6

# Plant tool parameters
@export var pesticide_amount: float = 0.35
@export var fungicide_amount: float = 0.30

# Visual FX parameters
@export var fx_enabled: bool = true
@export var fx_duration: float = 0.25

# Particle FX toggle
@export var particles_enabled: bool = true

# Invalid action feedback parameters
@export var invalid_feedback_enabled: bool = true
@export var invalid_shake_duration: float = 0.18
@export var invalid_shake_pixels: float = 6.0
@export var invalid_flash_duration: float = 0.12
@export var invalid_fx_color: Color = Color(1.0, 0.2, 0.2, 0.95)

# Debug logging toggle
@export var debug_log: bool = true

@export var highlight_ok: Color = Color(1, 1, 1, 0.75)
@export var highlight_bad: Color = Color(1, 0.2, 0.2, 0.75)

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D

var last_dir: String = "Down"

var tilemap: TileMap
var plantable_layer: int = -1
var plants_parent: Node

var hl1: Sprite2D
var hl2: Sprite2D

# Shake timer for invalid feedback
var _shake_left: float = 0.0


# Cache node references and resolve TileMap layers
func _ready() -> void:
	tilemap = get_node_or_null(tilemap_path) as TileMap
	if tilemap == null:
		push_warning("TileMap not found. Set tilemap_path on Player instance.")
	else:
		plantable_layer = _find_layer_by_name(tilemap, plantable_layer_name)
		if plantable_layer == -1:
			push_warning("Plantable layer not found: %s" % plantable_layer_name)

	plants_parent = get_node_or_null(plants_parent_path)
	if plants_parent == null:
		plants_parent = get_parent()

	hl1 = get_node_or_null(cell_highlight_1x1_path) as Sprite2D
	hl2 = get_node_or_null(cell_highlight_2x1_path) as Sprite2D
	if hl1: hl1.visible = false
	if hl2: hl2.visible = false


# Handle movement, targeting UI, and tool usage input
func _physics_process(delta: float) -> void:
	var dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * speed
	move_and_slide()
	_update_animation(dir)

	if _shake_left > 0.0:
		_shake_left -= delta

	if Input.is_action_pressed("aim_mode"):
		if _shake_left <= 0.0:
			_update_highlight()
	else:
		_hide_highlights()

	if Input.is_action_pressed("aim_mode") and Input.is_action_just_pressed("interact"):
		_apply_current_tool()


# Validate and execute the selected tool action
func _apply_current_tool() -> void:
	var a = _get_anchor_cell()
	if a == null:
		return
	var cell: Vector2i = a

	var t: int = Toolsystem.current_tool
	var ok_reason := _validate_action(t, cell)
	if ok_reason.ok == false:
		_invalid_feedback(t, cell, ok_reason.reason)
		return

	match t:
		ToolSystem.Tool.PLANT:
			_do_plant(cell)
		ToolSystem.Tool.WATER:
			_do_water(cell)
		ToolSystem.Tool.FERTILIZE:
			_do_fertilize(cell)
		ToolSystem.Tool.LIME:
			_do_ph(cell, lime_amount)
		ToolSystem.Tool.ACID:
			_do_ph(cell, acid_amount)
		ToolSystem.Tool.PESTICIDE:
			_do_pesticide(cell)
		ToolSystem.Tool.FUNGICIDE:
			_do_fungicide(cell)
		ToolSystem.Tool.SHOVEL:
			_do_shovel(cell)
		_:
			pass


# Animation state update
func _update_animation(dir: Vector2) -> void:
	var target: String
	if dir == Vector2.ZERO:
		target = "Idle_%s" % last_dir
	else:
		if abs(dir.x) > abs(dir.y):
			last_dir = "Right" if dir.x > 0.0 else "Left"
		else:
			last_dir = "Down" if dir.y > 0.0 else "Up"
		target = "Walk_%s" % last_dir

	if anim.animation != target:
		anim.play(target)


# Target highlight update
func _hide_highlights() -> void:
	if hl1: hl1.visible = false
	if hl2: hl2.visible = false


# Update highlight position, size, and validity color
func _update_highlight() -> void:
	if tilemap == null or plantable_layer == -1 or hl1 == null or hl2 == null:
		return

	var anchor = _get_anchor_cell()
	if anchor == null:
		_hide_highlights()
		return
	var a: Vector2i = anchor

	var t: int = Toolsystem.current_tool

	var use_2x1 := false
	var center: Vector2 = tilemap.to_global(tilemap.map_to_local(a))
	var ok := false

	match t:
		ToolSystem.Tool.PLANT:
			ok = _can_plant_at(a, selected_data)
			if selected_data != null and selected_data.footprint_size == Vector2i(2, 1):
				use_2x1 = true
				center = _get_footprint_center_global(a, selected_data)

		ToolSystem.Tool.PESTICIDE, ToolSystem.Tool.FUNGICIDE, ToolSystem.Tool.SHOVEL:
			ok = _has_plant_at(a)

			var p = PlantRegistry.get_plant(a)
			if p != null:
				var pd: PlantData = p.get("data")
				var anch: Vector2i = p.get("anchor_cell")
				if pd != null and pd.footprint_size == Vector2i(2, 1):
					use_2x1 = true
					center = _get_footprint_center_global(anch, pd)

		_:
			ok = _can_affect_zone_at(a)

	if use_2x1:
		hl1.visible = false
		hl2.visible = true
		hl2.global_position = center
		hl2.modulate = highlight_ok if ok else highlight_bad
	else:
		hl2.visible = false
		hl1.visible = true
		hl1.global_position = center
		hl1.modulate = highlight_ok if ok else highlight_bad


# Action validation helpers
class ActionCheck:
	var ok: bool
	var reason: String
	func _init(_ok: bool, _reason: String) -> void:
		ok = _ok
		reason = _reason


# Validate current tool action for the selected cell
func _validate_action(t: int, a: Vector2i) -> ActionCheck:
	if not _is_in_range(a):
		return ActionCheck.new(false, "OUT_OF_RANGE")

	if tilemap == null or plantable_layer == -1:
		return ActionCheck.new(false, "NO_TILEMAP")

	if tilemap.get_cell_tile_data(plantable_layer, a) == null:
		return ActionCheck.new(false, "NOT_PLANTABLE_TILE")

	match t:
		ToolSystem.Tool.PLANT:
			if selected_data == null:
				return ActionCheck.new(false, "NO_SELECTED_PLANTDATA")
			return _validate_plant_at(a, selected_data)

		ToolSystem.Tool.WATER, ToolSystem.Tool.FERTILIZE, ToolSystem.Tool.LIME, ToolSystem.Tool.ACID:
			if BiomeSystem.get_zone_id(a) == -1:
				return ActionCheck.new(false, "NO_ZONE")
			return ActionCheck.new(true, "")

		ToolSystem.Tool.PESTICIDE, ToolSystem.Tool.FUNGICIDE, ToolSystem.Tool.SHOVEL:
			if PlantRegistry.get_plant(a) == null:
				return ActionCheck.new(false, "NO_PLANT_ON_CELL")
			return ActionCheck.new(true, "")

		_:
			return ActionCheck.new(false, "UNKNOWN_TOOL")


# Validate planting constraints for a footprint
func _validate_plant_at(anchor: Vector2i, pd: PlantData) -> ActionCheck:
	var footprint := _get_footprint_cells(anchor, pd)

	for fc in footprint:
		var td: TileData = tilemap.get_cell_tile_data(plantable_layer, fc)
		if td == null:
			return ActionCheck.new(false, "FOOTPRINT_NOT_PLANTABLE")

		var soil_v = td.get_custom_data("soil_type")
		if soil_v == null:
			return ActionCheck.new(false, "NO_SOIL_TYPE")

		var soil := str(soil_v)
		if not pd.allowed_soils.has(soil):
			return ActionCheck.new(false, "WRONG_SOIL(%s)" % soil)

	for fc in footprint:
		if PlantRegistry.get_plant(fc) != null:
			return ActionCheck.new(false, "OCCUPIED")

	return ActionCheck.new(true, "")


# Invalid action feedback effects
func _invalid_feedback(t: int, a: Vector2i, reason: String) -> void:
	if debug_log:
		print("[Invalid] tool=", Toolsystem.get_tool_name(t), " cell=", a, " reason=", reason)

	if not invalid_feedback_enabled:
		return

	var use_2x1 := false
	var center: Vector2 = tilemap.to_global(tilemap.map_to_local(a))

	if t == ToolSystem.Tool.PLANT and selected_data != null and selected_data.footprint_size == Vector2i(2, 1):
		use_2x1 = true
		center = _get_footprint_center_global(a, selected_data)

	if t == ToolSystem.Tool.PESTICIDE or t == ToolSystem.Tool.FUNGICIDE or t == ToolSystem.Tool.SHOVEL:
		var p = PlantRegistry.get_plant(a)
		if p != null:
			var pd: PlantData = p.get("data")
			var anch: Vector2i = p.get("anchor_cell")
			if pd != null and pd.footprint_size == Vector2i(2, 1):
				use_2x1 = true
				center = _get_footprint_center_global(anch, pd)

	var node := hl2 if use_2x1 else hl1
	if node == null:
		return

	node.visible = true
	node.global_position = center

	var base_mod := node.modulate
	node.modulate = invalid_fx_color
	var tw := create_tween()
	tw.tween_property(node, "modulate", base_mod, invalid_flash_duration)

	_shake_left = invalid_shake_duration
	var tw2 := create_tween()
	tw2.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in range(6):
		var dx := invalid_shake_pixels if (i % 2 == 0) else -invalid_shake_pixels
		tw2.tween_property(node, "global_position", center + Vector2(dx, 0), invalid_shake_duration / 6.0)
	tw2.tween_property(node, "global_position", center, 0.01)

	if fx_enabled:
		FxSpawner.spawn_fx(center, invalid_fx_color, Vector2.ONE if not use_2x1 else Vector2(2, 1), fx_duration)


# Common cell/target checks
func _can_affect_zone_at(a: Vector2i) -> bool:
	if not _is_in_range(a):
		return false
	if tilemap.get_cell_tile_data(plantable_layer, a) == null:
		return false
	return BiomeSystem.get_zone_id(a) != -1


# Check whether a plant exists at the selected cell
func _has_plant_at(a: Vector2i) -> bool:
	if not _can_affect_zone_at(a):
		return false
	return PlantRegistry.get_plant(a) != null


# Zone tool actions
func _do_water(a: Vector2i) -> void:
	BiomeSystem.add_moisture(a, water_amount)
	_spawn_fx_cell(a, Color(0.3, 0.6, 1.0, 0.9))
	_spawn_particles_cell(a, "water", Vector2.ONE)
	if debug_log:
		print("[Action] WATER cell=", a, " +", water_amount)


# Apply fertilizer to the zone and spawn effects
func _do_fertilize(a: Vector2i) -> void:
	BiomeSystem.add_nutrients(a, fertilizer_amount)
	_spawn_fx_cell(a, Color(0.3, 1.0, 0.4, 0.9))
	_spawn_particles_cell(a, "fertilize", Vector2.ONE)
	if debug_log:
		print("[Action] FERTILIZE cell=", a, " +", fertilizer_amount)


# Apply pH change to the zone and spawn effects
func _do_ph(a: Vector2i, delta: float) -> void:
	BiomeSystem.add_ph(a, delta)
	if delta >= 0.0:
		_spawn_fx_cell(a, Color(0.95, 0.95, 0.95, 0.9))
		_spawn_particles_cell(a, "lime", Vector2.ONE)
	else:
		_spawn_fx_cell(a, Color(0.7, 0.3, 1.0, 0.9))
		_spawn_particles_cell(a, "acid", Vector2.ONE)

	if debug_log:
		print("[Action] PH cell=", a, " delta=", delta)


# Plant tool actions
func _do_pesticide(a: Vector2i) -> void:
	var plant = PlantRegistry.get_plant(a)
	plant.call("apply_pesticide", pesticide_amount)
	_spawn_fx_plant(a, Color(1.0, 0.6, 0.2, 0.9))
	_spawn_particles_plant(a, "pesticide")
	if debug_log:
		print("[Action] PESTICIDE cell=", a, " amount=", pesticide_amount)


# Apply fungicide to the target plant and spawn effects
func _do_fungicide(a: Vector2i) -> void:
	var plant = PlantRegistry.get_plant(a)
	plant.call("apply_fungicide", fungicide_amount)
	_spawn_fx_plant(a, Color(0.2, 1.0, 1.0, 0.9))
	_spawn_particles_plant(a, "fungicide")
	if debug_log:
		print("[Action] FUNGICIDE cell=", a, " amount=", fungicide_amount)


# Remove the target plant and spawn effects
func _do_shovel(a: Vector2i) -> void:
	_spawn_fx_plant(a, Color(1.0, 0.2, 0.2, 0.9))
	_spawn_particles_plant(a, "shovel")

	var plant = PlantRegistry.get_plant(a)
	if plant.has_method("despawn"):
		plant.call("despawn")
	else:
		plant.queue_free()

	if debug_log:
		print("[Action] SHOVEL cell=", a, " removed")


# Plant placement action
func _do_plant(a: Vector2i) -> void:
	var pd := selected_data
	var footprint := _get_footprint_cells(a, pd)

	var world_pos: Vector2 = _get_footprint_center_global(a, pd)
	world_pos.y += plant_y_offset

	var plant := plant_scene.instantiate() as Node2D
	plant.name = "%s_%s_%s" % [pd.display_name, a.x, a.y]
	plant.global_position = world_pos
	plant.set("data", pd)
	plant.set("anchor_cell", a)
	plant.set("occupied_cells", footprint)

	plants_parent.add_child(plant)

	for fc in footprint:
		PlantRegistry.register(fc, plant)

	_spawn_fx_at(world_pos, Color(0.35, 1.0, 0.5, 0.9), Vector2(pd.footprint_size.x, pd.footprint_size.y))
	# Planting particle effect
	_spawn_particles_at(world_pos, "fertilize", Vector2(pd.footprint_size.x, pd.footprint_size.y))

	if debug_log:
		print("[Action] PLANT ", pd.display_name, " anchor=", a, " footprint=", footprint)


# Quick boolean wrapper for planting validation
func _can_plant_at(anchor: Vector2i, pd: PlantData) -> bool:
	return _validate_plant_at(anchor, pd).ok


# Target cell selection
func _get_anchor_cell():
	var mouse_global: Vector2 = get_global_mouse_position()
	var mouse_cell: Vector2i = tilemap.local_to_map(tilemap.to_local(mouse_global))

	if _is_in_range(mouse_cell) and tilemap.get_cell_tile_data(plantable_layer, mouse_cell) != null:
		return mouse_cell

	var player_cell: Vector2i = tilemap.local_to_map(tilemap.to_local(global_position))
	var offset := Vector2i.ZERO
	match last_dir:
		"Up": offset = Vector2i(0, -1)
		"Down": offset = Vector2i(0, 1)
		"Left": offset = Vector2i(-1, 0)
		"Right": offset = Vector2i(1, 0)

	var front_cell: Vector2i = player_cell + offset
	if _is_in_range(front_cell) and tilemap.get_cell_tile_data(plantable_layer, front_cell) != null:
		return front_cell

	return null


# Check player interaction range in tile cells
func _is_in_range(c: Vector2i) -> bool:
	var player_cell: Vector2i = tilemap.local_to_map(tilemap.to_local(global_position))
	var dx = abs(c.x - player_cell.x)
	var dy = abs(c.y - player_cell.y)
	return max(dx, dy) <= plant_range_cells


# Footprint helpers
func _get_footprint_cells(anchor: Vector2i, pd: PlantData) -> Array[Vector2i]:
	var size := pd.footprint_size
	var origin := pd.footprint_origin
	var top_left := anchor + origin

	var cells: Array[Vector2i] = []
	for y in range(size.y):
		for x in range(size.x):
			cells.append(top_left + Vector2i(x, y))
	return cells


# Compute world center position of a footprint
func _get_footprint_center_global(anchor: Vector2i, pd: PlantData) -> Vector2:
	var cells := _get_footprint_cells(anchor, pd)
	var sum := Vector2.ZERO
	for c in cells:
		sum += tilemap.to_global(tilemap.map_to_local(c))
	return sum / float(cells.size())


# Find TileMap layer index by layer name
func _find_layer_by_name(map: TileMap, layer_name: String) -> int:
	for i in range(map.get_layers_count()):
		if map.get_layer_name(i) == layer_name:
			return i
	return -1


# FX spawn helpers
func _spawn_fx_cell(a: Vector2i, tint: Color, scale_cells: Vector2 = Vector2.ONE) -> void:
	if not fx_enabled:
		return
	var pos := tilemap.to_global(tilemap.map_to_local(a))
	FxSpawner.spawn_fx(pos, tint, scale_cells, fx_duration)


# Spawn a visual FX at a plant center
func _spawn_fx_plant(a: Vector2i, tint: Color) -> void:
	if not fx_enabled:
		return
	var p = PlantRegistry.get_plant(a)
	if p == null:
		return
	var pos: Vector2 = p.global_position
	var pd: PlantData = p.get("data")
	var sc := Vector2.ONE
	if pd != null:
		sc = Vector2(pd.footprint_size.x, pd.footprint_size.y)
	FxSpawner.spawn_fx(pos, tint, sc, fx_duration)


# Spawn a visual FX at a world position
func _spawn_fx_at(world_pos: Vector2, tint: Color, scale_cells: Vector2 = Vector2.ONE) -> void:
	if not fx_enabled:
		return
	FxSpawner.spawn_fx(world_pos, tint, scale_cells, fx_duration)


# Particle spawn helpers
func _tile_px() -> Vector2:
	if tilemap != null and tilemap.tile_set != null:
		return Vector2(tilemap.tile_set.tile_size)
	return Vector2(32, 32)


# Spawn tool particles at a cell center
func _spawn_particles_cell(a: Vector2i, kind: String, scale_cells: Vector2) -> void:
	if not particles_enabled:
		return
	var pos := tilemap.to_global(tilemap.map_to_local(a))
	_spawn_particles_at(pos, kind, scale_cells)


# Spawn tool particles at a plant center
func _spawn_particles_plant(a: Vector2i, kind: String) -> void:
	if not particles_enabled:
		return
	var p = PlantRegistry.get_plant(a)
	if p == null:
		return
	var pos: Vector2 = p.global_position
	var pd: PlantData = p.get("data")
	var sc := Vector2.ONE
	if pd != null:
		sc = Vector2(pd.footprint_size.x, pd.footprint_size.y)
	_spawn_particles_at(pos, kind, sc)


# Dispatch tool particle type spawn
func _spawn_particles_at(world_pos: Vector2, kind: String, scale_cells: Vector2) -> void:
	var cell_px := _tile_px()

	match kind:
		"water":
			ToolParticles.spawn_water(world_pos, cell_px, scale_cells)
		"fertilize":
			ToolParticles.spawn_fertilize(world_pos, cell_px, scale_cells)
		"lime":
			ToolParticles.spawn_lime(world_pos, cell_px, scale_cells)
		"acid":
			ToolParticles.spawn_acid(world_pos, cell_px, scale_cells)
		"pesticide":
			ToolParticles.spawn_pesticide(world_pos, cell_px, scale_cells)
		"fungicide":
			ToolParticles.spawn_fungicide(world_pos, cell_px, scale_cells)
		"shovel":
			ToolParticles.spawn_shovel(world_pos, cell_px, scale_cells)
		_:
			# Default particel style
			ToolParticles.spawn_fertilize(world_pos, cell_px, scale_cells)
