@tool
extends PandoraEntity
## 断晓肉鸽改招词条实体（继承 PandoraEntity）。
## 避免 Pandora 默认 OverridingProperty 在无头退出时产生 RefCounted 环引用泄漏，
## 同时完整兼容 Pandora 编辑器属性面板与运行时 get_string / get_float / get_bool 读取。


func has_entity_property(prop_name: String) -> bool:
	if is_instance():
		return super.has_entity_property(prop_name)
	_initialize_if_not_loaded()
	for property in _properties:
		if property.get_property_name() == prop_name:
			return true
	return false


func get_string(property_name: String) -> String:
	if not is_instance() and _property_overrides.has(property_name):
		return String(_property_overrides[property_name])
	for property in _properties:
		if property.get_property_name() == property_name:
			return String(property.get_default_value())
	return super.get_string(property_name)


func get_float(property_name: String) -> float:
	if not is_instance() and _property_overrides.has(property_name):
		return float(_property_overrides[property_name])
	for property in _properties:
		if property.get_property_name() == property_name:
			return float(property.get_default_value())
	return super.get_float(property_name)


func get_bool(property_name: String) -> bool:
	if not is_instance() and _property_overrides.has(property_name):
		return bool(_property_overrides[property_name])
	for property in _properties:
		if property.get_property_name() == property_name:
			return bool(property.get_default_value())
	return super.get_bool(property_name)


func get_integer(property_name: String) -> int:
	if not is_instance() and _property_overrides.has(property_name):
		return int(_property_overrides[property_name])
	for property in _properties:
		if property.get_property_name() == property_name:
			return int(property.get_default_value())
	return super.get_integer(property_name)
