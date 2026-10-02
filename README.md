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

## 素材来源与授权

| 素材 | 内容 | 来源 | 授权 |
|---|---|---|---|
| 侦察坦克 `tank/recon_tank.fbx` + PBR 贴图 | 敌人「坦克」(自带 Drive/Forward/Idle/Shoot 动画) | [OpenGameArt - Recon Tank](https://opengameart.org/content/recon-tank-update)(作者 Mophs / MNDV.ecb) | CC-BY 4.0 |
| 步兵 `enemy_infantry.glb` | 敌人「士兵」(自带 Run_Gun/Run/Walk/Idle/Death 等动画) | [Poly Pizza - Character Soldier](https://poly.pizza/m/PpLF4rt4ah)(Quaternius) | CC0 |
| 轻型坦克 `enemy_jeep.glb` | 敌人「吉普」 | [Poly Pizza - Light Tank](https://poly.pizza/m/S1jUTRmAjD)(Zsky) | CC0 |
| 多管机枪塔 `tower_mg.glb` | 机枪塔 | [Poly Pizza - Gatling Gun Turret](https://poly.pizza/m/T8ofhRSenf) | CC0 |
| 双管自动炮 `tower_cannon.glb` | 加农炮 | [Poly Pizza - Gun Cannon Turret](https://poly.pizza/m/rxgAVyYKh6) | CC0 |
| 导弹发射箱 `tower_missile.glb` | 导弹车 | [Poly Pizza - Missile Turret](https://poly.pizza/m/RqnAj5N9fL) | CC0 |
| 沙袋/油桶/帐篷/松树/铁丝网/补给箱/岗楼 | 战场装饰 | Poly Pizza(Quaternius 等) | CC0 |
| 岩石/土堆/小树 | 地面细节 | [Kenney Tower Defense Kit](https://kenney.nl/assets/tower-defense-kit) | CC0 |
| 沙漠地面/碎石路 PBR 贴图 | 地面与道路 | [ambientCG](https://ambientcg.com/)(Ground054 / Gravel022 / Ground080) | CC0 |
| 天空 HDRI | 真实天空与光照 | [Poly Haven](https://polyhaven.com/)(kloofendal_48d_partly_cloudy_puresky) | CC0 |
| 音效(射击/爆炸/命中/UI) | 开火、爆炸、建塔、波次提示 | [Kenney Impact Sounds](https://kenney.nl/assets/impact-sounds) / [Sci-Fi Sounds](https://kenney.nl/assets/sci-fi-sounds) / [Interface Sounds](https://kenney.nl/assets/interface-sounds) | CC0 |

> 唯一需要署名的是 Recon Tank(CC-BY 4.0),署名信息在 `assets/models/tank/CREDITS.txt`。
> 如果发布游戏,记得在说明中标注该模型作者。

## 项目结构

```
tafang/
├── project.godot          # Godot 项目配置
├── scenes/main.tscn       # 主场景(仅一个根节点,其余全部由代码生成)
├── assets/
│   ├── models/            # 游戏用模型(glb / fbx)
│   │   ├── tank/          # 侦察坦克 + PBR 贴图 + 署名文件
│   │   ├── enemy_*.glb    # 敌人(步兵/吉普/备用 SWAT)
│   │   ├── tower_*.glb    # 防御塔(多管机枪/双管自动炮/导弹箱)
│   │   └── prop_*.glb     # 战场道具
│   ├── audio/             # 音效(射击/爆炸/命中/UI,来自 Kenney)
│   ├── textures/          # 地面/道路 PBR 贴图(ambientCG)
│   └── hdri/sky.hdr       # HDRI 天空(Poly Haven)
├── assets_raw/            # 素材仓库(Godot 已忽略,不参与导入)
├── tools/                 # 开发调试工具(截图/模型检查,不影响游戏运行)
└── scripts/
    ├── game_state.gd      # 全局状态:资金/生命/波次(autoload 单例)
    ├── audio.gd           # 音效管理:预加载/限流/3D 定位播放(autoload 单例 Sfx)
    ├── main.gd            # 地图、UI、波次管理、建塔交互、场景搭建
    ├── tower.gd           # 防御塔:索敌、转炮塔、开火
    ├── enemy.gd           # 敌人:沿路径行进、血条、受伤、车道、模型动画
    └── bullet.gd          # 炮弹/导弹:追踪、爆炸、范围伤害
```

## 动画与音效机制

- **模型动画**:`enemy.gd` 的 `ANIM_KEYS` 定义每种敌人优先匹配的动画关键字,加载模型后自动找到
  `AnimationPlayer` 并循环播放(步兵 → `Run_Gun`,坦克 → `Drive`),播放速度随单位速度缩放。
  有骨骼动画的单位会自动关闭程序化颠簸,避免「动画叠加抖动」。
- **音效**:`scripts/audio.gd`(autoload `Sfx`)统一管理,`Sfx.play("shot_mg", 世界坐标)` 即可做 3D 定位播放;
  内置同音效最短间隔(0.045s)与同时播放上限(26)防止爆音。要换音效只需替换 `assets/audio/` 下的同名文件,
  或在 `SOUNDS` 字典里增删。

## 模型机制说明

- 代码会**优先加载真实模型**,文件缺失时自动回退到程序化几何体,删掉模型文件游戏也能跑。
- 模型加载后会**自动缩放、自动居中、自动贴地**(`fit_model()` / `place_model()`),换任何模型都不用手动调大小。
- 如果某个模型朝向不对(敌人倒着走 / 炮塔转 180° 开火),改 `MODEL_YAW` 即可:
  - `scripts/enemy.gd` 里的 `MODEL_YAW`(当前三种敌人都是 180)
  - `scripts/tower.gd` 里的 `MODEL_YAW`(当前是 180)
- 想换模型:把新的 `.glb/.fbx` 放进 `assets/models/`,改 `MODEL_FILES` 里的路径即可;
  像坦克那样带外置 PBR 贴图的,把贴图目录加进 `PBR_DIRS`。

## 开发调试工具(`tools/`)

| 文件 | 用途 |
|---|---|
| `capture.tscn` | 运行后自动建塔、放敌人、多角度截图到 `tools/shot_*.png`,并输出场景对象清单 |
| `showcase.tscn` | 逐个展示 `tools/showcase.gd` 里列出的模型(带红/蓝朝向标记),用于核对朝向与比例 |
| `inspect_report.txt` / `tree_report.txt` / `big_report.txt` | 上面两个工具输出的诊断数据 |

用法示例:

```powershell
& "$env:USERPROFILE\Godot\Godot_v4.7.2-stable_win64.exe" --path "c:\Users\Administrator\Documents\code\tafang" "res://tools/capture.tscn"
```

## 可以继续加的功能(路线图)

- [ ] 塔的升级/出售
- [ ] 更多敌人种类(直升机、Boss)
- [ ] 音效、爆炸粒子
- [ ] 摄像机缩放/旋转
- [ ] 多关卡选择
