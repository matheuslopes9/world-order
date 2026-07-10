class_name MetaProgression
extends RefCounted
## Meta-progressão: XP que acumula entre partidas (independente do save da
## partida atual). Desbloqueia cenários novos, perks permanentes e líderes
## alternativos.
##
## Persistido em user://meta_progression.json — compartilhado entre saves.

const SAVE_PATH := "user://meta_progression.json"

# Estado
var total_xp: int = 0
var lifetime_games: int = 0
var lifetime_wins: int = 0
var unlocked_scenarios: Array = ["campanha", "decada_critica", "guerra_fria_2", "sandbox"]  # default unlocked
var active_perks: Array = []  # perks selecionados pra próxima partida (max 2)
var available_perks: Array = []  # perks já unlocked (jogador pode escolher 2)

# Custos pra unlock (em XP)
const PERK_COST_BASIC: int = 100
const PERK_COST_ADVANCED: int = 300
const SCENARIO_COST: int = 500

# Catálogo de perks que podem ser desbloqueados
const PERK_CATALOG := [
	{
		"id": "perk_economia_inicial",
		"name": "Capital Inicial",
		"description": "+$100B tesouro inicial em qualquer partida",
		"cost": 100,
		"category": "economia",
		"effects": {"tesouro_offset": 100}
	},
	{
		"id": "perk_estabilidade_inicial",
		"name": "Mandato Forte",
		"description": "+10 estabilidade política no início",
		"cost": 100,
		"category": "politica",
		"effects": {"stab_offset": 10}
	},
	{
		"id": "perk_apoio_inicial",
		"name": "Lua de Mel Estendida",
		"description": "+15 apoio popular inicial + 3 turnos extras de imunidade",
		"cost": 200,
		"category": "politica",
		"effects": {"apoio_offset": 15, "honeymoon_extra": 3}
	},
	{
		"id": "perk_pesquisa_acelerada",
		"name": "Mente Brilhante",
		"description": "+25% velocidade de pesquisa",
		"cost": 200,
		"category": "tech",
		"effects": {"research_bonus": 25}
	},
	{
		"id": "perk_acoes_extra",
		"name": "Equipe Eficiente",
		"description": "+1 ação por turno (4 ao invés de 3)",
		"cost": 500,
		"category": "gameplay",
		"effects": {"actions_per_turn": 1}
	},
	{
		"id": "perk_diplomacia",
		"name": "Carisma Natural",
		"description": "+20 relação inicial com TODOS os países",
		"cost": 200,
		"category": "diplomacia",
		"effects": {"global_relations": 20}
	},
	{
		"id": "perk_recursos",
		"name": "Solo Generoso",
		"description": "+10 em todos os recursos naturais",
		"cost": 300,
		"category": "economia",
		"effects": {"recursos_bonus": 10}
	},
	{
		"id": "perk_inflacao",
		"name": "Banco Central Sólido",
		"description": "Inflação cresce 30% mais devagar",
		"cost": 300,
		"category": "economia",
		"effects": {"inflation_decay": 30}
	},
]

func _init() -> void:
	_load()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH): return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null: return
	var raw := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(raw) != OK: return
	var d: Dictionary = json.data
	total_xp = int(d.get("total_xp", 0))
	lifetime_games = int(d.get("lifetime_games", 0))
	lifetime_wins = int(d.get("lifetime_wins", 0))
	if d.has("unlocked_scenarios"):
		unlocked_scenarios = d["unlocked_scenarios"]
	if d.has("available_perks"):
		available_perks = d["available_perks"]
	if d.has("active_perks"):
		active_perks = d["active_perks"]

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify({
		"total_xp": total_xp,
		"lifetime_games": lifetime_games,
		"lifetime_wins": lifetime_wins,
		"unlocked_scenarios": unlocked_scenarios,
		"available_perks": available_perks,
		"active_perks": active_perks,
	}, "  "))
	f.close()

# Concede XP no final de uma partida
# stats = { "victory": bool, "turns_played": int, "tier": str, "tech_count": int, "decisions": int }
func award_end_game_xp(stats: Dictionary) -> int:
	var xp_earned: int = 0
	# Base por turno jogado
	xp_earned += int(stats.get("turns_played", 0)) * 2
	# Bônus de vitória
	if stats.get("victory", false):
		xp_earned += 500
		lifetime_wins += 1
	# Bônus de tier (mais difícil = mais XP)
	match String(stats.get("tier", "NORMAL")):
		"FACIL": xp_earned += 50
		"NORMAL": xp_earned += 150
		"DIFICIL": xp_earned += 300
		"MUITO_DIFICIL": xp_earned += 500
		"QUASE_IMPOSSIVEL": xp_earned += 800
	# Bônus de tech researched
	xp_earned += int(stats.get("tech_count", 0)) * 5
	# Bônus de decisões históricas
	xp_earned += int(stats.get("decisions", 0)) * 10
	total_xp += xp_earned
	lifetime_games += 1
	# Auto-unlock de cenários se tem grana suficiente
	_check_scenario_unlocks()
	_save()
	return xp_earned

func _check_scenario_unlocks() -> void:
	# Apocalipse Climático desbloqueia após 1 vitória
	if lifetime_wins >= 1 and not ("apocalipse_climatico" in unlocked_scenarios):
		unlocked_scenarios.append("apocalipse_climatico")

# Tenta comprar um perk com XP
func purchase_perk(perk_id: String) -> Dictionary:
	if perk_id in available_perks:
		return {"ok": false, "reason": "Já desbloqueado"}
	for p in PERK_CATALOG:
		if p.get("id", "") == perk_id:
			var cost: int = int(p.get("cost", 9999))
			if total_xp < cost:
				return {"ok": false, "reason": "XP insuficiente: precisa %d, tem %d" % [cost, total_xp]}
			total_xp -= cost
			available_perks.append(perk_id)
			_save()
			return {"ok": true}
	return {"ok": false, "reason": "Perk não encontrado"}

# Toggle perk ativo (max 2 ativos por vez)
func toggle_active_perk(perk_id: String) -> Dictionary:
	if not (perk_id in available_perks):
		return {"ok": false, "reason": "Perk não desbloqueado"}
	if perk_id in active_perks:
		active_perks.erase(perk_id)
		_save()
		return {"ok": true, "active": false}
	if active_perks.size() >= 2:
		return {"ok": false, "reason": "Máximo 2 perks ativos. Desative um primeiro."}
	active_perks.append(perk_id)
	_save()
	return {"ok": true, "active": true}

# Aplica perks ativos no Nation do jogador no início da partida
func apply_perks_to_player(nation) -> void:
	if nation == null: return
	for perk_id in active_perks:
		for p in PERK_CATALOG:
			if p.get("id", "") == perk_id:
				_apply_perk_effects(nation, p.get("effects", {}))
				break

func _apply_perk_effects(n, effects: Dictionary) -> void:
	if effects.has("tesouro_offset"):
		n.tesouro = max(0.0, n.tesouro + float(effects["tesouro_offset"]))
	if effects.has("stab_offset"):
		n.estabilidade_politica = clamp(n.estabilidade_politica + float(effects["stab_offset"]), 0.0, 100.0)
	if effects.has("apoio_offset"):
		n.apoio_popular = clamp(n.apoio_popular + float(effects["apoio_offset"]), 0.0, 100.0)
	if effects.has("research_bonus"):
		n.velocidade_pesquisa *= (1.0 + float(effects["research_bonus"]) / 100.0)
	if effects.has("global_relations"):
		n.set_meta("perk_global_relations", float(effects["global_relations"]))
	if effects.has("recursos_bonus"):
		var bonus: float = float(effects["recursos_bonus"])
		if n.recursos:
			for k in n.recursos.keys():
				n.recursos[k] = min(100.0, float(n.recursos[k]) + bonus)
	if effects.has("actions_per_turn"):
		n.set_meta("perk_extra_actions", int(effects["actions_per_turn"]))
