class_name HitInfo
extends RefCounted
## Everything a target needs to resolve one incoming hit.

var attacker: Combatant
var attack: AttackData
## Normalized, from attacker toward target.
var direction: Vector2 = Vector2.ZERO
var damage: float = 0.0
var stagger: float = 0.0
var knockback: float = 0.0
var is_crit: bool = false
