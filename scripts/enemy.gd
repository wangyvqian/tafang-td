extends Node3D
class_name Enemy
## 敌人:沿路径点行进,走到终点扣玩家生命,死亡给资金

signal died(enemy: Enemy)
signal reached_end(enemy: Enemy)

var max_hp: float = 30.0
var hp: float = 30.0
var speed: float = 3.0
var reward: int = 8
var kind: String = "soldier"
var waypoints: Array[Vector3] = []
var wp_index: int = 0
var is_dead: bool = false

var visual: Node3D
var hp_bar_root: Node3D
var bar_fill: MeshInstance3D
var anim_time: float = 0.0


func setup(cfg: Dictionary, wave: int, path: Array[Vector3]) -> void:
	kind = cfg.kind
	max_hp = float(cfg.hp) * pow(1.18, wave - 1)
	hp = max_hp
	speed = float(cfg.speed) * (1.0 + 0.02 * (wave - 1))
	reward = int(cfg.reward)
	waypoints = path
	position = waypoints[0]
	add_to_group("enemies")
	build_visuals()
	build_hp_bar()
	update_bar()


func _process(delta: float) -> void:
	if is_dead:
		return
	var target := waypoints[wp_index]
	var to := target - global_position
	to.y = 0.0
	var dist := to.length()
	var step := speed * delta
	if dist <= step:
		global_position = target
		wp_index += 1
		if wp_index >= waypoints.size():
			is_dead = true
			reached_end.emit(self)
			queue_free()
			return
	else:
		global_position += to / dist * step
		if dist > 0.01:
			look_at(global_position + to / dist, Vector3.UP)
	# 行进动画:士兵颠簸摇摆,车辆轻微晃动
	anim_time += delta
	if visual != null:
		if kind == "soldier":
			var f := anim_time * 9.0
			visual.position.y = absf(sin(f)) * 0.12
			visual.rotation.z = sin(f) * 0.07
			visual.rotation.x = sin(f * 0.5) * 0.04
		else:
			var f := anim_time * 6.0
			visual.rotation.z = sin(f) * 0.03
			visual.rotation.x = sin(f * 1.3) * 0.02
			visual.position.y = absf(sin(f)) * 0.03
	# 血条始终面向摄像机
	var cam := get_viewport().get_camera_3d()
	if cam and hp_bar_root:
		var gt := hp_bar_root.global_transform
		gt.basis = cam.global_transform.basis
		hp_bar_root.global_transform = gt


func take_damage(d: float) -> void:
	if is_dead:
		return
	hp -= d
	update_bar()
	if hp <= 0.0:
		is_dead = true
		died.emit(self)
		queue_free()


func update_bar() -> void:
	var r := clampf(hp / max_hp, 0.0, 1.0)
	bar_fill.scale.x = maxf(r, 0.001)
	bar_fill.position.x = -0.58 * (1.0 - r)
	var mat := bar_fill.material_override as StandardMaterial3D
	mat.albedo_color = Color(0.2, 0.85, 0.2).lerp(Color(0.9, 0.2, 0.1), 1.0 - r)


# ---------- 外观:优先加载 GLB 模型,缺失时回退到程序化几何体 ----------

## 每种敌人对应的模型文件(来源:Poly Pizza,CC0 授权)
const MODEL_FILES := {
	"soldier": "res://assets/models/enemy_soldier.glb",
	"jeep": "res://assets/models/enemy_jeep.glb",
	"tank": "res://assets/models/enemy_tank.glb",
}
## 模型最长边缩放到的目标尺寸(米)
const MODEL_SIZE := {"soldier": 1.7, "jeep": 2.0, "tank": 3.0}
## 若模型朝向不对(倒着走),把对应值改成 180
const MODEL_YAW := {"soldier": 0.0, "jeep": 0.0, "tank": 0.0}


func build_visuals() -> void:
	visual = Node3D.new()
	add_child(visual)
	var path: String = MODEL_FILES.get(kind, "")
	if path != "" and ResourceLoader.exists(path):
		var model := (load(path) as PackedScene).instantiate() as Node3D
		visual.add_child(model)
		model.rotation_degrees.y = float(MODEL_YAW.get(kind, 0.0))
		fit_model(model, float(MODEL_SIZE.get(kind, 2.0)))
		return
	build_fallback_visuals()


## 自动缩放模型到目标尺寸、旋转朝向 -Z、底部贴地
func fit_model(model: Node3D, target: float) -> void:
	var a := node_aabb(model)
	# 最长水平轴对齐到 Z(前进方向)
	if a.size.x > a.size.z:
		model.rotation_degrees.y += 90.0
		a = node_aabb(model)
	var longest := maxf(a.size.x, maxf(a.size.y, a.size.z))
	if longest > 0.001:
		model.scale = Vector3.ONE * (target / longest)
	# 底部贴地
	var a2 := node_aabb(model)
	model.position.y -= a2.position.y - global_position.y


## 计算节点树的包围盒(需在场景树中)
func node_aabb(n: Node3D) -> AABB:
	var stack: Array[Node] = [n]
	var result := AABB()
	var has := false
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.mesh != null:
				var a := mi.global_transform * mi.mesh.get_aabb()
				if has:
					result = result.merge(a)
				else:
					result = a
					has = true
		for c in cur.get_children():
			if c is Node3D:
				stack.append(c)
	return result


func build_fallback_visuals() -> void:
	var col := Color(0.55, 0.22, 0.18)
	var dark := Color(0.25, 0.12, 0.1)
	match kind:
		"soldier":
			var body := cap(0.28, 1.0, col)
			body.position.y = 0.7
			visual.add_child(body)
			var head := sph(0.2, Color(0.8, 0.65, 0.5))
			head.position.y = 1.42
			visual.add_child(head)
			var helmet := sph(0.23, dark)
			helmet.position.y = 1.5
			helmet.scale = Vector3(1, 0.55, 1)
			visual.add_child(helmet)
		"jeep":
			var b := box(1.3, 0.5, 2.0, col)
			b.position.y = 0.55
			visual.add_child(b)
			var cab := box(1.0, 0.45, 0.8, dark)
			cab.position = Vector3(0, 1.0, 0.25)
			visual.add_child(cab)
			for s in [-1, 1]:
				for z in [-0.6, 0.6]:
					var w := cyl(0.3, 0.3, 0.18, Color(0.08, 0.08, 0.08))
					w.rotation_degrees.z = 90
					w.position = Vector3(0.68 * s, 0.3, z)
					visual.add_child(w)
		"tank":
			var hull := box(1.9, 0.6, 2.6, col)
			hull.position.y = 0.6
			visual.add_child(hull)
			for s in [-1, 1]:
				var tr := box(0.45, 0.55, 2.8, dark)
				tr.position = Vector3(0.88 * s, 0.35, 0)
				visual.add_child(tr)
			var tur := box(1.1, 0.5, 1.2, col.darkened(0.15))
			tur.position = Vector3(0, 1.15, 0.15)
			visual.add_child(tur)
			var barrel := cyl(0.09, 0.09, 1.6, dark)
			barrel.rotation_degrees.x = 90
			barrel.position = Vector3(0, 1.15, -1.2)
			visual.add_child(barrel)


func build_hp_bar() -> void:
	hp_bar_root = Node3D.new()
	var h := 2.6 if kind == "tank" else 2.0
	hp_bar_root.position = Vector3(0, h, 0)
	add_child(hp_bar_root)
	var bg := box(1.2, 0.16, 0.02, Color(0.12, 0.02, 0.02))
	hp_bar_root.add_child(bg)
	bar_fill = box(1.16, 0.12, 0.02, Color(0.2, 0.85, 0.2))
	bar_fill.position.z = -0.012
	hp_bar_root.add_child(bar_fill)


func make_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m


func box(sx: float, sy: float, sz: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(sx, sy, sz)
	mi.mesh = bm
	mi.material_override = make_mat(c)
	return mi


func cyl(rt: float, rb: float, h: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = rt
	cm.bottom_radius = rb
	cm.height = h
	mi.mesh = cm
	mi.material_override = make_mat(c)
	return mi


func sph(r: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = make_mat(c)
	return mi


func cap(r: float, h: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = make_mat(c)
	return mi
