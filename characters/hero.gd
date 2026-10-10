class_name Hero
extends CharacterBody2D
## Placeholder controllable character (M0): movement and aim only.
## Combat comes in M1 as components; control will move to a pluggable controller in M3.

const STICK_AIM_DEADZONE := 0.3

@export var max_speed: float = 90.0
@export var acceleration: float = 900.0
@export var friction: float = 1100.0
@export var radius: float = 6.0
@export var body_color: Color = Color(0.85, 0.75, 0.55)

## Normalized direction the character faces / attacks toward.
var aim_direction: Vector2 = Vector2.RIGHT

var _using_stick_aim := false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_using_stick_aim = false


func _physics_process(delta: float) -> void:
	var move_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if move_input != Vector2.ZERO:
		velocity = velocity.move_toward(move_input * max_speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	move_and_slide()
	_update_aim()
	queue_redraw()


func _update_aim() -> void:
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length() > STICK_AIM_DEADZONE:
		_using_stick_aim = true
		aim_direction = stick.normalized()
	elif not _using_stick_aim:
		var to_mouse := get_global_mouse_position() - global_position
		if to_mouse.length() > 1.0:
			aim_direction = to_mouse.normalized()


func _draw() -> void:
	draw_circle(Vector2(0, 2), radius, Color(0, 0, 0, 0.35))
	draw_circle(Vector2.ZERO, radius, body_color)
	var base := aim_direction * radius
	var side := aim_direction.orthogonal() * 3.0
	var tip := aim_direction * (radius + 6.0)
	draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), Color.WHITE)
