class_name BeltItemRenderer
extends Node2D
## Draws every item currently in transit on any belt, batched into one
## MultiMeshInstance2D per distinct icon, not a Sprite2D per item, since the
## number of in-transit items can get large once there are many belts --
## kept as one single global batch (unlike the per-segment flow-marker
## rendering, see BeltFlowMarkerRenderer) since it scales with item count,
## not stretch count, and item rendering was never involved in the bug that
## motivated splitting markers per segment.
## Owned and driven by BeltManager (created once in its _ready() and added
## as its child), but ticks itself via its own _process() below rather than
## being rebuilt by BeltManager, since BeltManager itself no longer runs a
## per-frame loop -- each BeltSegment now owns that. process_priority is set
## high in _ready() so this still reliably rebuilds after every segment's
## own _process() each frame.
## Parented under the BeltManager autoload rather than the current level on
## purpose: a level gets freed wholesale on reload/transition, and tying the
## renderer's lifetime to it crashed BeltComponent._ready() on the very next
## registration (Cannot call method on a previously freed instance). A
## CanvasItem with no CanvasItem ancestor still renders into the same
## viewport canvas as everything else, so global_position math here lines up
## with the rest of the world the same way it does throughout this codebase.

const ITEM_QUAD_SIZE: Vector2 = Vector2(8, 8)

var _multimeshes_by_texture: Dictionary = {}   # Texture2D (resolved) -> MultiMeshInstance2D
## Item icons are commonly AtlasTextures cropped from a shared spritesheet
## (see e.g. transport_belt.tres, chest.tres). MultiMeshInstance2D.texture
## is handed straight to the rendering server as a raw texture RID, bypassing
## AtlasTexture's region entirely -- so assigning icon directly draws the
## *whole* underlying spritesheet, not just its region. Baking each icon
## down to a standalone, already-cropped ImageTexture once (cached here)
## sidesteps that: get_image() returns the correctly-cropped pixels for any
## Texture2D, atlas or not.
var _resolved_texture_by_icon: Dictionary = {}   # Texture2D (icon) -> Texture2D (resolved)
## QuadMesh's default UV mapping runs its V axis opposite to 2D's top-left-
## origin/Y-down texture convention -- fine for a 3D ground plane, but it
## rendered every item icon upside down here. Built once (identical geometry
## for every texture) with UVs laid out to match ordinary 2D sprite drawing.
var _item_mesh: ArrayMesh

func _ready() -> void:
	# Must run after every BeltSegment's default-priority _process() in the
	# same frame, or items render one frame stale.
	process_priority = 1

func _process(_delta: float) -> void:
	rebuild(BeltManager.get_all_belts())

func rebuild(belts: Array[BeltComponent]) -> void:
	var buckets: Dictionary = {}   # Texture2D (resolved) -> Array[Vector2]
	for belt in belts:
		for entry in belt.items_in_transit:
			var icon: Texture2D = entry.item.icon
			if icon == null:
				continue
			var resolved := _resolve_texture(icon)
			if not buckets.has(resolved):
				buckets[resolved] = []
			buckets[resolved].append(belt.get_world_position_for(entry.progress))

	for texture in buckets:
		var mmi := _get_or_create(texture)
		var positions: Array = buckets[texture]
		mmi.multimesh.instance_count = positions.size()
		for i in positions.size():
			mmi.multimesh.set_instance_transform_2d(i, Transform2D(0.0, positions[i]))

	# Textures no longer carried by anything this frame still keep their
	# MultiMeshInstance2D (cheap, avoids realloc churn) but draw nothing.
	for texture in _multimeshes_by_texture:
		if not buckets.has(texture):
			_multimeshes_by_texture[texture].multimesh.instance_count = 0

func _resolve_texture(icon: Texture2D) -> Texture2D:
	if _resolved_texture_by_icon.has(icon):
		return _resolved_texture_by_icon[icon]
	var resolved: Texture2D = ImageTexture.create_from_image(icon.get_image())
	_resolved_texture_by_icon[icon] = resolved
	return resolved

func _get_or_create(texture: Texture2D) -> MultiMeshInstance2D:
	if _multimeshes_by_texture.has(texture):
		return _multimeshes_by_texture[texture]
	var mmi := MultiMeshInstance2D.new()
	mmi.z_index = 2   # well above belt sprites/other world objects (Furnace/GroundItem use z_index=1)
	mmi.texture = texture
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.mesh = _get_item_mesh()
	mmi.multimesh = mm
	add_child(mmi)
	_multimeshes_by_texture[texture] = mmi
	return mmi

func _get_item_mesh() -> ArrayMesh:
	if _item_mesh != null:
		return _item_mesh
	var half := ITEM_QUAD_SIZE * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# UV (0,0) at the top-left vertex, V increasing downward -- matches how
	# Sprite2D/TextureRect read a texture, unlike QuadMesh's default mapping.
	st.set_uv(Vector2(0, 0)); st.add_vertex(Vector3(-half.x, -half.y, 0))
	st.set_uv(Vector2(1, 0)); st.add_vertex(Vector3(half.x, -half.y, 0))
	st.set_uv(Vector2(1, 1)); st.add_vertex(Vector3(half.x, half.y, 0))
	st.set_uv(Vector2(0, 0)); st.add_vertex(Vector3(-half.x, -half.y, 0))
	st.set_uv(Vector2(1, 1)); st.add_vertex(Vector3(half.x, half.y, 0))
	st.set_uv(Vector2(0, 1)); st.add_vertex(Vector3(-half.x, half.y, 0))
	_item_mesh = st.commit()
	return _item_mesh
