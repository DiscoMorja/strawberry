class_name Combatant
extends CharacterBody2D
## Shared base for anything that fights: health, mass (for cleave), stagger tiers,
## knockback, attack tokens and hit feedback. Subclasses own movement and decisions.

signal died(combatant: Combatant)
signal damaged(combatant: Combatant, hit: HitInfo, amount: float)

enum Team { PARTY, ENEMY }
enum StaggerTier { NONE, FLINCH, STAGGER, KNOCKDOWN }

## Seconds spent staggered, indexed by StaggerTier.
const STAGGER_DURATIONS: Array[float] = [0.0, 0.2, 0.6, 1.2]
const STAGGERED_DAMAGE_BONUS := 0.25
const CRIT_DAMAGE_MULTIPLIER := 1.5
const CRIT_STAGGER_MULTIPLIER := 1.5
const KNOCKBACK_DECAY := 9.0
const FLASH_DURATION := 0.08

@export var team: Team = Team.ENEMY
@export var max_health: float = 100.0
## Cleave cost to pass through this body. Horde ~1, elites 4+.
@export var mass: float = 1.0
## Incoming stagger / resist = tier reached (floored, capped at KNOCKDOWN).
@export var stagger_resist: float = 10.0
## Footprint radius on the ground plane (collision, reach checks).
@export var body_radius: float = 6.0
## Visual height of the upright figure above its feet (the node origin).
@export var body_height: float = 14.0
@export var body_color: Color = Color.WHITE
## Attack-token budget: limits how many enemies may attack this target at once.
@export var max_attackers: int = 3

var health: float
var aim_direction: Vector2 = Vector2.RIGHT
var stagger_time: float = 0.0
var stagger_tier: int = StaggerTier.NONE
var knockback_velocity: Vector2 = Vector2.ZERO
var is_dead: bool = false
## Set while a disabler holds this combatant; it can't act until released.
var grabbed_by: Combatant

var _flash_time: float = 0.0
var _tokens_used: int = 0
var _facing_sign: float = 1.0
var _ground: GroundDecal


func _ready() -> void:
	health = max_health
	_ground = GroundDecal.new()
	_ground.draw_callback = _draw_ground
	add_child(_ground)


## Redraws both the upright figure and its ground layer.
func redraw() -> void:
	queue_redraw()
	_ground.queue_redraw()


## Override to draw flat, ground-level visuals (telegraphs, swing arcs) into `canvas`.
func _draw_ground(_canvas: CanvasItem) -> void:
	pass


## Point above the figure's head, for popups and bars.
func head_position() -> Vector2:
	return global_position + Vector2(0, -body_height - body_radius * 0.7 - 4)


func is_staggered() -> bool:
	return stagger_time > 0.0


## True during an attack wind-up. Hits landed then are crits (the "crit window").
func is_winding_up() -> bool:
	return false


func is_grabbed() -> bool:
	return is_instance_valid(grabbed_by) and not grabbed_by.is_dead


## Resolves a hit. Returns true if it landed, false if it was blocked or ignored.
func receive_hit(hit: HitInfo) -> bool:
	if is_dead:
		return false
	if _try_block(hit):
		return false
	var amount := hit.damage
	if is_staggered():
		amount *= 1.0 + STAGGERED_DAMAGE_BONUS
	if hit.is_crit:
		amount *= CRIT_DAMAGE_MULTIPLIER
	knockback_velocity += hit.direction * hit.knockback / sqrt(mass)
	_apply_stagger(hit.stagger * (CRIT_STAGGER_MULTIPLIER if hit.is_crit else 1.0))
	if amount <= 0.0:
		return true
	health -= amount
	_flash_time = FLASH_DURATION
	var heavy := hit.stagger >= 30.0 or hit.is_crit
	Sfx.play_cue(Sfx.Cue.HIT_HEAVY if heavy else Sfx.Cue.HIT, 1.2 / sqrt(mass), -4.0 if team == Team.ENEMY else 0.0)
	damaged.emit(self, hit, amount)
	var color := Color(1.0, 0.35, 0.3) if team == Team.PARTY else (Color(1.0, 0.85, 0.2) if hit.is_crit else Color.WHITE)
	Juice.popup_text(head_position(), str(roundi(amount)), color)
	Gore.bleed(global_position, hit.direction, amount, body_height * 0.6)
	if health <= 0.0:
		die(hit)
	return true


func die(hit: HitInfo) -> void:
	is_dead = true
	died.emit(self)
	Gore.gib(global_position, hit.direction if hit else Vector2.ZERO, mass, body_height * 0.5)
	queue_free()


func request_attack_token(cost: int) -> bool:
	if _tokens_used + cost > max_attackers:
		return false
	_tokens_used += cost
	return true


func attackers_full() -> bool:
	return _tokens_used >= max_attackers


func release_attack_token(cost: int) -> void:
	_tokens_used = maxi(0, _tokens_used - cost)


## Override to absorb hits (blocking, dodge i-frames). Return true if the hit was negated.
func _try_block(_hit: HitInfo) -> bool:
	return false


## Override to react to stagger (interrupt attacks, super armor).
func _on_staggered(_tier: int) -> void:
	pass


func _apply_stagger(amount: float) -> void:
	var tier := clampi(int(amount / stagger_resist), StaggerTier.NONE, StaggerTier.KNOCKDOWN)
	if tier == StaggerTier.NONE:
		return
	if tier >= stagger_tier or not is_staggered():
		stagger_tier = tier
		stagger_time = maxf(stagger_time, STAGGER_DURATIONS[tier])
		_on_staggered(tier)


## Call once per physics frame from subclasses before deciding movement.
func update_combat_state(delta: float) -> void:
	stagger_time = maxf(0.0, stagger_time - delta)
	if stagger_time == 0.0:
		stagger_tier = StaggerTier.NONE
	_flash_time = maxf(0.0, _flash_time - delta)
	knockback_velocity *= exp(-KNOCKBACK_DECAY * delta)


## True when the aim crossed to the other side and the figure needs to be redrawn flipped.
func facing_sign_changed() -> bool:
	return (aim_direction.x < -0.1 and _facing_sign > 0.0) or (aim_direction.x > 0.1 and _facing_sign < 0.0)


## Upright placeholder figure standing on its origin (feet), facing left or right.
func draw_body() -> void:
	if aim_direction.x < -0.1:
		_facing_sign = -1.0
	elif aim_direction.x > 0.1:
		_facing_sign = 1.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, body_radius * 1.1, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var color := Color.WHITE if _flash_time > 0.0 else body_color
	var width := body_radius * 1.5
	var head_radius := width * 0.45
	draw_rect(Rect2(-width * 0.5, -body_height, width, body_height - 1.0), color)
	draw_circle(Vector2(0, -body_height), head_radius, color.lightened(0.15) if _flash_time <= 0.0 else color)
	draw_circle(Vector2(_facing_sign * head_radius * 0.45, -body_height - 0.5), 0.9, Color.BLACK)
	if is_staggered():
		var spin := Time.get_ticks_msec() / 120.0
		for i in stagger_tier:
			var offset := Vector2.from_angle(spin + TAU * i / stagger_tier) * Vector2(5, 2)
			draw_circle(Vector2(0, -body_height - head_radius - 4) + offset, 1.2, Color(1.0, 0.9, 0.3))


## Weapon held at hand height, pointing toward the aim direction.
func draw_weapon(length: float, color: Color = Color(0.8, 0.8, 0.85)) -> void:
	var hand := Vector2(_facing_sign * body_radius * 0.6, -body_height * 0.45)
	draw_line(hand, hand + aim_direction * length, color, 1.5)
