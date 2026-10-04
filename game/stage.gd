extends Node2D

const WIDTH_PER_PLAYER: float = 200.0
const SHRINK_DELAY: float = 7.0
const JOIN_FLASH_DURATION: float = 0.6
const CAMERA_ZOOM_DURATION: float = 0.35
const CAMERA_GROWTH_FACTOR: float = 0.9
const CAMERA_EDGE_PADDING: float = 100.0
@export_range(1, 16) var test_player_count: int = 1
@export_range(0.0, 22.0, 1.0) var max_tilt_degrees: float = 22.0
@export_range(1.0, 90.0, 1.0) var tilt_speed_degrees: float = 5.0
@export var test_tilt_override: bool = false
@export_range(-1.0, 1.0, 0.05) var test_tilt_balance: float = 0.0
@export var void_kill_y: float = 1100.0
@export var respawn_enabled: bool = true:
	set(value):
		respawn_enabled = value
		if is_instance_valid(_respawn_button):
			_respawn_button.set_pressed_no_signal(value)
			_respawn_button.text = "Respawning: " + str(value)

var _stage_count: int = 1
var _target_count: int = 1
var _shrink_timers: Array[float] = []
var _join_flash_remaining: float = 0.0
var _join_flash_start_count: int = 1
var _warning := Node2D.new()
var _respawn_button: CheckButton
var _death_status: Label
var _camera: Camera2D
var _camera_origin: Vector2
var _camera_base_zoom: float
var _camera_base_view_width: float
var _camera_start_zoom: float
var _camera_target_zoom: float
var _camera_transition_elapsed: float = CAMERA_ZOOM_DURATION
var _platform_base_sizes: Array[Vector2] = []
var _platform_base_points: Array[PackedVector2Array] = []
var _platform_width_ratios: Array[float] = []
var _platform_base_transforms: Array[Transform2D] = []
var _arena_pivot: Vector2
var _arena_tilt: float = 0.0
var _arena_angular_velocity: float = 0.0
var _void_platform_clearance: float = 600.0

@onready var platforms: Array[Node2D] = [
	$BottomPlatform,
	$TopPlatform,
]


func _ready() -> void:
	var initial_bounds := _get_platform_bounds()
	_arena_pivot = initial_bounds.get_center()
	_void_platform_clearance = maxf(100.0, void_kill_y - initial_bounds.end.y)
	for platform in platforms:
		_platform_base_transforms.append(platform.global_transform)
		var collision: CollisionShape2D = platform.get_node("CollisionShape2D")
		collision.shape = collision.shape.duplicate()
		_platform_base_sizes.append((collision.shape as RectangleShape2D).size)
		_platform_base_points.append(platform.get_node("Line2D").points.duplicate())
		_platform_width_ratios.append((collision.shape as RectangleShape2D).size.x / _platform_base_sizes[0].x)

	add_child(_warning)
	_warning.z_index = 1
	_warning.draw.connect(_draw_warning)
	_create_test_controls()
	_create_camera()


func _create_camera() -> void:
	var bounds := _get_platform_bounds()
	_camera = Camera2D.new()
	_camera.name = "ArenaCamera"
	add_child(_camera)
	# Preserve the original framing at one player.
	_camera_origin = Vector2(bounds.get_center().x, get_viewport_rect().size.y / 2.0)
	_camera.global_position = _camera_origin
	_camera_base_zoom = minf(1.0, _get_camera_fit_zoom(bounds))
	_camera_base_view_width = get_viewport_rect().size.x / _camera_base_zoom
	_camera_start_zoom = _camera_base_zoom
	_camera_target_zoom = _camera_base_zoom
	_camera.zoom = Vector2.ONE * _camera_base_zoom
	_camera.make_current()


func _process(delta: float) -> void:
	if not is_instance_valid(_camera):
		return
	var fit_zoom := _get_camera_fit_zoom(_get_platform_bounds())
	var target_zoom := _get_camera_target_zoom(fit_zoom)
	if target_zoom != _camera_target_zoom:
		_camera_start_zoom = _camera.zoom.x
		_camera_target_zoom = target_zoom
		_camera_transition_elapsed = 0.0
	_camera_transition_elapsed = minf(CAMERA_ZOOM_DURATION, _camera_transition_elapsed + delta)
	var progress := _camera_transition_elapsed / CAMERA_ZOOM_DURATION
	var eased_progress := 1.0 - pow(1.0 - progress, 3.0)
	var zoom_value := lerpf(_camera_start_zoom, _camera_target_zoom, eased_progress)
	if _camera_transition_elapsed >= CAMERA_ZOOM_DURATION:
		zoom_value = _camera_target_zoom
	# Keep pending red removals in view, including after large count changes.
	_camera.zoom = Vector2.ONE * minf(zoom_value, fit_zoom)
	_camera.global_position = _camera_origin


func _get_camera_target_zoom(fit_zoom: float) -> float:
	# Tighter world-space framing gives diminishing zoom changes at higher counts.
	# Always calculate from the original frame, never the previous zoom.
	var extra_width := (_target_count - 1) * WIDTH_PER_PLAYER * CAMERA_GROWTH_FACTOR
	var desired_width := _camera_base_view_width + extra_width
	var count_zoom := minf(_camera_base_zoom, get_viewport_rect().size.x / desired_width)
	return minf(count_zoom, fit_zoom)


func _get_platform_bounds() -> Rect2:
	var bounds := Rect2()
	var initialized := false
	for platform in platforms:
		var line: Line2D = platform.get_node("Line2D")
		for point in line.points:
			var world_point := line.to_global(point)
			if not initialized:
				bounds = Rect2(world_point, Vector2.ZERO)
				initialized = true
			else:
				bounds = bounds.expand(world_point)
	return bounds


func _get_camera_fit_zoom(bounds: Rect2) -> float:
	var viewport_size := get_viewport_rect().size
	var horizontal_extent := maxf(
		absf(bounds.position.x - _camera_origin.x),
		absf(bounds.end.x - _camera_origin.x)
	)
	var required_width := (horizontal_extent + CAMERA_EDGE_PADDING) * 2.0
	var vertical_extent := maxf(
		absf(bounds.position.y - _camera_origin.y),
		absf(bounds.end.y - _camera_origin.y)
	)
	var required_height := (vertical_extent + CAMERA_EDGE_PADDING) * 2.0
	return minf(viewport_size.x / required_width, viewport_size.y / required_height)


func get_void_kill_y() -> float:
	# Leave falling room beneath the low end of a large tilted arena.
	return maxf(void_kill_y, _get_platform_bounds().end.y + _void_platform_clearance)


func is_player_alive(player: Dictionary) -> bool:
	if not player.get("online", true) or not player.get("alive", true):
		return false
	if player.get("me", false):
		var local_player = get_node_or_null("Player")
		if local_player != null:
			return not local_player.is_dead and local_player.global_position.y <= get_void_kill_y()
	# The existing network state publishes a dead player's final void position.
	return float(player.get("y", 0.0)) <= get_void_kill_y()


func _get_active_player_count() -> int:
	var count := 0
	if Stdb.is_connected_to_server():
		for player in Stdb.get_players():
			if is_player_alive(player):
				count += 1
	else:
		count = test_player_count if OS.has_feature("editor") else 1
		var local_player = get_node_or_null("Player")
		if local_player != null and local_player.is_dead:
			count -= 1
	# Keep a minimum-size arena even when no players remain alive.
	return maxi(count, 1)


func _create_test_controls() -> void:
	var hud := CanvasLayer.new()
	hud.name = "TestControls"
	add_child(hud)
	_respawn_button = CheckButton.new()
	_respawn_button.name = "RespawnToggle"
	_respawn_button.position = Vector2(16, 16)
	_respawn_button.text = "Respawning: " + str(respawn_enabled)
	_respawn_button.button_pressed = respawn_enabled
	_respawn_button.focus_mode = Control.FOCUS_NONE
	_respawn_button.toggled.connect(_on_respawn_toggled)
	hud.add_child(_respawn_button)
	_death_status = Label.new()
	_death_status.name = "DeathStatus"
	_death_status.position = Vector2(16, 62)
	_death_status.modulate = Color(1.0, 0.65, 0.6)
	hud.add_child(_death_status)


func _on_respawn_toggled(enabled: bool) -> void:
	respawn_enabled = enabled


func _physics_process(delta: float) -> void:
	# Advance existing timers independently.
	for i in range(_shrink_timers.size()):
		_shrink_timers[i] -= delta

	_join_flash_remaining = maxf(0.0, _join_flash_remaining - delta)

	var count := _get_active_player_count()

	if count < _target_count:
		# One new timer for each decrease in player count.
		for _i in range(_target_count - count):
			_shrink_timers.append(SHRINK_DELAY)

	elif count > _target_count:
		_join_flash_start_count = _target_count
		for _i in range(count - _target_count):
			if not _shrink_timers.is_empty():
				# Reuse space awaiting removal; preserve older timers.
				_shrink_timers.pop_back()
			else:
				_resize_stage(_stage_count + 1)

		_join_flash_remaining = JOIN_FLASH_DURATION

	_target_count = count

	# Remove one player's worth of space per expired timer.
	while not _shrink_timers.is_empty() and _shrink_timers[0] <= 0.0:
		_shrink_timers.pop_front()
		_resize_stage(_stage_count - 1)

	_update_arena_tilt(delta)
	_warning.queue_redraw()
	var local_player = get_node_or_null("Player")
	if local_player != null and local_player.is_dead:
		_death_status.text = "You died. Respawning..." if respawn_enabled else "You died. Respawning is disabled."
	else:
		_death_status.text = ""


func _get_tilt_player_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if Stdb.is_connected_to_server():
		for player in Stdb.get_players():
			if not is_player_alive(player):
				continue
			if player.get("me", false):
				var local_player = get_node_or_null("Player")
				if local_player != null and _is_player_touching_platform(local_player):
					positions.append(local_player.global_position)
			else:
				var point := Vector2(float(player.get("x", _arena_pivot.x)), float(player.get("y", 0.0)))
				var velocity := Vector2(float(player.get("vx", 0.0)), float(player.get("vy", 0.0)))
				# Network snapshots have positions/velocities but no grounded flag.
				if _is_player_position_on_platform(point, velocity, 10.0):
					positions.append(point)
	else:
		for player in get_tree().get_nodes_in_group("grapple_players"):
			if not player is Node2D or player.is_queued_for_deletion():
				continue
			if player.get("is_dead") == true or player.global_position.y > get_void_kill_y():
				continue
			if _is_player_touching_platform(player):
				positions.append(player.global_position)
	return positions


func _is_player_touching_platform(player: Node2D) -> bool:
	if not player is CharacterBody2D or not player.is_on_floor():
		return false
	# Require an actual arena collision, excluding other players or terrain.
	for i in range(player.get_slide_collision_count()):
		if platforms.has(player.get_slide_collision(i).get_collider()):
			return _is_player_position_on_platform(player.global_position, player.get_real_velocity(), 4.0)
	return false


func _is_player_position_on_platform(point: Vector2, velocity: Vector2, tolerance: float) -> bool:
	var player_collision := get_node("Player/CollisionShape2D") as CollisionShape2D
	var player_shape := player_collision.shape as RectangleShape2D
	var half_size := player_shape.size * player_collision.global_scale.abs() / 2.0
	for platform in platforms:
		var collision := platform.get_node("CollisionShape2D") as CollisionShape2D
		var shape := collision.shape as RectangleShape2D
		var tangent := collision.global_transform.x.normalized()
		var normal := -collision.global_transform.y.normalized()
		var surface := collision.to_global(Vector2(0.0, -shape.size.y / 2.0))
		var offset := point - surface
		var support_height := absf(normal.x) * half_size.x + absf(normal.y) * half_size.y
		var support_width := absf(tangent.x) * half_size.x + absf(tangent.y) * half_size.y
		var half_width := shape.size.x * collision.global_transform.x.length() / 2.0
		if absf(offset.dot(tangent)) > half_width + support_width:
			continue
		if absf(offset.dot(normal) - support_height) > tolerance:
			continue
		# Jumping or dropping through must stop contributing immediately.
		var pivot_offset := point - _arena_pivot
		var terrain_velocity := Vector2(-pivot_offset.y, pivot_offset.x) * _arena_angular_velocity
		# Snapshots publish input velocity, which can omit the floor's carry velocity.
		var speed_tolerance := 60.0 + absf(terrain_velocity.dot(normal))
		if absf((velocity - terrain_velocity).dot(normal)) > speed_tolerance:
			continue
		return true
	return false


func _calculate_tilt_balance(positions: Array[Vector2]) -> float:
	if positions.is_empty():
		return 0.0
	var balance := 0.0
	for point in positions:
		var distance_from_center := point.x - _arena_pivot.x
		# A small center band prevents twitching; full weight beyond 64 pixels.
		var weight := clampf((absf(distance_from_center) - 16.0) / 48.0, 0.0, 1.0)
		balance += signf(distance_from_center) * weight
	return clampf(balance / positions.size(), -1.0, 1.0)


func _update_arena_tilt(delta: float) -> void:
	var balance := _calculate_tilt_balance(_get_tilt_player_positions())
	if OS.has_feature("editor") and test_tilt_override:
		balance = clampf(test_tilt_balance, -1.0, 1.0)
	var target_tilt := deg_to_rad(clampf(max_tilt_degrees, 0.0, 22.0)) * balance
	var previous_tilt := _arena_tilt
	_arena_tilt = move_toward(_arena_tilt, target_tilt, deg_to_rad(tilt_speed_degrees) * delta)
	_arena_angular_velocity = (_arena_tilt - previous_tilt) / delta if delta > 0.0 else 0.0
	# Rotate terrain around one shared pivot, keeping players and HUD independent.
	var arena_transform := Transform2D(_arena_tilt, _arena_pivot)
	arena_transform.origin -= _arena_pivot.rotated(_arena_tilt)
	for i in range(platforms.size()):
		platforms[i].global_transform = arena_transform * _platform_base_transforms[i]


func _resize_stage(count: int) -> void:
	var width_change := (count - 1) * WIDTH_PER_PLAYER
	_stage_count = count

	for i in range(platforms.size()):
		var platform := platforms[i]
		var collision: CollisionShape2D = platform.get_node("CollisionShape2D")
		var shape := collision.shape as RectangleShape2D
		var platform_width_change := width_change * _platform_width_ratios[i]
		shape.size = _platform_base_sizes[i] + Vector2(platform_width_change, 0.0)

		var line: Line2D = platform.get_node("Line2D")
		var offset := Vector2(platform_width_change / 2.0, 0.0)
		line.set_point_position(0, _platform_base_points[i][0] - offset)
		line.set_point_position(1, _platform_base_points[i][1] + offset)


func _draw_warning() -> void:
	var removed_width := (_stage_count - _target_count) * WIDTH_PER_PLAYER
	var added_width := maxi(_target_count - _join_flash_start_count, 0) * WIDTH_PER_PLAYER
	for i in range(platforms.size()):
		var line: Line2D = platforms[i].get_node("Line2D")
		var offset := Vector2(removed_width * _platform_width_ratios[i] / 2.0, 0.0)
		var added_offset := Vector2(added_width * _platform_width_ratios[i] / 2.0, 0.0)
		var left := line.get_point_position(0)
		var right := line.get_point_position(1)
		if _join_flash_remaining > 0.0 and added_width > 0.0:
			_draw_platform_segment(line, left + offset, left + offset + added_offset, Color.GREEN)
			_draw_platform_segment(line, right - offset - added_offset, right - offset, Color.GREEN)
		if removed_width > 0.0:
			_draw_platform_segment(line, left, left + offset, Color.RED)
			_draw_platform_segment(line, right - offset, right, Color.RED)


func _draw_platform_segment(line: Line2D, from: Vector2, to: Vector2, color: Color) -> void:
	# Convert both endpoints so growth/removal highlights follow the tilted terrain.
	_warning.draw_line(
		_warning.to_local(line.to_global(from)),
		_warning.to_local(line.to_global(to)),
		color, line.width
	)
