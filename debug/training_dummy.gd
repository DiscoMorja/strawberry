extends StaticBody2D
## Static target for testing movement and (from M1) attacks.

@export var radius: float = 7.0


func _ready() -> void:
	add_to_group("enemies")


func _draw() -> void:
	draw_circle(Vector2(0, 2), radius, Color(0, 0, 0, 0.35))
	draw_circle(Vector2.ZERO, radius, Color(0.55, 0.35, 0.25))
	draw_line(Vector2(-radius, 0), Vector2(radius, 0), Color(0.3, 0.2, 0.12), 2.0)
