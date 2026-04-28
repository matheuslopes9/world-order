class_name AchievementManager
extends RefCounted
## Sistema de Achievements local (preparado pra Steam Achievements depois).
##
## 15 marcos que detectam estados específicos do jogo. Persiste em
## user://achievements.json (compartilhado entre saves — uma vez conquistado,
## fica desbloqueado pra sempre).
##
## Quando integrar Steamworks SDK, basta chamar Steam.set_achievement(id) em
## _unlock(). API mantém compatibilidade.

const SAVE_PATH := "user://achievements.json"

signal achievement_unlocked(id: String, name: String, description: String)

# Lista mestre de 15 conquistas. Cada uma com check function lógico
# rodado a cada turno em update(engine).
const ACHIEVEMENTS := [
	# ─── PROGRESSÃO ───
	{"id": "first_turn",        "name": "Primeiro Passo",         "desc": "Avance seu primeiro turno",                "icon": "🎮"},
	{"id": "first_decade",      "name": "Década Sobrevivida",     "desc": "Jogue 40 turnos (10 anos)",                "icon": "📅"},
	{"id": "century",           "name": "Século Civilizatório",   "desc": "Atinja o ano 2100 (campanha completa)",     "icon": "🏆"},
	# ─── ECONOMIA ───
	{"id": "trillion_treasury", "name": "Cofres de Midas",        "desc": "Acumule $1 trilhão em tesouro",            "icon": "💰"},
	{"id": "double_pib",        "name": "Crescimento Histórico",  "desc": "Dobre seu PIB inicial",                    "icon": "📈"},
	{"id": "trade_network",     "name": "Rede Comercial",          "desc": "Mantenha 5 acordos comerciais simultâneos", "icon": "🤝"},
	# ─── MILITAR/DIPLOMÁTICO ───
	{"id": "first_war",         "name": "Trompete da Guerra",      "desc": "Declare sua primeira guerra",              "icon": "⚔"},
	{"id": "peacekeeper",       "name": "Pomba da Paz",            "desc": "Sobreviva 100 turnos sem declarar guerra", "icon": "🕊"},
	{"id": "alliance_master",   "name": "Tecedor de Alianças",     "desc": "Tenha 3 tratados ativos simultaneamente",  "icon": "📜"},
	{"id": "hegemon",           "name": "Hegemonia Global",        "desc": "Vença a campanha por hegemonia",            "icon": "👑"},
	# ─── TECH/CIÊNCIA ───
	{"id": "first_tech",        "name": "Mente Curiosa",           "desc": "Conclua sua primeira pesquisa",            "icon": "🔬"},
	{"id": "tech_wizard",       "name": "Sábio Nacional",          "desc": "Conclua 25 tecnologias",                   "icon": "🧠"},
	# ─── HISTÓRICO/EVENTOS ───
	{"id": "history_maker",     "name": "Forjador da História",    "desc": "Tome 10 decisões em eventos históricos",   "icon": "🕰"},
	{"id": "convergent",        "name": "Espelho da Realidade",    "desc": "Tome 5 decisões alinhadas com a história", "icon": "📖"},
	# ─── DESAFIO ───
	{"id": "underdog",          "name": "Davi vs Golias",          "desc": "Vença com nação tier MUITO_DIFICIL ou QUASE_IMPOSSIVEL", "icon": "💪"},
]

var unlocked: Dictionary = {}  # id → { unlocked_at_turn, unlocked_at_date }
var engine = null  # ref ao GameEngine

func _init(eng) -> void:
	engine = eng
	_load_from_disk()

func _load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null: return
	var raw := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(raw) != OK: return
	var data: Dictionary = json.data
	unlocked = data.get("unlocked", {})

func _save_to_disk() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify({"unlocked": unlocked}, "  "))
	f.close()

func is_unlocked(id: String) -> bool:
	return unlocked.has(id)

func get_progress() -> Dictionary:
	return {
		"total": ACHIEVEMENTS.size(),
		"unlocked": unlocked.size(),
		"pct": int(100.0 * unlocked.size() / max(1, ACHIEVEMENTS.size())),
	}

# Chamado todo turno por GameEngine.end_turn()
func update() -> void:
	if engine == null or engine.player_nation == null: return
	var n = engine.player_nation
	# Cada conquista tem sua lógica de check
	if engine.current_turn >= 1: _try_unlock("first_turn")
	if engine.current_turn >= 40: _try_unlock("first_decade")
	if engine.date_year >= 2100: _try_unlock("century")
	if n.tesouro >= 1000.0: _try_unlock("trillion_treasury")
	if n.pib_inicial > 0 and n.pib_bilhoes_usd >= n.pib_inicial * 2.0:
		_try_unlock("double_pib")
	# Trade network: 5+ acordos simultâneos
	var my_trades: int = 0
	if engine.has_method("get") and engine.get("active_trades") != null:
		for t in engine.active_trades:
			if t.get("exporter", "") == n.codigo_iso or t.get("importer", "") == n.codigo_iso:
				my_trades += 1
	if my_trades >= 5: _try_unlock("trade_network")
	# Pacificadores
	if engine.current_turn >= 100 and not n.has_meta("declared_war"):
		_try_unlock("peacekeeper")
	# Tratados ativos
	if engine.diplomacy != null:
		var my_treaties: int = 0
		for t in engine.diplomacy.treaties:
			var sigs: Array = t.get("signatories", [])
			if n.codigo_iso in sigs:
				my_treaties += 1
		if my_treaties >= 3: _try_unlock("alliance_master")
	# Tech
	if n.tecnologias_concluidas.size() >= 1: _try_unlock("first_tech")
	if n.tecnologias_concluidas.size() >= 25: _try_unlock("tech_wizard")
	# Histórico de decisões
	if engine.timeline != null:
		var dlog_size: int = engine.timeline.decision_log.size()
		if dlog_size >= 10: _try_unlock("history_maker")
		# Convergência: conta quantas decisões batem com a "história real"
		var historical_choices := {
			"ataques_911": "war_terror", "invasao_iraque": "support_invasion",
			"tsunami_indico": "help_big", "kp_nuclear_1": "sanctions",
			"lehman_crash": "bailout", "primavera_arabe": "support_revolutions",
			"fukushima": "nuclear_safe", "crimea_anexada": "heavy_sanctions",
			"acordo_paris": "sign_full", "covid_19": "lockdown_hard",
			"russia_ucrania": "heavy_sanctions_ru",
		}
		var convergent: int = 0
		for d in engine.timeline.decision_log:
			var entry: Dictionary = d
			var eid: String = entry.get("event_id", "")
			var cid: String = entry.get("choice_id", "")
			if historical_choices.get(eid, "") == cid:
				convergent += 1
		if convergent >= 5: _try_unlock("convergent")

# Chamados sob demanda por outros sistemas
func on_war_declared(by_player: bool) -> void:
	if by_player and engine and engine.player_nation:
		engine.player_nation.set_meta("declared_war", true)
		_try_unlock("first_war")

func on_victory(tier: String) -> void:
	_try_unlock("hegemon")
	if tier in ["MUITO_DIFICIL", "QUASE_IMPOSSIVEL"]:
		_try_unlock("underdog")

func _try_unlock(id: String) -> void:
	if unlocked.has(id): return
	# Acha o achievement
	var ach: Dictionary = {}
	for a in ACHIEVEMENTS:
		if a.get("id", "") == id:
			ach = a
			break
	if ach.is_empty(): return
	unlocked[id] = {
		"turn": engine.current_turn if engine else 0,
		"year": engine.date_year if engine else 0,
	}
	_save_to_disk()
	emit_signal("achievement_unlocked", id, ach.get("name", id), ach.get("desc", ""))
