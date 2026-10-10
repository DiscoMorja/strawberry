class_name FlowField
extends Node
## Shared pathfinding for hordes: one Dijkstra search (circular bucket queue, 8 directions)
## from every living party member over a walkability grid; each enemy just reads the
## smoothed downhill gradient at its cell. Cost is O(cells) per refresh regardless of
## enemy count. Neighbour lists are precomputed as flat int arrays because per-cell
## Vector2i math in GDScript was the dominant cost.

const UNREACHABLE := 1 << 30
const STRAIGHT_COST := 10
const DIAGONAL_COST := 14
const BUCKET_COUNT := DIAGONAL_COST + 1
const OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

@export var cell_size: float = 16.0
@export var bounds: Rect2 = Rect2(0, 0, 960, 640)
@export var refresh_interval: float = 0.2
## Clearance (px) kept from walls when deciding if a cell is walkable.
@export var wall_clearance: float = 5.0

var _size: Vector2i
var _walkable := PackedByteArray()
var _distance := PackedInt32Array()
## Per cell: neighbour cell indices, step costs and unit directions (parallel arrays).
var _neighbors: Array[PackedInt32Array] = []
var _neighbor_costs: Array[PackedInt32Array] = []
var _neighbor_dirs: Array[PackedVector2Array] = []
var _refresh_left := 0.0


func _ready() -> void:
	add_to_group("flow_field")
	# Walls are added by the level in _ready; build the grid once physics has them.
	await get_tree().physics_frame
	rebuild_walkability()


func _physics_process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left <= 0.0 and not _walkable.is_empty():
		_refresh_left = refresh_interval
		_recompute()


func rebuild_walkability() -> void:
	_size = Vector2i(ceili(bounds.size.x / cell_size), ceili(bounds.size.y / cell_size))
	var count := _size.x * _size.y
	_walkable.resize(count)
	_distance.resize(count)
	var space := get_viewport().world_2d.direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2.ONE * (cell_size * 0.5 + wall_clearance)
	query.shape = shape
	query.collision_mask = PhysicsLayers.WORLD
	for y in _size.y:
		for x in _size.x:
			query.transform = Transform2D(0.0, cell_center(Vector2i(x, y)))
			_walkable[y * _size.x + x] = 0 if space.intersect_shape(query, 1).size() > 0 else 1
	_build_neighbors()
	_recompute()


## Normalized direction toward the nearest party member, or ZERO if unknown/unreachable.
## Weighted over all downhill neighbours, so crowds fan out instead of marching in single file.
func direction_at(world_position: Vector2) -> Vector2:
	var cell := world_to_cell(world_position)
	if not _in_bounds(cell):
		return Vector2.ZERO
	var i := _index(cell)
	var here := _distance[i]
	if here >= UNREACHABLE:
		return Vector2.ZERO
	var neighbors := _neighbors[i]
	var dirs := _neighbor_dirs[i]
	var gradient := Vector2.ZERO
	for k in neighbors.size():
		var drop := here - _distance[neighbors[k]]
		if drop > 0:
			gradient += dirs[k] * drop
	return gradient.normalized()


## Path distance in cost units (STRAIGHT_COST per orthogonal cell).
func distance_at(world_position: Vector2) -> int:
	var cell := world_to_cell(world_position)
	return _distance[_index(cell)] if _in_bounds(cell) else UNREACHABLE


func is_walkable(world_position: Vector2) -> bool:
	var cell := world_to_cell(world_position)
	return _in_bounds(cell) and _walkable[_index(cell)] == 1


func world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(floori((world_position.x - bounds.position.x) / cell_size), floori((world_position.y - bounds.position.y) / cell_size))


func cell_center(cell: Vector2i) -> Vector2:
	return bounds.position + (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size


func _build_neighbors() -> void:
	var count := _size.x * _size.y
	_neighbors.resize(count)
	_neighbor_costs.resize(count)
	_neighbor_dirs.resize(count)
	for y in _size.y:
		for x in _size.x:
			var cell := Vector2i(x, y)
			var indices := PackedInt32Array()
			var costs := PackedInt32Array()
			var dirs := PackedVector2Array()
			if _walkable[_index(cell)]:
				for offset in OFFSETS:
					if _can_step(cell, offset):
						indices.append(_index(cell + offset))
						var diagonal := offset.x != 0 and offset.y != 0
						costs.append(DIAGONAL_COST if diagonal else STRAIGHT_COST)
						dirs.append(Vector2(offset).normalized())
			var i := _index(cell)
			_neighbors[i] = indices
			_neighbor_costs[i] = costs
			_neighbor_dirs[i] = dirs


func _recompute() -> void:
	_distance.fill(UNREACHABLE)
	# Dial's algorithm with a circular bucket queue (edge costs are small integers).
	var buckets: Array = []
	for b in BUCKET_COUNT:
		buckets.append([])
	var pending := 0
	for node in get_tree().get_nodes_in_group("party"):
		var member := node as Combatant
		if member == null or not member.is_targetable():
			continue
		var cell := world_to_cell(member.global_position)
		if _in_bounds(cell) and _distance[_index(cell)] != 0:
			_distance[_index(cell)] = 0
			buckets[0].append(_index(cell))
			pending += 1
	var current := 0
	while pending > 0:
		var slot := current % BUCKET_COUNT
		var bucket: Array = buckets[slot]
		buckets[slot] = []
		pending -= bucket.size()
		for i: int in bucket:
			if _distance[i] != current:
				continue
			var neighbors := _neighbors[i]
			var costs := _neighbor_costs[i]
			for k in neighbors.size():
				var n := neighbors[k]
				var cost := current + costs[k]
				if cost < _distance[n]:
					_distance[n] = cost
					buckets[cost % BUCKET_COUNT].append(n)
					pending += 1
		current += 1


## Walkable neighbour, with no corner cutting: diagonals need both adjacent orthogonals open.
func _can_step(cell: Vector2i, offset: Vector2i) -> bool:
	var next := cell + offset
	if not _in_bounds(next) or not _walkable[_index(next)]:
		return false
	if offset.x != 0 and offset.y != 0:
		return _walkable[_index(Vector2i(cell.x + offset.x, cell.y))] and _walkable[_index(Vector2i(cell.x, cell.y + offset.y))]
	return true


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < _size.x and cell.y < _size.y


func _index(cell: Vector2i) -> int:
	return cell.y * _size.x + cell.x
