extends Node2D
## Grey-box test arena. Walls and pillars are built in code so layout tweaks are one-liners.

const TrainingDummyScene := preload("res://debug/training_dummy.tscn")
const TrashScene := preload("res://enemies/trash.tscn")
const EliteScene := preload("res://enemies/elite.tscn")
const TRASH_PACK_SIZE := 6

@export var arena_size := Vector2(960, 640)
@export var tile_size := 32.0
@export var wall_thickness := 32.0
@export var pillars: Array[Rect2] = [
	Rect2(224, 160, 32, 32),
	Rect2(704, 160, 32, 32),
	Rect2(224, 448, 32, 32),
	Rect2(704, 448, 32, 32),
	Rect2(448, 96, 64, 16),
]

const FLOOR_A := Color(0.13, 0.12, 0.14)
const FLOOR_B := Color(0.15, 0.14, 0.16)
const WALL_COLOR := Color(0.32, 0.30, 0.34)

var _solid_rects: Array[Rect2] = []


func _ready() -> void:
	var t := wall_thickness
	_solid_rects = [
		Rect2(-t, -t, arena_size.x + t * 2, t),
		Rect2(-t, arena_size.y, arena_size.x + t * 2, t),
		Rect2(-t, 0, t, arena_size.y),
		Rect2(arena_size.x, 0, t, arena_size.y),
	]
	_solid_rects.append_array(pillars)
	for rect in _solid_rects:
		_add_solid(rect)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var mouse := get_global_mouse_position()
	if event.is_action_pressed("debug_spawn_dummy"):
		_spawn(TrainingDummyScene, mouse)
	elif event.is_action_pressed("debug_spawn_trash"):
		for i in TRASH_PACK_SIZE:
			_spawn(TrashScene, mouse + Vector2.from_angle(TAU * i / TRASH_PACK_SIZE) * 14.0)
	elif event.is_action_pressed("debug_spawn_elite"):
		_spawn(EliteScene, mouse)
	elif event.is_action_pressed("debug_clear_enemies"):
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.queue_free()


func _spawn(scene: PackedScene, at: Vector2) -> void:
	var node := scene.instantiate() as Node2D
	node.position = at
	add_child(node)


func _add_solid(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = PhysicsLayers.WORLD
	body.collision_mask = 0
	body.position = rect.get_center()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)


func _draw() -> void:
	var cols := int(ceil(arena_size.x / tile_size))
	var rows := int(ceil(arena_size.y / tile_size))
	for y in rows:
		for x in cols:
			var color := FLOOR_A if (x + y) % 2 == 0 else FLOOR_B
			draw_rect(Rect2(x * tile_size, y * tile_size, tile_size, tile_size), color)
	for rect in _solid_rects:
		draw_rect(rect, WALL_COLOR)
