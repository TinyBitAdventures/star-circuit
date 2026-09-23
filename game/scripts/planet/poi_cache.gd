class_name PoiCache
extends Node3D
## The interactable part of a point of interest (a cache or glyph panel).

var poi: Poi


func interact_info() -> Dictionary:
	return poi.cache_info()


func interact(_player: Node) -> void:
	poi.open_cache()
