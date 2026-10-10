extends Node2D
## Grey-box test arena. Walls and pillars are built in code so layout tweaks are one-liners.
## The root is Y-sorted: actors and walls are depth-ordered by their feet / bottom edge.

const TrainingDummyScene := preload("res://debug/training_dummy.tscn")
const TrashScene := preload("res://enemies/trash.tscn")
const EliteScene := preload("res://enemies/elite.tscn")
const TRASH_PACK_SIZE := 6
const STRESS_PACKS := 5
const STRESS_PACK_SIZE := 10
const WALL_HEIGHT := 20.0

const FLOOR_A := Color(0.13, 0.12, 0.14)
const FLOOR_B := Color(0.15, 0.14, 0.16)

@export var arena_size := Vector2(960, 640)
@export var tile_size := 32.0
@export var wall_thickness := 32.0
@export var pillars: Array[Rect2] = [
	Rect2(224, 160, 32, 24),
	Rect2(704, 160, 32, 24),
	Rect2(224, 448, 32, 24),
	Rect2(704, 448, 32, 24),
	Rect2(448, 96, 64, 16),
]

var _director: Director


func _ready() -> void:
	y_sort_enabled = true
	var floor_layer := Node2D.new()
	floor_layer.name = "Floor"
	floor_layer.z_as_relative = false
	floor_layer.z_index = ZLayers.FLOOR
	floor_layer.draw.connect(_draw_floor.bind(floor_layer))
	add_child(floor_layer)

	var t := wall_thickness
	var solids: Array[Rect2] = [
		Rect2(-t, -t, arena_size.x + t * 2, t),
		Rect2(-t, arena_size.y, arena_size.x + t * 2, t),
		Rect2(-t, 0, t, arena_size.y),
		Rect2(arena_size.x, 0, t, arena_size.y),
	]
	solids.append_array(pillars)
	for rect in solids:
		add_child(WallBlock.create(rect, WALL_HEIGHT))

	var flow_field := FlowField.new()
	flow_field.bounds = Rect2(Vector2.ZERO, arena_size)
	add_child(flow_field)
	add_child(Crowd.new())
	_director = Director.new()
	_director.trash_scene = TrashScene
	_director.elite_scene = EliteScene
	add_child(_director)


func _unhandled_input(event: InputEvent) -> void:
	var mouse := get_global_mouse_position()
	if event.is_action_pressed("debug_spawn_dummy"):
		_spawn(TrainingDummyScene, mouse)
	elif event.is_action_pressed("debug_spawn_trash"):
		for i in TRASH_PACK_SIZE:
			_spawn(TrashScene, mouse + Vector2.from_angle(TAU * i / TRASH_PACK_SIZE) * 14.0)
	elif event.is_action_pressed("debug_spawn_elite"):
		_spawn(EliteScene, mouse)
	elif event.is_action_pressed("debug_toggle_director"):
		_director.set_enabled(not _director.enabled)
		Juice.popup_text(get_viewport().get_camera_2d().get_screen_center_position() + Vector2(0, -60),
				"director " + ("ON" if _director.enabled else "OFF"), Color.WHITE, 10)
	elif event.is_action_pressed("debug_stress_spawn"):
		for i in STRESS_PACKS:
			_director.spawn_pack(TrashScene, STRESS_PACK_SIZE)
	elif event.is_action_pressed("debug_clear_enemies"):
		for enemy in get_tree().get_nodes_in_group("enemies"):
			enemy.queue_free()


func _spawn(scene: PackedScene, at: Vector2) -> void:
	var node := scene.instantiate() as Node2D
	# Keep debug spawns inside the walls even when the cursor is outside the arena.
	node.position = at.clamp(Vector2(16, 16), arena_size - Vector2(16, 16))
	add_child(node)


func _draw_floor(canvas: Node2D) -> void:
	var cols := int(ceil(arena_size.x / tile_size))
	var rows := int(ceil(arena_size.y / tile_size))
	for y in rows:
		for x in cols:
			var color := FLOOR_A if (x + y) % 2 == 0 else FLOOR_B
			canvas.draw_rect(Rect2(x * tile_size, y * tile_size, tile_size, tile_size), color)
