extends Area3D

## A speed ramp / launch pad that flings the player into the air when they step on it.
## Place in the scene and configure the launch direction and force.

@export_group("Launch Settings")
@export var launch_speed: float = 25.0 ## Upward launch velocity.
@export var forward_boost: float = 15.0 ## Additional forward velocity (along ramp's -Z direction).
@export var override_velocity: bool = true ## If true, replaces the player's vertical velocity instead of adding to it.

@export_group("Cooldown")
@export var cooldown: float = 0.5 ## Seconds before the ramp can launch the same player again.

var _on_cooldown: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _on_cooldown:
		return

	# Check if the body is the player (GoldGdt_Body is a CharacterBody3D)
	if body is CharacterBody3D:
		print("Speed ramp launched player!")

		# Apply upward launch
		if override_velocity:
			body.velocity.y = launch_speed
		else:
			body.velocity.y += launch_speed

		# Apply forward boost along the ramp's facing direction (-Z is forward)
		var forward_dir = - global_transform.basis.z.normalized()
		# Only apply horizontal component of the forward boost
		forward_dir.y = 0
		forward_dir = forward_dir.normalized()
		body.velocity.x += forward_dir.x * forward_boost
		body.velocity.z += forward_dir.z * forward_boost

		# Start cooldown
		_on_cooldown = true
		await get_tree().create_timer(cooldown).timeout
		_on_cooldown = false
