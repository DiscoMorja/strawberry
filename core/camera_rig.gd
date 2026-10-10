class_name CameraRig
extends Camera2D
## Follows a target with smoothing and looks ahead toward its aim direction.
## Kept separate from characters so control swapping (M3) only changes `target`.
## Screen shake uses trauma (shake = trauma²) and is triggered through Juice.shake().

@export var target: Node2D
@export var look_ahead_distance: float = 40.0
@export var look_ahead_smoothing: float = 6.0
@export var max_shake_offset: float = 6.0
@export var trauma_decay: float = 1.8

var _look_ahead := Vector2.ZERO
var _trauma := 0.0


func _ready() -> void:
	add_to_group("game_camera")
	position_smoothing_enabled = true
	position_smoothing_speed = 8.0
	if is_instance_valid(target):
		global_position = target.global_position
		reset_smoothing()


func add_trauma(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func _process(delta: float) -> void:
	_trauma = maxf(0.0, _trauma - trauma_decay * delta)
	var shake := _trauma * _trauma * max_shake_offset
	offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	if not is_instance_valid(target):
		return
	var desired := Vector2.ZERO
	var aim: Variant = target.get("aim_direction")
	if aim is Vector2:
		desired = aim * look_ahead_distance
	_look_ahead = _look_ahead.lerp(desired, 1.0 - exp(-look_ahead_smoothing * delta))
	global_position = target.global_position + _look_ahead
