extends Node3D
## 临时工具:逐个展示指定 glb 模型并截图,用于核对朝向、比例与结构
## 红色球标记模型 -Z 方向(游戏里"正面"),蓝色球标记 +Z 方向

const MODELS := [
	"res://assets/models/tower_mg.glb",
	"res://assets/models/tower_cannon.glb",
	"res://assets/models/tower_missile.glb",
	"res://assets/models/enemy_infantry.glb",
	"res://assets/models/enemy_jeep.glb",
	"res://assets/models/tank/recon_tank.fbx",
	"res://assets/models/enemy_swat.glb",
]
const TARGET := 3.5
const SPACING := 8.0

var report: PackedStringArray = []
var cam: Camera3D


func _ready() -> void:
	build_env()
	cam = Camera3D.new()
	cam.fov = 45
	add_child(cam)
	cam.make_current()
	for i in MODELS.size():
		var m := spawn(MODELS[i], Vector3(0, 0, 0))
		if m == null:
			report.append("MODEL %d 缺失" % i)
			continue
		# 红球在 -Z(=游戏正面),蓝球在 +Z(背面)
		report.append("MODEL %d %s" % [i, MODELS[i].get_file()])
		add_sphere(Vector3(0, 0.15, -3.2), Color(1, 0.15, 0.1))
		add_sphere(Vector3(0, 0.15, 3.2), Color(0.15, 0.35, 1))
		var a := node_aabb_raw(m)
		report.append("  尺寸 x=%.2f y=%.2f z=%.2f" % [a.size.x, a.size.y, a.size.z])
		# 记录结构
		dump_structure(m, "  ")
		cam.position = Vector3(0.5, 5.5, 9.5)
		cam.look_at(Vector3(0, 1.0, 0))
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tools/inspect_%d.png" % i)
		report.append("  saved inspect_%d.png" % i)
		# 侧视图(从 +X 看,便于判断炮管/车头朝向;红球在左侧 -Z,蓝球在右侧 +Z)
		cam.position = Vector3(9.5, 1.6, 0.0)
		cam.look_at(Vector3(0, 1.0, 0))
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tools/inspect_%d_side.png" % i)
		report.append("  saved inspect_%d_side.png" % i)
		m.queue_free()
		await get_tree().process_frame
	var f := FileAccess.open("res://tools/inspect_report.txt", FileAccess.WRITE)
	f.store_string("\n".join(report))
	f.close()
	print("=== inspect done")
	get_tree().quit()


func dump_structure(n: Node, indent: String) -> void:
	for c in n.get_children():
		var extra := ""
		if c is Node3D:
			var p: Vector3 = (c as Node3D).position
			extra = " pos=(%.1f,%.1f,%.1f)" % [p.x, p.y, p.z]
		if c is AnimationPlayer:
			extra += " ANIMS=%s" % str((c as AnimationPlayer).get_animation_list())
		report.append("%s%s [%s]%s" % [indent, c.name, c.get_class(), extra])
		if indent.length() < 6:
			dump_structure(c, indent + "  ")


func add_sphere(pos: Vector3, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.3
	sm.height = 0.6
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = c
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


func build_env() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.47, 0.56)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.8
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	g.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.55, 0.53, 0.47)
	g.material_override = gm
	add_child(g)
	# 每米一条参考线(横向 1 米间隔,纵向 1 米)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.4, 0.4, 0.37)
	for k in range(-6, 7):
		var lz := MeshInstance3D.new()
		var b1 := BoxMesh.new()
		b1.size = Vector3(30, 0.01, 0.02)
		lz.mesh = b1
		lz.material_override = lm
		lz.position = Vector3(0, 0.02, k * 1.0)
		add_child(lz)
		var lx := MeshInstance3D.new()
		var b2 := BoxMesh.new()
		b2.size = Vector3(0.02, 0.01, 30)
		lx.mesh = b2
		lx.material_override = lm
		lx.position = Vector3(k * 1.0, 0.02, 0)
		add_child(lx)


func spawn(path: String, pos: Vector3) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var m := (load(path) as PackedScene).instantiate() as Node3D
	add_child(m)
	var a := node_aabb_raw(m)
	var longest := maxf(a.size.x, maxf(a.size.y, a.size.z))
	if longest > 0.001:
		m.scale = Vector3.ONE * (TARGET / longest)
	var a2 := node_aabb_raw(m)
	m.position = pos - Vector3(0, a2.position.y, 0)
	return m


func node_aabb_raw(root: Node3D) -> AABB:
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
