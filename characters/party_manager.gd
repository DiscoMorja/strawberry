class_name PartyManager
extends Node2D
## Owns the party: who the player controls, the current order, focus target, hold points and
## tactical slow-motion. Followers read their instructions from here.

signal controlled_changed(member: PartyMember)
signal order_changed(order: Order)

enum Order { FOLLOW, HOLD, FOCUS, REGROUP }

const FOCUS_PICK_RADIUS := 48.0
const FOCUS_AIM_RANGE := 220.0
const REGROUP_DONE_DISTANCE := 34.0

@export var camera: CameraRig
## Time scale while the tactical key is held.
@export var tactical_time_scale: float = 0.25

var members: Array[PartyMember] = []
var controlled: PartyMember
var order: Order = Order.FOLLOW
var focus_target: Combatant
## Enemies alive this frame, refreshed once for all followers.
var enemies: Array[Enemy] = []

var player_controller := PlayerController.new()
var _ai: Dictionary = {}
var _hold_points: Dictionary = {}
var _tactical := false


func _ready() -> void:
	add_to_group("party_manager")
	z_as_relative = false
	z_index = ZLayers.FX
	# Refresh shared state before any party member thinks this frame.
	process_physics_priority = -50
	_collect_members.call_deferred()


func _collect_members() -> void:
	for node in get_tree().get_nodes_in_group("party"):
		var member := node as PartyMember
		if member and not members.has(member):
			register(member)


func register(member: PartyMember) -> void:
	members.append(member)
	_ai[member] = FollowerAI.new(self)
	member.controller = _ai[member]
	member.downed.connect(_on_member_downed)
	member.died.connect(_on_member_died)
	if controlled == null and member.is_hero:
		set_controlled(member)


func set_controlled(member: PartyMember) -> void:
	if controlled and is_instance_valid(controlled):
		controlled.controller = _ai.get(controlled)
		controlled.is_controlled = false
		controlled.remove_from_group("player")
	controlled = member
	member.controller = player_controller
	member.is_controlled = true
	member.add_to_group("player")
	if camera:
		camera.target = member
	controlled_changed.emit(member)


## Cycles control to the next member who can act.
func swap_next() -> void:
	var standing := members.filter(func(m: PartyMember) -> bool: return m.is_targetable())
	if standing.is_empty():
		return
	var index := standing.find(controlled)
	set_controlled(standing[(index + 1) % standing.size()])


func set_order(new_order: Order) -> void:
	match new_order:
		Order.FOCUS:
			var target := _pick_focus_target()
			if target == null:
				_announce("no target", Color(0.7, 0.7, 0.7))
				return
			focus_target = target
		Order.HOLD:
			_hold_points.clear()
			for member in members:
				_hold_points[member] = member.global_position
		_:
			focus_target = null
	order = new_order
	_announce(Order.keys()[order], Color(0.9, 0.9, 0.6))
	order_changed.emit(order)


## Where a follower should be centred: the controlled member, or its hold point.
func anchor_for(member: PartyMember) -> Vector2:
	if order == Order.HOLD and _hold_points.has(member):
		return _hold_points[member]
	if is_instance_valid(controlled):
		return controlled.global_position
	return member.global_position


## Formation spot behind the controlled member, fanned out by follower index.
func slot_position(member: PartyMember) -> Vector2:
	if order == Order.HOLD and _hold_points.has(member):
		return _hold_points[member]
	if not is_instance_valid(controlled) or member == controlled:
		return member.global_position
	var followers := members.filter(func(m: PartyMember) -> bool: return m != controlled)
	var index := followers.find(member)
	var count := followers.size()
	var angle := controlled.aim_direction.angle() + PI + (index - (count - 1) * 0.5) * FollowerAI.FORMATION_SPREAD
	return controlled.global_position + Vector2.from_angle(angle) * FollowerAI.FORMATION_RADIUS


func nearest_downed(exclude: PartyMember, from: Vector2, radius: float) -> PartyMember:
	var best: PartyMember = null
	var best_distance := radius
	for member in members:
		if member != exclude and is_instance_valid(member) and member.is_downed():
			var d := from.distance_to(member.global_position)
			if d < best_distance:
				best_distance = d
				best = member
	return best


func enemies_near(point: Vector2, radius: float) -> int:
	var count := 0
	var radius_squared := radius * radius
	for enemy in enemies:
		if enemy.is_targetable() and enemy.global_position.distance_squared_to(point) <= radius_squared:
			count += 1
	return count


func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, PhysicsLayers.WORLD)
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _physics_process(_delta: float) -> void:
	enemies.clear()
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy and not enemy.is_dead:
			enemies.append(enemy)
	if order == Order.FOCUS and not (is_instance_valid(focus_target) and focus_target.is_targetable()):
		focus_target = null
		order = Order.FOLLOW
		order_changed.emit(order)
	if order == Order.REGROUP and _regrouped():
		order = Order.FOLLOW
		_announce("FOLLOW", Color(0.9, 0.9, 0.6))
		order_changed.emit(order)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		player_controller.notify_mouse_motion()
	elif event.is_action_pressed("swap_character"):
		swap_next()
	elif event.is_action_pressed("command_follow"):
		set_order(Order.FOLLOW)
	elif event.is_action_pressed("command_hold"):
		set_order(Order.HOLD)
	elif event.is_action_pressed("command_focus"):
		set_order(Order.FOCUS)
	elif event.is_action_pressed("command_regroup"):
		set_order(Order.REGROUP)
	elif event.is_action_pressed("tactical"):
		_tactical = true
		Juice.tactical_scale = tactical_time_scale
	elif event.is_action_released("tactical"):
		_tactical = false
		Juice.tactical_scale = 1.0


func is_tactical() -> bool:
	return _tactical


func _on_member_downed(member: PartyMember) -> void:
	if member == controlled:
		swap_next()


func _on_member_died(member: Combatant) -> void:
	var party_member := member as PartyMember
	if party_member == null or party_member.is_hero:
		return
	members.erase(party_member)
	_ai.erase(party_member)
	_hold_points.erase(party_member)
	if controlled == party_member:
		controlled = null
		swap_next()


## Enemy under the cursor, else the best-aligned enemy along the controlled member's aim.
func _pick_focus_target() -> Combatant:
	var mouse := get_global_mouse_position()
	var best: Combatant = null
	var best_distance := FOCUS_PICK_RADIUS
	for enemy in enemies:
		var d := enemy.global_position.distance_to(mouse)
		if d < best_distance:
			best_distance = d
			best = enemy
	if best or not is_instance_valid(controlled):
		return best
	var best_score := -INF
	for enemy in enemies:
		var offset := enemy.global_position - controlled.global_position
		if offset.length() > FOCUS_AIM_RANGE:
			continue
		var score := controlled.aim_direction.dot(offset.normalized()) - offset.length() / FOCUS_AIM_RANGE * 0.3
		if score > best_score and controlled.aim_direction.dot(offset.normalized()) > 0.8:
			best_score = score
			best = enemy
	return best


func _regrouped() -> bool:
	if not is_instance_valid(controlled):
		return true
	for member in members:
		if member != controlled and member.is_targetable() and member.global_position.distance_to(controlled.global_position) > REGROUP_DONE_DISTANCE:
			return false
	return true


func _announce(text: String, color: Color) -> void:
	if is_instance_valid(controlled):
		Juice.popup_text(controlled.head_position() + Vector2(0, -10), text, color, 9)


func _draw() -> void:
	if order == Order.FOCUS and is_instance_valid(focus_target):
		var center := focus_target.global_position + Vector2(0, -focus_target.body_height * 0.5)
		var r := focus_target.body_height * 0.5 + 6.0
		var color := Color(1.0, 0.25, 0.2)
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var c: Vector2 = center + corner * r
			draw_line(c, c - Vector2(corner.x * 4.0, 0), color, 1.5)
			draw_line(c, c - Vector2(0, corner.y * 4.0), color, 1.5)
	if order == Order.HOLD:
		for member in _hold_points:
			if is_instance_valid(member):
				var p: Vector2 = _hold_points[member]
				draw_arc(p, 5.0, 0.0, TAU, 12, Color(member.ring_color, 0.6), 1.0)
				draw_line(p + Vector2(-3, 0), p + Vector2(3, 0), Color(member.ring_color, 0.6), 1.0)
	if _tactical:
		var view := get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_visible_rect()
		draw_rect(view, Color(0.1, 0.15, 0.3, 0.18))
