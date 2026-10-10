class_name CharacterIntent
extends RefCounted
## What a party member wants to do this physics frame. Filled by whichever controller
## drives it (player input or follower AI); the character only ever reads this.

var move: Vector2 = Vector2.ZERO
## Desired facing. ZERO keeps the current aim.
var aim: Vector2 = Vector2.ZERO
## Edge-triggered: true only on the frame the action starts.
var attack_pressed: bool = false
var attack_held: bool = false
var block_held: bool = false
var dodge_pressed: bool = false
var interact_held: bool = false


func clear() -> void:
	move = Vector2.ZERO
	aim = Vector2.ZERO
	attack_pressed = false
	attack_held = false
	block_held = false
	dodge_pressed = false
	interact_held = false
