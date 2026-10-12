@tool
extends EditorPlugin

const LadderGizmoPlugin := preload("res://addons/ladder_3d/ladder_3d_gizmo_plugin.gd")

var _gizmo_plugin: EditorNode3DGizmoPlugin


func _enter_tree() -> void:
	_gizmo_plugin = LadderGizmoPlugin.new()
	add_node_3d_gizmo_plugin(_gizmo_plugin)


func _exit_tree() -> void:
	if _gizmo_plugin != null:
		remove_node_3d_gizmo_plugin(_gizmo_plugin)
		_gizmo_plugin = null
