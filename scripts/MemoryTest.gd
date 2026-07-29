extends Node
## Teste do MUNDO VIVO Bloco A — memória, rancor e reputação.
## Godot_console.exe --headless --path . res://scenes/MemoryTest.tscn

const SAVE_PATH := "user://nations_new_dawn_save.json"
var _save_backup := ""
var _had_save := false

func _ready() -> void:
	await get_tree().process_frame
	_had_save = FileAccess.file_exists(SAVE_PATH)
	if _had_save:
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f: _save_backup = f.get_as_text(); f.close()

	var E = GameEngine
	print("\n=== TESTE DE MEMÓRIA & RANCOR (Mundo Vivo A) ===")
	var tally := [0, 0]
	var _t = func(desc, ok):
		if ok: tally[0] += 1
		else: tally[1] += 1
		print(("  ✓ " if ok else "  ✗ ") + desc)

	var ar = E.nations["AR"]

	# 1. remember registra e grudge_against soma
	ar.memoria = []
	ar.remember("guerra_declarada", "BR", 100)
	_t.call("agravo registrado", ar.memoria.size() == 1)
	_t.call("grudge_against soma o peso", ar.grudge_against("BR") > 0.0)
	_t.call("grudge contra outro país é 0", ar.grudge_against("US") == 0.0)

	# 2. território perdido pesa MAIS que sanção
	var na = E.nations["CL"]; na.memoria = []
	na.remember("sancao", "BR", 100)
	var peso_sancao: float = na.grudge_against("BR")
	na.memoria = []
	na.remember("provincia_perdida", "BR", 100)
	var peso_terr: float = na.grudge_against("BR")
	_t.call("província perdida (%.0f) dói mais que sanção (%.0f)" % [peso_terr, peso_sancao], peso_terr > peso_sancao)

	# 3. decaimento reduz mas não zera o rancor de território de imediato
	var p0: float = na.grudge_against("BR")
	for i in 5: na.decay_memory()
	var p1: float = na.grudge_against("BR")
	_t.call("rancor DECAI ao agir (%.0f→%.0f)" % [p0, p1], p1 < p0 and p1 > 0.0)

	# 4. cap de 12 entradas
	var nb = E.nations["PE"]; nb.memoria = []
	for i in 20:
		nb.remember("sancao", "C%02d" % i, 100)  # 20 culpados distintos
	_t.call("memória respeita o cap de 12", nb.memoria.size() <= 12)

	# 5. a IA prioriza quem tem RANCOR como alvo de guerra
	# BR guarda muito rancor de US; a relação com US e AR é igual → deve mirar US
	var br = E.nations["BR"]
	br.memoria = []
	br.relacoes["US"] = -20.0
	br.relacoes["AR"] = -20.0
	br.remember("provincia_perdida", "US", 100)
	br.remember("provincia_perdida", "US", 100)  # rancor forte
	var rel_ef_us: float = float(br.relacoes["US"]) - br.grudge_against("US")
	var rel_ef_ar: float = float(br.relacoes["AR"]) - br.grudge_against("AR")
	_t.call("relação efetiva com o agressor (US) é pior (%.0f < %.0f)" % [rel_ef_us, rel_ef_ar], rel_ef_us < rel_ef_ar)

	# 6. reputação do jogador sobe com agressão e decai
	E.player_nation = E.nations["BR"]
	E.player_reputation = 0.0
	E._add_player_reputation(6.0)
	_t.call("reputação sobe com agressão", E.player_reputation == 6.0)
	E._add_player_reputation(200.0)
	_t.call("reputação tem teto (<=150)", E.player_reputation <= 150.0)

	# 7. save/load preserva memória e reputação
	var SaveSys = load("res://scripts/SaveSystem.gd")
	E.nations["AR"].memoria = [{"tipo":"guerra_declarada","culpado":"BR","turno":50,"peso":30.0}]
	E.player_reputation = 42.0
	SaveSys.save_game(E)
	E.nations["AR"].memoria = []
	E.player_reputation = 0.0
	SaveSys.load_game(E)
	_t.call("memória restaurada após load", E.nations["AR"].grudge_against("BR") > 0.0)
	_t.call("reputação restaurada após load (%.0f)" % E.player_reputation, abs(E.player_reputation - 42.0) < 0.1)

	if _had_save:
		var fw := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if fw: fw.store_string(_save_backup); fw.close()

	print("\n║  RESULTADO: %d PASS / %d FAIL" % [tally[0], tally[1]])
	get_tree().quit(0 if tally[1] == 0 else 1)
