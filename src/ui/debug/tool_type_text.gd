extends Control

@onready var tool_type_text: Label = $VBoxContainer/ToolTypeText
@onready var durability_text: Label = $VBoxContainer/DurabilityText
@onready var mining_experience_text: Label = $VBoxContainer/MiningExperienceText
@onready var woodcutting_experience_text: Label = $VBoxContainer/WoodcuttingExperienceText


func _ready() -> void:
	EventBus.tool_changed.connect(_on_player_tool_changed)
	EventBus.tool_durability_changed.connect(_on_tool_durability_changed)
	EventBus.skill_experience_changed.connect(_on_skill_experience_changed)

func _process(_delta: float) -> void:
	visible = DebugSettings.show_tool_debug

func _on_player_tool_changed(tool_type: Item.ToolTypes)-> void:
	var s = Item.TOOL_TYPE_NAMES.get(tool_type)
	tool_type_text.text = str("Tool Type: ", s)

func _on_tool_durability_changed(current: int, max_durability: int) -> void:
	durability_text.text = str("Durability: ", current, " / ", max_durability) if max_durability > 0 else ""

func _on_skill_experience_changed(skill_type: Skill.Type, experience: int, level: int) -> void:
	match skill_type:
		Skill.Type.Mining:
			mining_experience_text.text = str("Mining XP: ", experience, " (Lvl ", level, ")")
		Skill.Type.Woodcutting:
			woodcutting_experience_text.text = str("Woodcutting XP: ", experience, " (Lvl ", level, ")")
