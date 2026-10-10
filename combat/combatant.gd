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
@export var body_radius: float = 6.0
@export var body_color: Color = Color.WHITE
## Attack-token budget: limits how many enemies may attack this target at once.
@export var max_attackers: int = 3

var health: float
var aim_direction: Vector2 = Vector2.RIGHT
var stagger_time: float = 0.0
var stagger_tier: int = StaggerTier.NONE
var knockback_velocity: Vector2 = Vector2.ZERO
var is_dead: bool = false

var _flash_time: float = 0.0
var _tokens_used: int = 0


func _ready() -> void:
	health = max_health


func is_staggered() -> bool:
	return stagger_time > 0.0


## True during an attack wind-up. Hits landed then are crits (the "crit window").
func is_winding_up() -> bool:
	return false


func receive_hit(hit: HitInfo) -> void:
	if is_dead:
		return
	if _try_block(hit):
		return
	var amount := hit.damage
	if is_staggered():
		amount *= 1.0 + STAGGERED_DAMAGE_BONUS
	if hit.is_crit:
		amount *= CRIT_DAMAGE_MULTIPLIER
	knockback_velocity += hit.direction * hit.knockback / sqrt(mass)
	_apply_stagger(hit.stagger * (CRIT_STAGGER_MULTIPLIER if hit.is_crit else 1.0))
	if amount <= 0.0:
		return
	health -= amount
	_flash_time = FLASH_DURATION
	damaged.emit(self, hit, amount)
	var color := Color(1.0, 0.35, 0.3) if team == Team.PARTY else (Color(1.0, 0.85, 0.2) if hit.is_crit else Color.WHITE)
	Juice.popup_text(global_position + Vector2(0, -body_radius - 6), str(roundi(amount)), color)
	Gore.bleed(global_position, hit.direction, amount)
	if health <= 0.0:
		die(hit)


func die(hit: HitInfo) -> void:
	is_dead = true
	died.emit(self)
	Gore.gib(global_position, hit.direction if hit else Vector2.ZERO, mass)
	queue_free()


func request_attack_token(cost: int) -> bool:
	if _tokens_used + cost > max_attackers:
		return false
	_tokens_used += cost
	return true


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


func draw_body() -> void:
	draw_circle(Vector2(0, 2), body_radius, Color(0, 0, 0, 0.35))
	draw_circle(Vector2.ZERO, body_radius, Color.WHITE if _flash_time > 0.0 else body_color)
	if is_staggered():
		var spin := Time.get_ticks_msec() / 120.0
		for i in stagger_tier:
			var offset := Vector2.from_angle(spin + TAU * i / stagger_tier) * Vector2(5, 2)
			draw_circle(Vector2(0, -body_radius - 4) + offset, 1.2, Color(1.0, 0.9, 0.3))
