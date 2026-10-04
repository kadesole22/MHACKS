extends Node
## Publishes the local Player's state and draws every other player in the room as a tinted ghost.
## Ghosts have combat hitboxes; received impulses are applied to the local Player.

const SEND_INTERVAL = 0.05
const SNAP_DISTANCE = 300.0
const SMOOTHING = 18.0
const ICON = preload("res://icon.svg")
const GRAPPLE_PLAYER_LAYER = 1 << 7 # Physics layer 8, shared with grapple_hook.gd.

var _send_timer = 0.0
var _last_facing = 1
var _targets = {}  # player id -> latest state from Stdb.get_players()
var _ghosts = {}  # player id -> Node2D


func _process(delta: float) -> void:
	if not Stdb.is_connected_to_server():
		return
	var scene = get_tree().current_scene
	if scene == null:
		return

	_send_timer += delta
	if _send_timer >= SEND_INTERVAL:
		_send_timer = 0.0
		_publish_local(scene)
		_refresh_remote(scene)

	_smooth_ghosts(delta)


func _physics_process(_delta: float) -> void:
	if not Stdb.is_connected_to_server():
		return
	var scene = get_tree().current_scene
	if scene == null:
		return
	var player = scene.get_node_or_null("Player")
	if player == null:
		return
	var impulse := Stdb.take_impulse()
	if impulse != Vector2.ZERO:
		player.apply_knockback(impulse)


func _publish_local(scene: Node) -> void:
	var player = scene.get_node_or_null("Player")
	if player == null:
		return
	if absf(player.velocity.x) > 1.0:
		_last_facing = 1 if player.velocity.x > 0.0 else -1
	Stdb.send_state(player.global_position, player.velocity, _last_facing)


func _refresh_remote(scene: Node) -> void:
	var seen = {}
	for p in Stdb.get_players():
		if p.get("me", false) or not p.get("online", true):
			continue
		if scene.has_method("is_player_alive") and not scene.is_player_alive(p):
			continue
		var id = str(p["id"])
		seen[id] = true
		_targets[id] = p
		var ghost = _ghosts.get(id)
		if ghost == null or not is_instance_valid(ghost):
			ghost = _make_ghost(p)
			scene.add_child(ghost)
			ghost.global_position = Vector2(p["x"], p["y"])
			_ghosts[id] = ghost

	for id in _ghosts.keys():
		if seen.has(id):
			continue
		var gone = _ghosts[id]
		if is_instance_valid(gone):
			gone.queue_free()
		_ghosts.erase(id)
		_targets.erase(id)


func _smooth_ghosts(delta: float) -> void:
	var weight = 1.0 - exp(-SMOOTHING * delta)
	for id in _ghosts:
		var ghost = _ghosts[id]
		if not is_instance_valid(ghost) or not _targets.has(id):
			continue
		var state = _targets[id]
		var target = Vector2(state["x"], state["y"])
		if ghost.global_position.distance_to(target) > SNAP_DISTANCE:
			ghost.global_position = target
		else:
			ghost.global_position = ghost.global_position.lerp(target, weight)
		ghost.get_node("Sprite2D").flip_h = int(state["facing"]) < 0


func _make_ghost(p: Dictionary) -> Node2D:
	var ghost = Area2D.new()
	ghost.name = "Ghost_" + str(p["id"]).substr(0, 8)
	ghost.collision_layer = GRAPPLE_PLAYER_LAYER
	ghost.collision_mask = 0
	ghost.monitoring = false
	ghost.add_to_group("grapple_players")
	ghost.set_meta("player_id", str(p["id"]))

	var hitbox := CollisionShape2D.new()
	var source := get_tree().current_scene.get_node_or_null("Player/CollisionShape2D") as CollisionShape2D
	if source != null and source.shape != null:
		hitbox.shape = source.shape.duplicate()
		hitbox.transform = source.transform
	else:
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(50, 50)
		hitbox.shape = rectangle
	ghost.add_child(hitbox)

	var sprite = Sprite2D.new()
	sprite.name = "Sprite2D"
	sprite.texture = ICON
	sprite.scale = Vector2(0.4, 0.4)
	sprite.modulate = Color.from_hsv(float(str(p["id"]).hash() % 360) / 360.0, 0.6, 1.0)
	ghost.add_child(sprite)

	var label = Label.new()
	label.text = str(p["name"])
	label.custom_minimum_size = Vector2(80, 0)
	label.position = Vector2(-40, -62)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ghost.add_child(label)
	return ghost
