class_name FollowerAI
extends CharacterController
## Follower brain. Produces the same intent a player would, guided by the party's current
## order. Priorities, top first: struggle free, regroup, revive a downed ally, defend against an
## incoming attack, return to the anchor if leashed, fight a target, hold formation.
## Followers help with triage (archers prefer specials, everyone rescues grabbed allies) but
## don't solve it: the Focus order is how the player points them at what matters.

const RETARGET_INTERVAL := 0.3
const FORMATION_RADIUS := 26.0
const FORMATION_SPREAD := 0.9
const LEASH_FOLLOW := 120.0
const LEASH_HOLD := 40.0
const ENGAGE_RADIUS_AGGRESSIVE := 110.0
const ENGAGE_RADIUS_DEFENSIVE := 60.0
const RESCUE_RADIUS := 220.0
const REVIVE_SEARCH_RADIUS := 160.0
const REVIVE_SAFE_RADIUS := 30.0
const THREAT_RADIUS := 60.0
## Wind-up time left at which followers react (randomized per member so they aren't perfect).
const REACTION_WINDOW := Vector2(0.12, 0.3)
const RANGED_MIN_DISTANCE := 50.0
const HEAVY_CROWD := 3

var manager: PartyManager

var _target: Combatant
var _retarget_left := 0.0
var _heavy_hold_left := 0.0
var _reaction := 0.2
var _strafe_sign := 1.0
var _strafe_switch_left := 0.0
var _attack_gap_left := 0.0


func _init(p_manager: PartyManager) -> void:
	manager = p_manager
	_reaction = randf_range(REACTION_WINDOW.x, REACTION_WINDOW.y)


func update(member: PartyMember, delta: float) -> void:
	var intent := member.intent
	var position := member.global_position
	_attack_gap_left -= delta

	if member.is_grabbed():
		# Mash free once there's stamina for it (a little hesitation reads as human).
		intent.dodge_pressed = member.stamina >= member.struggle_cost and randf() < delta * 3.0
		return

	var anchor := manager.anchor_for(member)
	if manager.order == PartyManager.Order.REGROUP:
		_move_to(intent, position, anchor, 10.0)
		return

	var downed := manager.nearest_downed(member, position, REVIVE_SEARCH_RADIUS)
	if downed and manager.enemies_near(downed.global_position, REVIVE_SAFE_RADIUS) == 0:
		var to_ally := downed.global_position - position
		intent.aim = to_ally.normalized()
		if to_ally.length() > member.revive_range * 0.7:
			intent.move = to_ally.normalized()
		else:
			intent.interact_held = true
		return

	var threat := _incoming_threat(member)
	if threat:
		_defend(member, threat)
		return

	_retarget_left -= delta
	if _retarget_left <= 0.0 or not _valid(_target):
		_retarget_left = RETARGET_INTERVAL
		_target = _choose_target(member, anchor)

	var leash := LEASH_HOLD if manager.order == PartyManager.Order.HOLD else LEASH_FOLLOW
	if position.distance_to(anchor) > leash + _engage_radius(member) * 0.5 and manager.order != PartyManager.Order.FOCUS:
		_target = null
		_move_to(intent, position, anchor, 8.0)
		return

	if _target == null:
		_heavy_hold_left = 0.0
		_move_to(intent, position, manager.slot_position(member), 6.0)
		return

	if member.weapon.is_ranged:
		_fight_ranged(member, delta)
	else:
		_fight_melee(member, delta)


# --- Decisions ---------------------------------------------------------------

func _choose_target(member: PartyMember, anchor: Vector2) -> Combatant:
	if manager.order == PartyManager.Order.FOCUS and _valid(manager.focus_target):
		return manager.focus_target
	# Rescue grabbed allies: the grabber is everyone's problem.
	for ally in manager.members:
		if ally != member and ally.is_grabbed() and member.global_position.distance_to(ally.global_position) < RESCUE_RADIUS:
			return ally.grabbed_by
	var position := member.global_position
	var engage := _engage_radius(member)
	var best: Combatant = null
	var best_score := INF
	for enemy in manager.enemies:
		if not enemy.is_targetable():
			continue
		var from_anchor := enemy.global_position.distance_to(anchor)
		var from_me := enemy.global_position.distance_to(position)
		if from_anchor > engage and from_me > engage:
			continue
		var score := from_me
		if member.weapon.is_ranged:
			if from_me > member.weapon.projectile_range * 0.9:
				continue
			if enemy.is_priority:
				score -= 200.0
		# Help whoever the player is controlling.
		if enemy.target == manager.controlled:
			score -= 20.0
		if score < best_score:
			best_score = score
			best = enemy
	return best


## An enemy about to hit this member, once its wind-up is inside our reaction window.
func _incoming_threat(member: PartyMember) -> Enemy:
	for enemy in manager.enemies:
		if enemy.target != member or enemy.global_position.distance_to(member.global_position) > THREAT_RADIUS:
			continue
		if enemy.state == Enemy.State.ACTIVE or enemy.windup_remaining() <= _reaction:
			return enemy
	return null


func _defend(member: PartyMember, threat: Enemy) -> void:
	var intent := member.intent
	var to_threat := (threat.global_position - member.global_position).normalized()
	intent.aim = to_threat
	_heavy_hold_left = 0.0
	var attack := threat._attack
	var can_block := not member.weapon.is_ranged and attack and not attack.unblockable and member.stamina >= attack.block_cost
	var defensive := member.ai_stance == PartyMember.Stance.DEFENSIVE
	if can_block and (defensive or member.stamina > attack.block_cost or randf() < 0.7):
		intent.block_held = true
	elif member.state != PartyMember.State.DODGING:
		intent.move = to_threat.orthogonal() * _strafe_sign - to_threat * 0.5
		intent.dodge_pressed = threat.state == Enemy.State.WINDUP
		_reaction = randf_range(REACTION_WINDOW.x, REACTION_WINDOW.y)


func _fight_melee(member: PartyMember, delta: float) -> void:
	var intent := member.intent
	var to_target := _target.global_position - member.global_position
	var distance := to_target.length() - _target.body_radius - member.body_radius
	intent.aim = to_target.normalized()
	var reach := member.weapon.light_chain[0].reach
	if _heavy_hold_left > 0.0:
		_heavy_hold_left -= delta
		intent.attack_held = _heavy_hold_left > 0.0
		intent.move = intent.aim * 0.3
		return
	if distance > reach * 0.8:
		intent.move = to_target.normalized()
		return
	if _attack_gap_left > 0.0 or not _can_start_attack(member):
		return
	_attack_gap_left = randf_range(0.05, 0.2)
	intent.attack_pressed = true
	intent.attack_held = true
	var crowd := manager.enemies_near(member.global_position + intent.aim * reach * 0.6, reach)
	if crowd >= HEAVY_CROWD and randf() < 0.35:
		_heavy_hold_left = member.weapon.heavy_charge_time + 0.05


func _fight_ranged(member: PartyMember, delta: float) -> void:
	var intent := member.intent
	var to_target := _target.global_position - member.global_position
	var distance := to_target.length()
	intent.aim = to_target / maxf(distance, 0.001)
	if _heavy_hold_left > 0.0:
		_heavy_hold_left -= delta
		intent.attack_held = _heavy_hold_left > 0.0
		return
	var sees := manager.has_line_of_sight(member.global_position, _target.global_position)
	if distance < RANGED_MIN_DISTANCE:
		intent.move = -intent.aim
	elif not sees or distance > member.weapon.projectile_range * 0.8:
		intent.move = intent.aim
	else:
		_strafe_switch_left -= delta
		if _strafe_switch_left <= 0.0:
			_strafe_switch_left = randf_range(1.0, 2.5)
			_strafe_sign = -_strafe_sign
		intent.move = intent.aim.orthogonal() * 0.3 * _strafe_sign
	if not sees or _attack_gap_left > 0.0 or not _can_start_attack(member):
		return
	_attack_gap_left = randf_range(0.1, 0.35)
	intent.attack_pressed = true
	intent.attack_held = true
	var big_target := _target is Enemy and ((_target as Enemy).is_priority or _target.mass >= 4.0)
	if big_target and randf() < 0.5:
		_heavy_hold_left = member.weapon.heavy_charge_time + 0.05


# --- Helpers -----------------------------------------------------------------

func _can_start_attack(member: PartyMember) -> bool:
	return member.state == PartyMember.State.FREE or member.state == PartyMember.State.ATTACKING


func _move_to(intent: CharacterIntent, from: Vector2, to: Vector2, arrive_distance: float) -> void:
	var offset := to - from
	var distance := offset.length()
	if distance <= arrive_distance:
		return
	intent.move = offset / distance * clampf(distance / 30.0, 0.35, 1.0)
	intent.aim = offset / distance


func _engage_radius(member: PartyMember) -> float:
	return ENGAGE_RADIUS_DEFENSIVE if member.ai_stance == PartyMember.Stance.DEFENSIVE else ENGAGE_RADIUS_AGGRESSIVE


## Untyped on purpose: a freed target can't be passed through a typed parameter.
func _valid(combatant: Variant) -> bool:
	return is_instance_valid(combatant) and combatant.is_targetable()
