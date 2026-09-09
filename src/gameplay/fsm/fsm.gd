extends Node
class_name FSM

signal on_state_transitioned(state_name: String)

@export var initial_state: NodePath

var curr_state: State

func _ready() -> void:
	await owner.ready
	# Give every child state access to this controller before the first transition.
	for state: State in get_children():
		state.fsm = self
	
	curr_state = get_node(initial_state)
	curr_state.enter_state()
	
	
func transition_to(state_name: String) -> void:
	# Invalid state names are ignored so input cannot leave the FSM without a state.
	if not has_node(state_name):
		#print("No State with name: %s", state_name)
		return
	
	curr_state.exit_state()
	curr_state = get_node(state_name)
	curr_state.enter_state()
	on_state_transitioned.emit(curr_state.name)


func _process(delta: float) -> void:
	# Forward the engine update loops to whichever state currently owns the player.
	if curr_state:
		#print("Current State: ",  curr_state)
		curr_state.process_state(delta)


func _physics_process(delta: float) -> void:
	if curr_state:
		curr_state.process_physics_state(delta)
