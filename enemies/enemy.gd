class_name Enemy
extends Combatant
## Melee enemy brain: chase the nearest party member, request an attack token,
## telegraph, swing. Tracking is limited during wind-up so sidestepping works.

enum State { IDLE, CHASE, WINDUP, ACTIVE, RECOVERY, STAGGERED }

const RETARGET_INTERVAL := 0.5

@export var move_speed: float = 50.0
@export var attacks: Array[AttackData] = []
@export var attack_cooldown: float = 1.2
@export var token_cost: int = 1
## Max turn speed (rad/s) while winding up. Low = easier to dodge sideways.
@export var windup_turn_rate: float = 1.5
## Minimum stagger tier that interrupts this enemy's attacks (super armor below it).
@export var interrupt_tier: StaggerTier = StaggerTier.FLINCH
@export var show_health_bar: bool = false

var target: Combatant
var state: State = State.IDLE

var _attack: AttackData
var _swing: MeleeSwing
var _phase_time := 0.0
var _cooldown_left := 0.0
## Who we hold an attack token from. Kept separate from `target`, which can change or die.
var _token_holder: Combatant
var _retarget_left := 0.0


func _ready() -> void:
	super._ready()
	team = Team.ENEMY
	add_to_group("enemies")
	_cooldown_left = randf() * attack_cooldown


func _exit_tree() -> void:
	_release_token()


func is_winding_up() -> bool:
	return state == State.WINDUP


func _physics_process(delta: float) -> void:
	update_combat_state(delta)
	queue_redraw()
	_cooldown_left -= delta
	_retarget_left -= delta
	var attacking := state == State.WINDUP or state == State.ACTIVE or state == State.RECOVERY
	if not attacking and (_retarget_left <= 0.0 or not _target_valid()):
		_retarget_left = RETARGET_INTERVAL
		_pick_target()

	var desired := Vector2.ZERO
	match state:
		State.IDLE:
			if _target_valid():
				state = State.CHASE
		State.STAGGERED:
			if not is_staggered():
				state = State.CHASE
		State.CHASE:
			desired = _chase()
		State.WINDUP:
			_phase_time += delta
			if _target_valid():
				var to_target := target.global_position - global_position
				var turn := clampf(aim_direction.angle_to(to_target), -windup_turn_rate * delta, windup_turn_rate * delta)
				aim_direction = aim_direction.rotated(turn)
			desired = aim_direction * move_speed * _attack.move_speed_multiplier
			if _phase_time >= _attack.windup:
				state = State.ACTIVE
				_phase_time = 0.0
				_swing = MeleeSwing.new(self, _attack, aim_direction, PhysicsLayers.PARTY_BODY)
				knockback_velocity += aim_direction * _attack.lunge_speed
		State.ACTIVE:
			_phase_time += delta
			if _swing.advance(clampf(_phase_time / maxf(_attack.active, 0.001), 0.0, 1.0)) > 0:
				Juice.shake(_attack.shake)
			if _phase_time >= _attack.active:
				state = State.RECOVERY
				_phase_time = 0.0
		State.RECOVERY:
			_phase_time += delta
			if _phase_time >= _attack.recovery:
				_end_attack()
				state = State.CHASE

	velocity = desired + knockback_velocity
	move_and_slide()


func _chase() -> Vector2:
	if not _target_valid():
		state = State.IDLE
		return Vector2.ZERO
	var to_target := target.global_position - global_position
	var distance := to_target.length() - target.body_radius - body_radius
	aim_direction = to_target.normalized()
	var attack := _pick_attack(distance)
	if attack and _cooldown_left <= 0.0 and target.request_attack_token(token_cost):
		_token_holder = target
		_attack = attack
		state = State.WINDUP
		_phase_time = 0.0
		return Vector2.ZERO
	# Hold just inside reach instead of shoving into the target.
	var min_reach := attacks[0].reach if not attacks.is_empty() else 12.0
	if distance > min_reach * 0.6:
		return aim_direction * move_speed
	return Vector2.ZERO


func _pick_attack(distance: float) -> AttackData:
	var in_range: Array[AttackData] = []
	for attack in attacks:
		if distance <= attack.reach * 0.9:
			in_range.append(attack)
	return in_range.pick_random() if not in_range.is_empty() else null


func _pick_target() -> void:
	var best: Combatant = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("party"):
		var candidate := node as Combatant
		if candidate and not candidate.is_dead:
			var d := global_position.distance_squared_to(candidate.global_position)
			if d < best_dist:
				best_dist = d
				best = candidate
	target = best


func _target_valid() -> bool:
	return is_instance_valid(target) and not target.is_dead


func _end_attack() -> void:
	_swing = null
	_release_token()
	_cooldown_left = attack_cooldown * randf_range(0.8, 1.2)


func _release_token() -> void:
	if is_instance_valid(_token_holder):
		_token_holder.release_attack_token(token_cost)
	_token_holder = null


func _on_staggered(tier: int) -> void:
	var attacking := state == State.WINDUP or state == State.ACTIVE
	if attacking and tier < interrupt_tier:
		# Super armor: shrug off light stagger mid-attack.
		stagger_time = 0.0
		stagger_tier = StaggerTier.NONE
		return
	if attacking or state == State.RECOVERY:
		_end_attack()
	state = State.STAGGERED


func die(hit: HitInfo) -> void:
	_release_token()
	super.die(hit)


func _draw() -> void:
	match state:
		State.WINDUP:
			var t := clampf(_phase_time / _attack.windup, 0.0, 1.0)
			var color := Color(1.0, 0.5, 0.1) if _attack.block_cost >= 3 or _attack.unblockable else Color(0.9, 0.1, 0.1)
			CombatDraw.sector(self, aim_direction, _attack.reach + body_radius, _attack.arc_degrees, Color(color, 0.12))
			CombatDraw.sector(self, aim_direction, (_attack.reach + body_radius) * t, _attack.arc_degrees, Color(color, 0.3))
		State.ACTIVE:
			var progress := clampf(_phase_time / maxf(_attack.active, 0.001), 0.0, 1.0)
			CombatDraw.swing(self, aim_direction, _attack, progress, Color(1.0, 0.3, 0.2, 0.6))
	draw_body()
	draw_line(Vector2.ZERO, aim_direction * body_radius, Color(0, 0, 0, 0.6), 2.0)
	if show_health_bar and health < max_health:
		var width := body_radius * 3.0
		var top_left := Vector2(-width / 2, -body_radius - 7)
		draw_rect(Rect2(top_left, Vector2(width, 2)), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(top_left, Vector2(width * health / max_health, 2)), Color(0.85, 0.15, 0.15))
