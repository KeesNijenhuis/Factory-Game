class_name Skill
extends Node
## Data + behavior for a single player skill (e.g. Mining, Woodcutting).
## Added as a child node of SkillsManager and configured entirely from the
## editor (skill_type/skill_name/icon); add_experience() grants experience
## and handles leveling.

enum Type {
	None,
	Mining,
	Woodcutting,
	Crafting,
	Smithing
}

## Flat experience cost of each level for now; may become a per-level curve later.
const EXPERIENCE_PER_LEVEL: int = 10

@export var skill_type: Skill.Type = Skill.Type.None
@export var skill_name: String = "Skill"
@export var icon: Texture2D

var experience: int = 0
var level: int = 1

signal experience_changed(experience: int, level: int)
signal leveled_up(level: int)

## Total cumulative experience required to reach the next level.
func get_experience_for_next_level() -> int:
	return level * EXPERIENCE_PER_LEVEL

func add_experience(amount: int) -> void:
	if amount <= 0:
		return
	experience += amount
	while experience >= level * EXPERIENCE_PER_LEVEL:
		level += 1
		leveled_up.emit(level)
	experience_changed.emit(experience, level)
