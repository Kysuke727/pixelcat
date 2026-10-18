
extends Control

@onready var buff_label: Label = $PanelContainer/BuffLabel


func _ready() -> void:
	show_buff("夜晚加成：等待状态计算")


func show_buff(message: String) -> void:
	buff_label.text = message
