extends Node2D
## A short, mouse-aimed melee swing. The aim stays fixed for this swing.

const REACH: float = 48.0
const ANIMATION_BASE_REACH: float = 96.0
const HALF_ANGLE: float = PI * 0.30
const DURATION: float = 0.22
const HIT_START: float = 0.03
const HIT_END: float = 0.16
const KNOCKBACK_SPEED: float = 900.0
const UPWARD_BOOST: float = 180.0
const PLAYER_MASK: int = 1 | (1 << 7)

var _attacker: CollisionObject2D
var _elapsed: float = 0.0
var _hit_targets: Dictionary = {}
var _shape := ConvexPolygonShape2D.new()


func initialize(attacker: CollisionObject2D, direction: Vector2) -> void:
	_attacker = attacker
	rotation = direction.angle() - attacker.global_rotation
	z_index = 2
	var points := PackedVector2Array([Vector2.ZERO])
	for i in range(13):
		var angle := lerpf(-HALF_ANGLE, HALF_ANGLE, float(i) / 12.0)
		points.append(Vector2.from_angle(angle) * REACH)
	_shape.points = points


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_attacker) or _attacker.is_queued_for_deletion():
		queue_free()
		return
	var previous_elapsed := _elapsed
	_elapsed += delta
	# Check any tick overlapping the active window, even during a frame hitch.
	if _elapsed >= HIT_START and previous_elapsed < HIT_END:
		_check_hits()
	if _elapsed >= DURATION:
		queue_free()
		return
	queue_redraw()


func _check_hits() -> void:
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _shape
	query.transform = global_transform
	query.collision_mask = PLAYER_MASK
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [_attacker.get_rid()]
	for hit in get_world_2d().direct_space_state.intersect_shape(query, 32):
		var target := hit["collider"] as Node2D
		if target == null or target == _attacker or target.is_queued_for_deletion():
			continue
		if not target.is_in_group("grapple_players"):
			continue
		var target_id := target.get_instance_id()
		if _hit_targets.has(target_id):
			continue
		_hit_targets[target_id] = true
		var away := target.global_position - _attacker.global_position
		if away.length_squared() < 1.0:
			away = Vector2.RIGHT.rotated(global_rotation)
		var impulse := away.normalized() * KNOCKBACK_SPEED + Vector2.UP * UPWARD_BOOST
		if target.has_method("apply_knockback"):
			target.call("apply_knockback", impulse)
		elif target.has_method("apply_grapple_impulse"):
			target.call("apply_grapple_impulse", impulse)
		else:
			# Remote players already receive combat impulses over this bridge.
			Stdb.send_grapple_hit(str(target.get_meta("player_id", "")), impulse)


func _draw() -> void:
	# Keep the original visual size independent of the shorter hit reach.
	var progress := clampf(_elapsed / DURATION, 0.0, 1.0)
	var sweep := 1.0 - pow(1.0 - progress, 2.0)
	var leading_angle := lerpf(-HALF_ANGLE, HALF_ANGLE, sweep)
	var trailing_angle := maxf(-HALF_ANGLE, leading_angle - 1.1)
	var fade := 1.0 - smoothstep(0.55, 1.0, progress)
	var crescent := PackedVector2Array()
	for i in range(19):
		var angle := lerpf(trailing_angle, leading_angle, float(i) / 18.0)
		crescent.append(Vector2.from_angle(angle) * (ANIMATION_BASE_REACH - 2.0))
	for i in range(18, -1, -1):
		var t := float(i) / 18.0
		var angle := lerpf(trailing_angle, leading_angle, t)
		var thickness := 3.0 + sin(t * PI) * 15.0
		crescent.append(Vector2.from_angle(angle) * (ANIMATION_BASE_REACH - 2.0 - thickness))
	if leading_angle > trailing_angle:
		draw_colored_polygon(crescent, Color(0.72, 0.94, 1.0, fade))
		draw_arc(Vector2.ZERO, ANIMATION_BASE_REACH - 2.0, trailing_angle, leading_angle,
			24, Color(1.0, 1.0, 1.0, fade), 2.5, true)
	draw_line(Vector2.from_angle(leading_angle) * 30.0,
		Vector2.from_angle(leading_angle) * ANIMATION_BASE_REACH,
		Color(1.0, 1.0, 1.0, fade), 3.0, true)
