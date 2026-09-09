extends Resource
class_name ShapedCraftingRecipe
## Data for a single crafting-bench craft: a shaped grid pattern of inputs,
## what it produces, and what it costs to make.

enum WorkbenchType { CRAFTING_BENCH }
## Extensibility hook: only one workbench type exists today. A future type
## is added here plus a matching entry in WORKBENCH_GRID_SIZE below; the
## recipe editor addon looks the grid size up from that table rather than
## hardcoding it, so adding a type doesn't require touching the addon UI.
const WORKBENCH_GRID_SIZE: Dictionary = {
	WorkbenchType.CRAFTING_BENCH: Vector2i(3, 3),
}

## Side length of a crafting bench's shaped grid.
const SHAPE_SIZE: int = 3

@export var workbench_type: WorkbenchType = WorkbenchType.CRAFTING_BENCH
## Exactly SHAPE_SIZE * SHAPE_SIZE entries, row-major (index = row *
## SHAPE_SIZE + column), null for an empty cell. Each occupied cell always
## needs exactly 1 of that item, per slot.
@export var shape: Array[Item] = []
@export var output_items: Array[Item] = []
@export var output_quantities: Array[int] = []
@export var skill_type: Skill.Type
@export var experience_gain: int
@export var level_requirement: int = 1

## Whether a crafting bench's 3x3 grid (row-major, at least SHAPE_SIZE^2
## entries; null = empty slot) matches this recipe's shape. The shape is
## matched at any translated position within the grid, and mirrored
## horizontally, but every grid cell outside the matched footprint must be
## empty -- extra items anywhere else in the grid block the match.
func matches_shape(grid_items: Array) -> bool:
	if shape.size() != SHAPE_SIZE * SHAPE_SIZE or grid_items.size() < SHAPE_SIZE * SHAPE_SIZE:
		return false
	var bounds := _shape_bounds()
	if bounds.is_empty():
		return false
	var min_row: int = bounds[0]
	var min_col: int = bounds[2]
	var pattern_rows: int = bounds[1] - bounds[0] + 1
	var pattern_cols: int = bounds[3] - bounds[2] + 1

	for mirrored in [false, true]:
		for row_offset in SHAPE_SIZE - pattern_rows + 1:
			for col_offset in SHAPE_SIZE - pattern_cols + 1:
				if _shape_matches_at(grid_items, min_row, min_col, pattern_rows, pattern_cols, row_offset, col_offset, mirrored):
					return true
	return false

## Returns [min_row, max_row, min_col, max_col] bounding the non-null cells of
## shape, or an empty array if shape has no items at all (never matches).
func _shape_bounds() -> Array:
	var min_row := SHAPE_SIZE
	var max_row := -1
	var min_col := SHAPE_SIZE
	var max_col := -1
	for row in SHAPE_SIZE:
		for col in SHAPE_SIZE:
			if shape[row * SHAPE_SIZE + col] != null:
				min_row = mini(min_row, row)
				max_row = maxi(max_row, row)
				min_col = mini(min_col, col)
				max_col = maxi(max_col, col)
	if max_row < 0:
		return []
	return [min_row, max_row, min_col, max_col]

func _shape_matches_at(grid_items: Array, min_row: int, min_col: int, pattern_rows: int, pattern_cols: int, row_offset: int, col_offset: int, mirrored: bool) -> bool:
	for row in SHAPE_SIZE:
		for col in SHAPE_SIZE:
			var pattern_row := row - row_offset
			var pattern_col := col - col_offset
			var in_pattern := pattern_row >= 0 and pattern_row < pattern_rows and pattern_col >= 0 and pattern_col < pattern_cols
			var expected: Item = null
			if in_pattern:
				var source_col := pattern_cols - 1 - pattern_col if mirrored else pattern_col
				expected = shape[(min_row + pattern_row) * SHAPE_SIZE + (min_col + source_col)]
			if grid_items[row * SHAPE_SIZE + col] != expected:
				return false
	return true
