class_name WallBlock
extends StaticBody2D
## Solid block with a ground footprint and visible height (3/4 view).
## The origin sits on the footprint's bottom edge so Y-sorting puts actors standing
## behind the block underneath its front face.

const TOP_COLOR := Color(0.40, 0.38, 0.43)
const FRONT_COLOR := Color(0.26, 0.24, 0.28)
const EDGE_COLOR := Color(0.18, 0.16, 0.20)

var footprint_size: Vector2
var wall_height: float


static func create(footprint: Rect2, height: float) -> WallBlock:
	var block := WallBlock.new()
	block.footprint_size = footprint.size
	block.wall_height = height
	block.position = Vector2(footprint.get_center().x, footprint.end.y)
	return block


func _ready() -> void:
	collision_layer = PhysicsLayers.WORLD
	collision_mask = 0
	var shape := RectangleShape2D.new()
	shape.size = footprint_size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = Vector2(0, -footprint_size.y * 0.5)
	add_child(collider)


func _draw() -> void:
	var w := footprint_size.x
	var d := footprint_size.y
	var h := wall_height
	draw_rect(Rect2(-w * 0.5, -d - h, w, d), TOP_COLOR)
	draw_rect(Rect2(-w * 0.5, -h, w, h), FRONT_COLOR)
	draw_line(Vector2(-w * 0.5, -h), Vector2(w * 0.5, -h), EDGE_COLOR, 1.0)
