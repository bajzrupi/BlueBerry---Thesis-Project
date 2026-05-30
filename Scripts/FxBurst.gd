extends Node2D

# Burst visual parameters
@export var duration: float = 0.25
@export var tint: Color = Color(1, 1, 1, 0.9)
@export var start_scale: Vector2 = Vector2(0.85, 0.85)
@export var end_scale: Vector2 = Vector2(1.15, 1.15)

@onready var spr: Sprite2D = $Sprite2D

# Play one-shot burst animation and self-destruct
func _ready() -> void:

	z_index = 1100


	spr.modulate = tint
	scale = start_scale

	var tw := create_tween()
	tw.tween_property(self, "scale", end_scale, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(spr, "modulate", Color(tint.r, tint.g, tint.b, 0.0), duration)
	tw.tween_callback(queue_free)
