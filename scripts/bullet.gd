extends Node3D
class_name Bullet
## 炮弹/导弹:追踪目标,命中造成伤害(导弹带范围伤害)

var target: Enemy = null
var damage: float = 10.0
var speed: float = 30.0
var aoe: float = 0.0
var is_missile: bool = false


func setup(pos: Vector3, t: Enemy, dmg: float, spd: float, aoe_r: float, col: Color) -> void:
	global_position = pos
	target = t
	damage = dmg
	speed = spd
	aoe = aoe_r
	is_missile = aoe > 0.0
	build_visual(col)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.is_dead:
		queue_free()
		return
	var to: Vector3 = target.global_position + Vector3(0, 0.6, 0) - global_position
	var d := to.length()
	var step := speed * delta
	if d <= maxf(step, 0.35):
		explode()
		return
	global_position += to / d * step
	if d > 0.01:
		look_at(global_position + to / d, Vector3.UP)


func explode() -> void:
	if aoe > 0.0:
		for node in get_tree().get_nodes_in_group("enemies"):
			var e := node as Enemy
			if e and not e.is_dead and e.global_position.distance_to(global_position) <= aoe:
				e.take_damage(damage)
		spawn_explosion()
	else:
		if is_instance_valid(target) and not target.is_dead:
			target.take_damage(damage)
	queue_free()


func spawn_explosion() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0.6, 0.2, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1, 0.4, 0.1)
	mi.material_override = mat
	mi.global_position = global_position
	get_parent().add_child(mi)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * (aoe * 2.0), 0.2)
	tw.tween_callback(mi.queue_free)


func build_visual(col: Color) -> void:
	var mi := MeshInstance3D.new()
	if is_missile:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.12
		cm.height = 0.6
		mi.mesh = cm
		mi.rotation_degrees.x = -90
	else:
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.18
		mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mi.material_override = mat
	add_child(mi)
