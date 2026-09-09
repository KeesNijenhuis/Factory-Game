extends Node2D
class_name PlacementController
## Shows a translucent ghost preview at the tile under the mouse cursor,
## while it's one of the 24 tiles in the 5x5 area surrounding the player,
## whenever a placeable item (any Item with placed_scene set) is the selected
## hotbar item, and instantiates that scene into the world on "place_item".
##
## Placed instances are parented directly under the level's Objects
## TileMapLayer at map_to_local(cell), exactly like a design-time
## TileSetScenesCollectionSource placement -- this is what lets
## InteractableContainer's existing compute_tile_object_id()/"saveable"
## machinery pick them up with no changes.

const GHOST_MODULATE: Color = Color(1.0, 1.0, 1.0, 0.5)

## Reused for the "not allowed" flash shown when the player presses place_item
## over an invalid spot -- the same scene Player.show_tool_denied_indicator()
## and ObjectResource.show_action_denied() already use for a denied swing, so
## a denied placement reads as the same familiar cue instead of a new one.
const ACTION_DENIED_SCENE: PackedScene = preload("res://src/levels/level_objects/components/action_denied_indicator.tscn")

## Child node names checked, in order, when reading a placed_scene's sprite
## offset for the ghost -- matches the "AnimatedSprite2D" convention
## InteractableContainer subclasses already follow (see its class doc
## comment), falling back to a plain Sprite2D for non-container placeables.
const SPRITE_CHILD_NAMES: Array[StringName] = [&"AnimatedSprite2D", &"Sprite2D"]

@onready var player: Player = get_parent()
@onready var ghost_sprite: Sprite2D = $GhostSprite

## Caches each placeable item's visual sprite offset (position + offset of
## its placed_scene's sprite child), keyed by Item, so the ghost only needs
## to spin up a throwaway instance of the scene once per item, not every
## frame, to figure out where its sprite actually renders relative to the
## node origin the object gets placed at.
var _ghost_offset_cache: Dictionary = {}
## Populated alongside _ghost_offset_cache (same throwaway instance), keyed
## by Item -- whether this placeable is a BeltComponent, i.e. whether
## placement-time rotation/auto-orient applies to it at all.
var _belt_item_cache: Dictionary = {}
## Populated alongside _ghost_offset_cache for belt items -- the belt scene's
## own BeltVisualSet, so the ghost can show the same straight/turn art the
## placed belt would use (picked by BeltComponent.visual_for()) instead of
## rotating a single texture.
var _belt_frames_cache: Dictionary = {}
## Populated alongside _ghost_offset_cache, keyed by Item -- how many tiles
## this placeable occupies (see AutomationUtils.get_object_footprint), read
## off the same throwaway instance. 1x1 for everything except a multi-tile
## machine like BlastFurnace.
var _grid_size_cache: Dictionary = {}
## Populated alongside _ghost_offset_cache, keyed by Item -- the matched
## sprite child's own scale (e.g. BlastFurnace's AnimatedSprite2D is scaled
## 2x to visually fill its bigger footprint). Without this the ghost always
## rendered at scale 1, looking exactly like a regular Furnace ghost even
## while previewing a 2x2 placement.
var _sprite_scale_cache: Dictionary = {}
## Populated alongside _ghost_offset_cache, keyed by Item -- the actual
## texture the placed_scene's sprite child would show at rest (an
## AnimatedSprite2D's frame 0 of its own default animation, or a plain
## Sprite2D's texture), so the ghost always matches whatever that scene
## currently looks like instead of a separately-authored Item.icon that can
## silently fall out of sync whenever the scene's own art changes. Falls back
## to item.icon (see _apply_ghost_texture) if no sprite child/frame is found.
var _ghost_texture_cache: Dictionary = {}
## Populated alongside _ghost_texture_cache, keyed by Item -- true if the
## resolved sprite child uses a manually-set region (region_enabled/
## region_rect on a plain Sprite2D) that needs copying to the ghost verbatim,
## rather than an AtlasTexture-typed texture, which already carries its own
## region internally and needs none of this.
var _ghost_region_enabled_cache: Dictionary = {}
var _ghost_region_cache: Dictionary = {}

## "" means auto-orient (continue a neighboring belt's line, or fall back to
## the player's own facing). Set by rotate_placement, reset after every
## successful placement and whenever the selected hotbar item changes, so a
## manual rotation only ever affects the one placement it was made for.
var _manual_facing_override: String = ""
var _last_ghost_item: Item = null

## Static (non-animated) preview chevrons shown on a belt ghost, one per
## Sprite2D, parented under ghost_sprite so they inherit its translucency
## and hide automatically whenever it does. Created once, up front, at the
## same fixed count and spacing a freshly-placed single tile's own
## flow_markers would settle into (see BeltSegment.refill_markers()) --
## derived from BeltComponent.MARKER_SPACING rather than a separate
## hardcoded count, so this stays in sync if that spacing ever changes.
var _ghost_marker_sprites: Array[Sprite2D] = []

## Outline drawn around every tile the hovered footprint would occupy (see
## _draw()) -- green/red the same way the ghost's own validity is implied
## elsewhere, so a multi-tile placement's actual occupied cells are always
## visible even if the ghost's own sprite art doesn't visually line up with
## them (e.g. an oversized/offset placed_scene sprite).
const OUTLINE_COLOR_VALID: Color = Color(0.3, 1.0, 0.3, 0.9)
const OUTLINE_COLOR_INVALID: Color = Color(1.0, 0.3, 0.3, 0.9)
const OUTLINE_WIDTH: float = 1.0
var _outline_visible: bool = false
var _outline_rect: Rect2 = Rect2()
var _outline_color: Color = OUTLINE_COLOR_VALID

func _ready() -> void:
	var progress := 0.0
	while progress < 1.0:
		var marker := Sprite2D.new()
		marker.visible = false
		ghost_sprite.add_child(marker)
		_ghost_marker_sprites.append(marker)
		progress += BeltComponent.MARKER_SPACING

func _process(_delta: float) -> void:
	var item := player.current_hotbar_item
	if item != _last_ghost_item:
		_manual_facing_override = ""
		_last_ghost_item = item

	if item == null or item.placed_scene == null:
		ghost_sprite.visible = false
		_hide_footprint_outline()
		return

	if player.hud.is_any_panel_visible():
		ghost_sprite.visible = false
		_hide_footprint_outline()
		return

	var level := _get_current_level()
	var objects_layer: TileMapLayer = level.get_objects_layer() if level else null
	if objects_layer == null:
		ghost_sprite.visible = false
		_hide_footprint_outline()
		return

	var player_cell := objects_layer.local_to_map(objects_layer.to_local(player.global_position))
	var target_cell := _get_target_cell(objects_layer)
	var footprint := _get_footprint(item)
	var in_reach := false
	for cell in AutomationUtils.get_footprint_cells(target_cell, footprint):
		if AutomationUtils.is_adjacent(player_cell, cell):
			in_reach = true
			break
	if not in_reach:
		ghost_sprite.visible = false
		_hide_footprint_outline()
		return

	var is_valid := _is_footprint_free(objects_layer, level.get_walls_layer(), level.get_ground_layer(), target_cell, footprint)
	_update_footprint_outline(objects_layer, target_cell, footprint, is_valid)

	if not is_valid and Input.is_action_just_pressed(&"place_item") and player.hud.held_item == null:
		_show_placement_denied(objects_layer, target_cell, footprint)

	ghost_sprite.visible = is_valid
	if is_valid:
		_apply_ghost_texture(item)
		var cell_position := objects_layer.to_global(objects_layer.map_to_local(target_cell))
		ghost_sprite.global_position = cell_position + _get_ghost_offset(item)
		ghost_sprite.scale = _get_sprite_scale(item)
		ghost_sprite.modulate = GHOST_MODULATE

	var facing := ""
	if _is_belt_item(item):
		if Input.is_action_just_pressed(&"rotate_placement"):
			var base: String = _manual_facing_override if _manual_facing_override != "" else _auto_orient_facing(objects_layer, target_cell)
			var next_index: int = ItemSlotComponent.FACING_ORDER.find(base)
			_manual_facing_override = ItemSlotComponent.FACING_ORDER[(next_index + 1) % ItemSlotComponent.FACING_ORDER.size()]
		facing = _manual_facing_override if _manual_facing_override != "" else _auto_orient_facing(objects_layer, target_cell)
		var input_facing := BeltManager.compute_input_facing(target_cell, facing)
		var anim := BeltComponent.visual_for(_belt_frames_cache.get(item), input_facing, facing)
		_apply_belt_ghost_texture(item, anim)
		_update_ghost_markers(_belt_frames_cache.get(item), anim)
	else:
		_hide_ghost_markers()

	if is_valid and Input.is_action_just_pressed(&"place_item") and player.hud.held_item == null:
		_place_item(item, objects_layer, target_cell, facing)
		_manual_facing_override = ""

## Placed objects are positioned at the tile's origin (see _place_item), but
## their sprite is drawn with its own position/offset within that scene (e.g.
## the furnace and chest sprites sit above the node origin so their collision
## footprint lines up with the tile's base). The ghost needs to apply the
## same visual offset, or it renders centered on the tile while the real
## object appears shifted once placed.
func _get_ghost_offset(item: Item) -> Vector2:
	if _ghost_offset_cache.has(item):
		return _ghost_offset_cache[item]
	var offset := Vector2.ZERO
	var instance: Node2D = item.placed_scene.instantiate()
	_belt_item_cache[item] = instance is BeltComponent
	_grid_size_cache[item] = AutomationUtils.get_object_footprint(instance)
	_sprite_scale_cache[item] = Vector2.ONE
	for child_name in SPRITE_CHILD_NAMES:
		var sprite := instance.get_node_or_null(NodePath(child_name)) as Node2D
		if sprite:
			offset = sprite.position + (sprite.get("offset") as Vector2)
			_sprite_scale_cache[item] = sprite.scale
			_cache_ghost_texture(item, sprite)
			break
	# visual_set lives on BeltComponent itself (an @export, so it's already
	# populated on this throwaway, never-_ready() instance) rather than on
	# whichever sprite-shaped child SPRITE_CHILD_NAMES matched above -- reading
	# it off the root decouples this cache from that child's node type.
	if instance is BeltComponent:
		_belt_frames_cache[item] = (instance as BeltComponent).visual_set
	instance.free()
	_ghost_offset_cache[item] = offset
	return offset

## Resolves the actual resting-frame texture (and, for a plain Sprite2D using
## a manual region, its region_rect) that sprite would currently be showing,
## caching it against item for _apply_ghost_texture(). An AnimatedSprite2D's
## SpriteFrames resource carries frame 0 of whichever animation the scene
## itself defaults to; a plain Sprite2D just has its own texture. Leaves the
## cache unset (falling back to item.icon) if neither yields a texture, e.g.
## an AnimatedSprite2D with no frames assigned to its default animation.
func _cache_ghost_texture(item: Item, sprite: Node2D) -> void:
	if sprite is AnimatedSprite2D:
		var anim_sprite := sprite as AnimatedSprite2D
		var frames := anim_sprite.sprite_frames
		if frames != null and frames.has_animation(anim_sprite.animation) and frames.get_frame_count(anim_sprite.animation) > 0:
			_ghost_texture_cache[item] = frames.get_frame_texture(anim_sprite.animation, 0)
	elif sprite is Sprite2D:
		var plain_sprite := sprite as Sprite2D
		if plain_sprite.texture != null:
			_ghost_texture_cache[item] = plain_sprite.texture
			if plain_sprite.region_enabled:
				_ghost_region_enabled_cache[item] = true
				_ghost_region_cache[item] = plain_sprite.region_rect

## Sets ghost_sprite's texture/region from the placed_scene's own resting
## sprite (see _cache_ghost_texture), falling back to item.icon if that
## resolved to nothing -- so the ghost always matches what the scene actually
## looks like right now instead of a separately-authored icon that can go
## stale whenever the scene's own art changes.
func _apply_ghost_texture(item: Item) -> void:
	if not _ghost_texture_cache.has(item):
		_get_ghost_offset(item)   # populates all caches together
	var texture: Texture2D = _ghost_texture_cache.get(item)
	ghost_sprite.texture = texture if texture != null else item.icon
	ghost_sprite.region_enabled = _ghost_region_enabled_cache.get(item, false)
	if ghost_sprite.region_enabled:
		ghost_sprite.region_rect = _ghost_region_cache[item]

## Shows the same static tile the real belt would be showing, whichever
## BeltComponent.visual_for() chose -- rather than rotating item.icon (which
## is always the same fixed icon art). Sets the ghost's texture/region
## directly (no shader/animation on the ghost, matching the fixed,
## un-animated frame the ghost always showed before this too).
func _apply_belt_ghost_texture(item: Item, anim: StringName) -> void:
	var visuals: BeltVisualSet = _belt_frames_cache.get(item)
	var entry := visuals.get_entry(anim) if visuals != null else null
	if entry == null:
		ghost_sprite.texture = item.icon
		ghost_sprite.region_enabled = false
		return
	ghost_sprite.texture = visuals.atlas
	ghost_sprite.region_enabled = true
	ghost_sprite.region_rect = entry.region

## Lays out _ghost_marker_sprites along the same lo/hi/axis/direction path
## BeltComponent.get_marker_world_position_for()/get_marker_world_direction_for()
## use for a real belt's flowing markers -- same formula, just evaluated once
## per fixed progress value instead of once per frame per moving marker, so
## the ghost shows a static preview of exactly where and which way that
## belt's chevrons would sit and point.
func _update_ghost_markers(visuals: BeltVisualSet, anim: StringName) -> void:
	var entry := visuals.get_entry(anim) if visuals != null else null
	if entry == null:
		_hide_ghost_markers()
		return
	var direction_vector := Vector2(entry.direction, 0.0) if entry.axis == "x" else Vector2(0.0, entry.direction)
	var marker_rotation := direction_vector.angle()
	var progress := 0.0
	for marker in _ghost_marker_sprites:
		var t := progress if entry.direction > 0 else (1.0 - progress)
		var local := entry.lo + t * (entry.hi - entry.lo) - BeltComponent.TILE_SIZE_PX * 0.5
		marker.texture = visuals.marker_texture
		marker.position = Vector2(local, 0.0) if entry.axis == "x" else Vector2(0.0, local)
		marker.rotation = marker_rotation
		marker.visible = true
		progress += BeltComponent.MARKER_SPACING

func _hide_ghost_markers() -> void:
	for marker in _ghost_marker_sprites:
		marker.visible = false

func _draw() -> void:
	if not DebugSettings.show_placement_footprint:
		return
	if _outline_visible:
		draw_rect(_outline_rect, _outline_color, false, OUTLINE_WIDTH)

## Computes the world-space rect covering every cell get_footprint_cells(anchor_cell,
## footprint) would return -- i.e. the actual tile area a placement targets --
## and queues it for _draw(). Built from two corner points run through
## objects_layer.to_global()/self.to_local() rather than a raw size vector, so
## it comes out correct regardless of any relative scale/rotation between
## objects_layer and this node (neither currently has any, but this way
## nothing here would need to change if that ever did).
func _update_footprint_outline(objects_layer: TileMapLayer, anchor_cell: Vector2i, footprint: Vector2i, is_valid: bool) -> void:
	var half_tile := Vector2.ONE * BeltComponent.TILE_SIZE_PX * 0.5
	var top_left_layer_local := objects_layer.map_to_local(anchor_cell) - half_tile
	var bottom_right_layer_local := top_left_layer_local + Vector2(footprint.x, footprint.y) * BeltComponent.TILE_SIZE_PX
	var top_left := to_local(objects_layer.to_global(top_left_layer_local))
	var bottom_right := to_local(objects_layer.to_global(bottom_right_layer_local))
	_outline_rect = Rect2(top_left, bottom_right - top_left)
	_outline_color = OUTLINE_COLOR_VALID if is_valid else OUTLINE_COLOR_INVALID
	_outline_visible = true
	queue_redraw()

func _hide_footprint_outline() -> void:
	if _outline_visible:
		_outline_visible = false
		queue_redraw()

func _is_belt_item(item: Item) -> bool:
	if not _belt_item_cache.has(item):
		_get_ghost_offset(item)   # populates both caches together
	return _belt_item_cache.get(item, false)

func _get_footprint(item: Item) -> Vector2i:
	if not _grid_size_cache.has(item):
		_get_ghost_offset(item)   # populates all four caches together
	return _grid_size_cache.get(item, Vector2i.ONE)

func _get_sprite_scale(item: Item) -> Vector2:
	if not _sprite_scale_cache.has(item):
		_get_ghost_offset(item)   # populates all four caches together
	return _sprite_scale_cache.get(item, Vector2.ONE)

## Defaults a belt's facing to continue an existing neighboring belt's line --
## either one that already feeds into target_cell, or one target_cell would
## naturally feed into -- falling back to the player's own facing when no
## neighbor qualifies. FACING_ORDER's order is just a deterministic tie-break
## between multiple qualifying neighbors (e.g. a T-junction-shaped spot).
func _auto_orient_facing(objects_layer: TileMapLayer, target_cell: Vector2i) -> String:
	for dir_name in ItemSlotComponent.FACING_ORDER:
		var offset: Vector2i = ItemSlotComponent.FACING_VECTORS[dir_name]
		var neighbor: BeltComponent = BeltManager.get_belt_at(objects_layer, target_cell + offset)
		if neighbor == null:
			continue
		if neighbor.facing == ItemSlotComponent.OPPOSITE_FACING[dir_name]:
			return neighbor.facing   # neighbor already feeds into target_cell -- continue its line
		if neighbor.facing == dir_name:
			return dir_name          # target_cell would feed into neighbor -- align with it
	return player.last_direction

func _get_current_level() -> BaseLevel:
	var main_game := get_tree().current_scene as MainGame
	return main_game.get_current_level() if main_game else null

func _get_target_cell(objects_layer: TileMapLayer) -> Vector2i:
	return objects_layer.local_to_map(objects_layer.to_local(get_global_mouse_position()))

func _is_cell_free(objects_layer: TileMapLayer, walls_layer: TileMapLayer, ground_layer: TileMapLayer, cell: Vector2i) -> bool:
	if walls_layer != null and walls_layer.get_cell_source_id(cell) != -1:
		return false
	if ground_layer != null and (ground_layer as CaveGroundLayer).is_dug(cell):
		return false
	return not AutomationUtils.is_cell_occupied(objects_layer, cell)

## True only if every cell size (anchored at anchor_cell) would cover is
## free -- for a 1x1 item this checks exactly the one cell _is_cell_free
## always checked, so a bigger placeable like BlastFurnace is validated
## across its whole footprint instead of just the tile under the cursor.
func _is_footprint_free(objects_layer: TileMapLayer, walls_layer: TileMapLayer, ground_layer: TileMapLayer, anchor_cell: Vector2i, size: Vector2i) -> bool:
	for cell in AutomationUtils.get_footprint_cells(anchor_cell, size):
		if not _is_cell_free(objects_layer, walls_layer, ground_layer, cell):
			return false
	return true

## Player-facing "not allowed" cue for a denied place_item press -- mirrors
## Player.show_tool_denied_indicator()/ObjectResource.show_action_denied(),
## the two other existing call sites for ACTION_DENIED_SCENE. Those parent it
## directly under the target object itself; PlacementController has no such
## node for an arbitrary tile, so it's parented under objects_layer instead
## and positioned at the footprint's own center, so it appears where the
## player was actually trying to place rather than always on their own tile.
func _show_placement_denied(objects_layer: TileMapLayer, target_cell: Vector2i, footprint: Vector2i) -> void:
	var indicator: Node2D = ACTION_DENIED_SCENE.instantiate()
	objects_layer.add_child(indicator)
	var offset := Vector2(footprint.x - 1, footprint.y - 1) * BeltComponent.TILE_SIZE_PX * 0.5
	indicator.position = objects_layer.map_to_local(target_cell) + offset

func _place_item(item: Item, objects_layer: TileMapLayer, cell: Vector2i, facing: String) -> void:
	var instance: Node2D = item.placed_scene.instantiate()
	# Position must be set before add_child(): _ready() fires the instant the
	# node enters the tree, and InteractableContainer._ready() computes its
	# save id from position at that moment -- setting it after add_child left
	# every runtime-placed object's save id computed from the scene's default
	# (0,0) position instead of its real cell, colliding with every other
	# placed object's id. BeltComponent._ready() additionally reads facing
	# right away to configure its InputSlot and register with BeltManager,
	# so facing must also be set before add_child() for the same reason.
	instance.position = objects_layer.map_to_local(cell)
	if instance is BeltComponent and facing != "":
		instance.facing = facing
	objects_layer.add_child(instance)
	AutomationUtils.notify_belt_manager_for_object(objects_layer, instance)
	var hotbar := player.hud.hotbar as Hotbar
	hotbar.inventory.remove_item(hotbar.selected_slot, 1)
