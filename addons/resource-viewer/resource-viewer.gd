@tool
extends EditorPlugin


var _dock


func _enter_tree():
	_dock = Dock.new(get_editor_interface())
	_dock.connect_reload(_reload)
	add_control_to_dock(DOCK_SLOT_LEFT_BR, _dock)
	
	_reload()


func _exit_tree():
	_dock.queue_free()


func _reload():
	var resources = []
	var fs = get_editor_interface().get_resource_filesystem()
	_scan_resources(
		fs.get_filesystem_path("res://"), 
		func(dir, i): resources.append(dir.get_file_path(i))
	)
	_dock.load_items(resources)


func _scan_resources(dir: EditorFileSystemDirectory, visit: Callable):
	for i in range(dir.get_subdir_count()):
		_scan_resources(dir.get_subdir(i), visit)
	
	for i in range(dir.get_file_count()):
		if ClassDB.is_parent_class(dir.get_file_type(i), "Resource") and dir.get_file_import_is_valid(i):
			visit.call(dir, i)


class Dock extends PanelContainer:
	var buttons = {
		'add': 1
	}
	
	var _line_edit: LineEditDebounced
	var _reload_btn: Button
	var _tree: ResourceTree
	var _new_resource_window: NewResourceWindow
	var _editor_interface: EditorInterface
	
	func _init(editor_interfase: EditorInterface):
		self._editor_interface = editor_interfase
		name = tr("Resources")
		
		var vb = VBoxContainer.new()
		add_child(vb)
		
		var hb = HBoxContainer.new()
		vb.add_child(hb)
		
		_line_edit = LineEditDebounced.new()
		_line_edit.clear_button_enabled = true
		_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_line_edit.placeholder_text = tr("Filter Resources")
		hb.add_child(_line_edit)
		
		_reload_btn = Button.new()
		_reload_btn.flat = true
		_reload_btn.tooltip_text = tr("Refresh List")
		hb.add_child(_reload_btn)
		
		_tree = ResourceTree.new()
		_tree.hide_root = true
		_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vb.add_child(_tree)
		
		_new_resource_window = NewResourceWindow.new()
		add_child(_new_resource_window)
		
		_tree.button_clicked.connect(_handle_button_clicked)
		_tree.item_activated.connect(_handle_item_activated)

	func _notification(what):
		if what == NOTIFICATION_THEME_CHANGED:
			_reload_btn.icon = _get_theme_icon("Reload", "EditorIcons")
			_line_edit.right_icon = _get_theme_icon("Search", "EditorIcons")
	
	func load_items(resource_pathes):
		_tree.clear()
		_tree.create_item()
		
		var script_map = {}
		var resource_pathes_copy = resource_pathes.duplicate()
		resource_pathes_copy.sort_custom(
			func(a, b): return a.similarity(_line_edit.text) > b.similarity(_line_edit.text)
		)
		var resources = resource_pathes_copy.map(
			func(x): return ResourceLoader.load(x)
		).filter(func(x): return x != null)
		
		for res in resources:
			var obj_type = _to_obj_type(res)
			_create_folding_item(obj_type, script_map)
		
		for res in resources:
			var obj_type = _to_obj_type(res)
			var res_key = _to_obj_type(res).get_key()
			if not res_key in script_map:
				continue
			var item = _tree.create_item(script_map[res_key])
			item.set_text(0, res.resource_path.get_file())
			item.set_metadata(0, res)
			item.set_icon(0, _get_theme_icon_by_class(res.get_class(), "File"))
	
	func connect_reload(callback):
		_reload_btn.pressed.connect(callback)
		_line_edit.search.connect(func(_t): callback.call())
	
	func _handle_item_activated():
		var selected = _tree.get_selected()
		if selected == null:
			return
		if selected.get_metadata(0) is Resource:
			var res = selected.get_metadata(0) as Resource
			_editor_interface.edit_resource(res)
	
	func _handle_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int):
		if id == buttons.add:
			_new_resource_window.setup(item.get_metadata(0))
			_new_resource_window.popup_centered()
	
	func _create_folding_item(type: ObjType, cache):
		var type_name = type.get_name()
		if type_name.is_empty():
			return
		if type.get_key() in cache:
			return
		
		var parent = type.get_parent()
		var item: TreeItem
		if parent.get_name().is_empty() or parent.get_name() == "Resource":
			item = _tree.create_item()
		else:
			_create_folding_item(parent, cache)
			item = _tree.create_item(cache[parent.get_key()])
		
		cache[type.get_key()] = item
		item.collapsed = true
		item.set_text(0, type_name)
		if type.get_src() is Script:
			item.set_metadata(0, type.get_src())
			item.add_button(0, _get_theme_icon("Add", "EditorIcons"), buttons.add)
			item.set_icon(0, _get_theme_icon("Object", "EditorIcons"))
		else:
			item.set_icon(0, _get_theme_icon_by_class(type_name))
	
	func _to_obj_type(obj: Object) -> ObjType:
		var script = obj.get_script()
		if script != null:
			return ObjType.new(script)
		else:
#			return ObjType.new(obj.get_class())
			return ObjType.new("")

	func _get_theme_icon_by_class(obj_class, default="Object"):
		if _editor_interface.get_base_control().has_theme_icon(obj_class, "EditorIcons"):
			return _get_theme_icon(obj_class, "EditorIcons")
		else:
			return _get_theme_icon(default, "EditorIcons")
	
	func _get_theme_icon(icon_name, theme_type):
		return _editor_interface.get_base_control().get_theme_icon(icon_name, theme_type)


class ObjType:
	var _src
	
	func _init(src):
		self._src = src
	
	func get_src():
		return _src
	
	func get_key():
		if _src is Script:
			return _src.resource_path
		else:
			return _src
	
	func get_name():
		if _src is Script:
			return _src.resource_path.get_basename().get_file()
		else:
			return _src
	
	func get_parent():
		if _src is Script:
			var base_script = _src.get_base_script()
			if base_script != null:
				return ObjType.new(base_script)
			else:
				return ObjType.new(_src.get_instance_base_type())
		else:
			return ObjType.new(ClassDB.get_parent_class(_src))


class ResourceTree extends Tree:
	func _get_drag_data(at_position):
		var selected = get_selected()
		var metadata = selected.get_metadata(0)
		if metadata != null and metadata is Resource:
			var label = Label.new()
			label.text = selected.get_text(0)
			
			var hbox = HBoxContainer.new()
			hbox.add_child(label)
			
			set_drag_preview(hbox)
			
			return {
				"type": "files",
				"files": [metadata.resource_path]
			}


class LineEditDebounced extends LineEdit:
	signal search(text)
	
	var _timer: Timer
	
	func _init():
		_timer = Timer.new()
		_timer.one_shot = true
		_timer.timeout.connect(func():
			search.emit(text)
		)
		add_child(_timer)
		
		text_changed.connect(func(_a):
			_timer.start(0.5)
		)


class NewResourceWindow extends ConfirmationDialog:
	var _name_edit: LineEdit
	var _res_to_copy
	
	func _init():
		dialog_hide_on_ok = false
		
		_name_edit = LineEdit.new()
		_name_edit.text_changed.connect(func(_a): _update_ok_btn())
		
		var vb = VBoxContainer.new()
		vb.add_child(_name_edit)
		
		add_child(vb)
		confirmed.connect(_confirm)
	
	func setup(res_to_copy):
		_res_to_copy = res_to_copy
		_name_edit.text = res_to_copy.resource_path.get_file().get_basename() + ".tres"
		var i = 1
		while FileAccess.file_exists(_to_file_path()):
			_name_edit.text = res_to_copy.resource_path.get_file().get_basename() + "%s.tres" % i
			i += 1
			if i == 10000:
				break
		_update_ok_btn()
	
	func _confirm():
		DirAccess.make_dir_absolute("res://resources")
		var res = Resource.new()
		res.script = _res_to_copy
		var err = ResourceSaver.save(res, _to_file_path())
		if err:
			push_error(error_string(err))
		hide()
	
	func _update_ok_btn():
		get_ok_button().disabled = FileAccess.file_exists(_to_file_path())
	
	func _to_file_path():
		return "res://resources/" + _name_edit.text.strip_edges()
