extends Area2D


signal hooked(point)
signal player_hooked(target)
signal missed
signal expired


const SPEED = 1200.0
const MAX_DISTANCE = 450.0
const GRAPPLE_DURATION = 2.0
const GRAPPLE_PLAYER_LAYER = 1 << 7 # Physics layer 8, shared with netplay.gd.

var direction: Vector2 = Vector2.ZERO
var start_position: Vector2 = Vector2.ZERO
var active = false

var is_hooked = false
var grapple_time_remaining = 0.0
var _shooter: CollisionObject2D = null
var _player_target: Node2D = null
var _attached_to_player = false
var _terrain_target: Node2D = null
var _terrain_anchor := Vector2.ZERO
var _visual_time: float = 0.0
var _impact_time: float = 0.0


func _ready() -> void:
	z_index = 5


func _process(delta: float) -> void:
	_visual_time += delta
	_impact_time = maxf(0.0, _impact_time - delta)
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	var source := start_position
	if is_instance_valid(_shooter):
		source = _shooter.global_position
	var rope_start := to_local(source)
	var rope_end := Vector2.ZERO
	var cable := rope_end - rope_start
	var cable_length := cable.length()
	var tangent := cable.normalized() if cable_length > 0.001 else direction
	var normal := tangent.orthogonal()
	var rope := PackedVector2Array()
	for i in range(25):
		var progress := float(i) / 24.0
		var wave := sin(progress * TAU * 2.0 - _visual_time * 24.0)
		var amplitude := 1.2 if is_hooked else 3.5
		rope.append(rope_start.lerp(rope_end, progress) + normal * wave * sin(progress * PI) * amplitude)
	draw_polyline(rope, Color(0.04, 0.10, 0.16, 0.85), 7.0, true)
	draw_polyline(rope, Color(0.1, 0.85, 1.0, 0.28), 5.0, true)
	draw_polyline(rope, Color(0.35, 0.95, 1.0), 2.5, true)
	# Small moving highlights make the cable read even while latched.
	if cable_length > 8.0:
		for i in range(4):
			var progress := fposmod(_visual_time * 1.8 + float(i) / 4.0, 1.0)
			var pulse := rope_start.lerp(rope_end, progress)
			draw_line(pulse - tangent * 5.0, pulse + tangent * 5.0, Color(0.9, 1.0, 1.0, 0.8), 3.0, true)
		draw_circle(rope_start, 4.0, Color(0.4, 0.95, 1.0))
	if _impact_time > 0.0:
		var progress := 1.0 - _impact_time / 0.25
		draw_arc(Vector2.ZERO, 8.0 + progress * 24.0, 0.0, TAU, 32, Color(1.0, 0.85, 0.25, 1.0 - progress), 3.0, true)
	var aim := direction
	if is_hooked and cable_length > 0.001:
		aim = tangent
	draw_set_transform(Vector2.ZERO, aim.angle())
	# The jaws flutter open in flight and close firmly on impact.
	var jaw_width := 5.0 if is_hooked else 10.0 + sin(_visual_time * 32.0) * 2.0
	var upper := PackedVector2Array([Vector2(-12, 0), Vector2(-5, -jaw_width), Vector2(8, -jaw_width), Vector2(13, -3)])
	var lower := PackedVector2Array([Vector2(-12, 0), Vector2(-5, jaw_width), Vector2(8, jaw_width), Vector2(13, 3)])
	draw_polyline(upper, Color(0.1, 0.08, 0.02), 6.0, true)
	draw_polyline(lower, Color(0.1, 0.08, 0.02), 6.0, true)
	draw_polyline(upper, Color(1.0, 0.72, 0.2), 3.5, true)
	draw_polyline(lower, Color(1.0, 0.72, 0.2), 3.5, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-10,-4), Vector2(8,-4), Vector2(17,0), Vector2(8,4), Vector2(-10,4)]), Color(1.0, 0.9, 0.5))
	draw_circle(Vector2(-8, 0), 3.0, Color(0.3, 0.9, 1.0))
	if not is_hooked:
		var trail_length := 24.0 + sin(_visual_time * 40.0) * 5.0
		draw_line(Vector2(-17, -4), Vector2(-trail_length - 10.0, -4), Color(0.55, 0.95, 1.0, 0.6), 2.0, true)
		draw_line(Vector2(-20, 4), Vector2(-trail_length, 4), Color(0.55, 0.95, 1.0, 0.6), 2.0, true)
	draw_set_transform(Vector2.ZERO)



func launch(from_position, launch_direction, shooter: CollisionObject2D = null):
	global_position = from_position
	start_position = from_position
	direction = launch_direction.normalized()
	_shooter = shooter
	active = true
	_visual_time = 0.0
	queue_redraw()


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

		elif is_instance_valid(_terrain_target):
			global_position = _terrain_target.to_global(_terrain_anchor)

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
		_impact_time = 0.25
		if target.is_in_group("grapple_players"):
			is_hooked = true
			_attached_to_player = true
			_player_target = target
			grapple_time_remaining = GRAPPLE_DURATION
			global_position = target.global_position
			player_hooked.emit(target)
		elif target.is_in_group("one_way_platforms"):
			_terrain_target = target
			_terrain_anchor = target.to_local(global_position)
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
