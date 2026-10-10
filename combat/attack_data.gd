class_name AttackData
extends Resource
## One melee attack: timing, shape and impact. Weapons and enemies are built from these.

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
@export var hit_stop: float = 0.05
@export var shake: float = 0.15
## Stamina pips drained when this attack is blocked.
@export var block_cost: int = 1
@export var unblockable: bool = false

@export_group("Movement")
## Forward burst at the start of the active window.
@export var lunge_speed: float = 0.0
@export var move_speed_multiplier: float = 0.3
