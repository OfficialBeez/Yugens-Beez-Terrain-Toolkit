extends RefCounted
class_name EngineWrapper


static var _editor_instance: EngineWrapper

static var instance : EngineWrapper:
	get:
		if Engine.is_editor_hint():
			if _editor_instance == null:
				_editor_instance = EngineWrapper.new()
			return _editor_instance
		# Avoid holding a static reference in runtime/headless (prevents shutdown leak warnings).
		return EngineWrapper.new()


func is_editor() -> bool:
	return Engine.is_editor_hint()


func get_edited_scene_root():
	var editor_interface = Engine.get_singleton('EditorInterface')
	return editor_interface.get_edited_scene_root()


func get_root_for_node(node: Node) -> Node:
	if is_editor():
		return get_edited_scene_root()
	if node != null and node.is_inside_tree():
		return node.get_tree().root
	return null


func set_owner_recursive(node: Node, _owner: Node = null) -> void:
	if node == null:
		return
	if not _owner:
		_owner = get_root_for_node(node)
	# Owner must be an ancestor in the tree; guard to avoid warnings during construction/teardown.
	if _owner != null and _owner.is_ancestor_of(node):
		node.owner = _owner
	for c in node.get_children():
		set_owner_recursive(c, _owner)
