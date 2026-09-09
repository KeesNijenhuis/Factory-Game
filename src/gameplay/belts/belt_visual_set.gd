class_name BeltVisualSet
extends Resource
## Bundles a belt's static background atlas with the shared flow-marker
## glyph, plus one BeltVisualEntry per named animation describing which
## atlas region to show. Looked up by name the same way SpriteFrames
## animations once were -- BeltComponent.visual_for() returns a StringName
## key into this set.

@export var atlas: Texture2D
## Small standalone glyph instanced many times along a belt's path by
## BeltFlowMarkerRenderer -- not part of the atlas, since it moves
## independently of any one tile.
@export var marker_texture: Texture2D
@export var entries: Array[BeltVisualEntry] = []

var _by_name: Dictionary = {}

func has_animation(anim_name: StringName) -> bool:
	return get_entry(anim_name) != null

func get_entry(anim_name: StringName) -> BeltVisualEntry:
	if _by_name.is_empty() and not entries.is_empty():
		for entry in entries:
			_by_name[entry.anim_name] = entry
	return _by_name.get(anim_name)
