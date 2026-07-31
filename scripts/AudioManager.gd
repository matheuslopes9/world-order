extends Node
## Sistema de áudio global (autoload).
##
## FILOSOFIA: o jogo NUNCA fica mudo. Se não houver arquivos de áudio em
## res://audio/, todos os efeitos são SINTETIZADOS proceduralmente na
## inicialização (PCM 16-bit gerado em código). Quando você adicionar
## arquivos CC0 (ver AUDIO_ASSETS.md), eles são usados automaticamente:
##
##   res://audio/sfx/click.ogg        → clique de botão
##   res://audio/sfx/hover.ogg        → hover de botão
##   res://audio/sfx/confirm.ogg      → ação executada com sucesso
##   res://audio/sfx/error.ogg        → ação negada/falhou
##   res://audio/sfx/turn.ogg         → avanço de turno
##   res://audio/sfx/alert.ogg        → evento histórico / decisão
##   res://audio/sfx/achievement.ogg  → conquista desbloqueada
##   res://audio/sfx/war.ogg          → DEFCON caiu / guerra
##   res://audio/music/*.ogg          → trilha ambiente (playlist embaralhada)
##
## Integração automática (zero-touch):
##   • TODO BaseButton adicionado à árvore ganha SFX de click/hover
##     (a UI deste jogo é 100% criada por código — hook via node_added)
##   • Sinais do GameEngine: turn_advanced, eventos, conquistas, DEFCON
##
## API pública: play("click"), set_sfx_volume(0.8), set_music_volume(0.5),
##              set_muted(true) — persistem em user://audio.cfg

const CFG_PATH := "user://audio.cfg"
const RATE := 22050  # sample rate da síntese procedural

# Nomes de SFX conhecidos (síntese + override por arquivo)
const SFX_NAMES := [
	"click", "hover", "confirm", "error", "turn", "alert", "achievement", "war",
	# Enriquecimento: feedback de ações e eventos-chave do jogo
	"success", "deny", "conquest", "coup", "money", "peace", "panel",
]

var sfx_volume: float = 0.8
var music_volume: float = 0.5
var muted: bool = false

var _sfx: Dictionary = {}            # name → AudioStream
var _sfx_players: Array = []         # pool de AudioStreamPlayer (polifonia)
var _sfx_pool_idx: int = 0
var _music_player: AudioStreamPlayer = null
var _music_tracks: Array = []        # caminhos res:// de músicas encontradas
var _music_idx: int = 0
var _last_defcon: int = 5
var _sfx_bus: int = -1
var _music_bus: int = -1

func _ready() -> void:
	_load_cfg()
	_setup_buses()
	_setup_players()
	_load_or_synth_sfx()
	# Hook global: todo botão criado no jogo ganha som automaticamente
	get_tree().node_added.connect(_on_node_added)
	# Conecta sinais de jogo (GameEngine é autoload declarado antes deste)
	call_deferred("_connect_game_signals")
	# Música: procura arquivos; se não houver, gera pad ambiente procedural
	call_deferred("_setup_music")

# ─────────────────────────────────────────────────────────────────
# API PÚBLICA
# ─────────────────────────────────────────────────────────────────

func play(name: String, volume_db: float = 0.0) -> void:
	if muted: return
	var stream: AudioStream = _sfx.get(name)
	if stream == null: return
	if _sfx_players.is_empty(): return
	var p: AudioStreamPlayer = _sfx_players[_sfx_pool_idx]
	_sfx_pool_idx = (_sfx_pool_idx + 1) % _sfx_players.size()
	p.stream = stream
	p.volume_db = volume_db
	p.play()

func set_sfx_volume(v: float) -> void:
	sfx_volume = clamp(v, 0.0, 1.0)
	if _sfx_bus >= 0:
		AudioServer.set_bus_volume_db(_sfx_bus, linear_to_db(max(0.0001, sfx_volume)))
	_save_cfg()

func set_music_volume(v: float) -> void:
	music_volume = clamp(v, 0.0, 1.0)
	if _music_bus >= 0:
		AudioServer.set_bus_volume_db(_music_bus, linear_to_db(max(0.0001, music_volume)) - 10.0)
	_save_cfg()

func set_muted(m: bool) -> void:
	muted = m
	if _music_player:
		_music_player.stream_paused = m
	_save_cfg()

# ─────────────────────────────────────────────────────────────────
# SETUP
# ─────────────────────────────────────────────────────────────────

func _setup_buses() -> void:
	# Buses dedicados pra controle independente de volume
	_sfx_bus = AudioServer.bus_count
	AudioServer.add_bus(_sfx_bus)
	AudioServer.set_bus_name(_sfx_bus, "SFX")
	AudioServer.set_bus_volume_db(_sfx_bus, linear_to_db(max(0.0001, sfx_volume)))
	_music_bus = AudioServer.bus_count
	AudioServer.add_bus(_music_bus)
	AudioServer.set_bus_name(_music_bus, "Music")
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(max(0.0001, music_volume)) - 10.0)

func _setup_players() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.finished.connect(_on_music_finished)
	add_child(_music_player)

func _load_or_synth_sfx() -> void:
	var t0 := Time.get_ticks_msec()
	var from_files: int = 0
	for name in SFX_NAMES:
		var found := ""
		for ext in ["ogg", "wav", "mp3"]:
			var path := "res://audio/sfx/%s.%s" % [name, ext]
			if ResourceLoader.exists(path):
				found = path
				break
		if found != "":
			_sfx[name] = load(found)
			from_files += 1
		else:
			_sfx[name] = _synth_sfx(name)
	print("[AUDIO] %d SFX prontos em %d ms (%d de arquivo, %d sintetizados)" %
		[_sfx.size(), Time.get_ticks_msec() - t0, from_files, _sfx.size() - from_files])

func _connect_game_signals() -> void:
	# GameEngine é autoload — referência direta (get_node("/root/…") dispara
	# "absolute paths from outside the active scene tree" quando este nó não está
	# na árvore ativa, ex. durante transições de cena/testes).
	var engine = GameEngine
	if engine == null: return
	if engine.has_signal("turn_advanced"):
		engine.turn_advanced.connect(_on_turn_advanced)
	if engine.has_signal("player_event_triggered"):
		engine.player_event_triggered.connect(func(_ev): play("alert"))
	# Managers internos (criados no _ready do GameEngine, que roda antes)
	if engine.get("timeline") != null and engine.timeline.has_signal("historic_event_decision"):
		engine.timeline.historic_event_decision.connect(func(_ev): play("alert"))
	if engine.get("achievements") != null and engine.achievements.has_signal("achievement_unlocked"):
		engine.achievements.achievement_unlocked.connect(func(_i, _n, _d): play("achievement"))
	if engine.get("storylines") != null and engine.storylines.has_signal("storyline_triggered"):
		engine.storylines.storyline_triggered.connect(func(_id, _ev): play("alert", -4.0))
	# Conquista de território: fanfarra só quando o JOGADOR ganha a província
	# (não a cada troca de dono entre bots — seria spam).
	if engine.has_signal("province_conquered"):
		engine.province_conquered.connect(_on_province_conquered)
	# Fim de jogo: vitória → conquista; derrota → golpe (tom dramático)
	if engine.has_signal("endgame_reached"):
		engine.endgame_reached.connect(_on_endgame_reached)
	# FMI oferece resgate: som de dinheiro (a proposta chega na mesa)
	if engine.has_signal("bailout_offered"):
		engine.bailout_offered.connect(func(_terms): play("money", -4.0))
	_last_defcon = int(engine.get("defcon")) if engine.get("defcon") != null else 5

func _on_province_conquered(_pid: String, _old_owner: String, new_owner: String) -> void:
	var pn = GameEngine.player_nation
	if pn != null and new_owner == pn.codigo_iso:
		play("conquest", -3.0)

func _on_endgame_reached(result: Dictionary) -> void:
	if bool(result.get("victory", false)):
		play("conquest", 0.0)
	else:
		play("coup", -2.0)

func _on_turn_advanced(_turn: int) -> void:
	play("turn", -4.0)
	# DEFCON caiu → tambores de guerra
	var engine = GameEngine  # autoload — ver nota em _connect_game_signals
	if engine == null: return
	var d: int = int(engine.get("defcon"))
	if d < _last_defcon:
		play("war", -2.0)
	_last_defcon = d

# Hook global de botões: qualquer BaseButton que entrar na árvore ganha SFX
func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta("no_sfx"):
		node.pressed.connect(func(): play("click", -6.0))
		node.mouse_entered.connect(func(): play("hover", -18.0))

# ─────────────────────────────────────────────────────────────────
# MÚSICA
# ─────────────────────────────────────────────────────────────────

func _setup_music() -> void:
	# 1) Procura .ogg em res://audio/music/
	var dir := DirAccess.open("res://audio/music")
	if dir != null:
		for f in dir.get_files():
			# Em builds exportadas os arquivos aparecem como .ogg.import/.remap
			var base := f.replace(".import", "").replace(".remap", "")
			if base.ends_with(".ogg") or base.ends_with(".wav") or base.ends_with(".mp3"):
				var p := "res://audio/music/" + base
				if ResourceLoader.exists(p) and not (p in _music_tracks):
					_music_tracks.append(p)
	if _music_tracks.size() > 0:
		_music_tracks.shuffle()
		_play_next_track()
		print("[AUDIO] Playlist: %d faixas" % _music_tracks.size())
		return
	# 2) Fallback: pad ambiente procedural (loop de 8s, gerado em ~1 frame)
	var pad := _synth_ambient_pad()
	if pad != null:
		_music_player.stream = pad
		_music_player.play()
		print("[AUDIO] Sem faixas em res://audio/music — usando pad ambiente procedural")

func _play_next_track() -> void:
	if _music_tracks.is_empty(): return
	_music_player.stream = load(_music_tracks[_music_idx])
	_music_idx = (_music_idx + 1) % _music_tracks.size()
	_music_player.play()

func _on_music_finished() -> void:
	if _music_tracks.size() > 0:
		_play_next_track()
	else:
		_music_player.play()  # re-loopa o pad

# ─────────────────────────────────────────────────────────────────
# SÍNTESE PROCEDURAL (PCM 16-bit mono @ 22050 Hz)
# ─────────────────────────────────────────────────────────────────

func _synth_sfx(name: String) -> AudioStreamWAV:
	match name:
		"click":       return _pcm(_tone(0.045, 2100, 1400, 0.32, 55.0))
		"hover":       return _pcm(_tone(0.03, 2800, 2800, 0.15, 80.0))
		"confirm":     return _pcm(_seq([_tone(0.07, 660, 660, 0.3, 22.0), _tone(0.1, 990, 990, 0.3, 18.0)]))
		"error":       return _pcm(_seq([_tone(0.09, 320, 250, 0.32, 14.0), _tone(0.12, 210, 160, 0.3, 12.0)]))
		"turn":        return _pcm(_mix([_tone(0.22, 130, 90, 0.4, 10.0), _tone(0.1, 1150, 900, 0.12, 30.0)]))
		"alert":       return _pcm(_seq([_tone(0.08, 1180, 1180, 0.3, 16.0), _silence(0.05), _tone(0.08, 1180, 1180, 0.3, 16.0)]))
		"achievement": return _pcm(_seq([_tone(0.09, 523, 523, 0.26, 10.0), _tone(0.09, 659, 659, 0.26, 10.0), _tone(0.09, 784, 784, 0.26, 10.0), _tone(0.16, 1046, 1046, 0.3, 7.0)]))
		"war":         return _pcm(_mix([_tone(0.5, 65, 48, 0.42, 5.0), _noise(0.35, 0.13, 9.0)]))
		# ── Enriquecimento ──
		# success: díade ascendente curta e satisfatória (ação executada)
		"success":     return _pcm(_seq([_tone(0.06, 587, 587, 0.26, 20.0), _tone(0.11, 880, 880, 0.28, 14.0)]))
		# deny: buzz grave e curto (ação negada, sem custo — mais suave que "error")
		"deny":        return _pcm(_tone(0.11, 196, 150, 0.26, 16.0))
		# conquest: fanfarra breve de 3 notas subindo (território tomado)
		"conquest":    return _pcm(_seq([_tone(0.09, 392, 392, 0.28, 11.0), _tone(0.09, 523, 523, 0.28, 11.0), _tone(0.18, 784, 784, 0.32, 7.0)]))
		# coup/plantão: hit grave + ruído tenso (drama geopolítico)
		"coup":        return _pcm(_mix([_tone(0.4, 98, 62, 0.4, 6.0), _noise(0.25, 0.10, 12.0)]))
		# money: brilho curto tipo "caixa registradora" (empréstimo/receita)
		"money":       return _pcm(_seq([_tone(0.04, 1568, 1568, 0.2, 40.0), _tone(0.07, 2093, 2093, 0.18, 30.0)]))
		# peace: acorde suave e resolvido (tratado/paz)
		"peace":       return _pcm(_mix([_tone(0.35, 523, 523, 0.16, 5.0), _tone(0.35, 659, 659, 0.14, 5.0), _tone(0.35, 784, 784, 0.12, 5.0)]))
		# panel: tick macio de abertura (abrir painel/modal)
		"panel":       return _pcm(_tone(0.05, 880, 1320, 0.14, 35.0))
	return _pcm(_tone(0.05, 1000, 1000, 0.2, 40.0))

# Pad ambiente escuro em Lá menor (loop seamless de 8s) — fallback de música
func _synth_ambient_pad() -> AudioStreamWAV:
	var dur := 8.0
	var count := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(count)
	# Frequências com nº inteiro de ciclos em 8s → loop perfeito
	var freqs := [55.0, 110.0, 165.0, 220.25, 261.75]  # A1, A2, E3, A3~, C4~
	var amps  := [0.16, 0.14, 0.09, 0.06, 0.05]
	var tau := TAU
	for i in count:
		var t := float(i) / RATE
		var v := 0.0
		for k in freqs.size():
			v += sin(tau * freqs[k] * t) * amps[k]
		# Respiração lenta (2 ciclos no loop → seamless)
		var breath := 0.75 + 0.25 * sin(tau * (2.0 / dur) * t)
		s[i] = v * breath * 0.5
	var wav := _pcm(s)
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = count
	return wav

# ── Blocos de síntese ──

func _tone(dur: float, f0: float, f1: float, amp: float, decay: float) -> PackedFloat32Array:
	var count := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / count
		var f := lerpf(f0, f1, t)
		phase += TAU * f / RATE
		var env := exp(-decay * (float(i) / RATE))
		# ataque de 3ms pra evitar estalo
		var attack: float = min(1.0, float(i) / (RATE * 0.003))
		out[i] = sin(phase) * amp * env * attack
	return out

func _noise(dur: float, amp: float, decay: float) -> PackedFloat32Array:
	var count := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var env := exp(-decay * (float(i) / RATE))
		out[i] = (randf() * 2.0 - 1.0) * amp * env
	return out

func _silence(dur: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int(RATE * dur))
	return out

func _seq(parts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in parts:
		out.append_array(p)
	return out

func _mix(parts: Array) -> PackedFloat32Array:
	var maxlen := 0
	for p in parts:
		maxlen = max(maxlen, p.size())
	var out := PackedFloat32Array()
	out.resize(maxlen)
	for p in parts:
		for i in p.size():
			out[i] += p[i]
	return out

func _pcm(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clamp(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav

# ─────────────────────────────────────────────────────────────────
# PERSISTÊNCIA
# ─────────────────────────────────────────────────────────────────

func _load_cfg() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK: return
	sfx_volume = float(cfg.get_value("audio", "sfx_volume", 0.8))
	music_volume = float(cfg.get_value("audio", "music_volume", 0.5))
	muted = bool(cfg.get_value("audio", "muted", false))

func _save_cfg() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "muted", muted)
	cfg.save(CFG_PATH)
