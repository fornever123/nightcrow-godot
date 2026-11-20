extends SceneTree
## Focused regression checks for AAA v5 hybrid audio bank, smart combat routing,
## stereo 48 kHz mastering contract, and intact sfx_v3 rollback archive.
const NightStage := preload("res://scenes/rain_street.tscn")
const AudioFeedback := preload("res://scripts/presentation/audio_feedback.gd")
const Config := preload("res://scripts/core/configuration.gd")

const PRE_ALIGNED_SWINGS := [
	"swing_l1", "swing_l2", "swing_l3", "swing_up", "swing_charge",
	"swing_air1", "swing_air2", "swing_air3", "swing_air_up", "swing_dash",
	"swing_dash_left",
]

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("run")


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		print("FAIL: ", label)


func _stream_in_bank(audio: Node, key: String, stream: AudioStream) -> bool:
	var arr: Array = audio._bank.get(key, {}).get("streams", [])
	return arr.has(stream)


func run() -> void:
	# 1. Legacy sfx_v3 archive remains intact on disk for instant rollback/A-B comparison.
	var legacy_manifest: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/audio/sfx_v3/manifest.json"))
	check(legacy_manifest is Dictionary and (legacy_manifest as Dictionary).get("clips", {}).size() >= 35,
		"archived sfx_v3 manifest remains intact on disk")

	# 2. Active sfx_aaa_v5 manifest & 48 kHz stereo contract.
	var manifest: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(AudioFeedback.BANK_DIR + "manifest.json"))
	var clips: Dictionary = manifest.get("clips", {})
	check(String(manifest.get("version", "")).begins_with("sfx_aaa_"),
		"active manifest version identifies sfx_aaa bank")
	check(int(manifest.get("sampleRate", 0)) == 48000 and int(manifest.get("channels", 0)) == 2,
		"active manifest specifies 48 kHz stereo mastering")

	var config: Dictionary = Config.read()
	var stage: Node2D = NightStage.instantiate()
	root.add_child(stage)
	current_scene = stage
	await process_frame
	var audio: Node = stage.audio
	check(audio.bank_size() == clips.size() and clips.size() >= 52,
		"all 52+ AAA manifest entries loaded into the audio bank (got %d)" % audio.bank_size())
	check(audio._is_aaa_bank, "audio feedback marks _is_aaa_bank = true")
	check(is_equal_approx(audio._configured_gain_db("step"), 0.0),
		"legacy battle.json +6 dB step boost is neutralized for calibrated AAA footsteps")

	var bad_format: Array[String] = []
	for key in clips:
		var bank_entry: Dictionary = audio._bank.get(key, {})
		var streams: Array = bank_entry.get("streams", [])
		if streams.is_empty():
			bad_format.append(key + ":empty")
			continue
		for st in streams:
			if not (st is AudioStreamWAV):
				bad_format.append(key + ":type")
			else:
				var wav := st as AudioStreamWAV
				if not wav.stereo or wav.mix_rate != 48000:
					bad_format.append("%s:%dHz_stereo=%s" % [key, wav.mix_rate, wav.stereo])
	check(bad_format.is_empty(), "every AAA bank variant loads as stereo 48 kHz WAV: %s" % [bad_format])

	var bad_swings: Array[String] = []
	for key in PRE_ALIGNED_SWINGS:
		var entry: Dictionary = audio._bank.get(key, {})
		if not bool(entry.get("pre_aligned", false)) or entry.get("bus") != AudioFeedback.BUS_BLADE:
			bad_swings.append(key)
	check(bad_swings.is_empty(),
		"all blade swings are pre-aligned and routed to dedicated SFX_Blade bus: %s" % [bad_swings])

	# 3. Smart routing checks (preserving exact last_event contracts for combat tests).
	audio.stop_all()
	audio.play_parry(0.55)
	check(audio.last_event == "parry" and audio._voices.size() == 1
			and _stream_in_bank(audio, "parry", audio._voices[0].stream),
		"normal parry plays crisp parry bank and sets last_event='parry'")
	audio.stop_all()
	audio.play_parry(0.90)
	check(audio.last_event == "parry" and audio._voices.size() == 1
			and _stream_in_bank(audio, "parry_heavy", audio._voices[0].stream),
		"max-momentum parry (>=0.80) upgrades to parry_heavy while keeping last_event='parry'")

	audio.stop_all()
	audio.play_slam(0.30)
	check(audio.last_event == "slam" and audio._voices.size() == 1
			and _stream_in_bank(audio, "impact_accent_light", audio._voices[0].stream),
		"light_2 accent slam (<0.45) routes to impact_accent_light instead of heavy rock thud")
	audio.stop_all()
	audio.play_slam(0.75)
	check(audio.last_event == "slam" and audio._voices.size() == 1
			and _stream_in_bank(audio, "slam", audio._voices[0].stream),
		"medium slam routes to wet stone slam")
	audio.stop_all()
	audio.play_slam(1.20)
	check(audio.last_event == "slam" and audio._voices.size() == 1
			and _stream_in_bank(audio, "rift_burst", audio._voices[0].stream),
		"overkill / enhanced A4 slam (>1.02) routes to dimensional rift_burst")

	audio.stop_all()
	audio.play_charge_start()
	check(audio.last_event == "charge_start" and _stream_in_bank(audio, "charge_start", audio._voices.back().stream),
		"play_charge_start uses AAA bank")
	audio.play_charge_release(true)
	check(audio.last_event == "charge_release" and _stream_in_bank(audio, "charge_release", audio._voices.back().stream),
		"play_charge_release uses AAA bank")
	audio.play_ranged()
	check(audio.last_event == "shuriken_throw" and _stream_in_bank(audio, "ranged_throw", audio._voices.back().stream),
		"play_ranged uses AAA ranged_throw and preserves last_event='shuriken_throw'")
	audio.play_shuriken_hit(0.6)
	check(audio.last_event == "shuriken_hit" and _stream_in_bank(audio, "ranged_hit", audio._voices.back().stream),
		"play_shuriken_hit uses AAA ranged_hit and preserves last_event='shuriken_hit'")
	audio.stop_all()

	# 4. A second instance must reuse the static cache without dropping _is_aaa_bank or pre_aligned.
	var second := AudioFeedback.new()
	root.add_child(second)
	check(second._is_aaa_bank and second.bank_size() == clips.size()
			and bool(second._bank.get("swing_l1", {}).get("pre_aligned", false)),
		"static bank cache preserves AAA flag and pre_aligned swing metadata")
	second.stop_all()
	second.free()

	# 5. Dash action emits both move_started and swing_cue -> plays 1 unified swing_dash voice.
	audio.stop_all()
	var dash_move: Resource = stage.player.dash_move
	stage.player.move_started.emit(dash_move, -1)
	stage.player.swing_cue.emit(dash_move, -1)
	check(audio._voices.size() == 1 and audio.last_event == "swing_dash",
		"dash_move plays unified swing_dash without double-whoosh")
	audio.stop_all()
	var dash_left: Resource = stage.player.dash_left_move
	stage.player.move_started.emit(dash_left, -1)
	stage.player.swing_cue.emit(dash_left, -1)
	check(audio._voices.size() == 1 and audio.last_event == "swing_dash_left",
		"dash_left_move plays unified swing_dash_left without double-whoosh")
	audio.stop_all()

	# 6. Draw/sheathe follows the displayed stance clip and ends when cancelled.
	audio.set_physics_process(false)
	var view: Node = stage.player.get_node("Visual/ActorSprite")
	view.clip_name = "draw"
	audio._sync_stance_audio()
	check(audio._voices.size() == 1 and audio.last_event == "draw",
		"draw stance starts its 48 kHz katana draw")
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
	OS.delay_msec(100)
	await process_frame
	print("SELECTED_AUDIO_TESTS: %d checks / %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)
