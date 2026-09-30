# 钢铁防线 —— 3D 军事塔防

用 **Godot 4** 制作的最小可玩 3D 塔防游戏(现代军事主题)。

## 玩法

- 敌人沿土黄色道路从左侧进攻,你要保护右侧的基地。
- 在道路以外的空地上建造防御塔,阻止敌人通过。
- 共 **15 波** 敌人,守住即胜利;漏过敌人扣基地生命,生命归零则失败。

## 操作

| 操作 | 说明 |
|---|---|
| 鼠标左键 | 在选中塔后,点击地面建造 |
| 按键 `1` / `2` / `3` | 选择 机枪塔($50) / 加农炮($100) / 导弹车($150) |
| `Esc` | 取消选择 |
| 绿色/红色半透明预览 | 可以建造 / 不能建造 |

## 塔的属性

| 塔 | 造价 | 射程 | 伤害 | 射速 | 特点 |
|---|---|---|---|---|---|
| 机枪塔 | $50 | 7 | 8 | 5发/秒 | 射速快,克制士兵 |
| 加农炮 | $100 | 9.5 | 45 | 0.8发/秒 | 单发高伤,克制坦克 |
| 导弹车 | $150 | 13 | 35 | 0.55发/秒 | 范围伤害,射程远 |

## 敌人

| 敌人 | 生命 | 速度 | 击杀奖励 |
|---|---|---|---|
| 士兵 | 30 | 3.0 | $8 |
| 吉普 | 24 | 5.5 | $10 |
| 坦克 | 160 | 1.6 | $25 |

每过一波,敌人生命 +18%、速度 +2%。每波结束奖励 `$20 + 波次×5`。

## 运行

1. 打开 Godot(已下载到 `C:\Users\Administrator\Godot\`)
2. 项目管理器 → **导入** → 选择本文件夹的 `project.godot`
3. 按 **F5** 运行

命令行运行:

```powershell
& "$env:USERPROFILE\Godot\Godot_v4.7.2-stable_win64.exe" --path "c:\Users\Administrator\Documents\code\tafang"
```

## 项目结构

```
tafang/
├── project.godot          # Godot 项目配置
├── scenes/main.tscn       # 主场景(仅一个根节点,其余全部由代码生成)
├── assets/models/         # 已接入游戏的 3D 模型(全部 CC0 免版权)
│   ├── enemy_soldier.glb  # 士兵(Poly Pizza / Quaternius)
│   ├── enemy_jeep.glb     # 轻型装甲车(Poly Pizza / Zsky)
│   ├── enemy_tank.glb     # 坦克(Poly Pizza / Quaternius)
│   ├── enemy_swat.glb     # 备用:SWAT 士兵
│   ├── tower_mg.glb       # 机枪塔武器(Kenney weapon-turret)
│   ├── tower_cannon.glb   # 加农炮武器(Kenney weapon-cannon)
│   └── tower_missile.glb  # 导弹车武器(Kenney weapon-ballista)
├── assets_raw/            # 原始下载素材(Kenney 全套 160+ 模型,可随意取用)
└── scripts/
    ├── game_state.gd      # 全局状态:资金/生命/波次(autoload 单例)
    ├── main.gd            # 地图、UI、波次管理、建塔交互
    ├── tower.gd           # 防御塔:索敌、转炮塔、开火
    ├── enemy.gd           # 敌人:沿路径行进、血条、受伤
    └── bullet.gd          # 炮弹/导弹:追踪、爆炸、范围伤害
```

## 模型机制说明

- 代码会**优先加载 GLB 模型**,文件缺失时自动回退到程序化几何体,删掉模型文件游戏也能跑。
- 模型加载后会**自动缩放、自动转向、自动贴地**(`fit_model()`),换任何模型都不用手动调大小。
- 如果某个模型朝向不对(敌人倒着走 / 炮塔转 180° 开火),改这两个常量即可:
  - `scripts/enemy.gd` 里的 `MODEL_YAW`(改成 180)
  - `scripts/tower.gd` 里的 `MODEL_YAW`(改成 180)
- 想换模型:把新的 `.glb` 放进 `assets/models/` 覆盖同名文件,或改 `MODEL_FILES` 里的路径。

## 更多素材来源

- `assets_raw/Models/GLB format/` 里有 Kenney Tower Defense Kit 全套(塔、UFO 敌人、地形块、树、水晶等 160+ 个模型),可以直接复制进 `assets/models/` 使用。
- [Poly Pizza](https://poly.pizza) —— 免费低多边形模型(CC0),搜 tank / soldier / helicopter 等。
- [Sketchfab](https://sketchfab.com/features/free-3d-models) —— 筛选免费 + CC 授权的模型,下载 glTF 格式。

## 可以继续加的功能(路线图)

- [ ] 塔的升级/出售
- [ ] 更多敌人种类(直升机、Boss)
- [ ] 音效、爆炸粒子
- [ ] 摄像机缩放/旋转
- [ ] 多关卡选择
