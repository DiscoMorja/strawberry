class_name GroundDecal
extends Node2D
## Draws an owner's ground-level visuals (telegraphs, swing arcs, aim marker)
## beneath every actor, so upright figures never get covered by flat effects.

var draw_callback: Callable


func _ready() -> void:
	z_as_relative = false
	z_index = ZLayers.GROUND_FX


func _draw() -> void:
	if draw_callback.is_valid():
		draw_callback.call(self)
