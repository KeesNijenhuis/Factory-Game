class_name DurabilityComponent
extends Node2D

@export var durability: int = 3
@export var accumulated_damage: int = 0

signal max_durability_reached

func damage(dmg: int):
	# Accumulated damage is capped so the depletion signal fires at the threshold.
	accumulated_damage = clamp(accumulated_damage + dmg, 0, durability)

	if accumulated_damage >= durability:
		max_durability_reached.emit()

func reset_damage() -> void:
	accumulated_damage = 0
