extends Node
## Talks to the SpacetimeDB connection owned by the hosting web page (web/src/bridge.ts).
## Outside a web export (for example the editor) every call is a harmless no-op.

var _bridge = null


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	# "parent" is window.parent: the page that embeds this export in an iframe.
	var parent = JavaScriptBridge.get_interface("parent")
	if parent != null:
		_bridge = parent.stdb


func is_connected_to_server() -> bool:
	return _bridge != null


func my_id() -> String:
	return str(_bridge.myId()) if _bridge != null else ""


func room_code() -> String:
	return str(_bridge.roomCode()) if _bridge != null else ""


func send_state(pos: Vector2, vel: Vector2, facing: int) -> void:
	if _bridge != null:
		_bridge.sendState(pos.x, pos.y, vel.x, vel.y, facing)


## Every player in my room, including me: { id, name, online, me, x, y, vx, vy, facing }.
func get_players() -> Array:
	if _bridge == null:
		return []
	var parsed = JSON.parse_string(str(_bridge.players()))
	return parsed if parsed is Array else []


func send_grapple_hit(target_id: String, impulse: Vector2) -> bool:
	if _bridge == null:
		return false
	return bool(_bridge.sendGrappleHit(target_id, impulse.x, impulse.y))


func take_impulse() -> Vector2:
	if _bridge == null:
		return Vector2.ZERO
	var parsed = JSON.parse_string(str(_bridge.takeImpulse()))
	if parsed is Array and parsed.size() == 2:
		return Vector2(float(parsed[0]), float(parsed[1]))
	return Vector2.ZERO
