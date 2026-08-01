extends Node
## Teste do sistema de ÁUDIO enriquecido: todos os SFX (antigos + novos) existem,
## são AudioStream válidos e play() não quebra. Godot_console.exe --headless
## res://scenes/AudioTest.tscn

func _ready() -> void:
	await get_tree().process_frame
	print("\n=== TESTE DE ÁUDIO (SFX enriquecidos) ===")
	var tally := [0, 0]
	var _t = func(desc, ok):
		if ok: tally[0] += 1
		else: tally[1] += 1
		print(("  ✓ " if ok else "  ✗ ") + desc)

	var A = AudioManager

	# 1. os 15 SFX estão carregados e são streams válidos
	var esperados := ["click", "hover", "confirm", "error", "turn", "alert",
		"achievement", "war", "success", "deny", "conquest", "coup", "money", "peace", "panel"]
	var faltando: Array = []
	for name in esperados:
		if not A._sfx.has(name) or A._sfx[name] == null or not (A._sfx[name] is AudioStream):
			faltando.append(name)
	_t.call("todos os %d SFX carregados (%s)" % [esperados.size(), "ok" if faltando.is_empty() else "faltam " + str(faltando)], faltando.is_empty())

	# 2. os NOVOS SFX estão presentes especificamente
	for novo in ["success", "deny", "conquest", "coup", "money", "peace", "panel"]:
		_t.call("SFX novo '%s' existe" % novo, A._sfx.has(novo) and A._sfx[novo] != null)

	# 3. play() não quebra com nome válido nem inválido
	A.play("success")
	A.play("conquest", -3.0)
	A.play("__inexistente__")  # não pode crashar
	_t.call("play() robusto (válido + inexistente sem crash)", true)

	# 4. pool de players existe (polifonia)
	_t.call("pool de SFX players criado", A._sfx_players.size() >= 4)

	# 5. muted silencia sem quebrar
	A.set_muted(true)
	A.play("turn")
	A.set_muted(false)
	_t.call("muted não quebra o play()", true)

	# 6. DUCKING: um SFX de peso abaixa o bus Music e depois ele volta ao base
	A._music_tension = 0.0
	var base_db: float = A._music_base_db()
	A.play("conquest")   # está em DUCK_SFX → dispara o duck
	await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout
	var ducked_db: float = AudioServer.get_bus_volume_db(A._music_bus)
	_t.call("ducking abaixa a música (%.1f < %.1f dB)" % [ducked_db, base_db], ducked_db < base_db - 1.0)
	# espera o release e confirma que voltou perto do base
	await get_tree().create_timer(1.1).timeout
	var back_db: float = AudioServer.get_bus_volume_db(A._music_bus)
	_t.call("música volta ao base após o duck (%.1f ~ %.1f)" % [back_db, base_db], abs(back_db - base_db) < 0.5)

	# 7. click/hover NÃO fazem duck (evita pisca-pisca)
	_t.call("click não está na lista de duck", not ("click" in A.DUCK_SFX))
	_t.call("hover não está na lista de duck", not ("hover" in A.DUCK_SFX))

	# 8. MÚSICA ADAPTATIVA: mais tensão (DEFCON baixo) = música mais discreta
	A._music_tension = 0.0
	var paz_db: float = A._music_base_db()
	A._music_tension = 1.0
	var guerra_db: float = A._music_base_db()
	_t.call("tensão máxima deixa a música mais baixa que na paz (%.1f < %.1f)" % [guerra_db, paz_db], guerra_db < paz_db)
	A._music_tension = 0.0

	print("\n║  RESULTADO: %d PASS / %d FAIL" % [tally[0], tally[1]])
	get_tree().quit(0 if tally[1] == 0 else 1)
