extends CharacterBody2D


const SPEED = 300.0
const JUMP_VELOCITY = -700.0
const GRAVITY = 1100.0


func _physics_process(delta):
	# Gravity
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Left/right movement
	var direction = Input.get_axis("move_left", "move_right")

	if direction != 0:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	# Drop down through the platform we're standing on
	if Input.is_action_just_pressed("drop_down") and is_on_floor():
		var platform = get_platform_below()

		if platform != null and platform.is_in_group("one_way_platform"):
			drop_through(platform)

	move_and_slide()


func get_platform_below():
	# Look through the player's current collisions
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)

		# A floor underneath the player has an upward-facing normal.
		if collision.get_normal().y < -0.7:
			return collision.get_collider()

	return null


func drop_through(platform):
	# Temporarily make the player ignore ONLY this platform.
	add_collision_exception_with(platform)

	# Start moving downward.
	velocity.y = 100.0

	# Give the player enough time to pass underneath the platform.
	await get_tree().create_timer(0.2).timeout

	# Turn collision with that platform back on.
	if is_instance_valid(platform):
		remove_collision_exception_with(platform)
