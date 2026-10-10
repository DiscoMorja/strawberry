class_name Projectile
extends Node2D
## Straight-flying ranged attack. Resolved with a ray per physics frame so fast shots never
## tunnel. Travels on the ground plane; drawn at `draw_height` above it to read as airborne.

## Called instead of the default receive_hit when set: (target: Combatant, hit: HitInfo) -> void.
var on_hit: Callable
var attack: AttackData
var velocity: Vector2
var max_distance: float = 220.0
var target_mask: int = PhysicsLayers.PARTY_BODY
var color: Color = Color(0.9, 0.85, 0.6)
var length: float = 8.0
var draw_height: float = 8.0
## Draw a chain back to the source (hooks).
var tethered: bool = false

var _source: Combatant
var _source_team: int
var _travelled := 0.0


static func launch(source: Combatant, p_attack: AttackData, direction: Vector2, speed: float) -> Projectile:
	var projectile := Projectile.new()
	projectile._source = source
	projectile._source_team = source.team
	projectile.attack = p_attack
	projectile.velocity = direction.normalized() * speed
	projectile.position = source.global_position + direction.normalized() * (source.body_radius + 2.0)
	source.get_parent().add_child(projectile)
	return projectile


func _physics_process(delta: float) -> void:
	var step := velocity * delta
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step, target_mask | PhysicsLayers.WORLD)
	if is_instance_valid(_source):
		query.exclude = [_source.get_rid()]
	var result := get_world_2d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		var target := result.collider as Combatant
		if target and not target.is_dead and target.team != _source_team:
			_hit(target)
		queue_free()
		return
	global_position += step
	_travelled += step.length()
	if _travelled >= max_distance:
		queue_free()
	queue_redraw()


func _hit(target: Combatant) -> void:
	var hit := HitInfo.new()
	hit.attacker = _source if is_instance_valid(_source) else null
	hit.attack = attack
	hit.direction = velocity.normalized()
	hit.damage = attack.damage
	hit.stagger = attack.stagger
	hit.knockback = attack.knockback
	if on_hit.is_valid():
		on_hit.call(target, hit)
	else:
		target.receive_hit(hit)


func _draw() -> void:
	var tip := Vector2(0, -draw_height)
	draw_line(tip - velocity.normalized() * length, tip, color, 1.5)
	if tethered and is_instance_valid(_source):
		var hand := to_local(_source.global_position + Vector2(0, -_source.body_height * 0.5))
		draw_line(hand, tip, Color(0.45, 0.4, 0.35), 1.0)
