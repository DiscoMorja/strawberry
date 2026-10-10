class_name PlayerController
extends CharacterController
## Reads keyboard/mouse and gamepad into the controlled member's intent.

const STICK_AIM_DEADZONE := 0.3

var _using_stick_aim := false


## Mouse movement hands aim back to the mouse after stick use.
func notify_mouse_motion() -> void:
	_using_stick_aim = false


func update(member: PartyMember, _delta: float) -> void:
	var intent := member.intent
	intent.move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	intent.aim = _read_aim(member)
	intent.attack_pressed = Input.is_action_just_pressed("attack")
	intent.attack_held = Input.is_action_pressed("attack")
	intent.block_held = Input.is_action_pressed("block")
	intent.dodge_pressed = Input.is_action_just_pressed("dodge")
	intent.interact_held = Input.is_action_pressed("interact")


func _read_aim(member: PartyMember) -> Vector2:
	var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if stick.length() > STICK_AIM_DEADZONE:
		_using_stick_aim = true
		return stick.normalized()
	if _using_stick_aim:
		return Vector2.ZERO
	var to_mouse := member.get_global_mouse_position() - member.global_position
	return to_mouse.normalized() if to_mouse.length() > 1.0 else Vector2.ZERO
