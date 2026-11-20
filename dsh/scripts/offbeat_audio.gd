extends Node
## 错拍专用音效：只读现有 sfx_v3 音效库，不生成、不覆盖任何素材。

const BANK := "res://assets/audio/sfx_v3/"

var clips: Dictionary = {}
var voices: Array = []
var _idx: int = 0


func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		voices.append(p)
	_load_bank()


func _load_bank() -> void:
	var text := FileAccess.get_file_as_string(BANK + "manifest.json")
	if text.is_empty():
		return
	var m: Variant = JSON.parse_string(text)
	if not (m is Dictionary):
		return
	var defs: Dictionary = m.get("clips", {})
	var wanted := ["swing_l1", "swing_l2", "swing_l3", "hit_light", "hit_heavy", "hurt",
		"parry", "deflect", "clear", "dash", "launch", "shade_swing", "shade_die", "shade_windup"]
	for key in wanted:
		if not defs.has(key):
			continue
		var files: Array = defs[key].get("files", [])
		if files.is_empty():
			continue
		var path := (BANK + String(files[0])).simplify_path()
		var stream: AudioStream = null
		if path.ends_with(".ogg.b64"):
			var raw := Marshalls.base64_to_raw(FileAccess.get_file_as_string(path).strip_edges())
			if not raw.is_empty():
				stream = AudioStreamOggVorbis.load_from_buffer(raw)
		else:
			var abs_path := ProjectSettings.globalize_path(path)
			if FileAccess.file_exists(abs_path):
				match abs_path.get_extension().to_lower():
					"wav":
						stream = AudioStreamWAV.load_from_file(abs_path)
					"ogg":
						stream = AudioStreamOggVorbis.load_from_file(abs_path)
		if stream != null:
			clips[key] = stream


func play(key: String, volume_db: float = -6.0, pitch: float = 1.0) -> void:
	if not clips.has(key) or voices.is_empty():
		return
	var p: AudioStreamPlayer = voices[_idx]
	_idx = (_idx + 1) % voices.size()
	p.stream = clips[key]
	p.volume_db = volume_db
	p.pitch_scale = clampf(pitch * randf_range(0.97, 1.03), 0.6, 1.6)
	p.play()
