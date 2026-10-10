class_name CameraRig
extends Camera2D
## Follows a target with smoothing and looks ahead toward its aim direction.
## Kept separate from characters so control swapping (M3) only changes `target`.

@export var target: Node2D
@export var look_ahead_distance: float = 40.0
@export var look_ahead_smoothing: float = 6.0

var _look_ahead := Vector2.ZERO


func _ready() -> void:
	position_smoothing_enabled = true
	position_smoothing_speed = 8.0
	if is_instance_valid(target):
		global_position = target.global_position
		reset_smoothing()


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var desired := Vector2.ZERO
	var aim: Variant = target.get("aim_direction")
	if aim is Vector2:
		desired = aim * look_ahead_distance
	_look_ahead = _look_ahead.lerp(desired, 1.0 - exp(-look_ahead_smoothing * delta))
	global_position = target.global_position + _look_ahead
