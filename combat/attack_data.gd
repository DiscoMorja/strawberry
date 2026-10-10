class_name AttackData
extends Resource
## One melee attack: timing, shape, impact and movement. Weapons and enemies are built from these.

@export var name: String = "attack"

@export_group("Timing")
@export var windup: float = 0.15
@export var active: float = 0.12
@export var recovery: float = 0.25

@export_group("Shape")
@export var reach: float = 28.0
@export_range(10.0, 360.0) var arc_degrees: float = 120.0
## 1 / -1 sweeps the arc across the active window (cleave order follows the sweep).
## 0 hits the whole shape at once, nearest first (stabs, slams, pushes).
@export_range(-1, 1) var sweep_direction: int = 1

@export_group("Impact")
@export var damage: float = 20.0
@export var stagger: float = 10.0
## Total target mass the swing passes through. The first target is always hit.
@export var cleave: float = 2.0
@export var knockback: float = 60.0
## Applied once per swing, on its first connecting frame.
@export var hit_stop: float = 0.05
@export var shake: float = 0.15
## Stamina pips drained when this attack is blocked.
@export var block_cost: int = 1
@export var unblockable: bool = false

@export_group("Movement")
## Speed (px/s) the attacker keeps advancing along its facing while winding up.
@export var windup_advance_speed: float = 0.0
## Forward distance (px) covered by the lunge, which eases out from just before the
## active window until it ends.
@export var lunge_distance: float = 0.0
## Sideways drift (px) in the direction the arc sweeps — the swing's momentum.
@export var lunge_lateral: float = 0.0
## How long before the active window the lunge begins.
@export var lunge_lead_time: float = 0.06
## How much of normal movement input still applies during the attack.
@export var move_speed_multiplier: float = 0.3

@export_group("AI")
## Enemies only pick this attack when at least this far from the target (leaps, charges).
@export var min_range: float = 0.0


## Velocity added by the attack's own motion, `elapsed` seconds after its wind-up started.
## The lunge uses a linear ease-out profile, so it integrates to exactly `lunge_distance`.
func motion_velocity(elapsed: float, facing: Vector2) -> Vector2:
	var velocity := Vector2.ZERO
	if elapsed < windup:
		velocity += facing * windup_advance_speed
	var lunge_begin := maxf(0.0, windup - lunge_lead_time)
	var lunge_end := windup + active
	var duration := lunge_end - lunge_begin
	if duration > 0.0 and elapsed >= lunge_begin and elapsed < lunge_end:
		var t := (elapsed - lunge_begin) / duration
		var scale := 2.0 * (1.0 - t) / duration
		velocity += facing * lunge_distance * scale
		velocity += facing.rotated(PI / 2.0) * lunge_lateral * sweep_direction * scale
	return velocity


## Distance from the target at which an AI should start this attack so it connects.
func trigger_range() -> float:
	return reach + lunge_distance + windup_advance_speed * windup * 0.8
