extends Node
## Blood and gibs (autoload). Splats persist in a per-scene BloodLayer;
## sprays are short-lived one-shot particles.

const BLOOD_COLORS: Array[Color] = [
	Color(0.45, 0.02, 0.03),
	Color(0.35, 0.01, 0.02),
	Color(0.55, 0.05, 0.05),
]

var _layer: BloodLayer


func bleed(origin: Vector2, direction: Vector2, damage: float) -> void:
	var layer := _get_layer()
	if layer == null:
		return
	var count := clampi(int(damage / 6.0), 1, 8)
	for i in count:
		var spread := direction.rotated(randf_range(-0.6, 0.6)) * randf_range(3.0, 10.0 + damage * 0.4)
		layer.add_splat(origin + spread, randf_range(0.8, 1.8) + damage * 0.02, BLOOD_COLORS.pick_random())
	_spray(origin, direction, count * 3, 90.0 + damage * 2.0)


func gib(origin: Vector2, direction: Vector2, mass: float) -> void:
	var layer := _get_layer()
	if layer == null:
		return
	layer.add_splat(origin, 4.0 + mass * 1.5, BLOOD_COLORS[1])
	var count := int(10 + mass * 6)
	for i in count:
		var dir := direction.rotated(randf_range(-1.2, 1.2)) if direction != Vector2.ZERO else Vector2.from_angle(randf() * TAU)
		layer.add_splat(origin + dir * randf_range(2.0, 18.0 + mass * 4.0), randf_range(0.8, 2.6), BLOOD_COLORS.pick_random())
	_spray(origin, direction, count * 2, 160.0)
	_spray(origin, Vector2.ZERO, int(6 + mass * 2), 70.0, Color(0.6, 0.15, 0.12), 2.5)


func _spray(origin: Vector2, direction: Vector2, amount: int, speed: float,
		color: Color = BLOOD_COLORS[2], size: float = 1.5) -> void:
	var particles := CPUParticles2D.new()
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.amount = maxi(1, amount)
	particles.lifetime = 0.35
	particles.direction = direction if direction != Vector2.ZERO else Vector2.UP
	particles.spread = 40.0 if direction != Vector2.ZERO else 180.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = speed * 0.4
	particles.initial_velocity_max = speed
	particles.damping_min = speed * 2.0
	particles.damping_max = speed * 3.0
	particles.scale_amount_min = size * 0.6
	particles.scale_amount_max = size
	particles.color = color
	particles.position = origin
	particles.z_index = 10
	particles.finished.connect(particles.queue_free)
	_layer.get_parent().add_child(particles)
	particles.emitting = true


func _get_layer() -> BloodLayer:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	if not is_instance_valid(_layer) or _layer.get_parent() != scene:
		_layer = BloodLayer.new()
		scene.add_child(_layer)
		# First child: draws above the floor (parent) but below every character.
		scene.move_child(_layer, 0)
	return _layer
