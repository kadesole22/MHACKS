extends CharacterBody2D


const SPEED = 300.0
const JUMP_VELOCITY = -700.0
const GRAVITY = 1100.0

# Jump settings
const MAX_JUMPS = 2
var jumps_remaining = MAX_JUMPS

# Grapple settings
const GRAPPLE_ACCELERATION = 2500.0
const GRAPPLE_MAX_SPEED = 900.0
const GRAPPLE_REACH_DISTANCE = 45.0

# Load our GrappleHook scene.
const GRAPPLE_HOOK = preload("res://grapple_hook.tscn")


var current_hook = null
var is_grappling = false
var grapple_point = Vector2.ZERO


func _physics_process(delta):
	# Fire grapple
	if Input.is_action_just_pressed("grapple"):
		fire_grapple()

	# ------------------------------------------------
	# If we're currently attached to a grapple point...
	# ------------------------------------------------
	if is_grappling:
		var to_grapple = grapple_point - global_position
		var distance = to_grapple.length()

		# We've reached the grapple point.
		if distance <= GRAPPLE_REACH_DISTANCE:
			is_grappling = false
			velocity = Vector2.ZERO

		else:
			# Accelerate toward the grapple point.
			var grapple_direction = to_grapple.normalized()

			velocity += grapple_direction * GRAPPLE_ACCELERATION * delta

			# Prevent the player from becoming infinitely fast.
			velocity = velocity.limit_length(GRAPPLE_MAX_SPEED)


	# ------------------------------------------------
	# Normal movement when we're NOT grappling
	# ------------------------------------------------
	else:
		# Gravity
		if not is_on_floor():
			velocity.y += GRAVITY * delta

		# Reset jumps when standing on a surface
		if is_on_floor():
			jumps_remaining = MAX_JUMPS

		# Jump / double jump
		if Input.is_action_just_pressed("jump") and jumps_remaining > 0:
			velocity.y = JUMP_VELOCITY
			jumps_remaining -= 1

		# Left/right movement
		var direction = Input.get_axis("move_left", "move_right")

		if direction != 0:
			velocity.x = direction * SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)

		# Drop through platform
		if Input.is_action_just_pressed("drop_down") and is_on_floor():
			var platform = get_platform_below()

			if platform != null and platform.is_in_group("one_way_platforms"):
				drop_through(platform)


	move_and_slide()


func fire_grapple():
	# Don't fire another grapple while one is already flying
	# or while we're already being pulled.
	if current_hook != null or is_grappling:
		return

	# Aim from the player toward the mouse cursor.
	var mouse_position = get_global_mouse_position()
	var grapple_direction = mouse_position - global_position

	# Avoid problems if the mouse is directly on top of the player.
	if grapple_direction.length() < 1.0:
		return

	# Create the grapple projectile.
	var hook = GRAPPLE_HOOK.instantiate()

	# Put it in the main level instead of inside the player.
	get_tree().current_scene.add_child(hook)

	# Listen for whether it hits terrain or misses.
	hook.hooked.connect(_on_grapple_hooked)
	hook.missed.connect(_on_grapple_missed)
	hook.expired.connect(_on_grapple_expired)

	current_hook = hook

	# Fire it.
	hook.launch(global_position, grapple_direction)


func _on_grapple_hooked(point):
	current_hook = null

	grapple_point = point
	is_grappling = true


func _on_grapple_missed():
	current_hook = null


func get_platform_below():
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)

		if collision.get_normal().y < -0.7:
			return collision.get_collider()

	return null


func drop_through(platform):
	add_collision_exception_with(platform)

	velocity.y = 100.0

	await get_tree().create_timer(0.2).timeout

	if is_instance_valid(platform):
		remove_collision_exception_with(platform)


func _on_grapple_expired():
	current_hook = null
	is_grappling = false
