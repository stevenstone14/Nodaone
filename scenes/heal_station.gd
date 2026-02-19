extends Area3D

## A heal station placed on the map. The player walks into it and holds E
## to channel healing to the base. Each station has a limited pool of
## healing energy that depletes as it's used.

signal heal_pool_changed(current: float, maximum: float)
signal station_depleted

@export_group("Healing")
@export var heal_pool: float = 50.0 ## Total healing this station can provide.
@export var heal_rate: float = 15.0 ## HP per second channeled to the base.

@export_group("Visuals")
@export var active_color: Color = Color(0.1, 0.9, 0.3) ## Color when station has energy.
@export var depleted_color: Color = Color(0.3, 0.3, 0.3) ## Color when empty.
@export var channeling_color: Color = Color(0.3, 1.0, 0.5) ## Color while actively channeling.

var current_pool: float
var is_player_inside: bool = false
var is_channeling: bool = false
var _base_node: Node3D = null
var _mesh: MeshInstance3D = null
var _label: Label3D = null
var _material: StandardMaterial3D = null


func _ready() -> void:
	current_pool = heal_pool

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Cache child nodes
	_mesh = get_node_or_null("MeshInstance3D")
	_label = get_node_or_null("Label3D")

	# Set up the material so we can change colors dynamically
	if _mesh:
		var mat = _mesh.get_active_material(0)
		if mat is StandardMaterial3D:
			# Duplicate so each station instance has its own material
			_material = mat.duplicate()
			_mesh.set_surface_override_material(0, _material)
		else:
			_material = StandardMaterial3D.new()
			_material.albedo_color = active_color
			_material.emission_enabled = true
			_material.emission = active_color * 0.6
			_material.emission_energy_multiplier = 1.5
			_mesh.set_surface_override_material(0, _material)

	_update_visuals()

	# Find the base — defer so scene is loaded
	call_deferred("_find_base")


func _find_base() -> void:
	_base_node = get_tree().current_scene.find_child("Base", true, false)
	if _base_node == null:
		push_warning("HealStation: No 'Base' node found!")


func _process(delta: float) -> void:
	if get_tree().paused:
		return

	var was_channeling = is_channeling

	# Check if player is inside AND holding interact AND station has energy
	if is_player_inside and current_pool > 0.0 and _base_node != null and is_instance_valid(_base_node):
		if Input.is_action_pressed("interact"):
			# Don't heal if base is already full
			if _base_node.current_health < _base_node.max_health:
				is_channeling = true
				_channel_heal(delta)
			else:
				is_channeling = false
		else:
			is_channeling = false
	else:
		is_channeling = false

	# Update visuals if channeling state changed
	if was_channeling != is_channeling:
		_update_visuals()

	# Update the floating label
	_update_label()


func _channel_heal(delta: float) -> void:
	var heal_amount = heal_rate * delta

	# Don't overspend the pool
	heal_amount = min(heal_amount, current_pool)

	# Don't over-heal the base
	if _base_node:
		var headroom = _base_node.max_health - _base_node.current_health
		heal_amount = min(heal_amount, headroom)

	if heal_amount <= 0.0:
		return

	# Apply healing
	current_pool -= heal_amount
	current_pool = max(current_pool, 0.0)

	if _base_node.has_method("heal"):
		_base_node.heal(heal_amount)

	heal_pool_changed.emit(current_pool, heal_pool)

	# Check if depleted
	if current_pool <= 0.0:
		is_channeling = false
		station_depleted.emit()
		print(">> Heal station depleted! <<")
		_update_visuals()


func _on_body_entered(body: Node3D) -> void:
	# Only react to the player (CharacterBody3D)
	if body is CharacterBody3D:
		is_player_inside = true
		_update_visuals()


func _on_body_exited(body: Node3D) -> void:
	if body is CharacterBody3D:
		is_player_inside = false
		is_channeling = false
		_update_visuals()


func _update_visuals() -> void:
	if _material == null:
		return

	if current_pool <= 0.0:
		# Depleted — grey and dim
		_material.albedo_color = depleted_color
		_material.emission_enabled = false
	elif is_channeling:
		# Actively channeling — bright green pulse
		_material.albedo_color = channeling_color
		_material.emission_enabled = true
		_material.emission = channeling_color * 0.8
		_material.emission_energy_multiplier = 3.0
	elif is_player_inside:
		# Player nearby but not channeling — slightly brighter
		_material.albedo_color = active_color
		_material.emission_enabled = true
		_material.emission = active_color * 0.7
		_material.emission_energy_multiplier = 2.0
	else:
		# Idle with energy — gentle glow
		_material.albedo_color = active_color
		_material.emission_enabled = true
		_material.emission = active_color * 0.5
		_material.emission_energy_multiplier = 1.0


func _update_label() -> void:
	if _label == null:
		return

	if current_pool <= 0.0:
		_label.text = "DEPLETED"
	elif is_channeling:
		_label.text = "HEALING... [%d]" % int(current_pool)
	elif is_player_inside:
		_label.text = "Hold [E] to Heal\n[%d / %d]" % [int(current_pool), int(heal_pool)]
	else:
		_label.text = "HEAL [%d]" % int(current_pool)
