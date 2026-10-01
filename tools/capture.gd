extends Node
## 临时调试脚本:自动摆塔 + 生成敌人,并在若干时间点截图,便于验证朝向与画面

var main: Node = null
var t := 0.0
var shot_index := 0
var pending := false
var setup_done := false
const SHOT_TIMES := [3.0, 5.5, 7.6, 9.0, 9.8]
var cam_moved := false
var zoomed := false
var angled := false
var lineup_done := false


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	main = packed.instantiate()
	add_child(main)
	RenderingServer.frame_post_draw.connect(_on_post_draw)


func _on_post_draw() -> void:
	if not pending:
		return
	pending = false
	var img := get_viewport().get_texture().get_image()
	var path := "res://tools/shot_%d.png" % shot_index
	img.save_png(path)
	print("=== saved ", path)
	# 详细输出每个敌人状态
	for e in get_tree().get_nodes_in_group("enemies"):
		var en: Node3D = e
		var aabb: AABB = main.node_aabb(en)
		var vis := en.get_node_or_null("Node3D")
		var vis_children := 0
		if vis:
			vis_children = vis.get_child_count()
		print("  ENEMY %s pos=%.1f,%.1f,%.1f yaw=%.0f size=%.1fx%.1fx%.1f viskids=%d speed=%.1f"
				% [en.kind, en.global_position.x, en.global_position.y, en.global_position.z,
				en.rotation_degrees.y, aabb.size.x, aabb.size.y, aabb.size.z, vis_children, en.speed])
	shot_index += 1
	if shot_index >= SHOT_TIMES.size():
		dump_tree()
		get_tree().quit()


## 输出场景中所有装饰模型的名称与位置,便于核对摆放
func dump_tree() -> void:
	var lines := PackedStringArray()
	lines.append("name | x | y | z | children_meshes")
	for c in main.get_children():
		if c is Node3D and not (c is Camera3D) and not (c is DirectionalLight3D) \
				and not (c is WorldEnvironment):
			var n: Node3D = c
			var meshes := 0
			var stack: Array[Node] = [n]
			while not stack.is_empty():
				var cur: Node = stack.pop_back()
				if cur is MeshInstance3D:
					meshes += 1
				for cc in cur.get_children():
					stack.append(cc)
			var aabb: AABB = main.node_aabb(n)
			lines.append("%s | %.1f | %.1f | %.1f | %d | %s | 尺寸 %.1f x %.1f x %.1f"
					% [n.name, n.global_position.x, n.global_position.y, n.global_position.z, meshes,
					n.scene_file_path, aabb.size.x, aabb.size.y, aabb.size.z])
	var f := FileAccess.open("res://tools/tree_report.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	# 扫描全场景中体积异常大的网格(定位神秘大圆盘)
	var big := PackedStringArray()
	var scan: Array[Node] = [main]
	while not scan.is_empty():
		var cur: Node = scan.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.mesh != null:
				var a: AABB = mi.global_transform * mi.mesh.get_aabb()
				var mx := maxf(a.size.x, maxf(a.size.y, a.size.z))
				if mx > 8.0 and a.size.y > 0.3:
					var mat := mi.material_override as StandardMaterial3D
					var col := "无" if mat == null else str(mat.albedo_color)
					big.append("%s | 世界位置 %.1f,%.1f,%.1f | 尺寸 %.1f x %.1f x %.1f | 颜色 %s"
							% [mi.name, a.position.x + a.size.x * 0.5, a.position.y,
							a.position.z + a.size.z * 0.5, a.size.x, a.size.y, a.size.z, col])
		for c in cur.get_children():
			scan.append(c)
	var f2 := FileAccess.open("res://tools/big_report.txt", FileAccess.WRITE)
	f2.store_string("\n".join(big))
	f2.close()


func _process(delta: float) -> void:
	if main == null or not main.has_method("spawn_enemy"):
		return
	t += delta
	if not setup_done and t > 2.0:
		setup_done = true
		_setup()
	# 第二张:沿道路方向近距离观察三个敌人(检查车道分离)
	if not lineup_done and t > 4.3:
		lineup_done = true
		var caml := get_viewport().get_camera_3d()
		if caml:
			caml.position = Vector3(14.0, 3.5, 10.0)
			caml.look_at(Vector3(-2.0, 1.0, 10.0))
			caml.fov = 55
	# 中途一张:从东南方向斜视地图边缘,检查神秘绿色区域
	if not angled and t > 7.3:
		angled = true
		var cam0 := get_viewport().get_camera_3d()
		if cam0:
			cam0.position = Vector3(16, 7, 30)
			cam0.look_at(Vector3(12, 0, 8))
			cam0.fov = 60
	# 最后一张切换为俯视图,便于核对摆放
	if not cam_moved and t > 8.2:
		cam_moved = true
		var cam := get_viewport().get_camera_3d()
		if cam:
			cam.position = Vector3(0, 62, 0.5)
			cam.rotation_degrees = Vector3(-89.0, 0.0, 0.0)
			cam.fov = 40
			print("=== 俯视摄像已切换")
		for e in get_tree().get_nodes_in_group("enemies"):
			print("敌人 ", e.kind, " 位置 ", e.global_position, " 朝向 ", e.rotation_degrees.y)
	# 最后一张:放大可疑区域(世界坐标约 2,0,-6)
	if not zoomed and t > 9.5:
		zoomed = true
		var cam2 := get_viewport().get_camera_3d()
		if cam2:
			cam2.position = Vector3(2.5, 16, -5.5)
			cam2.rotation_degrees = Vector3(-89.0, 0.0, 0.0)
			cam2.fov = 30
		# 递归查找该区域内的所有节点
		var lines := PackedStringArray()
		var stack: Array[Node] = [main]
		for idx in 8:
			if stack.is_empty():
				break
			var nxt: Array[Node] = []
			for n in stack:
				for c in n.get_children():
					nxt.append(c)
					if c is Node3D:
						var p: Vector3 = (c as Node3D).global_position
						if p.distance_to(Vector3(2.5, 0, -5.5)) < 9.0:
							var chain := ""
							var cur: Node = c
							while cur != null and cur != main:
								chain += "%s(%s)<-" % [cur.name, cur.scene_file_path.get_file()]
								cur = cur.get_parent()
							lines.append("pos=%.1f,%.1f,%.1f | %s"
									% [p.x, p.y, p.z, chain])
			stack = nxt
		var f := FileAccess.open("res://tools/zoom_report.txt", FileAccess.WRITE)
		f.store_string("\n".join(lines))
		f.close()
	if not pending and shot_index < SHOT_TIMES.size() and t >= SHOT_TIMES[shot_index]:
		pending = true


func _setup() -> void:
	GameState.money = 9999
	# 三种塔各放一座,朝向由索敌逻辑自动决定
	var tower_script: GDScript = load("res://scripts/tower.gd")
	var layout := {"mg": Vector2i(3, 4), "cannon": Vector2i(9, 12), "missile": Vector2i(16, 5)}
	for k in layout:
		var tw: Node3D = tower_script.new()
		main.add_child(tw)
		tw.setup(k, main.TOWER_TYPES[k])
		tw.position = main.cell_to_world(layout[k])
	# 三种敌人放到路径上排成一行,并冻结速度以便观察模型朝向与外观
	main.spawn_enemy("soldier")
	main.spawn_enemy("jeep")
	main.spawn_enemy("tank")
	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.size() >= 3:
		# 三个敌人并排放在同一横向位置,检验车道分配(士兵左/坦克中/吉普右)
		var spots := [Vector3(0.0, 0.155, 8.7), Vector3(0.0, 0.155, 11.2), Vector3(0.0, 0.155, 10.0)]
		for idx in 3:
			var e: Node3D = enemies[idx]
			e.global_position = spots[idx]
			e.wp_index = 1
			e.speed = 0.0
	print("=== setup done, enemies: ", enemies.size())
