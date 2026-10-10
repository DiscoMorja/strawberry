extends Node2D
## Grey-box test arena. Walls and pillars are built in code so layout tweaks are one-liners.

const TrainingDummyScene := preload("res://debug/training_dummy.tscn")

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
	if event.is_action_pressed("debug_spawn_dummy"):
		var dummy := TrainingDummyScene.instantiate() as Node2D
		dummy.position = get_global_mouse_position()
		add_child(dummy)


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
