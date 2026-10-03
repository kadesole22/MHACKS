extends Area2D


signal hooked(point)
signal missed


const SPEED = 1200.0
const MAX_DISTANCE = 450.0

var direction = Vector2.ZERO
var start_position = Vector2.ZERO
var active = false


func launch(from_position, launch_direction):
	global_position = from_position
	start_position = from_position
	direction = launch_direction.normalized()
	active = true


func _physics_process(delta):
	if not active:
		return

	# Move the grapple forward.
	global_position += direction * SPEED * delta

	# Check everything our circular hitbox is currently touching.
	for body in get_overlapping_bodies():
		if body.is_in_group("one_way_platforms"):
			active = false

			# Tell the player where the grapple connected.
			hooked.emit(global_position)

			queue_free()
			return

	# If we travelled 450 pixels without hitting terrain, disappear.
	if global_position.distance_to(start_position) >= MAX_DISTANCE:
		active = false
		missed.emit()
		queue_free()
