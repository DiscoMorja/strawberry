extends Node
## Blood and gibs (autoload). Splats persist in a per-scene BloodLayer;
## sprays are short-lived one-shot particles.

const BLOOD_COLORS: Array[Color] = [
	Color(0.45, 0.02, 0.03),
	Color(0.35, 0.01, 0.02),
	Color(0.55, 0.05, 0.05),
]

var _layer: BloodLayer


## The first particle burst and first floating label pay a one-time setup cost (shader
## pipelines, glyph caching) that otherwise lands as a stall on the first hit. Pay it while
## the game starts instead, off-screen. The caches are process-wide, so once is enough.
func _ready() -> void:
	await get_tree().process_frame
	var far := Vector2(-100000, -100000)
	bleed(far, Vector2.RIGHT, 30.0)
	Juice.popup_text(far, "0")


## Splats land on the ground around `origin` (feet); the spray starts `height` px above it.
func bleed(origin: Vector2, direction: Vector2, damage: float, height: float = 6.0) -> void:
	var layer := _get_layer()
	if layer == null:
		return
	var count := clampi(int(damage / 6.0), 1, 8)
	for i in count:
		var spread := direction.rotated(randf_range(-0.6, 0.6)) * randf_range(3.0, 10.0 + damage * 0.4)
		layer.add_splat(origin + spread, randf_range(0.8, 1.8) + damage * 0.02, BLOOD_COLORS.pick_random())
	_spray(origin + Vector2(0, -height), direction, count * 3, 90.0 + damage * 2.0)


func gib(origin: Vector2, direction: Vector2, mass: float, height: float = 6.0) -> void:
	var layer := _get_layer()
	if layer == null:
		return
	layer.add_splat(origin, 4.0 + mass * 1.5, BLOOD_COLORS[1])
	var count := int(10 + mass * 6)
	for i in count:
		var dir := direction.rotated(randf_range(-1.2, 1.2)) if direction != Vector2.ZERO else Vector2.from_angle(randf() * TAU)
		layer.add_splat(origin + dir * randf_range(2.0, 18.0 + mass * 4.0), randf_range(0.8, 2.6), BLOOD_COLORS.pick_random())
	var spray_origin := origin + Vector2(0, -height)
	_spray(spray_origin, direction, count * 2, 160.0)
	_spray(spray_origin, Vector2.ZERO, int(6 + mass * 2), 70.0, Color(0.6, 0.15, 0.12), 2.5)


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
	particles.z_as_relative = false
	particles.z_index = ZLayers.FX
	particles.finished.connect(particles.queue_free)
	_layer.get_parent().add_child(particles)
	particles.emitting = true


func _get_layer() -> BloodLayer:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	if not is_instance_valid(_layer) or _layer.get_parent() != scene:
		_layer = BloodLayer.new()
		_layer.z_as_relative = false
		_layer.z_index = ZLayers.BLOOD
		scene.add_child(_layer)
	return _layer
