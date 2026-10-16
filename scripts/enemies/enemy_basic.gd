
extends CharacterBody2D

@export var speed: float = 45.0
@export var patrol_distance: float = 80.0

var direction: float = 1.0
var start_x: float = 0.0

@onready var body_visual: Polygon2D = $BodyVisual
@onready var attack_sound: AudioStreamPlayer2D = $AttackSound
@onready var hit_sound: AudioStreamPlayer2D = $HitSound
@onready var death_sound: AudioStreamPlayer2D = $DeathSound

func _ready() -> void:
	start_x = position.x

	body_visual.color = Color("#B56BFF")
	body_visual.polygon = PackedVector2Array([
		Vector2(0, -12),
		Vector2(12, 0),
		Vector2(0, 12),
		Vector2(-12, 0)
	])

	# 简单待机动画：上下浮动
	var idle_tween = create_tween()
	idle_tween.set_loops()
	idle_tween.tween_property(
		body_visual, "position:y", -3.0, 0.5
	).set_trans(Tween.TRANS_SINE)
	idle_tween.tween_property(
		body_visual, "position:y", 0.0, 0.5
	).set_trans(Tween.TRANS_SINE)

func _physics_process(_delta: float) -> void:
	velocity.x = direction * speed
	velocity.y = 0.0
	move_and_slide()

	if position.x >= start_x + patrol_distance:
		direction = -1.0
	elif position.x <= start_x - patrol_distance:
		direction = 1.0

# 供战斗逻辑调用：播放受击音效和闪白
func play_hit_feedback() -> void:
	if hit_sound.stream != null:
		hit_sound.play()

	body_visual.modulate = Color.WHITE

	var tween = create_tween()
	tween.tween_property(
		body_visual, "modulate", Color("#B56BFF"), 0.15
	)

# 供战斗逻辑调用：播放攻击音效
func play_attack_sound() -> void:
	if attack_sound.stream != null:
		attack_sound.play()

# 供战斗逻辑调用：播放死亡音效
func play_death_sound() -> void:
	if death_sound.stream != null:
		death_sound.play()

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_H:
				play_hit_feedback()
