extends Node

# FX configuration and logging toggle
@export var fx_scene: PackedScene = preload("res://Scenes/FxBurst.tscn")

@export var debug_log: bool = true

# Spawn configured FxBurst at a world position
func spawn_fx(world_pos: Vector2, tint: Color, cell_scale: Vector2 = Vector2.ONE, duration: float = 0.25) -> void:
	if fx_scene == null:
		return

	var fx = fx_scene.instantiate() as Node2D
	fx.global_position = world_pos


	fx.set("tint", tint)
	fx.set("duration", duration)


	fx.set("start_scale", Vector2(0.85, 0.85) * cell_scale)
	fx.set("end_scale", Vector2(1.15, 1.15) * cell_scale)


	get_tree().current_scene.add_child(fx)

	if debug_log:
		print("[FX] spawn at=", world_pos, " tint=", tint, " scale=", cell_scale, " dur=", duration)
