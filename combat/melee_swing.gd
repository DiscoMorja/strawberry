class_name MeleeSwing
extends RefCounted
## Resolves one attack's active window as an arc that sweeps over time.
## Targets are hit in sweep order until the cleave budget is spent by their mass.

## Damage multiplier lost per extra target hit by the same swing.
const DAMAGE_FALLOFF_PER_TARGET := 0.15
const MIN_DAMAGE_MULTIPLIER := 0.4
const MAX_QUERY_RESULTS := 64

var attacker: Combatant
var attack: AttackData
var facing: Vector2
var target_mask: int

var _hit_ids: Dictionary = {}
var _cleave_left: float
var _hit_count := 0
var _finished := false
var _query := PhysicsShapeQueryParameters2D.new()
var _query_shape := CircleShape2D.new()


func _init(p_attacker: Combatant, p_attack: AttackData, p_facing: Vector2, p_target_mask: int) -> void:
	attacker = p_attacker
	attack = p_attack
	facing = p_facing.normalized()
	target_mask = p_target_mask
	_cleave_left = attack.cleave
	_query_shape.radius = attack.reach + 16.0
	_query.shape = _query_shape
	_query.collision_mask = target_mask
	_query.collide_with_areas = false
	_query.exclude = [attacker.get_rid()]


## Advances the sweep to `progress` (0..1 through the active window) and applies hits.
## Returns how many targets were hit by this call.
func advance(progress: float) -> int:
	if _finished:
		return 0
	var half := deg_to_rad(attack.arc_degrees) * 0.5
	var swept_to := -half + clampf(progress, 0.0, 1.0) * half * 2.0
	var entries: Array = []
	for target in _query_targets():
		var to := target.global_position - attacker.global_position
		var center_dist := to.length()
		if center_dist - target.body_radius > attack.reach:
			continue
		var rel := facing.angle_to(to)
		var angular_pad := atan2(target.body_radius, maxf(center_dist, 1.0))
		if absf(rel) > half + angular_pad:
			continue
		var key: float
		if attack.sweep_direction == 0:
			key = center_dist
		else:
			key = rel * attack.sweep_direction
			if key - angular_pad > swept_to:
				continue
		entries.append([key, target])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])

	var hits_now := 0
	for entry in entries:
		if _cleave_left <= 0.0:
			_finished = true
			break
		var target: Combatant = entry[1]
		_hit_ids[target.get_instance_id()] = true
		_cleave_left -= target.mass
		_apply_hit(target)
		hits_now += 1
	return hits_now


func _apply_hit(target: Combatant) -> void:
	var hit := HitInfo.new()
	hit.attacker = attacker
	hit.attack = attack
	hit.direction = (target.global_position - attacker.global_position).normalized()
	if hit.direction == Vector2.ZERO:
		hit.direction = facing
	var falloff := maxf(MIN_DAMAGE_MULTIPLIER, 1.0 - DAMAGE_FALLOFF_PER_TARGET * _hit_count)
	hit.damage = attack.damage * falloff
	hit.stagger = attack.stagger
	hit.knockback = attack.knockback
	# Crit window: punish enemies mid wind-up, or hit them from behind.
	hit.is_crit = target.is_winding_up() or target.aim_direction.dot(hit.direction) > 0.5
	_hit_count += 1
	target.receive_hit(hit)


func _query_targets() -> Array[Combatant]:
	var result: Array[Combatant] = []
	_query.transform = Transform2D(0.0, attacker.global_position)
	var space := attacker.get_world_2d().direct_space_state
	for hit in space.intersect_shape(_query, MAX_QUERY_RESULTS):
		var target := hit.collider as Combatant
		if target and target != attacker and not target.is_dead and not _hit_ids.has(target.get_instance_id()):
			result.append(target)
	return result
