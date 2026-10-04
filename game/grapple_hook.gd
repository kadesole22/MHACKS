extends Area2D


signal hooked(point)
signal player_hooked(target)
signal missed
signal expired


const SPEED = 1200.0
const MAX_DISTANCE = 450.0
const GRAPPLE_DURATION = 2.0
const GRAPPLE_PLAYER_LAYER = 1 << 7 # Physics layer 8, shared with netplay.gd.

var direction = Vector2.ZERO
var start_position = Vector2.ZERO
var active = false

var is_hooked = false
var grapple_time_remaining = 0.0
var _shooter: CollisionObject2D = null
var _player_target: Node2D = null
var _attached_to_player = false


func launch(from_position, launch_direction, shooter: CollisionObject2D = null):
	global_position = from_position
	start_position = from_position
	direction = launch_direction.normalized()
	_shooter = shooter
	active = true


func _physics_process(delta):
	if not active:
		return

	# Follow the player while the grapple is attached.
	if is_hooked:
		if _attached_to_player:
			if not is_instance_valid(_player_target) or _player_target.is_queued_for_deletion():
				active = false
				expired.emit()
				queue_free()
				return
			global_position = _player_target.global_position

		grapple_time_remaining -= delta
		if grapple_time_remaining <= 0.0:
			active = false
			expired.emit()
			queue_free()
		return

	# Sweep the distance travelled this tick so fast hooks do not skip players.
	var remaining: float = maxf(0.0, MAX_DISTANCE - global_position.distance_to(start_position))
	var next_position: Vector2 = global_position + direction * minf(SPEED * delta, remaining)
	var query := PhysicsRayQueryParameters2D.create(
		global_position, next_position, collision_mask | GRAPPLE_PLAYER_LAYER
	)
	query.collide_with_areas = true
	query.hit_from_inside = true
	var excluded: Array[RID] = [get_rid()]
	if is_instance_valid(_shooter):
		excluded.append(_shooter.get_rid())
	query.exclude = excluded
	var hit := get_world_2d().direct_space_state.intersect_ray(query)

	if not hit.is_empty():
		var target: Node2D = hit["collider"]
		global_position = hit["position"]
		if target.is_in_group("grapple_players"):
			is_hooked = true
			_attached_to_player = true
			_player_target = target
			grapple_time_remaining = GRAPPLE_DURATION
			global_position = target.global_position
			player_hooked.emit(target)
		elif target.is_in_group("one_way_platforms"):
			is_hooked = true
			grapple_time_remaining = GRAPPLE_DURATION
			hooked.emit(global_position)
		else:
			active = false
			missed.emit()
			queue_free()
		return

	global_position = next_position
	if global_position.distance_to(start_position) >= MAX_DISTANCE - 0.1:
		active = false
		missed.emit()
		queue_free()
