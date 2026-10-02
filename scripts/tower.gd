extends Node3D
class_name Tower
## 防御塔:搜索范围内最近的敌人,旋转炮塔并开火
## 也用作建造时的半透明"幽灵"预览

var type_key: String = ""
var config: Dictionary = {}
var is_ghost: bool = false
var cooldown: float = 0.0
var turret: Node3D
var muzzle: Marker3D
var range_ring: MeshInstance3D
var body_meshes: Array[MeshInstance3D] = []
var part_colors: Dictionary = {}


func setup(key: String, cfg: Dictionary) -> void:
	type_key = key
	config = cfg
	build_visuals()


func _process(delta: float) -> void:
	if is_ghost or config.is_empty():
		return
	cooldown -= delta
	var target := find_target()
	if target == null:
		return
	var d := target.global_position - global_position
	var desired := atan2(-d.x, -d.z)
	turret.rotation.y = lerp_angle(turret.rotation.y, desired, 10.0 * delta)
	if cooldown <= 0.0 and absf(angle_difference(turret.rotation.y, desired)) < 0.35:
		fire(target)
		cooldown = 1.0 / float(config.rate)


func find_target() -> Enemy:
	var best: Enemy = null
	var best_d: float = float(config.range)
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.is_dead or e.is_queued_for_deletion():
			continue
		var dist := global_position.distance_to(e.global_position)
		if dist <= best_d:
			best_d = dist
			best = e
	return best


func fire(target: Enemy) -> void:
	var b := Bullet.new()
	get_parent().add_child(b)
	b.setup(muzzle.global_position, target, float(config.damage),
			float(config.bullet_speed), float(config.aoe), config.color)
	Sfx.play("shot_%s" % type_key, muzzle.global_position,
			float(SHOT_VOLUME.get(type_key, -6.0)))


# ---------- 幽灵(建造预览)模式 ----------

func set_ghost(v: bool) -> void:
	is_ghost = v
	if not v:
		return
	# 范围指示圈
	range_ring = cyl(float(config.range), float(config.range), 0.03, Color(1, 1, 1, 0.12))
	var rm := range_ring.material_override as StandardMaterial3D
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	range_ring.position.y = 0.07
	add_child(range_ring)
	# 收集所有网格(含 GLB 模型内部的),统一半透明
	body_meshes.clear()
	collect_meshes(self)
	set_ghost_valid(true)


func collect_meshes(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			body_meshes.append(c)
		collect_meshes(c)


func set_ghost_valid(ok: bool) -> void:
	if not is_ghost:
		return
	var c := Color(0.3, 1.0, 0.3, 0.55) if ok else Color(1.0, 0.3, 0.3, 0.55)
	for mi in body_meshes:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = m


# ---------- 外观:优先加载 GLB 模型,缺失时回退到程序化几何体 ----------

## 每种塔对应的武器模型(来源:Poly Pizza 双管防空炮,CC0 授权)
const MODEL_FILES := {
	"mg": "res://assets/models/tower_mg.glb",
	"cannon": "res://assets/models/tower_cannon.glb",
	"missile": "res://assets/models/tower_missile.glb",
}
## 模型最长边缩放到的目标尺寸(米)
const MODEL_SIZE := {"mg": 2.5, "cannon": 3.0, "missile": 3.0}
## 炮口朝向修正(这批模型炮管指向 +Z,转 180° 后指向 -Z = 索敌方向)
const MODEL_YAW := {"mg": 180.0, "cannon": 180.0, "missile": 180.0}
## 各塔涂装色(覆盖模型贴图,形成统一军械配色)
const MODEL_TINT := {
	"mg": Color(0.25, 0.31, 0.22),
	"cannon": Color(0.3, 0.3, 0.28),
	"missile": Color(0.36, 0.33, 0.2),
}
## 开火音效音量(不同武器音量不同,机枪较密所以压低)
const SHOT_VOLUME := {"mg": -10.0, "cannon": -5.0, "missile": -5.0}


func build_visuals() -> void:
	var base := cyl(0.75, 0.85, 0.4, Color(0.2, 0.21, 0.19))
	base.position.y = 0.2
	add_child(base)
	body_meshes.append(base)

	turret = Node3D.new()
	turret.position.y = 0.4
	add_child(turret)
	muzzle = Marker3D.new()
	turret.add_child(muzzle)

	var path: String = MODEL_FILES.get(type_key, "")
	if path != "" and ResourceLoader.exists(path):
		var model := (load(path) as PackedScene).instantiate() as Node3D
		turret.add_child(model)
		model.rotation_degrees.y = float(MODEL_YAW.get(type_key, 0.0))
		var size := float(MODEL_SIZE.get(type_key, 2.0))
		fit_model(model, size)
		tint_model(model, MODEL_TINT.get(type_key, Color.WHITE))
		muzzle.position = Vector3(0, size * 0.30, -size * 0.55)
		return
	build_fallback_visuals()


## 自动缩放模型到目标尺寸、把模型中心对齐到炮塔原点、底部贴合平台
func fit_model(model: Node3D, target: float) -> void:
	var a := node_aabb(model)
	var longest := maxf(a.size.x, maxf(a.size.y, a.size.z))
	if longest > 0.001:
		model.scale = Vector3.ONE * (target / longest)
	var a2 := node_aabb(model)
	var center := a2.get_center()
	model.position.x -= center.x
	model.position.z -= center.z
	model.position.y -= a2.position.y


## 给模型内所有网格统一换色
func tint_model(n: Node, c: Color) -> void:
	for child in n.get_children():
		if child is MeshInstance3D:
			var m := StandardMaterial3D.new()
			m.albedo_color = c
			m.roughness = 0.72
			m.metallic = 0.25
			(child as MeshInstance3D).material_override = m
		tint_model(child, c)


## 计算节点树的包围盒,结果位于 root 父节点的局部坐标系(不依赖 global_transform)
func node_aabb(root: Node3D) -> AABB:
	var stack: Array = [[root, root.transform]]
	var result := AABB()
	var has := false
	while not stack.is_empty():
		var entry: Array = stack.pop_back()
		var node: Node3D = entry[0]
		var xf: Transform3D = entry[1]
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh != null:
				var a: AABB = xf * mi.mesh.get_aabb()
				if has:
					result = result.merge(a)
				else:
					result = a
					has = true
		for c in node.get_children():
			if c is Node3D:
				stack.append([c, xf * (c as Node3D).transform])
	return result


func build_fallback_visuals() -> void:
	var col: Color = config.color
	var dark := Color(0.1, 0.1, 0.1)
	var muzzle_pos := Vector3.ZERO
	match type_key:
		"mg":
			var body := box(0.55, 0.45, 0.7, col)
			body.position = Vector3(0, 0.42, 0)
			turret.add_child(body)
			body_meshes.append(body)
			var barrel := cyl(0.06, 0.06, 0.9, dark)
			barrel.rotation_degrees.x = 90
			barrel.position = Vector3(0, 0.45, -0.7)
			turret.add_child(barrel)
			body_meshes.append(barrel)
			muzzle_pos = Vector3(0, 0.45, -1.2)
		"cannon":
			var body := box(0.8, 0.55, 0.9, col)
			body.position = Vector3(0, 0.48, 0)
			turret.add_child(body)
			body_meshes.append(body)
			var barrel := cyl(0.13, 0.15, 1.5, dark)
			barrel.rotation_degrees.x = 90
			barrel.position = Vector3(0, 0.5, -1.0)
			turret.add_child(barrel)
			body_meshes.append(barrel)
			muzzle_pos = Vector3(0, 0.5, -1.8)
		"missile":
			var body := box(0.9, 0.4, 1.1, col)
			body.position = Vector3(0, 0.4, 0)
			turret.add_child(body)
			body_meshes.append(body)
			for s in [-1, 1]:
				var tube := cyl(0.14, 0.14, 1.0, dark)
				tube.rotation_degrees.x = -55
				tube.position = Vector3(0.28 * s, 0.85, -0.15)
				turret.add_child(tube)
				body_meshes.append(tube)
			muzzle_pos = Vector3(0, 1.15, -0.55)
	muzzle.position = muzzle_pos


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
