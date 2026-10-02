extends Node
## 临时调试脚本:自动摆塔 + 生成敌人,并在若干时间点截图
## 用途:核对塔/敌人朝向、模型外观、炮口位置(无头模式看不到画面,必须截图)

var main: Node = null
var t := 0.0
var shot_index := 0
var pending := false
var setup_done := false
var cam_towers := false
var cam_lineup := false
var cam_top := false
var cam_zoom := false
const SHOT_TIMES := [3.0, 5.5, 7.8, 9.2, 10.0]


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
	shot_index += 1
	if shot_index >= SHOT_TIMES.size():
		dump_tree()
		get_tree().quit()


func _process(delta: float) -> void:
	if main == null or not main.has_method("spawn_enemy"):
		return
	t += delta
	if not setup_done and t > 2.0:
		setup_done = true
		_setup()
	# 塔开火特写(敌人停在塔边上,方便看炮口与朝向)
	if not cam_towers and t > 4.3:
		cam_towers = true
		var cam := get_viewport().get_camera_3d()
		if cam:
			cam.position = Vector3(-2, 6.5, 12)
			cam.look_at(Vector3(11, 1.0, 0))
			cam.fov = 50
	# 敌人队列特写
	if not cam_lineup and t > 7.0:
		cam_lineup = true
		var cam := get_viewport().get_camera_3d()
		if cam:
			cam.position = Vector3(-4.0, 3.0, 10.0)
			cam.look_at(Vector3(-19.0, 1.0, 10.0))
			cam.fov = 55
	# 俯视图
	if not cam_top and t > 8.6:
		cam_top = true
		var cam := get_viewport().get_camera_3d()
		if cam:
			cam.position = Vector3(0, 62, 0.5)
			cam.rotation_degrees = Vector3(-89.0, 0.0, 0.0)
			cam.fov = 40
	# 近景放大(看路面与车道)
	if not cam_zoom and t > 9.6:
		cam_zoom = true
		var cam := get_viewport().get_camera_3d()
		if cam:
			cam.position = Vector3(12, 7, 12)
			cam.look_at(Vector3(6, 0.5, 2))
			cam.fov = 45
	if not pending and shot_index < SHOT_TIMES.size() and t >= SHOT_TIMES[shot_index]:
		pending = true


func _setup() -> void:
	GameState.money = 9999
	# 三种塔沿路径左侧一字排开,各自盯住一个停在路上的敌人
	var tower_script: GDScript = load("res://scripts/tower.gd")
	var layout := {"mg": Vector2i(16, 10), "cannon": Vector2i(16, 8), "missile": Vector2i(16, 6)}
	for k in layout:
		var tw: Node3D = tower_script.new()
		main.add_child(tw)
		tw.setup(k, main.TOWER_TYPES[k])
		tw.position = main.cell_to_world(layout[k])
	# 战斗组:三个敌人停在路上当靶子(塔会朝它们开火)
	main.spawn_enemy("soldier")
	main.spawn_enemy("jeep")
	main.spawn_enemy("tank")
	var fight_spots := [Vector3(12.0, 0.155, 5.0), Vector3(12.0, 0.155, 1.0), Vector3(12.0, 0.155, -3.0)]
	var fight := get_tree().get_nodes_in_group("enemies")
	for i in 3:
		var e: Node3D = fight[i]
		e.global_position = fight_spots[i]
		e.wp_index = 1
		e.speed = 0.0
		e.max_hp = 99999.0
		e.hp = 99999.0
	# 队列组:三种敌人并排,供特写核对朝向
	main.spawn_enemy("soldier")
	main.spawn_enemy("jeep")
	main.spawn_enemy("tank")
	var line := get_tree().get_nodes_in_group("enemies")
	var line_spots := [Vector3(-20.0, 0.155, 6.0), Vector3(-20.0, 0.155, 10.0), Vector3(-20.0, 0.155, 14.0)]
	for i in range(3, 6):
		var e: Node3D = line[i]
		e.global_position = line_spots[i - 3]
		e.wp_index = 1
		e.speed = 0.0
		e.max_hp = 99999.0
		e.hp = 99999.0
	print("=== setup done, enemies: ", line.size())


## 输出场景对象清单(位置/尺寸),便于核对摆放
func dump_tree() -> void:
	var lines := PackedStringArray()
	lines.append("name | x | y | z | meshes | scene | size")
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
			lines.append("%s | %.1f | %.1f | %.1f | %d | %s | %.1f x %.1f x %.1f"
					% [n.name, n.global_position.x, n.global_position.y, n.global_position.z,
					meshes, n.scene_file_path, aabb.size.x, aabb.size.y, aabb.size.z])
	var f := FileAccess.open("res://tools/tree_report.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
