extends Node
class_name SkillsManager
## Owns the player's Skill instances and grants experience to them. Listens for
## EventBus.object_depleted, which every depleted ExperienceComponent-bearing
## object fires with the skill and amount to grant.
##
## The skills themselves (their type, name, and icon) are configured entirely
## from the editor as Skill child nodes of this node, rather than hardcoded here.

## Which skill's level gates each tool type. Tool types with no entry (Sword,
## Shovel, Hoe for now) have no level requirement.
const TOOL_SKILL_MAP: Dictionary = {
	Item.ToolTypes.Pickaxe: Skill.Type.Mining,
	Item.ToolTypes.Axe: Skill.Type.Woodcutting,
}

var _skills: Dictionary = {}

func _ready() -> void:
	for child in get_children():
		if child is Skill:
			_register_skill(child)
	EventBus.object_depleted.connect(_on_object_depleted)

func _register_skill(skill: Skill) -> void:
	_skills[skill.skill_type] = skill
	skill.experience_changed.connect(_on_skill_experience_changed.bind(skill.skill_type))

func get_skill(skill_type: Skill.Type) -> Skill:
	return _skills.get(skill_type)

## Returns every registered skill, in registration order.
func get_skills() -> Array[Skill]:
	var result: Array[Skill] = []
	for skill in _skills.values():
		result.append(skill)
	return result

func grant_experience(skill_type: Skill.Type, amount: int) -> void:
	var skill: Skill = _skills.get(skill_type)
	if skill:
		skill.add_experience(amount)

## Checks whether the player's level in the tool's associated skill meets the
## tool's tier requirement. Tools with no associated skill (see TOOL_SKILL_MAP)
## always pass.
func check_tool_requirement(item: Item) -> bool:
	if item == null or item.tool_tier == null:
		return true
	if not TOOL_SKILL_MAP.has(item.tool_type):
		return true

	var skill_type: Skill.Type = TOOL_SKILL_MAP[item.tool_type]
	var skill: Skill = get_skill(skill_type)
	var required_level: int = item.tool_tier.required_level
	return skill != null and skill.level >= required_level

func _on_object_depleted(skill_type: Skill.Type, experience_amount: int) -> void:
	grant_experience(skill_type, experience_amount)

func _on_skill_experience_changed(experience: int, level: int, skill_type: Skill.Type) -> void:
	EventBus.skill_experience_changed.emit(skill_type, experience, level)
