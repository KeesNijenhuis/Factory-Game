class_name BeltFlowMarkerRenderer
extends Node2D
## Draws every decorative flow marker currently travelling on the belts of
## one BeltSegment, batched into one MultiMeshInstance2D per distinct marker
## texture -- the same pattern BeltItemRenderer uses for real items, and for
## the same reason (a Sprite2D per marker doesn't scale). Owned and driven
## by exactly one BeltSegment (created once in its _ready() and added as its
## child, rebuilt once per frame after that segment's own tiles have
## advanced) -- one instance per stretch of belts, not one shared globally,
## so a marker never appears in more than one segment's batch at a time.
##
## Simpler than BeltItemRenderer in one respect: a marker texture is already
## a standalone, pre-cropped PNG (see bake_belt_flow_markers.py), never an
## AtlasTexture region of a shared spritesheet, so there's no need for that
## file's _resolve_texture() re-bake step.

const MARKER_QUAD_SIZE: Vector2 = Vector2(3, 12)

var _multimeshes_by_texture: Dictionary = {}   # Texture2D -> MultiMeshInstance2D
var _marker_mesh: ArrayMesh

func rebuild(belts: Array[BeltComponent]) -> void:
	var buckets: Dictionary = {}   # Texture2D -> Array[Dictionary]{position, rotation}
	for belt in belts:
		if belt.visual_set == null or belt.visual_set.marker_texture == null:
			continue
		var texture: Texture2D = belt.visual_set.marker_texture
		if not buckets.has(texture):
			buckets[texture] = []
		var marker_rotation := belt.get_marker_world_direction_for().angle()
		for progress in belt.flow_markers:
			buckets[texture].append({
				"position": belt.get_marker_world_position_for(progress),
				"rotation": marker_rotation,
			})

	for texture in buckets:
		var mmi := _get_or_create(texture)
		var entries: Array = buckets[texture]
		mmi.multimesh.instance_count = entries.size()
		for i in entries.size():
			var entry: Dictionary = entries[i]
			mmi.multimesh.set_instance_transform_2d(i, Transform2D(entry.rotation, entry.position))

	# Textures no longer carried by anything this frame still keep their
	# MultiMeshInstance2D (cheap, avoids realloc churn) but draw nothing.
	for texture in _multimeshes_by_texture:
		if not buckets.has(texture):
			_multimeshes_by_texture[texture].multimesh.instance_count = 0

func _get_or_create(texture: Texture2D) -> MultiMeshInstance2D:
	if _multimeshes_by_texture.has(texture):
		return _multimeshes_by_texture[texture]
	var mmi := MultiMeshInstance2D.new()
	# z_index=1 (naively "one above the belt's z=0 sprite") wasn't actually
	# enough and rendered behind -- the belt sits inside a y_sort_enabled
	# TileMapLayer, and a sibling-less top-level item like this one (parented
	# under the BeltManager autoload, not that layer) needs more than a
	# naive +1 to clear it. z_index=5 cleared the belt but also drew over
	# the player, who should still occlude markers the normal top-down way.
	# Matching BeltItemRenderer's own z_index (2) verified live as the
	# correct value: above every belt tile, still behind/in front of the
	# player exactly as real items already are.
	mmi.z_index = 2
	mmi.texture = texture
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.mesh = _get_marker_mesh()
	mmi.multimesh = mm
	add_child(mmi)
	_multimeshes_by_texture[texture] = mmi
	return mmi

func _get_marker_mesh() -> ArrayMesh:
	if _marker_mesh != null:
		return _marker_mesh
	var half := MARKER_QUAD_SIZE * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# UV (0,0) at the top-left vertex, V increasing downward -- matches how
	# Sprite2D/TextureRect read a texture, unlike QuadMesh's default mapping
	# (see BeltItemRenderer._get_item_mesh(), identical reasoning).
	st.set_uv(Vector2(0, 0)); st.add_vertex(Vector3(-half.x, -half.y, 0))
	st.set_uv(Vector2(1, 0)); st.add_vertex(Vector3(half.x, -half.y, 0))
	st.set_uv(Vector2(1, 1)); st.add_vertex(Vector3(half.x, half.y, 0))
	st.set_uv(Vector2(0, 0)); st.add_vertex(Vector3(-half.x, -half.y, 0))
	st.set_uv(Vector2(1, 1)); st.add_vertex(Vector3(half.x, half.y, 0))
	st.set_uv(Vector2(0, 1)); st.add_vertex(Vector3(-half.x, half.y, 0))
	_marker_mesh = st.commit()
	return _marker_mesh
