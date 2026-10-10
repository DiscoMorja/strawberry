class_name Hero
extends Combatant
## Player-controlled melee fighter (M1). Input is read directly for now;
## it moves to a pluggable controller in M3 so followers can share this code.

enum State { FREE, CHARGING, ATTACKING, BLOCKING, PUSHING, DODGING, STAGGERED, DEAD }
enum Phase { WINDUP, ACTIVE, RECOVERY }

const STICK_AIM_DEADZONE := 0.3
const CHARGE_MOVE_MULTIPLIER := 0.6
const PUSH_STATE_TIME := 0.25

@export var weapon: WeaponData
@export var max_speed: float = 90.0
@export var acceleration: float = 900.0
@export var friction: float = 1100.0

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

@export_group("Debug")
@export var respawn_delay: float = 2.0

var stamina: int
var state: State = State.FREE

var _phase: Phase = Phase.WINDUP
var _phase_time := 0.0
var _state_time := 0.0
var _attack: AttackData
var _swing: MeleeSwing
var _swing_facing := Vector2.RIGHT
var _chain_index := 0
var _combo_timer := 0.0
var _charge_time := 0.0
var _attack_buffered := false
var _dodge_direction := Vector2.ZERO
var _dodge_cooldown_left := 0.0
var _push_cooldown_left := 0.0
var _regen_wait := 0.0
var _using_stick_aim := false


func _ready() -> void:
	super._ready()
	team = Team.PARTY
	stamina = max_stamina
	add_to_group("party")
	add_to_group("player")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_using_stick_aim = false


func _physics_process(delta: float) -> void:
	update_combat_state(delta)
	queue_redraw()
	if state == State.DEAD:
		velocity = knockback_velocity
		move_and_slide()
		return
	_tick_timers(delta)
	if is_staggered() and state != State.STAGGERED:
		_enter_staggered()

	var move_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var speed_multiplier := 1.0
	_state_time += delta

	match state:
		State.FREE:
			_update_aim()
			if not _try_defensive_action():
				if Input.is_action_just_pressed("attack"):
					_start_charge()
		State.CHARGING:
			_update_aim()
			speed_multiplier = CHARGE_MOVE_MULTIPLIER
			_charge_time += delta
			if not _try_defensive_action():
				if not Input.is_action_pressed("attack"):
					_start_attack(weapon.heavy if _charge_time >= weapon.heavy_charge_time else _next_light())
				elif _charge_time >= weapon.max_charge_hold:
					_start_attack(weapon.heavy)
		State.ATTACKING:
			speed_multiplier = _attack.move_speed_multiplier
			_tick_attack(delta)
		State.BLOCKING:
			_update_aim()
			speed_multiplier = block_move_multiplier
			if Input.is_action_just_pressed("dodge") and _dodge_cooldown_left <= 0.0:
				_start_dodge(move_input)
			elif not Input.is_action_pressed("block"):
				state = State.FREE
			elif Input.is_action_just_pressed("attack"):
				_try_push()
		State.PUSHING:
			speed_multiplier = block_move_multiplier
			if _swing:
				_swing.advance(clampf(_state_time / maxf(weapon.push.active, 0.001), 0.0, 1.0))
			if _state_time >= PUSH_STATE_TIME:
				_swing = null
				state = State.BLOCKING if Input.is_action_pressed("block") else State.FREE
		State.DODGING:
			if _state_time >= dodge_duration:
				state = State.FREE
		State.STAGGERED:
			speed_multiplier = 0.0
			if not is_staggered():
				state = State.FREE

	if state == State.DODGING:
		var t := _state_time / dodge_duration
		velocity = _dodge_direction * dodge_speed * (1.0 - t * t * 0.7)
	else:
		var target_velocity := move_input * max_speed * speed_multiplier
		var rate := acceleration if move_input != Vector2.ZERO else friction
		velocity = velocity.move_toward(target_velocity, rate * delta)
	velocity += knockback_velocity
	move_and_slide()
	velocity -= knockback_velocity


func is_winding_up() -> bool:
	return state == State.ATTACKING and _phase == Phase.WINDUP


func is_blocking() -> bool:
	return state == State.BLOCKING or state == State.PUSHING


func die(hit: HitInfo) -> void:
	is_dead = true
	state = State.DEAD
	_swing = null
	died.emit(self)
	Gore.gib(global_position, hit.direction if hit else Vector2.ZERO, mass)
	Juice.popup_text(global_position + Vector2(0, -20), "YOU DIED", Color(0.8, 0.1, 0.1), 16)
	get_tree().create_timer(respawn_delay).timeout.connect(_respawn)


func _respawn() -> void:
	health = max_health
	stamina = max_stamina
	is_dead = false
	stagger_time = 0.0
	state = State.FREE


# --- Actions -----------------------------------------------------------------

## Block and dodge can cancel most states. Returns true if one started.
func _try_defensive_action() -> bool:
	if Input.is_action_just_pressed("dodge") and _dodge_cooldown_left <= 0.0:
		_start_dodge(Input.get_vector("move_left", "move_right", "move_up", "move_down"))
		return true
	if Input.is_action_pressed("block"):
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
	_swing = null


func _tick_attack(delta: float) -> void:
	_phase_time += delta
	match _phase:
		Phase.WINDUP:
			_update_aim()
			if _try_defensive_action():
				return
			if _phase_time >= _attack.windup:
				_phase = Phase.ACTIVE
				_phase_time = 0.0
				_swing_facing = aim_direction
				_swing = MeleeSwing.new(self, _attack, _swing_facing, PhysicsLayers.ENEMY_BODY)
				velocity += _swing_facing * _attack.lunge_speed
		Phase.ACTIVE:
			if Input.is_action_just_pressed("attack"):
				_attack_buffered = true
			var progress := clampf(_phase_time / maxf(_attack.active, 0.001), 0.0, 1.0)
			var hits := _swing.advance(progress)
			if hits > 0:
				Juice.hit_stop(_attack.hit_stop * (1.0 + 0.3 * mini(hits - 1, 3)))
				Juice.shake(_attack.shake)
			if _phase_time >= _attack.active:
				_phase = Phase.RECOVERY
				_phase_time = 0.0
		Phase.RECOVERY:
			# Recovery is fully cancelable: chain into the next attack, block or dodge.
			if _try_defensive_action():
				return
			if _attack_buffered or Input.is_action_just_pressed("attack"):
				_combo_timer = weapon.combo_reset_time
				_start_charge()
			elif _phase_time >= _attack.recovery:
				_combo_timer = weapon.combo_reset_time
				_swing = null
				state = State.FREE


func _try_push() -> void:
	if _push_cooldown_left > 0.0 or stamina <= 0:
		return
	_spend_stamina(1)
	_push_cooldown_left = push_cooldown
	state = State.PUSHING
	_state_time = 0.0
	_swing_facing = aim_direction
	_swing = MeleeSwing.new(self, weapon.push, _swing_facing, PhysicsLayers.ENEMY_BODY)
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
	knockback_velocity += hit.direction * hit.knockback * 0.4
	Juice.hit_stop(0.03)
	Juice.shake(0.1)
	if cost > stamina:
		stamina = 0
		_regen_wait = stamina_regen_delay
		stagger_tier = StaggerTier.STAGGER
		stagger_time = guard_break_duration
		_enter_staggered()
		Juice.popup_text(global_position + Vector2(0, -16), "GUARD BREAK", Color(1.0, 0.5, 0.2), 10)
	else:
		_spend_stamina(cost)
		Juice.popup_text(global_position + Vector2(0, -14), "block", Color(0.6, 0.8, 1.0))
	return true


func _spend_stamina(amount: int) -> void:
	stamina = maxi(0, stamina - amount)
	_regen_wait = stamina_regen_delay


func _on_staggered(_tier: int) -> void:
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
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length() > STICK_AIM_DEADZONE:
		_using_stick_aim = true
		aim_direction = stick.normalized()
	elif not _using_stick_aim:
		var to_mouse := get_global_mouse_position() - global_position
		if to_mouse.length() > 1.0:
			aim_direction = to_mouse.normalized()


func _draw() -> void:
	if state == State.DEAD:
		draw_circle(Vector2.ZERO, body_radius, Color(0.3, 0.05, 0.05))
		return
	if state == State.DODGING:
		draw_circle(-_dodge_direction * 6.0, body_radius, Color(body_color, 0.3))
	draw_body()
	var base := aim_direction * body_radius
	var side := aim_direction.orthogonal() * 3.0
	draw_colored_polygon(PackedVector2Array([aim_direction * (body_radius + 6.0), base + side, base - side]), Color.WHITE)

	match state:
		State.CHARGING:
			var heavy_ready := _charge_time >= weapon.heavy_charge_time
			var t := clampf(_charge_time / weapon.heavy_charge_time, 0.0, 1.0)
			draw_arc(Vector2.ZERO, body_radius + 3.0, -PI / 2, -PI / 2 + TAU * t, 16,
					Color(1.0, 0.8, 0.3) if heavy_ready else Color(1, 1, 1, 0.5), 1.5)
		State.ATTACKING:
			if _phase == Phase.ACTIVE:
				var progress := clampf(_phase_time / maxf(_attack.active, 0.001), 0.0, 1.0)
				CombatDraw.swing(self, _swing_facing, _attack, progress, Color(1, 1, 1, 0.55))
		State.BLOCKING, State.PUSHING:
			var color := Color(0.5, 0.75, 1.0, 0.9) if state == State.BLOCKING else Color(1, 1, 1, 0.9)
			var half := deg_to_rad(weapon.block_arc_degrees) * 0.5
			draw_arc(Vector2.ZERO, body_radius + 4.0, aim_direction.angle() - half, aim_direction.angle() + half, 12, color, 2.0)
			if state == State.PUSHING:
				CombatDraw.sector(self, _swing_facing, weapon.push.reach, weapon.push.arc_degrees, Color(1, 1, 1, 0.25))
