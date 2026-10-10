class_name Crowd
extends Node
## Cheap horde separation. Enemies don't physically collide with each other (pairwise
## move_and_slide collisions are the main physics cost at horde sizes); instead this
## spatial hash pushes neighbours apart as a steering force.

@export var cell_size: float = 12.0
## Separation speed at full overlap (px/s). Must beat chase speed or crowds collapse into a pile.
@export var push_strength: float = 180.0
## Neighbours considered per body. Bounds the cost in dense clumps (otherwise O(n²)).
@export var max_neighbors: int = 6
## Extra spacing kept between bodies (px).
@export var padding: float = 2.0

var _cells: Dictionary = {}


func _ready() -> void:
	add_to_group("crowd")
	# Rebuild before enemies run their physics this frame.
	process_physics_priority = -100


func _physics_process(_delta: float) -> void:
	_cells.clear()
	for node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Combatant
		if body == null or body.is_dead:
			continue
		var key := _cell_of(body.global_position)
		if _cells.has(key):
			_cells[key].append(body)
		else:
			_cells[key] = [body]


## Steering velocity pushing `body` away from overlapping neighbours.
func separation(body: Combatant) -> Vector2:
	var push := Vector2.ZERO
	var center := _cell_of(body.global_position)
	var position := body.global_position
	var considered := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var bucket: Variant = _cells.get(center + Vector2i(dx, dy))
			if bucket == null:
				continue
			for other: Combatant in bucket:
				if other == body:
					continue
				var offset := position - other.global_position
				var min_distance := body.body_radius + other.body_radius + padding
				var distance_squared := offset.length_squared()
				if distance_squared >= min_distance * min_distance:
					continue
				if distance_squared < 0.0001:
					offset = Vector2.from_angle(randf() * TAU)
					distance_squared = 1.0
				var distance := sqrt(distance_squared)
				# Heavier bodies get pushed less.
				var weight := other.mass / (other.mass + body.mass)
				push += offset / distance * (1.0 - distance / min_distance) * weight * 2.0
				considered += 1
				if considered >= max_neighbors:
					return push * push_strength
	return push * push_strength


func _cell_of(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / cell_size), floori(world_position.y / cell_size))
