class_name WeaponData
extends Resource
## A weapon's moveset: light chain, charged heavy, push and block properties.

@export var name: String = "Weapon"
@export var light_chain: Array[AttackData] = []
@export var heavy: AttackData
@export var push: AttackData
## Hold time before a release becomes a heavy attack.
@export var heavy_charge_time: float = 0.35
## Heavy fires automatically after being held this long.
@export var max_charge_hold: float = 1.2
## Idle time after which the light chain restarts from the first attack.
@export var combo_reset_time: float = 0.6
@export_range(30.0, 360.0) var block_arc_degrees: float = 140.0
