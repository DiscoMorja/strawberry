class_name Director
extends Node
## Paces combat in Left 4 Dead / Vermintide style: a build-up of trickling packs,
## a horde peak, then a relax period. Spawns happen out of sight along the flow field.

signal phase_changed(phase: Phase)

enum Phase { BUILD_UP, HORDE, RELAX }

const SPAWN_SPREAD := 18.0
## Spawn points must be at least this far from the camera's visible rect (px).
const OFFSCREEN_MARGIN := 24.0
const SPAWN_POINT_ATTEMPTS := 40

@export var enabled: bool = false
@export var trash_scene: PackedScene
@export var elite_scene: PackedScene

@export_group("Build-up")
@export var build_up_duration: float = 25.0
@export var trickle_interval: Vector2 = Vector2(3.0, 6.0)
@export var trickle_pack_size: Vector2i = Vector2i(2, 5)
@export var elite_interval: float = 40.0

@export_group("Horde")
@export var horde_size: int = 40
@export var horde_spawn_duration: float = 8.0
## The horde ends once fewer than this many enemies are alive.
@export var horde_end_threshold: int = 8

@export_group("Relax")
@export var relax_duration: float = 12.0

@export_group("Limits")
@export var max_alive: int = 220
## Path distance from the party for spawn points, in flow-field cells.
@export var spawn_cell_distance: Vector2i = Vector2i(14, 30)

var phase: Phase = Phase.RELAX
var phase_time: float = 0.0

var _trickle_left := 0.0
var _elite_left := 0.0
var _horde_spawned := 0
var _horde_points: Array[Vector2] = []
var _flow_field: FlowField


func _ready() -> void:
	add_to_group("director")
	_elite_left = elite_interval


func _physics_process(delta: float) -> void:
	if not enabled:
		return
	if _flow_field == null:
		_flow_field = get_tree().get_first_node_in_group("flow_field") as FlowField
		if _flow_field == null:
			return
	phase_time += delta
	match phase:
		Phase.BUILD_UP:
			_trickle_left -= delta
			if _trickle_left <= 0.0:
				_trickle_left = randf_range(trickle_interval.x, trickle_interval.y)
				spawn_pack(trash_scene, randi_range(trickle_pack_size.x, trickle_pack_size.y))
			_elite_left -= delta
			if _elite_left <= 0.0 and elite_scene:
				_elite_left = elite_interval
				spawn_pack(elite_scene, 1)
			if phase_time >= build_up_duration:
				_set_phase(Phase.HORDE)
		Phase.HORDE:
			var target_spawned := int(horde_size * clampf(phase_time / horde_spawn_duration, 0.0, 1.0))
			while _horde_spawned < target_spawned:
				_spawn_at(trash_scene, _horde_points.pick_random())
				_horde_spawned += 1
			if _horde_spawned >= horde_size and alive_count() < horde_end_threshold:
				_set_phase(Phase.RELAX)
		Phase.RELAX:
			if phase_time >= relax_duration:
				_set_phase(Phase.BUILD_UP)


func set_enabled(value: bool) -> void:
	enabled = value
	if enabled:
		_set_phase(Phase.BUILD_UP)


func alive_count() -> int:
	return get_tree().get_node_count_in_group("enemies")


func phase_name() -> String:
	return Phase.keys()[phase]


## Spawns `count` of `scene` clustered at one out-of-sight point. Returns how many spawned.
func spawn_pack(scene: PackedScene, count: int) -> int:
	if scene == null:
		return 0
	var point: Variant = find_spawn_point()
	if point == null:
		return 0
	var spawned := 0
	for i in count:
		if _spawn_at(scene, point):
			spawned += 1
	return spawned


## Random walkable point out of camera view, at a path distance from the party. Null if none found.
func find_spawn_point() -> Variant:
	if _flow_field == null:
		_flow_field = get_tree().get_first_node_in_group("flow_field") as FlowField
		if _flow_field == null:
			return null
	var view := _camera_view_rect().grow(OFFSCREEN_MARGIN)
	var bounds := _flow_field.bounds
	for attempt in SPAWN_POINT_ATTEMPTS:
		var point := Vector2(randf_range(bounds.position.x, bounds.end.x), randf_range(bounds.position.y, bounds.end.y))
		if view.has_point(point) or not _flow_field.is_walkable(point):
			continue
		var cells := _flow_field.distance_at(point) / float(FlowField.STRAIGHT_COST)
		if cells >= spawn_cell_distance.x and cells <= spawn_cell_distance.y:
			return point
	return null


func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	phase_time = 0.0
	match phase:
		Phase.BUILD_UP:
			_trickle_left = 1.0
		Phase.HORDE:
			_horde_spawned = 0
			_horde_points.clear()
			for i in 2:
				var point: Variant = find_spawn_point()
				if point != null:
					_horde_points.append(point)
			if _horde_points.is_empty():
				_set_phase(Phase.RELAX)
				return
			_announce("HORDE INCOMING", Color(0.9, 0.2, 0.15))
			Sfx.play_cue(Sfx.Cue.HORDE)
	phase_changed.emit(phase)


func _spawn_at(scene: PackedScene, point: Vector2) -> bool:
	if alive_count() >= max_alive:
		return false
	var node := scene.instantiate() as Node2D
	node.position = point + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * SPAWN_SPREAD
	get_parent().add_child(node)
	return true


func _announce(text: String, color: Color) -> void:
	var camera := get_viewport().get_camera_2d()
	var at := camera.get_screen_center_position() + Vector2(0, -60) if camera else Vector2.ZERO
	Juice.popup_text(at, text, color, 14)
	Juice.shake(0.25)


func _camera_view_rect() -> Rect2:
	var canvas := get_viewport().get_canvas_transform()
	var top_left := canvas.affine_inverse() * Vector2.ZERO
	var size := get_viewport().get_visible_rect().size / canvas.get_scale()
	return Rect2(top_left, size)
