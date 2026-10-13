
extends CharacterBody2D

# 敌人移动速度
@export var speed: float = 45.0

# 从出生位置向左右巡逻的距离
@export var patrol_distance: float = 80.0

# 1 表示向右，-1 表示向左
var direction: float = 1.0

# 记录敌人的初始位置
var start_x: float = 0.0

@onready var body_visual: Polygon2D = $BodyVisual


func _ready() -> void:
	# 记录出生位置
	start_x = position.x

	# 设置临时敌人的外观
	body_visual.color = Color("#B56BFF")
	body_visual.polygon = PackedVector2Array([
		Vector2(0, -12),
		Vector2(12, 0),
		Vector2(0, 12),
		Vector2(-12, 0)
	])


func _physics_process(_delta: float) -> void:
	# 设置水平速度
	velocity.x = direction * speed

	# 暂时不进行上下移动
	velocity.y = 0.0

	# 执行物理移动
	move_and_slide()

	# 到达右侧边界，转向左边
	if position.x >= start_x + patrol_distance:
		direction = -1.0

	# 到达左侧边界，转向右边
	elif position.x <= start_x - patrol_distance:
		direction = 1.0
