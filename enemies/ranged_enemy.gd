class_name RangedEnemy
extends Enemy
## Archer special: keeps its distance, needs line of sight, telegraphs a shot along an aim line.
## Shots are blockable and dodgeable; the answer is to close in or kill it from range.

@export var preferred_range: float = 110.0
## Backs away when the target gets closer than this.
@export var flee_range: float = 60.0
@export var projectile_speed: float = 230.0
@export var projectile_range: float = 240.0

var _strafe_sign := 1.0
var _strafe_switch_left := 0.0


func _chase() -> Vector2:
	if not _target_valid():
		state = State.IDLE
		return Vector2.ZERO
	var to_target := target.global_position - global_position
	var distance := to_target.length()
	aim_direction = to_target / maxf(distance, 0.001)
	var sees_target := _has_line_of_sight()
	var shot := attacks[0] if not attacks.is_empty() else null
	if sees_target and shot and distance <= projectile_range * 0.8 and _cooldown_left <= 0.0 and _try_start_attack(shot):
		return Vector2.ZERO
	if not sees_target or distance > preferred_range * 1.3:
		return _path_toward_target(distance)
	if distance < flee_range:
		return -aim_direction * move_speed
	_strafe_switch_left -= get_physics_process_delta_time()
	if _strafe_switch_left <= 0.0:
		_strafe_switch_left = randf_range(1.0, 2.5)
		_strafe_sign = -_strafe_sign
	return aim_direction.orthogonal() * move_speed * 0.35 * _strafe_sign


func _begin_active() -> void:
	var projectile := Projectile.launch(self, _attack, aim_direction, projectile_speed)
	projectile.max_distance = projectile_range


func _has_line_of_sight() -> bool:
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position, PhysicsLayers.WORLD)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _draw_windup_telegraph(canvas: CanvasItem) -> void:
	var t := clampf(_phase_time / _attack.windup, 0.0, 1.0)
	var end := aim_direction * projectile_range * 0.6
	canvas.draw_line(Vector2.ZERO, end, Color(1.0, 0.85, 0.2, 0.15 + 0.45 * t), 1.0 + t * 1.5)
