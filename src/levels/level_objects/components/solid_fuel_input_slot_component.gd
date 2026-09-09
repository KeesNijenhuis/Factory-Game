class_name SolidFuelInputSlotComponent
extends ItemInputSlotComponent
## The fuel port on furnace-like machines, as its own distinct type rather
## than a plain ItemInputSlotComponent under a scene-authored name -- this is
## what lets a Solid Fuel Input Upgrade activate only fuel ports (never a
## regular Input Upgrade), and what WrenchSlotIndicator keys off to color it
## white instead of the regular input green (see
## AutomationUtils.find_upgradeable_component and
## WrenchSlotIndicator._color_for). No behavior differs from a plain
## ItemInputSlotComponent: FurnaceInventory.place_item()/add_item() already
## restrict this slot to FUEL-type items regardless of which script is on it.
