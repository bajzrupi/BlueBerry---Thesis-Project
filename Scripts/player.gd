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

# Editor fallback synchronized with the runtime plant selection.
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

@export_category("Harvest Quality")

# At zero health, money can still retain this fraction of the normal reward.
# At full health, the current/base reward remains unchanged.
@export_range(0.0, 1.0, 0.05)
var harvest_health_money_floor: float = 0.40


@export_category("Debug Logging")
# Logging is preserved for troubleshooting, but quiet by default.
@export var debug_log: bool = false

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
	_connect_character_system()
	_apply_character_appearance(
		CharacterSystem.get_current_character_id()
	)

	_sync_selected_plant()

	if not PlantSelectionSystem.selection_changed.is_connected(
		_on_plant_selection_changed
	):
		PlantSelectionSystem.selection_changed.connect(
			_on_plant_selection_changed
		)

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


# Connects the Player to the global character appearance state.
func _connect_character_system() -> void:
	if not CharacterSystem.character_changed.is_connected(
		_on_character_changed
	):
		CharacterSystem.character_changed.connect(
			_on_character_changed
		)


# Applies the SpriteFrames belonging to the selected character while
# keeping the Player's movement, collision and gameplay logic unchanged.
func _apply_character_appearance(character_id: StringName) -> void:
	var frames := CharacterSystem.get_sprite_frames(character_id)

	if frames == null:
		push_warning(
			"[Player] Character SpriteFrames unavailable id=%s"
			% String(character_id)
		)
		return

	var previous_animation: StringName = anim.animation
	var previous_frame: int = anim.frame
	var was_playing: bool = anim.is_playing()

	anim.sprite_frames = frames

	if frames.has_animation(previous_animation):
		anim.play(previous_animation)

		var frame_count := frames.get_frame_count(
			previous_animation
		)

		if frame_count > 0:
			anim.frame = clampi(
				previous_frame,
				0,
				frame_count - 1
			)

		if not was_playing:
			anim.pause()
	else:
		anim.play(
			StringName("Idle_%s" % last_dir)
		)

	if debug_log:
		print(
			"[Player] character appearance applied id=",
			character_id,
			" animation=",
			anim.animation
		)


# Reacts immediately when CharacterSystem changes the selected appearance.
func _on_character_changed(character_id: StringName) -> void:
	_apply_character_appearance(character_id)


# Handle movement, targeting UI, and tool usage input
func _physics_process(delta: float) -> void:
	if BuildSystem.is_active():
		velocity = Vector2.ZERO
		move_and_slide()
		_update_animation(Vector2.ZERO)
		_hide_highlights()
		return

	var previous_position: Vector2 = global_position
	var dir: Vector2 = Input.get_vector(
		"move_left",
		"move_right",
		"move_up",
		"move_down"
	)

	velocity = dir * speed
	move_and_slide()

	# Dynamic map barrier. The valid walking surface is derived from the
	# current Ground2/Plantable tiles and therefore expands together with
	# player-built terrain.
	WorldBoundsSystem.constrain_player_after_move(
		self,
		previous_position
	)

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


# Synchronizes the player with the current plant selection.
func _sync_selected_plant() -> void:
	selected_data = PlantSelectionSystem.get_current_plant()


# Applies a selected or deselected plant to placement behavior.
func _on_plant_selection_changed(
	plant_data: PlantData,
	_index: int
) -> void:
	selected_data = plant_data

	if Input.is_action_pressed("aim_mode"):
		_update_highlight()

	if not debug_log:
		return

	if selected_data == null:
		print("[Player] selected plant=NONE")
	else:
		print(
			"[Player] selected plant=",
			selected_data.display_name,
			" seed=",
			String(selected_data.seed_item_id),
			" available=",
			InventorySystem.get_amount(
				selected_data.seed_item_id
			)
		)


# Validate and execute the selected tool action
func _apply_current_tool() -> void:
	var t: int = Toolsystem.current_tool

	if not Toolsystem.can_use_tool(t):
		return

	var a = _get_anchor_cell()
	if a == null:
		return
	var cell: Vector2i = a

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
			_do_ph(
				cell,
				lime_amount,
				ProgressionSystem.EQUIPMENT_LIME
			)
		ToolSystem.Tool.ACID:
			_do_ph(
				cell,
				acid_amount,
				ProgressionSystem.EQUIPMENT_ACID
			)
		ToolSystem.Tool.PESTICIDE:
			_do_pesticide(cell)
		ToolSystem.Tool.FUNGICIDE:
			_do_fungicide(cell)
		ToolSystem.Tool.SHOVEL:
			_do_shovel(cell)
		ToolSystem.Tool.HARVEST:
			_do_harvest(cell)
		_:
			return

	# Durability is consumed only after a validated tool action. Planting is
	# intentionally maintenance-free and therefore ignored by ToolSystem.
	Toolsystem.consume_use(t)


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
			if selected_data == null:
				ok = false
			else:
				ok = _can_plant_at(a, selected_data)

				if selected_data.footprint_size == Vector2i(2, 1):
					use_2x1 = true
					center = _get_footprint_center_global(
						a,
						selected_data
					)

		ToolSystem.Tool.PESTICIDE, ToolSystem.Tool.FUNGICIDE, ToolSystem.Tool.SHOVEL:
			ok = _has_plant_at(a)

			var p = PlantRegistry.get_plant(a)
			if p != null:
				var pd: PlantData = p.get("data")
				var anch: Vector2i = p.get("anchor_cell")
				if pd != null and pd.footprint_size == Vector2i(2, 1):
					use_2x1 = true
					center = _get_footprint_center_global(anch, pd)

		ToolSystem.Tool.HARVEST:
			ok = _can_harvest_at(a)

			var harvest_plant = PlantRegistry.get_plant(a)
			if harvest_plant != null:
				var harvest_data: PlantData = harvest_plant.get("data")
				var harvest_anchor: Vector2i = harvest_plant.get("anchor_cell")
				if harvest_data != null and harvest_data.footprint_size == Vector2i(2, 1):
					use_2x1 = true
					center = _get_footprint_center_global(
						harvest_anchor,
						harvest_data
					)

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
			if plant_scene == null:
				return ActionCheck.new(false, "NO_PLANT_SCENE")
			return _validate_plant_at(a, selected_data)

		ToolSystem.Tool.WATER, ToolSystem.Tool.FERTILIZE, ToolSystem.Tool.LIME, ToolSystem.Tool.ACID:
			if BiomeSystem.get_zone_id(a) == -1:
				return ActionCheck.new(false, "NO_ZONE")
			return ActionCheck.new(true, "")

		ToolSystem.Tool.PESTICIDE, ToolSystem.Tool.FUNGICIDE, ToolSystem.Tool.SHOVEL:
			if PlantRegistry.get_plant(a) == null:
				return ActionCheck.new(false, "NO_PLANT_ON_CELL")
			return ActionCheck.new(true, "")

		ToolSystem.Tool.HARVEST:
			return _validate_harvest_at(a)

		_:
			return ActionCheck.new(false, "UNKNOWN_TOOL")


# Validate planting constraints for a footprint
func _validate_plant_at(anchor: Vector2i, pd: PlantData) -> ActionCheck:
	var footprint := _get_footprint_cells(anchor, pd)

	for fc in footprint:
		var td: TileData = tilemap.get_cell_tile_data(plantable_layer, fc)
		if td == null:
			return ActionCheck.new(false, "FOOTPRINT_NOT_PLANTABLE")

		var soil: String = BiomeSystem.get_soil_type_at_cell(fc)
		if soil == "":
			return ActionCheck.new(false, "NO_SOIL_TYPE")

		if not pd.allowed_soils.has(soil):
			return ActionCheck.new(false, "WRONG_SOIL(%s)" % soil)

	for fc in footprint:
		if PlantRegistry.get_plant(fc) != null:
			return ActionCheck.new(false, "OCCUPIED")

		# A plantable tile may now also contain a player-built farm object,
		# especially a sprinkler placed on the outer Loamy/Sandy biome edge.
		# Keep the soil tile intact for BiomeSystem, but reserve that crop cell
		# while the build object occupies it.
		if BuildSystem.has_build_object_at(fc):
			return ActionCheck.new(
				false,
				"BLOCKED_BY_BUILD_OBJECT"
			)

	if pd.seed_item_id == &"":
		return ActionCheck.new(false, "NO_SEED_ITEM_ID")

	var planting_cost := maxi(pd.planting_cost, 0)
	var available_seeds := InventorySystem.get_amount(pd.seed_item_id)

	if planting_cost > 0 and available_seeds < planting_cost:
		return ActionCheck.new(
			false,
			"INSUFFICIENT_SEEDS(%s required=%d available=%d)" % [
				String(pd.seed_item_id),
				planting_cost,
				available_seeds
			]
		)

	return ActionCheck.new(true, "")


# Validate harvest state and reward configuration for the target plant.
func _validate_harvest_at(a: Vector2i) -> ActionCheck:
	var plant = PlantRegistry.get_plant(a)

	if plant == null:
		return ActionCheck.new(false, "NO_PLANT_ON_CELL")

	if bool(plant.get("is_dead")):
		return ActionCheck.new(false, "PLANT_DEAD")

	if not plant.has_method("is_ready_to_harvest") or not plant.has_method("harvest"):
		return ActionCheck.new(false, "PLANT_NOT_HARVESTABLE")

	if not bool(plant.call("is_ready_to_harvest")):
		return ActionCheck.new(false, "PLANT_NOT_READY")

	var pd: PlantData = plant.get("data")
	if pd == null:
		return ActionCheck.new(false, "NO_PLANT_DATA")

	if pd.harvest_item_id == &"":
		return ActionCheck.new(false, "NO_HARVEST_ITEM_ID")

	var rewards := ProgressionSystem.get_harvest_rewards(
		pd.harvest_item_id
	)

	if int(rewards.get("seed_gain", 0)) <= 0:
		return ActionCheck.new(false, "INVALID_HARVEST_REWARD")

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

	if (
		t == ToolSystem.Tool.PESTICIDE
		or t == ToolSystem.Tool.FUNGICIDE
		or t == ToolSystem.Tool.SHOVEL
		or t == ToolSystem.Tool.HARVEST
	):
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


# Check whether the selected plant is currently harvestable.
func _can_harvest_at(a: Vector2i) -> bool:
	if not _can_affect_zone_at(a):
		return false
	return _validate_harvest_at(a).ok


# Zone tool actions
func _do_water(a: Vector2i) -> void:
	var multiplier: float = (
		ProgressionSystem.get_equipment_effectiveness_multiplier(
			ProgressionSystem.EQUIPMENT_WATERING_CAN
		)
	)
	var effective_amount: float = water_amount * multiplier

	BiomeSystem.add_moisture(a, effective_amount)
	_spawn_fx_cell(a, Color(0.3, 0.6, 1.0, 0.9))
	_spawn_particles_cell(a, "water", Vector2.ONE)

	if debug_log:
		print(
			"[Action] WATER cell=",
			a,
			" base=",
			water_amount,
			" equipment_x=",
			multiplier,
			" applied=",
			effective_amount
		)


# Apply fertilizer to the zone and spawn effects
func _do_fertilize(a: Vector2i) -> void:
	var multiplier: float = (
		ProgressionSystem.get_equipment_effectiveness_multiplier(
			ProgressionSystem.EQUIPMENT_FERTILIZER
		)
	)
	var effective_amount: float = fertilizer_amount * multiplier

	BiomeSystem.add_nutrients(a, effective_amount)
	_spawn_fx_cell(a, Color(0.3, 1.0, 0.4, 0.9))
	_spawn_particles_cell(a, "fertilize", Vector2.ONE)

	if debug_log:
		print(
			"[Action] FERTILIZE cell=",
			a,
			" base=",
			fertilizer_amount,
			" equipment_x=",
			multiplier,
			" applied=",
			effective_amount
		)


# Apply pH change to the zone and spawn effects
func _do_ph(
	a: Vector2i,
	delta: float,
	equipment_id: StringName
) -> void:
	var multiplier: float = (
		ProgressionSystem.get_equipment_effectiveness_multiplier(
			equipment_id
		)
	)
	var effective_delta: float = delta * multiplier

	BiomeSystem.add_ph(a, effective_delta)
	if effective_delta >= 0.0:
		_spawn_fx_cell(a, Color(0.95, 0.95, 0.95, 0.9))
		_spawn_particles_cell(a, "lime", Vector2.ONE)
	else:
		_spawn_fx_cell(a, Color(0.7, 0.3, 1.0, 0.9))
		_spawn_particles_cell(a, "acid", Vector2.ONE)

	if debug_log:
		print(
			"[Action] PH cell=",
			a,
			" base=",
			delta,
			" equipment_x=",
			multiplier,
			" applied=",
			effective_delta
		)


# Plant tool actions
func _do_pesticide(a: Vector2i) -> void:
	var plant = PlantRegistry.get_plant(a)
	var multiplier: float = (
		ProgressionSystem.get_equipment_effectiveness_multiplier(
			ProgressionSystem.EQUIPMENT_PESTICIDE
		)
	)
	var effective_amount: float = pesticide_amount * multiplier

	plant.call("apply_pesticide", effective_amount)
	_spawn_fx_plant(a, Color(1.0, 0.6, 0.2, 0.9))
	_spawn_particles_plant(a, "pesticide")

	if debug_log:
		print(
			"[Action] PESTICIDE cell=",
			a,
			" base=",
			pesticide_amount,
			" equipment_x=",
			multiplier,
			" applied=",
			effective_amount
		)


# Apply fungicide to the target plant and spawn effects
func _do_fungicide(a: Vector2i) -> void:
	var plant = PlantRegistry.get_plant(a)
	var multiplier: float = (
		ProgressionSystem.get_equipment_effectiveness_multiplier(
			ProgressionSystem.EQUIPMENT_FUNGICIDE
		)
	)
	var effective_amount: float = fungicide_amount * multiplier

	plant.call("apply_fungicide", effective_amount)
	_spawn_fx_plant(a, Color(0.2, 1.0, 1.0, 0.9))
	_spawn_particles_plant(a, "fungicide")

	if debug_log:
		print(
			"[Action] FUNGICIDE cell=",
			a,
			" base=",
			fungicide_amount,
			" equipment_x=",
			multiplier,
			" applied=",
			effective_amount
		)


# Remove the target plant and spawn effects
func _do_shovel(a: Vector2i) -> void:
	_spawn_fx_plant(a, Color(1.0, 0.2, 0.2, 0.9))
	_spawn_particles_plant(a, "shovel")

	var plant = PlantRegistry.get_plant(a)
	var recovered_item: StringName = &""
	var recovered_amount: int = 0
	var recovery_chance: float = (
		ProgressionSystem.get_shovel_seed_recovery_chance()
	)

	if plant != null:
		var pd: PlantData = plant.get("data")

		if (
			pd != null
			and pd.seed_item_id != &""
			and recovery_chance > 0.0
			and randf() <= recovery_chance
		):
			recovered_item = pd.seed_item_id
			recovered_amount = maxi(
				pd.planting_cost,
				1
			)

	if plant.has_method("despawn"):
		plant.call("despawn")
	else:
		plant.queue_free()

	if recovered_item != &"" and recovered_amount > 0:
		InventorySystem.add_item(
			recovered_item,
			recovered_amount
		)

	if debug_log:
		print(
			"[Action] SHOVEL cell=",
			a,
			" removed recovery_chance=",
			recovery_chance,
			" recovered_item=",
			String(recovered_item),
			" recovered_amount=",
			recovered_amount
		)


# Harvest the target plant and apply level-based rewards.
func _do_harvest(a: Vector2i) -> void:
	var plant = PlantRegistry.get_plant(a)
	if plant == null:
		_invalid_feedback(
			ToolSystem.Tool.HARVEST,
			a,
			"NO_PLANT_ON_CELL"
		)
		return

	var pd: PlantData = plant.get("data")
	if pd == null:
		_invalid_feedback(
			ToolSystem.Tool.HARVEST,
			a,
			"NO_PLANT_DATA"
		)
		return

	var plant_position: Vector2 = plant.global_position
	var scale_cells := Vector2(
		pd.footprint_size.x,
		pd.footprint_size.y
	)

	# Resolve rewards from the current plant mastery level.
	var rewards := ProgressionSystem.get_harvest_rewards(
		pd.harvest_item_id
	)
	var plant_level_before := int(
		rewards.get("plant_level", 0)
	)
	var base_seed_gain := int(
		rewards.get("seed_gain", 0)
	)
	var base_money_gain := int(
		rewards.get("money_gain", 0)
	)
	var harvest_multiplier: float = (
		ProgressionSystem.get_equipment_effectiveness_multiplier(
			ProgressionSystem.EQUIPMENT_HARVEST
		)
	)

	# Plant health is captured BEFORE harvest mutates/despawns the plant.
	# Full health preserves the existing balance. Poor health reduces both
	# money and seed yield, making actual plant care economically meaningful.
	var max_health: float = maxf(
		pd.max_health,
		0.001
	)
	var health_ratio: float = clampf(
		float(plant.get("health")) / max_health,
		0.0,
		1.0
	)
	var quality_rewards: Dictionary = (
		_calculate_harvest_quality_rewards(
			base_seed_gain,
			base_money_gain,
			health_ratio,
			harvest_multiplier
		)
	)
	var seed_gain: int = int(
		quality_rewards.get("seed_gain", 0)
	)
	var money_gain: int = int(
		quality_rewards.get("money_gain", 0)
	)
	var money_health_multiplier: float = float(
		quality_rewards.get(
			"money_health_multiplier",
			1.0
		)
	)
	var player_xp_gain := int(
		rewards.get("player_xp_gain", 0)
	)
	var plant_xp_gain := maxi(
		pd.plant_mastery_xp_per_harvest,
		1
	)

	var result_value = plant.call(
		"harvest",
		seed_gain
	)

	if not (result_value is Dictionary):
		_invalid_feedback(
			ToolSystem.Tool.HARVEST,
			a,
			"INVALID_HARVEST_RESULT"
		)
		return

	var result: Dictionary = result_value
	if not bool(result.get("ok", false)):
		_invalid_feedback(
			ToolSystem.Tool.HARVEST,
			a,
			String(
				result.get(
					"reason",
					"HARVEST_FAILED"
				)
			)
		)
		return

	var item_id := StringName(
		result.get("item_id", &"")
	)
	var yield_amount := int(
		result.get("yield_amount", 0)
	)
	var regrows := bool(
		result.get("regrows", false)
	)
	var previous_stage := int(
		result.get("previous_stage", -1)
	)
	var new_stage := int(
		result.get("new_stage", -1)
	)

	# Very poor plant health can reduce the seed yield to zero.
	# Harvest itself still succeeds and can still award money / XP.
	if yield_amount > 0:
		if not InventorySystem.add_item(
			item_id,
			yield_amount
		):
			push_error(
				"[Harvest] Reward add failed item=%s amount=%d" % [
					String(item_id),
					yield_amount
				]
			)
			return

	EconomySystem.add_money(
		money_gain,
		"HARVEST_%s" % pd.display_name
	)

	ProgressionSystem.add_player_xp(
		player_xp_gain,
		"HARVEST_%s" % pd.display_name
	)

	ProgressionSystem.add_plant_xp(
		item_id,
		plant_xp_gain,
		"HARVEST_%s" % pd.display_name
	)

	var plant_level_after := (
		ProgressionSystem.get_plant_level(item_id)
	)

	_spawn_fx_at(
		plant_position,
		Color(1.0, 0.85, 0.25, 0.95),
		scale_cells
	)
	_spawn_particles_at(
		plant_position,
		"harvest",
		scale_cells
	)

	if debug_log:
		print(
			"[Action] HARVEST ",
			pd.display_name,
			" cell=",
			a,
			" item=",
			String(item_id),
			" seeds=",
			yield_amount,
			" seed_total=",
			InventorySystem.get_amount(item_id),
			" money=",
			money_gain,
			" money_base=",
			base_money_gain,
			" health=",
			snapped(health_ratio * 100.0, 0.1),
			"%",
			" health_money_x=",
			snapped(money_health_multiplier, 0.01),
			" harvest_equipment_x=",
			harvest_multiplier,
			" money_total=",
			EconomySystem.get_money(),
			" player_xp=",
			player_xp_gain,
			" plant_xp=",
			plant_xp_gain,
			" plant_level=",
			plant_level_before,
			"->",
			plant_level_after,
			" regrows=",
			regrows,
			" stage=",
			previous_stage,
			"->",
			new_stage
		)


# Calculates the harvest reward after plant-health quality is applied.
#
# Money:
# - 100% health = 100% of the existing reward.
# - 0% health = harvest_health_money_floor of the existing reward.
# - Values between those points scale continuously.
#
# Seeds:
# - Scale directly with health and round to the nearest whole seed.
# - This can reach zero for a severely unhealthy plant.
# - At full health, the existing mastery seed reward is unchanged.
func _calculate_harvest_quality_rewards(
	base_seed_gain: int,
	base_money_gain: int,
	health_ratio: float,
	equipment_multiplier: float = 1.0
) -> Dictionary:
	var safe_health: float = clampf(
		health_ratio,
		0.0,
		1.0
	)
	var safe_money_floor: float = clampf(
		harvest_health_money_floor,
		0.0,
		1.0
	)
	var money_health_multiplier: float = lerpf(
		safe_money_floor,
		1.0,
		safe_health
	)

	var seed_gain: int = maxi(
		int(round(
			float(maxi(base_seed_gain, 0))
			* safe_health
		)),
		0
	)

	var money_gain: int = maxi(
		int(round(
			float(maxi(base_money_gain, 0))
			* maxf(equipment_multiplier, 0.0)
			* money_health_multiplier
		)),
		0
	)

	return {
		"health_ratio": safe_health,
		"seed_gain": seed_gain,
		"money_gain": money_gain,
		"money_health_multiplier": money_health_multiplier
	}


# Plant placement action
func _do_plant(a: Vector2i) -> void:
	var pd := selected_data
	var footprint := _get_footprint_cells(a, pd)
	var planting_cost := maxi(pd.planting_cost, 0)

	var world_pos: Vector2 = _get_footprint_center_global(a, pd)
	world_pos.y += plant_y_offset

	var plant := plant_scene.instantiate() as Node2D
	if plant == null:
		_invalid_feedback(ToolSystem.Tool.PLANT, a, "PLANT_SCENE_INSTANTIATE_FAILED")
		return

	if planting_cost > 0:
		var seed_removed := InventorySystem.remove_item(
			pd.seed_item_id,
			planting_cost
		)

		if not seed_removed:
			plant.queue_free()
			_invalid_feedback(
				ToolSystem.Tool.PLANT,
				a,
				"INSUFFICIENT_SEEDS(%s)" % String(pd.seed_item_id)
			)
			return

	plant.name = "%s_%s_%s" % [pd.display_name, a.x, a.y]
	plant.global_position = world_pos
	plant.set("data", pd)
	plant.set("anchor_cell", a)
	plant.set("occupied_cells", footprint)

	plants_parent.add_child(plant)

	for fc in footprint:
		PlantRegistry.register(fc, plant)

	_spawn_fx_at(
		world_pos,
		Color(0.35, 1.0, 0.5, 0.9),
		Vector2(pd.footprint_size.x, pd.footprint_size.y)
	)

	# Reuse the fertilizer particle style for planting soil feedback.
	_spawn_particles_at(
		world_pos,
		"fertilize",
		Vector2(pd.footprint_size.x, pd.footprint_size.y)
	)

	if debug_log:
		print(
			"[Action] PLANT ",
			pd.display_name,
			" anchor=",
			a,
			" footprint=",
			footprint,
			" seed=",
			String(pd.seed_item_id),
			" cost=",
			planting_cost,
			" remaining=",
			InventorySystem.get_amount(pd.seed_item_id)
		)


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


# Returns the equipment progression identifier for one tool.
func _equipment_id_for_tool(tool_id: int) -> StringName:
	match tool_id:
		ToolSystem.Tool.WATER:
			return ProgressionSystem.EQUIPMENT_WATERING_CAN
		ToolSystem.Tool.FERTILIZE:
			return ProgressionSystem.EQUIPMENT_FERTILIZER
		ToolSystem.Tool.LIME:
			return ProgressionSystem.EQUIPMENT_LIME
		ToolSystem.Tool.ACID:
			return ProgressionSystem.EQUIPMENT_ACID
		ToolSystem.Tool.PESTICIDE:
			return ProgressionSystem.EQUIPMENT_PESTICIDE
		ToolSystem.Tool.FUNGICIDE:
			return ProgressionSystem.EQUIPMENT_FUNGICIDE
		ToolSystem.Tool.SHOVEL:
			return ProgressionSystem.EQUIPMENT_SHOVEL
		ToolSystem.Tool.HARVEST:
			return ProgressionSystem.EQUIPMENT_HARVEST

	return &""


# Returns the current interaction range for the selected tool.
func _get_active_tool_range_cells() -> int:
	var tool_id: int = Toolsystem.current_tool
	var equipment_id: StringName = (
		_equipment_id_for_tool(tool_id)
	)

	if equipment_id == &"":
		return plant_range_cells

	return plant_range_cells + (
		ProgressionSystem.get_equipment_range_bonus(
			equipment_id
		)
	)


# Check player interaction range in tile cells.
func _is_in_range(c: Vector2i) -> bool:
	var player_cell: Vector2i = tilemap.local_to_map(
		tilemap.to_local(global_position)
	)
	var dx: int = abs(c.x - player_cell.x)
	var dy: int = abs(c.y - player_cell.y)
	var active_range: int = _get_active_tool_range_cells()

	return max(dx, dy) <= active_range


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
		"harvest":
			ToolParticles.spawn_harvest(world_pos, cell_px, scale_cells)
		_:
			# Default particel style
			ToolParticles.spawn_fertilize(world_pos, cell_px, scale_cells)
