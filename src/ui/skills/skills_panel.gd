extends Control
class_name SkillsPanel
## Displays the player's skills as a vertical list, one SkillEntry row per
## skill registered with SkillsManager. Toggled with the skills_menu action.
## Entries are built lazily the first time the panel is shown, since the
## player (and its SkillsManager) doesn't exist yet when this panel is ready.

const SKILL_ENTRY_SCENE: PackedScene = preload("res://src/ui/skills/skill_entry.tscn")

@onready var container: VBoxContainer = %Container

var _entries: Dictionary = {}
var _populated: bool = false

func _ready() -> void:
	EventBus.skill_experience_changed.connect(_on_skill_experience_changed)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"skills_menu"):
		visible = not visible
		if visible:
			_populate()
		var hud := get_tree().get_first_node_in_group("hud") as HUD
		if hud:
			hud.update_panel_layout()

func is_panel_visible() -> bool:
	return visible

func _populate() -> void:
	if _populated:
		return
	var skills_manager: SkillsManager = _find_skills_manager()
	if skills_manager == null:
		return
	for skill in skills_manager.get_skills():
		var entry: SkillEntry = SKILL_ENTRY_SCENE.instantiate()
		container.add_child(entry)
		entry.setup(skill.skill_name, skill.icon, skill.level, skill.experience, skill.get_experience_for_next_level())
		_entries[skill.skill_type] = entry
	_populated = true

func _find_skills_manager() -> SkillsManager:
	var main_game: MainGame = get_tree().current_scene as MainGame
	if main_game == null or main_game.player == null:
		return null
	return main_game.player.skills_manager

func _on_skill_experience_changed(skill_type: Skill.Type, experience: int, level: int) -> void:
	var entry: SkillEntry = _entries.get(skill_type)
	if entry:
		entry.update_display(level, experience, level * Skill.EXPERIENCE_PER_LEVEL)
