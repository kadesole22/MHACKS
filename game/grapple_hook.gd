extends Area2D


signal hooked(point)
signal missed
signal expired


const SPEED = 1200.0
const MAX_DISTANCE = 450.0
const GRAPPLE_DURATION = 2.0

var direction = Vector2.ZERO
var start_position = Vector2.ZERO
var active = false

var is_hooked = false
var grapple_time_remaining = 0.0


func launch(from_position, launch_direction):
	global_position = from_position
	start_position = from_position
	direction = launch_direction.normalized()
	active = true


func _physics_process(delta):
	if not active:
		return


	# If we're already hooked, count down.
	if is_hooked:
		grapple_time_remaining -= delta

		if grapple_time_remaining <= 0.0:
			active = false
			expired.emit()
			queue_free()

		return


	# Move the grapple forward.
	global_position += direction * SPEED * delta
	

	# Check everything our circular hitbox is currently touching.
	for body in get_overlapping_bodies():
		if body.is_in_group("one_way_platforms"):
			
			# Grapple is now attached.
			is_hooked = true
			grapple_time_remaining = GRAPPLE_DURATION

			# Tell the player where the grapple connected.
			hooked.emit(global_position)

			return


	# If we travelled 450 pixels without hitting terrain, disappear.
	if global_position.distance_to(start_position) >= MAX_DISTANCE:
		active = false
		missed.emit()
		queue_free()
