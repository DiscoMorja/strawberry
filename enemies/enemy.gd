class_name Enemy
extends Combatant
## Melee enemy brain: chase the nearest party member, request an attack token,
## telegraph, swing. Tracking is limited during wind-up so sidestepping works.

enum State { IDLE, CHASE, WINDUP, ACTIVE, RECOVERY, STAGGERED }

const RETARGET_INTERVAL := 0.5
## Within this distance (px) enemies steer straight at the target instead of following the flow field.
const DIRECT_CHASE_DISTANCE := 40.0
## Enemies that can't get an attack token slow to a shuffle inside this distance (px).
const WAITING_RING := 36.0

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
## Seconds since the current attack's wind-up began (drives AttackData.motion_velocity).
var _attack_elapsed := 0.0
var _cooldown_left := 0.0
## Who we hold an attack token from. Kept separate from `target`, which can change or die.
var _token_holder: Combatant
var _retarget_left := 0.0
var _flow_field: FlowField
var _crowd: Crowd
var _was_animating := false


func _ready() -> void:
	super._ready()
	team = Team.ENEMY
	add_to_group("enemies")
	_cooldown_left = randf() * attack_cooldown
	_retarget_left = randf() * RETARGET_INTERVAL
	_flow_field = get_tree().get_first_node_in_group("flow_field") as FlowField
	_crowd = get_tree().get_first_node_in_group("crowd") as Crowd


func _exit_tree() -> void:
	_release_token()


func is_winding_up() -> bool:
	return state == State.WINDUP


func _physics_process(delta: float) -> void:
	update_combat_state(delta)
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
			_attack_elapsed += delta
			if _target_valid():
				var to_target := target.global_position - global_position
				var turn := clampf(aim_direction.angle_to(to_target), -windup_turn_rate * delta, windup_turn_rate * delta)
				aim_direction = aim_direction.rotated(turn)
			desired = _attack.motion_velocity(_attack_elapsed, aim_direction)
			if _phase_time >= _attack.windup:
				state = State.ACTIVE
				_phase_time = 0.0
				_swing = MeleeSwing.new(self, _attack, aim_direction, PhysicsLayers.PARTY_BODY)
		State.ACTIVE:
			_phase_time += delta
			_attack_elapsed += delta
			desired = _attack.motion_velocity(_attack_elapsed, aim_direction)
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

	if _crowd:
		desired += _crowd.separation(self)
	velocity = desired + knockback_velocity
	move_and_slide()
	_redraw_if_needed()


## Redrawing every enemy every frame is the main per-enemy render cost at horde sizes;
## position changes don't need a redraw, only visual state changes do.
func _redraw_if_needed() -> void:
	var animating := state == State.WINDUP or state == State.ACTIVE or is_staggered() or _flash_time > 0.0
	if animating or _was_animating or facing_sign_changed():
		redraw()
	_was_animating = animating


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
		_attack_elapsed = 0.0
		return Vector2.ZERO
	# Close in to just inside the shortest reach instead of shoving into the target.
	var min_reach := INF
	for a in attacks:
		min_reach = minf(min_reach, a.reach)
	if min_reach == INF:
		min_reach = 12.0
	if distance <= min_reach * 0.6:
		return Vector2.ZERO
	# No attack slot free: hover at the edge of the fight instead of piling in.
	if distance <= WAITING_RING and target.attackers_full():
		return aim_direction * move_speed * 0.15
	if distance > DIRECT_CHASE_DISTANCE and _flow_field:
		var flow := _flow_field.direction_at(global_position)
		if flow != Vector2.ZERO:
			return flow * move_speed
	return aim_direction * move_speed


func _pick_attack(distance: float) -> AttackData:
	var in_range: Array[AttackData] = []
	for attack in attacks:
		if distance >= attack.min_range and distance <= attack.trigger_range() * 0.9:
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
	draw_body()
	draw_weapon(body_radius + 4.0, Color(0.6, 0.55, 0.5))
	if show_health_bar and health < max_health:
		var width := body_radius * 3.0
		var top_left := head_position() - global_position + Vector2(-width / 2, 2)
		draw_rect(Rect2(top_left, Vector2(width, 2)), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(top_left, Vector2(width * health / max_health, 2)), Color(0.85, 0.15, 0.15))


func _draw_ground(canvas: CanvasItem) -> void:
	match state:
		State.WINDUP:
			var t := clampf(_phase_time / _attack.windup, 0.0, 1.0)
			var color := Color(1.0, 0.5, 0.1) if _attack.block_cost >= 3 or _attack.unblockable else Color(0.9, 0.1, 0.1)
			var radius := _attack.reach + body_radius
			CombatDraw.sector(canvas, aim_direction, radius, _attack.arc_degrees, Color(color, 0.12))
			CombatDraw.sector(canvas, aim_direction, radius * t, _attack.arc_degrees, Color(color, 0.3))
			if _attack.lunge_distance + _attack.windup_advance_speed > 20.0:
				# Moving attack: show where the lunge carries it.
				canvas.draw_line(Vector2.ZERO, aim_direction * (_attack.lunge_distance + radius), Color(color, 0.35), 1.0)
		State.ACTIVE:
			var progress := clampf(_phase_time / maxf(_attack.active, 0.001), 0.0, 1.0)
			CombatDraw.swing(canvas, aim_direction, _attack, progress, Color(1.0, 0.3, 0.2, 0.6))
