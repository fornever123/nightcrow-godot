extends SceneTree
## Focused regression checks for original-video audio routing.
const NightStage := preload("res://scenes/night_trial.tscn")
const AudioFeedback := preload("res://scripts/presentation/audio_feedback.gd")
const Config := preload("res://scripts/core/configuration.gd")

const SOURCE_KEYS := [
	"swing_l1", "swing_l2", "swing_l3", "swing_up", "swing_charge",
	"swing_air1", "swing_air2", "swing_air3", "swing_air_up", "swing_dash",
	"swing_dash_left", "block", "parry", "die", "draw", "sheathe",
]
const BANK_KEYS := ["step", "jump", "hit_light", "clear", "shade_swing", "launch"]

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("FAIL: ", label)

func run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://assets/audio/sfx_v3/manifest.json"))
	var clips: Dictionary = manifest.get("clips", {})
	var bad_manifest: Array[String] = []
	for key in SOURCE_KEYS:
		var entry: Dictionary = clips.get(key, {})
		var source_video: Variant = entry.get("sourceVideo", "")
		var files: Array = entry.get("files", [])
		var path := String(files[0]) if not files.is_empty() else ""
		if String(source_video).is_empty() or not path.ends_with(".wav") \
				or not path.begins_with("../selected-video/"):
			bad_manifest.append(key)
	check(SOURCE_KEYS.size() == 16 and bad_manifest.is_empty(),
		"all 16 replaced events identify a direct archived WAV and source video: %s" % [bad_manifest])

	var config: Dictionary = Config.read()
	var stage: Node2D = NightStage.instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	var audio: Node = stage.audio
	check(audio.bank_size() == clips.size(), "all manifest entries loaded into the audio bank")
	var bad_loaded: Array[String] = []
	for key in SOURCE_KEYS:
		var bank_entry: Dictionary = audio._bank.get(key, {})
		var streams: Array = bank_entry.get("streams", [])
		if String(bank_entry.get("source_video", "")).is_empty() \
				or float(bank_entry.get("jitter", -1.0)) != 0.0 \
				or streams.size() != 1 or not streams[0] is AudioStreamWAV:
			bad_loaded.append(key)
		elif not streams[0].stereo or streams[0].mix_rate != 32000:
			bad_loaded.append(key + " (format)")
	check(bad_loaded.is_empty(),
		"source WAVs retain metadata, load once, stay stereo 32 kHz, and have no jitter: %s" % [bad_loaded])
	var bad_unmatched: Array[String] = []
	for key in BANK_KEYS:
		var files: Array = clips.get(key, {}).get("files", [])
		if files.is_empty() or not String(files[0]).ends_with(".ogg.b64") \
				or audio._bank.get(key, {}).has("source_video"):
			bad_unmatched.append(key)
	check(bad_unmatched.is_empty(), "unmatched events remain generated OGG: %s" % [bad_unmatched])

	# A second instance must reuse the static cache without dropping provenance.
	var second := AudioFeedback.new()
	root.add_child(second)
	var cache_metadata_missing: Array[String] = []
	for key in SOURCE_KEYS:
		if String(second._bank.get(key, {}).get("source_video", "")).is_empty():
			cache_metadata_missing.append(key)
	check(cache_metadata_missing.is_empty(),
		"static bank cache preserves source metadata: %s" % [cache_metadata_missing])
	second.stop_all()
	second.free()

	# The dash action is wired to move_started and swing_cue in the night scene.
	audio.stop_all()
	var dash_move: Resource = stage.player.dash_move
	stage.player.move_started.emit(dash_move, -1)
	stage.player.swing_cue.emit(dash_move, -1)
	check(audio._voices.size() == 1 and audio.last_event == "swing_dash",
		"raw dash source replaces the additive dash whoosh")
	if audio._voices.size() == 1:
		check(is_equal_approx(audio._voices[0].pitch_scale, 1.0),
			"raw source dash plays at its original pitch")
	audio.stop_all()
	check(audio._play_bank("swing_dash", 0.2) and is_equal_approx(audio._voices.back().pitch_scale, 1.0),
		"raw source bank ignores a caller pitch offset")
	audio.stop_all()
	var dash_left: Resource = stage.player.dash_left_move
	stage.player.move_started.emit(dash_left, -1)
	stage.player.swing_cue.emit(dash_left, -1)
	check(audio._voices.size() == 1 and audio.last_event == "swing_dash_left",
		"raw left dash source also replaces the additive dash whoosh")
	audio.stop_all()

	# Draw/sheathe follows the displayed stance clip and ends when cancelled.
	audio.set_physics_process(false)
	var view: Node = stage.player.get_node("Visual/ActorSprite")
	view.clip_name = "draw"
	audio._sync_stance_audio()
	check(audio._voices.size() == 1 and audio.last_event == "draw",
		"draw stance starts its raw source once")
	view.clip_name = "attack"
	audio._sync_stance_audio()
	var draw_cancelled: bool = audio._voices.is_empty()
	view.clip_name = "sheathe"
	audio._sync_stance_audio()
	var sheathe_started: bool = audio._voices.size() == 1 and audio.last_event == "sheathe"
	view.clip_name = "run"
	audio._sync_stance_audio()
	check(draw_cancelled and sheathe_started and audio._voices.is_empty(),
		"draw/sheathe once then stance cancel (draw=%s sheathe=%s voices=%d)" % [draw_cancelled, sheathe_started, audio._voices.size()])

	audio.stop_all()
	check(audio._voices.is_empty(), "stop_all removes active audio voices")
	audio.enabled = false
	check(not audio._play_bank("swing_l1") and audio._voices.is_empty(),
		"disabled audio starts no voices")
	check(config.has("audio"), "audio configuration is available from the project config")
	await process_frame
	audio._bank.clear()
	AudioFeedback._bank_cache.clear()
	stage.queue_free()
	await process_frame
	# WAV playbacks are released on the real audio thread, not the fixed-FPS clock.
	OS.delay_msec(100)
	await process_frame
	print("SELECTED_AUDIO_TESTS: %d checks / %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)
