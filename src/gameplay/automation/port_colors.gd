class_name PortColors
extends RefCounted
## Shared color list for numbered input ports (see WrenchSlotIndicator and
## InventoryPanel/InventorySlot) -- lets a player tell apart a multi-input
## machine's ports (e.g. Blast Furnace's two ore inputs) by matching color
## between the world-space arrow over a port and that port's slot in the
## inventory panel. Indexed by the port's linked Inventory slot index (see
## ItemSlotComponent.linked_slot_index), wrapping past the end for any object
## with more than 8 colored inputs. Placeholder hues -- easy to retune since
## these are plain Color constants, not baked pixel art.

const COLORS: Array[Color] = [
	Color("f2994a"), # orange
	Color("f2c94c"), # yellow
	Color("a8e063"), # lime
	Color("27ae60"), # green
	Color("17c9c0"), # teal
	Color("2d9cdb"), # blue
	Color("9b51e0"), # purple
	Color("eb5da8"), # pink
]
const COLORS_DARK: Array[Color] = [
	Color("c9761f"),
	Color("c9a100"),
	Color("7fb238"),
	Color("1e8449"),
	Color("109089"),
	Color("1d6fa3"),
	Color("7133b0"),
	Color("c13a82"),
]
