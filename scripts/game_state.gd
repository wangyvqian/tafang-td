extends Node
## 全局游戏状态(自动加载单例):资金、生命、波次

signal money_changed(v: int)
signal lives_changed(v: int)
signal wave_changed(v: int)

var money: int = 150:
	set(v):
		money = v
		money_changed.emit(money)

var lives: int = 20:
	set(v):
		lives = v
		lives_changed.emit(lives)

var wave: int = 0:
	set(v):
		wave = v
		wave_changed.emit(v)


func reset() -> void:
	money = 150
	lives = 20
	wave = 0
