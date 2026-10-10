class_name Enemy
extends Combatant
## Enemy brain: chase the nearest party member, request an attack token, telegraph, attack.
## Tracking is limited during wind-up so sidestepping works. Specials extend this through
## the virtual hooks (_chase, _begin_active, _tick_custom, _draw_ground).

enum State { IDLE, CHASE, WINDUP, ACTIVE, RECOVERY, STAGGERED, CUSTOM }

const RETARGET_INTERVAL := 0.5
## Within this distance (px) enemies steer straight at the target instead of following the flow field.
const DIRECT_CHASE_DISTANCE := 40.0
## Enemies that can't get an attack token slow to a shuffle inside this distance (px).
const WAITING_RING := 36.0
const SHIELD_GUARD_BREAK_TIME := 1.0

@export var move_speed: float = 50.0
@export var attacks: Array[AttackData] = []
@export var attack_cooldown: float = 1.2
@export var token_cost: int = 1
## Max turn speed (rad/s) while winding up. Low = easier to dodge sideways.
@export var windup_turn_rate: float = 1.5
## Minimum stagger tier that interrupts this enemy's attacks (super armor below it).
@export var interrupt_tier: StaggerTier = StaggerTier.FLINCH
@export var show_health_bar: bool = false

@export_group("Shield")
## Frontal arc that blocks hits while the shield is up. 0 = no shield.
@export var shield_arc_degrees: float = 0.0
## Hits with at least this much stagger (heavies, pushes) break the guard instead of bouncing.
@export var shield_break_stagger: float = 24.0

@export_group("Priority")
## Priority targets (specials) get a ground ring, a spawn cue and off-screen indicators.
@export var is_priority: bool = false
@export var priority_color: Color = Color(1.0, 0.55, 0.1)
@export_enum("None:-1", "Elite:4", "Archer:5", "Grabber:6") var spawn_cue: int = -1

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
	if is_priority:
		add_to_group("priority")
	if spawn_cue >= 0:
		Sfx.play_cue(spawn_cue)


func _exit_tree() -> void:
	_release_token()


func is_winding_up() -> bool:
	return state == State.WINDUP


func is_attacking() -> bool:
	return state == State.WINDUP or state == State.ACTIVE or state == State.RECOVERY


func shield_up() -> bool:
	return shield_arc_degrees > 0.0 and not is_staggered() and state != State.ACTIVE and state != State.RECOVERY


func _physics_process(delta: float) -> void:
	update_combat_state(delta)
	_cooldown_left -= delta
	_retarget_left -= delta
	if not is_attacking() and state != State.CUSTOM and (_retarget_left <= 0.0 or not _target_valid()):
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
				_begin_active()
		State.ACTIVE:
			_phase_time += delta
			_attack_elapsed += delta
			desired = _attack.motion_velocity(_attack_elapsed, aim_direction)
			if _swing and _swing.advance(clampf(_phase_time / maxf(_attack.active, 0.001), 0.0, 1.0)) > 0:
				Juice.shake(_attack.shake)
			if _phase_time >= _attack.active:
				state = State.RECOVERY
				_phase_time = 0.0
		State.RECOVERY:
			_phase_time += delta
			if _phase_time >= _attack.recovery:
				_end_attack()
				state = State.CHASE
		State.CUSTOM:
			desired = _tick_custom(delta)

	if _crowd:
		desired += _crowd.separation(self)
	velocity = desired + knockback_velocity
	move_and_slide()
	_redraw_if_needed()


# --- Hooks for specials ------------------------------------------------------

## Called when the active window opens. Default: a melee sweep.
func _begin_active() -> void:
	_swing = MeleeSwing.new(self, _attack, aim_direction, PhysicsLayers.PARTY_BODY)


## Per-frame logic while in State.CUSTOM. Returns desired velocity.
func _tick_custom(_delta: float) -> Vector2:
	state = State.CHASE
	return Vector2.ZERO


func _chase() -> Vector2:
	if not _target_valid():
		state = State.IDLE
		return Vector2.ZERO
	var to_target := target.global_position - global_position
	var distance := to_target.length() - target.body_radius - body_radius
	aim_direction = to_target.normalized()
	var attack := _pick_attack(distance)
	if attack and _cooldown_left <= 0.0 and _try_start_attack(attack):
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
	return _path_toward_target(distance)


# --- Shared helpers ----------------------------------------------------------

func _try_start_attack(attack: AttackData) -> bool:
	if not target.request_attack_token(token_cost):
		return false
	_token_holder = target
	_attack = attack
	state = State.WINDUP
	_phase_time = 0.0
	_attack_elapsed = 0.0
	return true


func _path_toward_target(distance: float) -> Vector2:
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


## Redrawing every enemy every frame is the main per-enemy render cost at horde sizes;
## position changes don't need a redraw, only visual state changes do.
func _redraw_if_needed() -> void:
	var animating := is_priority or state == State.WINDUP or state == State.ACTIVE or state == State.CUSTOM \
			or is_staggered() or _flash_time > 0.0
	if animating or _was_animating or facing_sign_changed():
		redraw()
	_was_animating = animating


# --- Combat reactions --------------------------------------------------------

func _try_block(hit: HitInfo) -> bool:
	if not shield_up() or hit.attack.unblockable:
		return false
	if absf(aim_direction.angle_to(-hit.direction)) > deg_to_rad(shield_arc_degrees) * 0.5:
		return false
	if hit.stagger >= shield_break_stagger:
		# Heavy hit or push: knock the shield aside and open a punish window.
		stagger_tier = StaggerTier.STAGGER
		stagger_time = SHIELD_GUARD_BREAK_TIME
		knockback_velocity += hit.direction * hit.knockback * 0.6
		_on_staggered(StaggerTier.STAGGER)
		Sfx.play_cue(Sfx.Cue.SHIELD, 0.7)
		Juice.popup_text(head_position(), "OPEN", Color(1.0, 0.8, 0.3))
	else:
		Sfx.play_cue(Sfx.Cue.SHIELD)
		Juice.popup_text(head_position(), "clang", Color(0.7, 0.75, 0.85))
		if is_instance_valid(hit.attacker):
			hit.attacker.knockback_velocity -= hit.direction * 50.0
	redraw()
	return true


func _on_staggered(tier: int) -> void:
	var attacking := state == State.WINDUP or state == State.ACTIVE
	if attacking and tier < interrupt_tier:
		# Super armor: shrug off light stagger mid-attack.
		stagger_time = 0.0
		stagger_tier = StaggerTier.NONE
		return
	if is_attacking():
		_end_attack()
	state = State.STAGGERED


func die(hit: HitInfo) -> void:
	_release_token()
	super.die(hit)


# --- Drawing -----------------------------------------------------------------

func _draw() -> void:
	draw_body()
	draw_weapon(body_radius + 4.0, Color(0.6, 0.55, 0.5))
	if shield_arc_degrees > 0.0:
		var up := shield_up()
		var w := body_radius * 0.9
		var h := body_height * (0.75 if up else 0.45)
		var x := _facing_sign * body_radius * 0.8 - w * 0.5
		var y := -body_height * (0.85 if up else 0.5)
		draw_rect(Rect2(x, y, w, h), Color(0.55, 0.6, 0.7) if up else Color(0.35, 0.37, 0.42))
		draw_rect(Rect2(x, y, w, h), Color(0.2, 0.22, 0.27), false, 1.0)
	if is_priority:
		var top := head_position() - global_position + Vector2(0, -2)
		draw_colored_polygon(PackedVector2Array([top + Vector2(0, -3), top + Vector2(2.5, 0), top + Vector2(0, 3), top + Vector2(-2.5, 0)]), priority_color)
	if show_health_bar and health < max_health:
		var width := body_radius * 3.0
		var top_left := head_position() - global_position + Vector2(-width / 2, 2)
		draw_rect(Rect2(top_left, Vector2(width, 2)), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(top_left, Vector2(width * health / max_health, 2)), Color(0.85, 0.15, 0.15))


func _draw_ground(canvas: CanvasItem) -> void:
	if is_priority:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
		canvas.draw_arc(Vector2.ZERO, body_radius + 3.0 + pulse * 2.0, 0.0, TAU, 20, Color(priority_color, 0.5 + pulse * 0.4), 1.5)
	match state:
		State.WINDUP:
			_draw_windup_telegraph(canvas)
		State.ACTIVE:
			if _swing:
				var progress := clampf(_phase_time / maxf(_attack.active, 0.001), 0.0, 1.0)
				CombatDraw.swing(canvas, aim_direction, _attack, progress, Color(1.0, 0.3, 0.2, 0.6))


func _draw_windup_telegraph(canvas: CanvasItem) -> void:
	var t := clampf(_phase_time / _attack.windup, 0.0, 1.0)
	var color := Color(1.0, 0.5, 0.1) if _attack.block_cost >= 3 or _attack.unblockable else Color(0.9, 0.1, 0.1)
	var radius := _attack.reach + body_radius
	CombatDraw.sector(canvas, aim_direction, radius, _attack.arc_degrees, Color(color, 0.12))
	CombatDraw.sector(canvas, aim_direction, radius * t, _attack.arc_degrees, Color(color, 0.3))
	if _attack.lunge_distance + _attack.windup_advance_speed > 20.0:
		# Moving attack: show where the lunge carries it.
		canvas.draw_line(Vector2.ZERO, aim_direction * (_attack.lunge_distance + radius), Color(color, 0.35), 1.0)
