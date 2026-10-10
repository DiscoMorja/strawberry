class_name BloodLayer
extends Node2D
## Persistent floor blood for one scene, painted into image chunks.
## Splats are rasterized once into CHUNK_SIZE textures and only dirty chunks re-upload
## (once per frame), so a hit costs the same no matter how much blood is already on the floor.
## (Redrawing every splat with draw_circle on each hit grew linearly and caused hit stalls.)

const CHUNK_SIZE := 128

## Vector2i chunk coordinate -> {image, texture}
var _chunks: Dictionary = {}
var _dirty: Dictionary = {}


func add_splat(at: Vector2, radius: float, color: Color) -> void:
	_paint_disc(at, radius, color)
	if radius > 2.0:
		# Irregular edge so larger pools don't read as perfect circles.
		_paint_disc(at + Vector2(radius * 0.5, radius * 0.3), radius * 0.6, color)
		_paint_disc(at - Vector2(radius * 0.4, radius * 0.5), radius * 0.5, color)


func _process(_delta: float) -> void:
	if _dirty.is_empty():
		return
	for key in _dirty:
		var chunk: Dictionary = _chunks[key]
		(chunk.texture as ImageTexture).update(chunk.image)
	_dirty.clear()


## Fills a disc row by row (one fill_rect per row, split across chunk borders).
func _paint_disc(center: Vector2, radius: float, color: Color) -> void:
	var r := maxf(radius, 0.5)
	var y0 := floori(center.y - r)
	var y1 := ceili(center.y + r)
	for y in range(y0, y1 + 1):
		var dy := (y + 0.5) - center.y
		var half_squared := r * r - dy * dy
		if half_squared < 0.0:
			continue
		var half := sqrt(half_squared)
		_fill_span(floori(center.x - half), ceili(center.x + half), y, color)


func _fill_span(x0: int, x1: int, y: int, color: Color) -> void:
	var x := x0
	while x < x1:
		var chunk_x := floori(float(x) / CHUNK_SIZE)
		var chunk_y := floori(float(y) / CHUNK_SIZE)
		var key := Vector2i(chunk_x, chunk_y)
		var chunk_end := (chunk_x + 1) * CHUNK_SIZE
		var span_end := mini(x1, chunk_end)
		var image: Image = _chunk(key).image
		image.fill_rect(Rect2i(x - chunk_x * CHUNK_SIZE, y - chunk_y * CHUNK_SIZE, span_end - x, 1), color)
		_dirty[key] = true
		x = span_end


func _chunk(key: Vector2i) -> Dictionary:
	if _chunks.has(key):
		return _chunks[key]
	var image := Image.create_empty(CHUNK_SIZE, CHUNK_SIZE, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.texture = texture
	sprite.position = Vector2(key) * CHUNK_SIZE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	var chunk := {"image": image, "texture": texture}
	_chunks[key] = chunk
	return chunk
