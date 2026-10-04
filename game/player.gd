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
const KNOCKBACK_DURATION = 0.65

# Load our GrappleHook scene.
const GRAPPLE_HOOK = preload("res://grapple_hook.tscn")
const SLASH_ATTACK = preload("res://slash_attack.gd")
const SLASH_COOLDOWN = 0.35
const RESPAWN_DELAY = 0.75


var current_hook = null
var is_grappling = false
var grapple_point = Vector2.ZERO
var grapple_target: Node2D = null
var grappling_player = false
var _knockback_remaining = 0.0
var _slash_cooldown_remaining = 0.0
var is_dead: bool = false
var _spawn_position: Vector2
var _spawn_collision_layer: int
var _spawn_collision_mask: int
var _respawn_remaining: float = 0.0


func _ready() -> void:
	add_to_group("grapple_players")
	_spawn_position = global_position
	_spawn_collision_layer = collision_layer
	_spawn_collision_mask = collision_mask


func _physics_process(delta):
	var stage = get_tree().current_scene
	if is_dead:
		if stage != null and stage.get("respawn_enabled") == true:
			_respawn_remaining = maxf(0.0, _respawn_remaining - delta)
			if _respawn_remaining <= 0.0:
				respawn()
		return
	if stage != null and stage.get("void_kill_y") != null:
		var kill_y: float = stage.get_void_kill_y() if stage.has_method("get_void_kill_y") else float(stage.get("void_kill_y"))
		if global_position.y > kill_y:
			die()
			return

	_slash_cooldown_remaining = maxf(0.0, _slash_cooldown_remaining - delta)
	# Keep transferred momentum instead of overwriting it with movement input.
	if _knockback_remaining > 0.0:
		_knockback_remaining = maxf(0.0, _knockback_remaining - delta)
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		move_and_slide()
		return

	# Fire grapple
	if Input.is_action_just_pressed("grapple") and get_viewport().gui_get_hovered_control() == null:
		fire_grapple()
	if Input.is_action_just_pressed("slash") and get_viewport().gui_get_hovered_control() == null:
		fire_slash()

	if is_grappling and grappling_player:
		if not is_instance_valid(grapple_target) or grapple_target.is_queued_for_deletion():
			_end_grapple()
		else:
			grapple_point = grapple_target.global_position

	# ------------------------------------------------
	# If we're currently attached to a grapple point...
	# ------------------------------------------------
	if is_grappling:
		var to_grapple = grapple_point - global_position
		var distance = to_grapple.length()

		# We've reached the grapple point.
		if distance <= GRAPPLE_REACH_DISTANCE:
			_complete_grapple(velocity)

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


	var position_before_move := global_position
	var velocity_before_move := velocity
	move_and_slide()
	# Check the path actually travelled, including a fast pass through the target.
	if is_grappling and grappling_player and is_instance_valid(grapple_target):
		var closest := Geometry2D.get_closest_point_to_segment(
			grapple_target.global_position, position_before_move, global_position
		)
		if closest.distance_to(grapple_target.global_position) <= GRAPPLE_REACH_DISTANCE:
			_complete_grapple(velocity_before_move)


func fire_slash() -> void:
	if is_dead or _slash_cooldown_remaining > 0.0 or _knockback_remaining > 0.0:
		return
	var aim := get_global_mouse_position() - global_position
	if aim.length_squared() < 1.0:
		return
	var slash = SLASH_ATTACK.new()
	slash.initialize(self, aim.normalized())
	add_child(slash)
	_slash_cooldown_remaining = SLASH_COOLDOWN


func fire_grapple():
	if is_dead or _knockback_remaining > 0.0:
		return
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
	hook.player_hooked.connect(_on_grapple_player_hooked)
	hook.missed.connect(_on_grapple_missed)
	hook.expired.connect(_on_grapple_expired)

	current_hook = hook

	# Fire it.
	hook.launch(global_position, grapple_direction, self)


func _on_grapple_hooked(point):
	grapple_target = null
	grappling_player = false
	grapple_point = point
	is_grappling = true


func _on_grapple_player_hooked(target: Node2D):
	grapple_target = target
	grappling_player = true
	grapple_point = target.global_position
	is_grappling = true


func _on_grapple_missed():
	_end_grapple()


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
	_end_grapple()


func _complete_grapple(impact_velocity: Vector2) -> void:
	if grappling_player and is_instance_valid(grapple_target):
		if grapple_target.has_method("apply_grapple_impulse"):
			# Allows a local practice target to use the same mechanic.
			grapple_target.call("apply_grapple_impulse", impact_velocity)
		else:
			Stdb.send_grapple_hit(str(grapple_target.get_meta("player_id", "")), impact_velocity)
	velocity = Vector2.ZERO
	_end_grapple()


func _end_grapple() -> void:
	is_grappling = false
	grappling_player = false
	grapple_target = null
	if is_instance_valid(current_hook):
		current_hook.active = false
		current_hook.queue_free()
	current_hook = null


func apply_grapple_impulse(impulse: Vector2) -> void:
	apply_knockback(impulse)


func apply_knockback(impulse: Vector2) -> void:
	if is_dead:
		return
	_end_grapple()
	velocity += impulse
	_knockback_remaining = KNOCKBACK_DURATION


func die() -> void:
	if is_dead:
		return
	is_dead = true
	_respawn_remaining = RESPAWN_DELAY
	_end_grapple()
	velocity = Vector2.ZERO
	_knockback_remaining = 0.0
	_slash_cooldown_remaining = 0.0
	for child in get_children():
		if child.get_script() == SLASH_ATTACK:
			child.set_physics_process(false)
			child.queue_free()
	for body in get_collision_exceptions():
		if is_instance_valid(body):
			remove_collision_exception_with(body)
	remove_from_group("grapple_players")
	collision_layer = 0
	collision_mask = 0
	hide()


func respawn() -> void:
	if not is_dead:
		return
	global_position = _spawn_position
	velocity = Vector2.ZERO
	jumps_remaining = MAX_JUMPS
	_knockback_remaining = 0.0
	_slash_cooldown_remaining = 0.0
	_respawn_remaining = 0.0
	collision_layer = _spawn_collision_layer
	collision_mask = _spawn_collision_mask
	add_to_group("grapple_players")
	is_dead = false
	show()
