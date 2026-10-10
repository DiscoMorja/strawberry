class_name PartyMember
extends Combatant
## A party character: the hero or a follower. Every decision comes from `intent`, which the
## active controller (PlayerController or FollowerAI) fills each physics frame, so control
## can be swapped between members at any time.

signal downed(member: PartyMember)
signal revived(member: PartyMember)

enum State { FREE, CHARGING, ATTACKING, BLOCKING, PUSHING, DODGING, STAGGERED, GRABBED, REVIVING, DOWNED, DEAD }
enum Phase { WINDUP, ACTIVE, RECOVERY }
enum Stance { AGGRESSIVE, DEFENSIVE }

const CHARGE_MOVE_MULTIPLIER := 0.6
const PUSH_STATE_TIME := 0.25
## Damage taken while downed shortens the bleed-out timer by damage × this (seconds).
const DOWNED_DAMAGE_TO_BLEED := 0.1

@export var display_name: String = "Hero"
## The hero is fixed: always in the party, and its death ends the run.
@export var is_hero: bool = false
## Identifying color for rings and HUD.
@export var ring_color: Color = Color(1.0, 0.85, 0.4)
## Default AI stance when not player-controlled.
@export var ai_stance: Stance = Stance.AGGRESSIVE
@export var weapon: WeaponData
@export var max_speed: float = 90.0
@export var acceleration: float = 900.0
@export var friction: float = 1100.0
## Acceleration multiplier while attacking: low values let momentum carry through swings.
@export var attack_steer_factor: float = 0.45

@export_group("Stamina")
@export var max_stamina: int = 4
@export var stamina_regen_delay: float = 0.9
@export var stamina_regen_interval: float = 0.45

@export_group("Dodge")
@export var dodge_speed: float = 280.0
@export var dodge_duration: float = 0.18
@export var dodge_cooldown: float = 0.35
## Small invulnerability window at dodge start. Positioning should do most of the work.
@export var dodge_iframes: float = 0.06

@export_group("Block")
@export var block_move_multiplier: float = 0.5
@export var guard_break_duration: float = 0.8
@export var push_cooldown: float = 0.5

@export_group("Grabbed")
## Stamina spent to struggle free of a grab (dodge input).
@export var struggle_cost: int = 2
## How tightly a grabber tows this character (higher = snappier).
@export var tow_stiffness: float = 12.0

@export_group("Downed")
@export var bleed_out_time: float = 20.0
@export var revive_time: float = 2.0
@export var revive_health_fraction: float = 0.35
@export var revive_range: float = 20.0

@export_group("Debug")
## Sandbox only: the hero comes back after this long instead of ending the run.
@export var respawn_delay: float = 2.0

var stamina: int
var state: State = State.FREE
var controller: CharacterController
var intent := CharacterIntent.new()
var is_controlled: bool = false

## Service record.
var kills: int = 0
var times_downed: int = 0
var revives_given: int = 0

var bleed_left: float = 0.0
var revive_progress: float = 0.0
var _last_revive_frame := -10

var _phase: Phase = Phase.WINDUP
var _phase_time := 0.0
var _state_time := 0.0
var _attack: AttackData
var _swing: MeleeSwing
var _swing_facing := Vector2.RIGHT
var _attack_elapsed := 0.0
var _hit_stop_done := false
## Input-driven velocity, kept separate from attack motion and knockback so momentum persists.
var _move_velocity := Vector2.ZERO
var _chain_index := 0
var _combo_timer := 0.0
var _charge_time := 0.0
var _attack_buffered := false
var _dodge_direction := Vector2.ZERO
var _dodge_cooldown_left := 0.0
var _push_cooldown_left := 0.0
var _regen_wait := 0.0
var _revive_target: PartyMember


func _ready() -> void:
	super._ready()
	team = Team.PARTY
	stamina = max_stamina
	add_to_group("party")


func is_targetable() -> bool:
	return not is_dead and state != State.DOWNED


func is_downed() -> bool:
	return state == State.DOWNED


func is_winding_up() -> bool:
	return state == State.ATTACKING and _phase == Phase.WINDUP


func is_blocking() -> bool:
	return state == State.BLOCKING or state == State.PUSHING


func on_killed(_victim: Combatant) -> void:
	kills += 1


func _physics_process(delta: float) -> void:
	update_combat_state(delta)
	redraw()
	intent.clear()
	if controller and state != State.DOWNED and state != State.DEAD:
		controller.update(self, delta)
	if state == State.DEAD or state == State.DOWNED:
		if state == State.DOWNED:
			_tick_downed(delta)
		velocity = knockback_velocity
		move_and_slide()
		return
	_tick_timers(delta)
	if is_grabbed():
		_tick_grabbed()
		return
	if state == State.GRABBED:
		state = State.STAGGERED if is_staggered() else State.FREE
	if is_staggered() and state != State.STAGGERED:
		_enter_staggered()
	if _tick_reviving():
		return

	var move_input := intent.move
	var speed_multiplier := 1.0
	_state_time += delta

	match state:
		State.FREE:
			_update_aim()
			if not _try_defensive_action():
				if intent.attack_pressed:
					_start_charge()
		State.CHARGING:
			_update_aim()
			speed_multiplier = CHARGE_MOVE_MULTIPLIER
			_charge_time += delta
			if not _try_defensive_action():
				if not intent.attack_held:
					_start_attack(weapon.heavy if _charge_time >= weapon.heavy_charge_time else _next_light())
				elif _charge_time >= weapon.max_charge_hold:
					_start_attack(weapon.heavy)
		State.ATTACKING:
			speed_multiplier = _attack.move_speed_multiplier
			_tick_attack(delta)
		State.BLOCKING:
			_update_aim()
			speed_multiplier = block_move_multiplier
			if intent.dodge_pressed and _dodge_cooldown_left <= 0.0:
				_start_dodge(move_input)
			elif not intent.block_held:
				state = State.FREE
			elif intent.attack_pressed:
				_try_push()
		State.PUSHING:
			speed_multiplier = block_move_multiplier
			if _swing:
				_swing.advance(clampf(_state_time / maxf(weapon.push.active, 0.001), 0.0, 1.0))
			if _state_time >= PUSH_STATE_TIME:
				_swing = null
				state = State.BLOCKING if intent.block_held else State.FREE
		State.DODGING:
			if _state_time >= dodge_duration:
				state = State.FREE
		State.STAGGERED:
			speed_multiplier = 0.0
			if not is_staggered():
				state = State.FREE

	if state == State.DODGING:
		var t := _state_time / dodge_duration
		_move_velocity = _dodge_direction * dodge_speed * (1.0 - t * t * 0.7)
		velocity = _move_velocity
	else:
		var target_velocity := move_input * max_speed * speed_multiplier
		var rate := acceleration if move_input != Vector2.ZERO else friction
		if state == State.ATTACKING:
			rate *= attack_steer_factor
		_move_velocity = _move_velocity.move_toward(target_velocity, rate * delta)
		velocity = _move_velocity
		if state == State.ATTACKING:
			var facing := aim_direction if _phase == Phase.WINDUP else _swing_facing
			velocity += _attack.motion_velocity(_attack_elapsed, facing)
	velocity += knockback_velocity
	move_and_slide()


# --- Grabbed / downed / revive ----------------------------------------------

## Towed by the grabber; the only action is struggling free.
func _tick_grabbed() -> void:
	if state != State.GRABBED:
		_swing = null
		state = State.GRABBED
		_state_time = 0.0
	if intent.dodge_pressed and stamina >= struggle_cost:
		_spend_stamina(struggle_cost)
		var grabber := grabbed_by as GrabberEnemy
		if grabber:
			grabber.release_grab()
		Juice.popup_text(head_position(), "BROKE FREE", Color(0.6, 0.9, 1.0), 10)
		Juice.shake(0.2)
		state = State.FREE
		return
	var anchor := grabbed_by.global_position
	var offset := global_position - anchor
	var hold_distance := body_radius + grabbed_by.body_radius + 4.0
	var desired_position := anchor + offset.normalized() * hold_distance
	aim_direction = -offset.normalized()
	_move_velocity = Vector2.ZERO
	velocity = (desired_position - global_position) * tow_stiffness
	move_and_slide()


## Holding interact next to a downed ally revives it. Returns true while reviving.
func _tick_reviving() -> bool:
	var can_revive := state == State.FREE or state == State.BLOCKING or state == State.REVIVING
	var ally := _nearest_downed_ally() if intent.interact_held and can_revive else null
	if ally == null:
		if state == State.REVIVING:
			state = State.FREE
		_revive_target = null
		return false
	state = State.REVIVING
	_revive_target = ally
	aim_direction = (ally.global_position - global_position).normalized()
	ally.receive_revive(self, get_physics_process_delta_time())
	_move_velocity = Vector2.ZERO
	velocity = knockback_velocity
	move_and_slide()
	return true


func receive_revive(reviver: PartyMember, delta: float) -> void:
	if state != State.DOWNED:
		return
	_last_revive_frame = Engine.get_physics_frames()
	revive_progress += delta
	if revive_progress >= revive_time:
		reviver.revives_given += 1
		_revive()


func _tick_downed(delta: float) -> void:
	bleed_left -= delta
	if Engine.get_physics_frames() - _last_revive_frame > 2:
		revive_progress = maxf(0.0, revive_progress - delta * 0.5)
	if bleed_left <= 0.0:
		_die_for_real(null)


func _nearest_downed_ally() -> PartyMember:
	var best: PartyMember = null
	var best_distance := revive_range
	for node in get_tree().get_nodes_in_group("party"):
		var ally := node as PartyMember
		if ally and ally != self and ally.is_downed():
			var d := global_position.distance_to(ally.global_position)
			if d <= best_distance:
				best_distance = d
				best = ally
	return best


func _revive() -> void:
	state = State.FREE
	health = max_health * revive_health_fraction
	revive_progress = 0.0
	stagger_time = 0.0
	Juice.popup_text(head_position(), "REVIVED", Color(0.5, 1.0, 0.6), 10)
	revived.emit(self)


func receive_hit(hit: HitInfo) -> bool:
	if state == State.DOWNED:
		bleed_left -= hit.damage * DOWNED_DAMAGE_TO_BLEED
		return false
	return super.receive_hit(hit)


## Reaching 0 health downs the character first; only bleeding out kills.
func die(hit: HitInfo) -> void:
	if state == State.DOWNED or state == State.DEAD:
		return
	var grabber := grabbed_by as GrabberEnemy
	if grabber:
		grabber.release_grab()
	_swing = null
	health = 0.0
	state = State.DOWNED
	bleed_left = bleed_out_time
	revive_progress = 0.0
	times_downed += 1
	Gore.bleed(global_position, hit.direction if hit else Vector2.ZERO, 30.0, body_height * 0.4)
	Juice.popup_text(head_position(), "%s DOWN" % display_name.to_upper(), Color(1.0, 0.4, 0.3), 10)
	Juice.shake(0.3)
	downed.emit(self)


func _die_for_real(hit: HitInfo) -> void:
	is_dead = true
	state = State.DEAD
	_swing = null
	died.emit(self)
	Gore.gib(global_position, hit.direction if hit else Vector2.ZERO, mass, body_height * 0.5)
	if is_hero:
		Juice.popup_text(head_position(), "YOU DIED", Color(0.8, 0.1, 0.1), 16)
		get_tree().create_timer(respawn_delay).timeout.connect(_respawn)
	else:
		Juice.popup_text(head_position(), "%s has fallen" % display_name, Color(0.8, 0.8, 0.8), 10)
		queue_free()


func _respawn() -> void:
	health = max_health
	stamina = max_stamina
	is_dead = false
	stagger_time = 0.0
	state = State.FREE


# --- Actions -----------------------------------------------------------------

## Block and dodge can cancel most states. Returns true if one started.
func _try_defensive_action() -> bool:
	if intent.dodge_pressed and _dodge_cooldown_left <= 0.0:
		_start_dodge(intent.move)
		return true
	if intent.block_held:
		_swing = null
		state = State.BLOCKING
		_state_time = 0.0
		return true
	return false


func _start_charge() -> void:
	state = State.CHARGING
	_charge_time = 0.0
	_state_time = 0.0


func _next_light() -> AttackData:
	if _combo_timer <= 0.0:
		_chain_index = 0
	var attack := weapon.light_chain[_chain_index % weapon.light_chain.size()]
	_chain_index += 1
	return attack


func _start_attack(attack: AttackData) -> void:
	_attack = attack
	state = State.ATTACKING
	_phase = Phase.WINDUP
	_phase_time = 0.0
	_attack_buffered = false
	_attack_elapsed = 0.0
	_hit_stop_done = false
	_swing = null


func _tick_attack(delta: float) -> void:
	_phase_time += delta
	_attack_elapsed += delta
	match _phase:
		Phase.WINDUP:
			_update_aim()
			if _try_defensive_action():
				return
			if _phase_time >= _attack.windup:
				_phase = Phase.ACTIVE
				_phase_time = 0.0
				_swing_facing = aim_direction
				if weapon.is_ranged:
					_fire_projectile()
				else:
					_swing = MeleeSwing.new(self, _attack, _swing_facing, PhysicsLayers.ENEMY_BODY)
		Phase.ACTIVE:
			if intent.attack_pressed:
				_attack_buffered = true
			if _swing:
				var progress := clampf(_phase_time / maxf(_attack.active, 0.001), 0.0, 1.0)
				var hits := _swing.advance(progress)
				if hits > 0:
					# One hit-stop per swing: stopping again for every target the sweep reaches feels choppy.
					# Only the controlled character's hits freeze the game; follower hits would stutter it.
					if not _hit_stop_done and is_controlled:
						_hit_stop_done = true
						Juice.hit_stop(_attack.hit_stop)
					if is_controlled:
						Juice.shake(_attack.shake)
			if _phase_time >= _attack.active:
				_phase = Phase.RECOVERY
				_phase_time = 0.0
		Phase.RECOVERY:
			# Recovery is fully cancelable: chain into the next attack, block or dodge.
			if _try_defensive_action():
				return
			if _attack_buffered or intent.attack_pressed:
				_combo_timer = weapon.combo_reset_time
				_start_charge()
			elif _phase_time >= _attack.recovery:
				_combo_timer = weapon.combo_reset_time
				_swing = null
				state = State.FREE


func _fire_projectile() -> void:
	var arrow := Projectile.launch(self, _attack, _swing_facing, weapon.projectile_speed)
	arrow.target_mask = PhysicsLayers.ENEMY_BODY
	arrow.max_distance = weapon.projectile_range
	arrow.color = Color(0.85, 0.95, 0.75)


func _try_push() -> void:
	if _push_cooldown_left > 0.0 or stamina <= 0:
		return
	_spend_stamina(1)
	_push_cooldown_left = push_cooldown
	state = State.PUSHING
	_state_time = 0.0
	_swing_facing = aim_direction
	_swing = MeleeSwing.new(self, weapon.push, _swing_facing, PhysicsLayers.ENEMY_BODY)
	if is_controlled:
		Juice.shake(weapon.push.shake)


func _start_dodge(move_input: Vector2) -> void:
	_swing = null
	_dodge_direction = move_input.normalized() if move_input != Vector2.ZERO else -aim_direction
	_dodge_cooldown_left = dodge_cooldown
	state = State.DODGING
	_state_time = 0.0


func _enter_staggered() -> void:
	_swing = null
	state = State.STAGGERED
	_state_time = 0.0


# --- Defense -----------------------------------------------------------------

func _try_block(hit: HitInfo) -> bool:
	if state == State.DODGING and _state_time < dodge_iframes:
		return true
	if not is_blocking() or hit.attack.unblockable:
		return false
	var half_arc := deg_to_rad(weapon.block_arc_degrees) * 0.5
	if absf(aim_direction.angle_to(-hit.direction)) > half_arc:
		return false
	var cost := hit.attack.block_cost
	Sfx.play_cue(Sfx.Cue.BLOCK, 1.0 / maxf(1.0, cost * 0.6), 0.0 if is_controlled else -6.0)
	knockback_velocity += hit.direction * hit.knockback * 0.4
	if is_controlled:
		Juice.hit_stop(0.03)
		Juice.shake(0.1)
	if cost > stamina:
		stamina = 0
		_regen_wait = stamina_regen_delay
		stagger_tier = StaggerTier.STAGGER
		stagger_time = guard_break_duration
		_enter_staggered()
		Juice.popup_text(head_position(), "GUARD BREAK", Color(1.0, 0.5, 0.2), 10)
	else:
		_spend_stamina(cost)
		Juice.popup_text(head_position(), "block", Color(0.6, 0.8, 1.0))
	return true


func _spend_stamina(amount: int) -> void:
	stamina = maxi(0, stamina - amount)
	_regen_wait = stamina_regen_delay


func _on_staggered(_tier: int) -> void:
	if state != State.DOWNED and state != State.DEAD:
		_enter_staggered()


# --- Helpers -----------------------------------------------------------------

func _tick_timers(delta: float) -> void:
	_dodge_cooldown_left = maxf(0.0, _dodge_cooldown_left - delta)
	_push_cooldown_left = maxf(0.0, _push_cooldown_left - delta)
	if state == State.FREE:
		_combo_timer = maxf(0.0, _combo_timer - delta)
	if not is_blocking() and stamina < max_stamina:
		_regen_wait -= delta
		if _regen_wait <= 0.0:
			stamina += 1
			_regen_wait = stamina_regen_interval


func _update_aim() -> void:
	if intent.aim != Vector2.ZERO:
		aim_direction = intent.aim.normalized()


func _draw() -> void:
	match state:
		State.DEAD:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
			draw_circle(Vector2.ZERO, body_radius * 1.4, Color(0.3, 0.05, 0.05))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return
		State.DOWNED:
			# Lying on the ground.
			draw_rect(Rect2(-body_height * 0.5, -body_radius * 0.8, body_height, body_radius * 1.2), body_color.darkened(0.3))
			draw_circle(Vector2(body_height * 0.5 * _facing_sign, -body_radius * 0.2), body_radius * 0.6, body_color.darkened(0.2))
			return
		State.DODGING:
			draw_rect(Rect2(-_dodge_direction * 7.0 + Vector2(-body_radius * 0.75, -body_height), Vector2(body_radius * 1.5, body_height)),
					Color(body_color, 0.3))
	draw_body()
	draw_weapon(9.0 if not weapon.is_ranged else 7.0, Color(0.8, 0.8, 0.85) if not weapon.is_ranged else Color(0.6, 0.45, 0.3))


func _draw_ground(canvas: CanvasItem) -> void:
	if state == State.DEAD:
		return
	var ring := body_radius + 3.0
	if state == State.DOWNED:
		var bleed := clampf(bleed_left / bleed_out_time, 0.0, 1.0)
		canvas.draw_arc(Vector2.ZERO, ring + 4.0, -PI / 2, -PI / 2 + TAU * bleed, 24, Color(0.9, 0.2, 0.2, 0.8), 2.0)
		if revive_progress > 0.0:
			var t := revive_progress / revive_time
			canvas.draw_arc(Vector2.ZERO, ring + 1.0, -PI / 2, -PI / 2 + TAU * t, 24, Color(0.5, 1.0, 0.6), 2.0)
		return
	# Identity ring under every party member; brighter for the one you control.
	canvas.draw_arc(Vector2.ZERO, ring, 0.0, TAU, 20, Color(ring_color, 0.9 if is_controlled else 0.35), 1.0)
	# Aim marker: the figure only faces left/right, this shows the true aim.
	var base := aim_direction * ring
	var side := aim_direction.orthogonal() * 2.5
	canvas.draw_colored_polygon(PackedVector2Array([aim_direction * (ring + 5.0), base + side, base - side]),
			Color(1, 1, 1, 0.8 if is_controlled else 0.3))

	match state:
		State.CHARGING:
			var heavy_ready := _charge_time >= weapon.heavy_charge_time
			var t := clampf(_charge_time / weapon.heavy_charge_time, 0.0, 1.0)
			canvas.draw_arc(Vector2.ZERO, ring + 1.5, -PI / 2, -PI / 2 + TAU * t, 16,
					Color(1.0, 0.8, 0.3) if heavy_ready else Color(1, 1, 1, 0.5), 1.5)
		State.ATTACKING:
			if _phase == Phase.ACTIVE and _swing:
				var progress := clampf(_phase_time / maxf(_attack.active, 0.001), 0.0, 1.0)
				CombatDraw.swing(canvas, _swing_facing, _attack, progress, Color(1, 1, 1, 0.55 if is_controlled else 0.3))
		State.BLOCKING, State.PUSHING:
			var color := Color(0.5, 0.75, 1.0, 0.9) if state == State.BLOCKING else Color(1, 1, 1, 0.9)
			var half := deg_to_rad(weapon.block_arc_degrees) * 0.5
			canvas.draw_arc(Vector2.ZERO, ring + 1.5, aim_direction.angle() - half, aim_direction.angle() + half, 12, color, 2.0)
			if state == State.PUSHING:
				CombatDraw.sector(canvas, _swing_facing, weapon.push.reach, weapon.push.arc_degrees, Color(1, 1, 1, 0.25))
		State.REVIVING:
			if is_instance_valid(_revive_target):
				canvas.draw_line(Vector2.ZERO, to_local(_revive_target.global_position), Color(0.5, 1.0, 0.6, 0.6), 1.0)
