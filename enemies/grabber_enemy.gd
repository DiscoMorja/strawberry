class_name GrabberEnemy
extends Enemy
## Disabler special: throws a hook, then drags its victim away from the group, hurting it over time.
## Released when the grabber is staggered or killed, when the victim struggles free, or after
## max_drag_time (victim knocked down). The hook is unblockable: dodge it or kill the grabber first.

@export var hook_speed: float = 260.0
@export var hook_range: float = 90.0
@export var drag_speed: float = 32.0
@export var max_drag_time: float = 4.0
@export var drag_damage_per_second: float = 8.0
@export var release_cooldown: float = 5.0

const DRAG_TICK := 0.5

var _victim: Combatant
var _drag_time := 0.0
var _drag_tick_left := 0.0
var _drag_attack := AttackData.new()


func _ready() -> void:
	super._ready()
	_drag_attack.name = "Drag"
	_drag_attack.unblockable = true
	_drag_attack.stagger = 0.0
	_drag_attack.knockback = 0.0
	_drag_attack.hit_stop = 0.0


func _begin_active() -> void:
	var hook := Projectile.launch(self, _attack, aim_direction, hook_speed)
	hook.max_distance = hook_range
	hook.tethered = true
	hook.color = Color(0.75, 0.7, 0.65)
	hook.on_hit = _on_hook_hit


func _on_hook_hit(victim: Combatant, hit: HitInfo) -> void:
	if not victim.receive_hit(hit) or victim.is_dead or is_dead or victim.is_grabbed():
		return
	if state != State.ACTIVE and state != State.RECOVERY:
		return
	_victim = victim
	victim.grabbed_by = self
	_drag_time = 0.0
	_drag_tick_left = DRAG_TICK
	state = State.CUSTOM
	Sfx.play_cue(Sfx.Cue.SPECIAL_GRABBER, 0.8)
	Juice.popup_text(victim.head_position(), "GRABBED!", priority_color, 10)


func release_grab(knock_down: bool = false) -> void:
	if is_instance_valid(_victim):
		if _victim.grabbed_by == self:
			_victim.grabbed_by = null
		if knock_down:
			_victim.stagger_tier = StaggerTier.KNOCKDOWN
			_victim.stagger_time = STAGGER_DURATIONS[StaggerTier.KNOCKDOWN]
			_victim._on_staggered(StaggerTier.KNOCKDOWN)
	_victim = null
	_end_attack()
	_cooldown_left = release_cooldown
	if state == State.CUSTOM:
		state = State.CHASE


func _tick_custom(delta: float) -> Vector2:
	if not is_instance_valid(_victim) or _victim.is_dead or _victim.grabbed_by != self:
		release_grab()
		return Vector2.ZERO
	_drag_time += delta
	_drag_tick_left -= delta
	if _drag_tick_left <= 0.0:
		_drag_tick_left = DRAG_TICK
		var tick := HitInfo.new()
		tick.attacker = self
		tick.attack = _drag_attack
		tick.direction = (_victim.global_position - global_position).normalized()
		tick.damage = drag_damage_per_second * DRAG_TICK
		_victim.receive_hit(tick)
	if _drag_time >= max_drag_time:
		release_grab(true)
		return Vector2.ZERO
	# Walk away from the victim, towing it.
	var away := (global_position - _victim.global_position).normalized()
	aim_direction = -away
	return away * drag_speed


func _on_staggered(tier: int) -> void:
	if state == State.CUSTOM:
		release_grab()
		Juice.popup_text(head_position(), "released", Color.WHITE)
	super._on_staggered(tier)


func die(hit: HitInfo) -> void:
	release_grab()
	super.die(hit)


func _draw() -> void:
	super._draw()
	if state == State.CUSTOM and is_instance_valid(_victim):
		var hand := Vector2(_facing_sign * body_radius * 0.6, -body_height * 0.5)
		var victim_chest := to_local(_victim.global_position) + Vector2(0, -_victim.body_height * 0.5)
		draw_line(hand, victim_chest, Color(0.45, 0.4, 0.35), 1.5)


func _draw_windup_telegraph(canvas: CanvasItem) -> void:
	var t := clampf(_phase_time / _attack.windup, 0.0, 1.0)
	canvas.draw_line(Vector2.ZERO, aim_direction * hook_range, Color(priority_color, 0.15 + 0.5 * t), 1.0 + t * 1.5)
	canvas.draw_arc(aim_direction * hook_range, 3.0, 0.0, TAU, 8, Color(priority_color, 0.3 + 0.5 * t), 1.0)
