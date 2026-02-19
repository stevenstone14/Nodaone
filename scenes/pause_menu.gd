extends CanvasLayer

## The pause menu overlay. This node's process_mode is set to ALWAYS
## so it continues to receive input even when the scene tree is paused.

@onready var panel: PanelContainer = $PanelContainer
@onready var resume_button: Button = $PanelContainer/MarginContainer/VBoxContainer/ResumeButton
@onready var quit_button: Button = $PanelContainer/MarginContainer/VBoxContainer/QuitButton

var is_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel.visible = false
	resume_button.pressed.connect(_on_resume_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	is_paused = !is_paused
	panel.visible = is_paused
	get_tree().paused = is_paused

	# Show / hide the mouse cursor so the player can click buttons
	if is_paused:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_resume_pressed() -> void:
	_toggle_pause()


func _on_quit_pressed() -> void:
	# In multiplayer, go back to lobby instead of quitting
	if NetworkManager.is_multiplayer_active():
		get_tree().paused = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		NetworkManager.leave_game()
		get_tree().change_scene_to_file("res://scenes/lobby.tscn")
	else:
		get_tree().quit()
