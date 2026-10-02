extends Node
## 音效管理器(autoload 单例):预加载、限流、支持 3D 定位播放

const SOUNDS := {
	"shot_mg": [
		"res://assets/audio/shot_mg_0.ogg",
		"res://assets/audio/shot_mg_1.ogg",
	],
	"shot_cannon": [
		"res://assets/audio/shot_cannon_0.ogg",
		"res://assets/audio/shot_cannon_1.ogg",
	],
	"shot_missile": ["res://assets/audio/shot_missile.ogg"],
	"explosion": [
		"res://assets/audio/explosion_0.ogg",
		"res://assets/audio/explosion_1.ogg",
	],
	"hit": ["res://assets/audio/hit.ogg"],
	"build": ["res://assets/audio/build.ogg"],
	"click": ["res://assets/audio/click.ogg"],
	"error": ["res://assets/audio/error.ogg"],
	"wave": ["res://assets/audio/wave.ogg"],
}

## 同一音效的最短重复间隔(秒):连续开火时避免叠加爆音
const MIN_INTERVAL := 0.045
## 同时播放的声音数量上限
const MAX_ACTIVE := 26

var _cache: Dictionary = {}
var _last_time: Dictionary = {}
var _active: int = 0


func _ready() -> void:
	for key in SOUNDS:
		var list: Array = []
		for path in SOUNDS[key]:
			if ResourceLoader.exists(path):
				list.append(load(path))
		_cache[key] = list


## 播放音效。pos 传 Vector3 时做 3D 定位,传 null 时按全局音播放。
func play(key: String, pos = null, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var list: Array = _cache.get(key, [])
	if list.is_empty() or _active >= MAX_ACTIVE:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_time.get(key, -999.0)) < MIN_INTERVAL:
		return
	_last_time[key] = now
	var stream: AudioStream = list[randi() % list.size()]
	if pos is Vector3:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = stream
		p3.volume_db = volume_db
		p3.pitch_scale = pitch * randf_range(0.95, 1.08)
		p3.unit_size = 9.0
		p3.max_distance = 80.0
		add_child(p3)
		p3.position = pos
		p3.finished.connect(_release.bind(p3))
		p3.play()
	else:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = volume_db
		p.pitch_scale = pitch
		add_child(p)
		p.finished.connect(_release.bind(p))
		p.play()
	_active += 1


func _release(p: Node) -> void:
	_active = maxi(0, _active - 1)
	p.queue_free()
