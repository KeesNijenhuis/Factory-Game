extends NinePatchRect
class_name SkillEntry
## A single row in the SkillsPanel's list: an icon plus the skill's name,
## level, and progress toward the next level.

@onready var icon: TextureRect = $Margin/Content/Icon
@onready var name_label: Label = $Margin/Content/Info/NameLabel
@onready var level_xp_label: Label = $Margin/Content/Info/LevelXpLabel

func setup(skill_name: String, skill_icon: Texture2D, level: int, experience: int, experience_for_next_level: int) -> void:
	name_label.text = skill_name
	icon.texture = skill_icon
	update_display(level, experience, experience_for_next_level)

func update_display(level: int, experience: int, experience_for_next_level: int) -> void:
	level_xp_label.text = "LvL %d - %d/%d XP" % [level, experience, experience_for_next_level]
