class_name Nation
extends RefCounted
## Porte do nation.js para GDScript.
## Representa uma nação com toda lógica de economia, política, finanças, dívida.

# Identificação
var codigo_iso: String = ""
var nome: String = ""
var continente: String = ""
var capital: String = ""
var regime_politico: String = ""
var ideologia_dominante: String = ""

# Demografia/Economia
var populacao: int = 0
var pib_bilhoes_usd: float = 0.0
var tesouro: float = 0.0
var divida_publica: float = 0.0
var inflacao: float = 5.0

# Política interna
var estabilidade_politica: float = 50.0
var apoio_popular: float = 50.0
var corrupcao: float = 30.0
var burocracia_eficiencia: float = 70.0
var felicidade: float = 60.0

# Eleições
var proxima_eleicao_turno = null  # Variant: int ou null
var intervalo_eleicoes: int = 20

# Recursos & Militar (Dictionaries)
var recursos: Dictionary = {}
var militar: Dictionary = {}
var geografia: Dictionary = {}

# Pesquisa & Tech
var tecnologias_concluidas: Array = []
var pesquisa_atual = null  # { id, progresso } ou null
var velocidade_pesquisa: float = 1.0

# Diplomacia
var relacoes: Dictionary = {}
var em_guerra: Array = []
var personalidade: String = "agressivo"

# Espionagem
var intel_score: float = 0.0
var seguranca_intel: float = 1.0
var intel_data: Dictionary = {}
var spy_ops_log: Array = []

# Estado interno
var memoria: Array = []
var gasto_social: Dictionary = {"saude": 0, "educacao": 0, "previdencia": 0, "seguranca": 0}
var revolucao_turnos: int = 0
var falencia_turnos: int = 0
var default_turnos: int = 0
var poderes_emergencia_ativo: bool = false
var conquistas_historicas: Array = []
var pib_inicial: float = 0.0  # snapshot do PIB no início — usado para soft-cap de crescimento

# Dificuldade
var tier_dificuldade: String = "NORMAL"

# Histórico (até 20 valores cada)
var historico: Dictionary = {
	"estabilidade": [], "apoio_popular": [], "corrupcao": [],
	"felicidade": [], "burocracia": [], "poder_militar": [],
	"orcamento_militar": [], "infantaria": [], "tanques": [],
	"avioes": [], "navios": [], "pib": [], "populacao": [],
	"tesouro": [], "inflacao": []
}

const HIST_MAX: int = 20

func from_dict(data: Dictionary, code: String, baked_tier: String = "") -> Nation:
	codigo_iso = code
	nome = data.get("nome", code)
	continente = data.get("continente", "")
	capital = data.get("capital", "")
	regime_politico = data.get("regime_politico", "DEMOCRACIA")
	ideologia_dominante = data.get("ideologia_dominante", "")
	populacao = int(data.get("populacao", 0))
	pib_bilhoes_usd = float(data.get("pib_bilhoes_usd", 0))
	estabilidade_politica = float(data.get("estabilidade_politica", 50))
	recursos = data.get("recursos", {}).duplicate()
	militar = data.get("militar", {}).duplicate(true)
	geografia = data.get("geografia", {}).duplicate(true)
	conquistas_historicas = data.get("conquistas_historicas", [])
	personalidade = data.get("personalidade", "agressivo")

	# Tesouro inicial: 5% do PIB anual, piso $60B para jogabilidade
	if data.has("tesouro"):
		tesouro = float(data["tesouro"])
	else:
		tesouro = max(60.0, round(pib_bilhoes_usd * 0.05))

	pib_inicial = pib_bilhoes_usd

	# Tier de dificuldade
	if baked_tier != "":
		tier_dificuldade = baked_tier
	else:
		tier_dificuldade = _compute_difficulty_tier()

	# Inicializa eleições se democracia
	if is_democratic() and proxima_eleicao_turno == null:
		proxima_eleicao_turno = intervalo_eleicoes

	return self

# ─────────────────────────────────────────────────────────────────
# DIFICULDADE
# ─────────────────────────────────────────────────────────────────

func _compute_difficulty_tier() -> String:
	var score: float = 0.0
	if pib_bilhoes_usd >= 2000.0:    score += 55
	elif pib_bilhoes_usd >= 500.0:   score += 45
	elif pib_bilhoes_usd >= 150.0:   score += 35
	elif pib_bilhoes_usd >= 50.0:    score += 22
	elif pib_bilhoes_usd >= 15.0:    score += 10
	else:                            score += 3
	score += (estabilidade_politica / 100.0) * 30.0
	score += (apoio_popular / 100.0) * 15.0
	if "REGIME_HIBRIDO" in regime_politico: score -= 10
	if "TEOCRACIA"     in regime_politico: score -= 8
	if "DITADURA"      in regime_politico: score -= 6
	if "AUTORITARISMO" in regime_politico: score -= 3
	if em_guerra.size() > 0: score -= 12

	if score >= 75: return "FACIL"
	if score >= 62: return "NORMAL"
	if score >= 48: return "DIFICIL"
	if score >= 32: return "MUITO_DIFICIL"
	return "QUASE_IMPOSSIVEL"

func get_action_multiplier() -> float:
	# Calibrado via playtest massivo (3 rodadas):
	# NORMAL recebe bônus maior pra não ficar atrás de DIFICIL.
	# Curva monotônica: quanto mais difícil o tier, maior o multiplicador de ação.
	var base: float
	match tier_dificuldade:
		"QUASE_IMPOSSIVEL": base = 1.80
		"MUITO_DIFICIL":    base = 1.50
		"DIFICIL":          base = 1.10
		"NORMAL":           base = 1.20
		"FACIL":            base = 0.95
		_:                  base = 1.0
	# Penalidade de guerra: cada frente reduz eficiência em 12%, máximo 50% (3 frentes ou +)
	# Nações em guerra simultânea com 3+ inimigos são DRAMATICAMENTE menos eficientes
	# em ações domésticas (saúde, educação, propaganda) — guerra absorve recursos/atenção.
	var wars: int = em_guerra.size()
	if wars > 0:
		var penalty: float = clamp(1.0 - wars * 0.12, 0.5, 1.0)
		base *= penalty
	return base

# ─────────────────────────────────────────────────────────────────
# ECONOMIA
# ─────────────────────────────────────────────────────────────────

func calc_tax_rate() -> float:
	if "COMUNIS"  in regime_politico: return 0.35
	if "SOCIAL"   in regime_politico: return 0.28
	if "DEMOCRA"  in regime_politico: return 0.22
	if "AUTORITA" in regime_politico: return 0.18
	return 0.20

func calc_receita() -> float:
	var tax_rate := calc_tax_rate()
	var impostos: float = (pib_bilhoes_usd * tax_rate / 4.0) + 5.0
	var vals: Array = recursos.values() if recursos else []
	var avg_resource: float = 30.0
	if vals.size() > 0:
		var sum: float = 0.0
		for v in vals: sum += float(v)
		avg_resource = sum / vals.size()
	var export_bonus: float = pib_bilhoes_usd * (avg_resource / 100.0) * 0.02 / 4.0
	var bur_pct: float = (burocracia_eficiencia - 50.0) / 50.0
	var cor_pct: float = (50.0 - corrupcao) / 50.0
	var eficiencia: float = 1.0 + (bur_pct * 0.075) + (cor_pct * 0.075)
	var infl_penalty: float = max(0.0, (inflacao - 15.0) / 100.0)
	var infl_factor: float = max(0.5, 1.0 - infl_penalty * 0.6)
	return (impostos + export_bonus) * eficiencia * infl_factor

func calc_despesas() -> float:
	var mil_budget: float = float(militar.get("orcamento_militar_bilhoes", 0)) / 4.0
	var gov_spend: float = pib_bilhoes_usd * 0.10 / 4.0
	var interest: float = divida_publica * 0.025
	var social_sum: float = 0.0
	for v in gasto_social.values(): social_sum += float(v)
	var social_spend: float = social_sum / 4.0
	return mil_budget + gov_spend + interest + social_spend

func calc_saldo() -> float:
	return calc_receita() - calc_despesas()

func update_pib(global_factor: float = 1.0) -> void:
	var stab: float = estabilidade_politica / 100.0
	var happy: float = felicidade / 100.0
	var corr: float = corrupcao / 100.0
	var bur: float = burocracia_eficiencia / 100.0
	var wars: int = em_guerra.size()
	var growth: float = 0.008 * global_factor * (0.5 + stab * 0.5 + happy * 0.3 + bur * 0.2 - corr * 0.4)
	growth -= wars * 0.005
	if inflacao > 15.0: growth -= (inflacao - 15.0) * 0.0008
	if tesouro <= 0.0: growth -= 0.003
	if divida_publica > pib_bilhoes_usd * 1.5: growth -= 0.004
	growth += min(0.005, tecnologias_concluidas.size() * 0.0003)
	growth = clamp(growth, -0.03, 0.025)

	# Soft cap: crescimento decai quando PIB supera 2x o inicial; ~0 em 4x
	if pib_inicial > 0.0 and growth > 0.0:
		var ratio: float = pib_bilhoes_usd / pib_inicial
		if ratio > 2.0:
			var damp: float = clamp(1.0 - (ratio - 2.0) / 2.0, 0.0, 1.0)
			growth *= damp

	pib_bilhoes_usd *= (1.0 + growth)

# Helper público: aplica multiplicador no PIB respeitando o soft cap.
# Usar isto em ações/eventos que multiplicam pib_bilhoes_usd, ao invés
# de fazer "n.pib_bilhoes_usd *= fator" direto (que ignora o cap).
func apply_pib_multiplier(fator: float) -> void:
	if pib_inicial <= 0.0 or fator <= 1.0:
		# Pequenas perdas e crescimento mínimo passam direto
		pib_bilhoes_usd *= fator
		return
	var ratio: float = pib_bilhoes_usd / pib_inicial
	# Cap composto: em 4× já não cresce; em 6× há ligeira retração
	var hard_cap: float = pib_inicial * 6.0
	if pib_bilhoes_usd >= hard_cap:
		return  # ignora ganhos extras
	var growth_pct: float = fator - 1.0
	if ratio > 2.0:
		var damp: float = clamp(1.0 - (ratio - 2.0) / 4.0, 0.0, 1.0)
		growth_pct *= damp
	pib_bilhoes_usd *= (1.0 + growth_pct)

func process_turn_finances() -> void:
	var saldo: float = calc_saldo()
	var novo: float = tesouro + saldo
	if novo < 0.0:
		var deficit: float = -novo
		var limite_divida: float = pib_bilhoes_usd * 2.5
		var espaco_divida: float = max(0.0, limite_divida - divida_publica)
		if deficit <= espaco_divida:
			divida_publica += deficit
			tesouro = 0.0
			default_turnos = 0
		else:
			divida_publica += deficit
			tesouro = 0.0
			default_turnos += 1
			estabilidade_politica = max(0.0, estabilidade_politica - 8.0)
			felicidade            = max(0.0, felicidade            - 5.0)
			apoio_popular         = max(0.0, apoio_popular         - 6.0)
	else:
		tesouro = novo
		if divida_publica > 0.0 and tesouro > 10.0:
			var pagamento: float = min(tesouro * 0.10, divida_publica * 0.05)
			tesouro -= pagamento
			divida_publica = max(0.0, divida_publica - pagamento)
		default_turnos = 0
	tesouro = min(tesouro, pib_bilhoes_usd * 0.25)

	# Inflação dinâmica
	var gdp_q: float = max(1.0, pib_bilhoes_usd / 4.0)
	var deficit_ratio: float = max(0.0, -saldo) / gdp_q
	var mil_pct: float = float(militar.get("orcamento_militar_bilhoes", 0)) / max(1.0, pib_bilhoes_usd) * 100.0
	var mil_pressure: float = max(0.0, mil_pct - 5.0)
	var war_pressure: float = em_guerra.size() * 3.0
	var social_sum: float = 0.0
	for v in gasto_social.values(): social_sum += float(v)
	var social_pressure: float = max(0.0, (social_sum / gdp_q) - 0.5)
	var inflacao_target: float = 2.0 + deficit_ratio * 25.0 + mil_pressure * 1.5 + war_pressure + social_pressure * 10.0
	var shock: float = (randf() - 0.5) * 2.0
	inflacao = clamp(inflacao * 0.80 + inflacao_target * 0.20 + shock, 0.0, 100.0)

	# Inflação alta corrói felicidade e apoio
	if inflacao > 15.0:
		var penalty: float = (inflacao - 15.0) * 0.25
		felicidade    = max(0.0, felicidade    - penalty)
		apoio_popular = max(0.0, apoio_popular - penalty * 0.8)

# ─────────────────────────────────────────────────────────────────
# GOVERNO / POLÍTICA
# ─────────────────────────────────────────────────────────────────

func update_government(global_factor: float = 1.0) -> void:
	# Felicidade reage a crescimento + estabilidade
	var growth: float = (pib_bilhoes_usd - (pib_bilhoes_usd / (1.0 + global_factor))) / max(1.0, pib_bilhoes_usd)
	felicidade = clamp(felicidade + growth * 10.0 + (estabilidade_politica - 50.0) * 0.1, 0.0, 100.0)

	# Corrupção: reverte para média do regime
	var corr_base: float = 30.0
	if "DEMOCRA"   in regime_politico: corr_base = 20.0
	elif "SOCIAL"  in regime_politico: corr_base = 25.0
	elif "PARLAM"  in regime_politico: corr_base = 18.0
	elif "AUTORITA" in regime_politico: corr_base = 55.0
	elif "DITADURA" in regime_politico: corr_base = 65.0
	elif "TEOCRA"  in regime_politico: corr_base = 50.0
	elif "COMUNIS" in regime_politico: corr_base = 40.0
	corrupcao += (corr_base - corrupcao) * 0.03
	if randf() < 0.3: corrupcao += randf() * 2.0 - 1.0

	# Burocracia converge para 70
	burocracia_eficiencia += (70.0 - burocracia_eficiencia) * 0.05

	# ESTABILIDADE deriva de apoio + felicidade - corrupção - guerras
	var wars: int = em_guerra.size()
	var in_default: bool = default_turnos > 0
	var stab_target: float = clamp(
		apoio_popular * 0.40 + felicidade * 0.35 + (50.0 - corrupcao) * 0.25
		- wars * 5.0 + (-10.0 if in_default else 0.0),
		0.0, 100.0)
	estabilidade_politica = estabilidade_politica * 0.90 + stab_target * 0.10

	corrupcao = clamp(corrupcao, 0.0, 100.0)
	burocracia_eficiencia = clamp(burocracia_eficiencia, 0.0, 100.0)
	estabilidade_politica = clamp(estabilidade_politica, 0.0, 100.0)

func update_approval() -> void:
	var target: float = (estabilidade_politica * 0.5 + felicidade * 0.5) - corrupcao * 0.2
	target = clamp(target, 0.0, 100.0)
	apoio_popular = clamp(apoio_popular * 0.8 + target * 0.2, 0.0, 100.0)

# ─────────────────────────────────────────────────────────────────
# ELEIÇÕES
# ─────────────────────────────────────────────────────────────────

func is_democratic() -> bool:
	return ("DEMOCRACIA" in regime_politico) or ("REPUBLICA" in regime_politico) or ("PARLAMENTAR" in regime_politico)

func update_elections() -> void:
	if not is_democratic() or proxima_eleicao_turno == null:
		return
	if proxima_eleicao_turno > 0:
		proxima_eleicao_turno -= 1
	else:
		trigger_election()

func trigger_election() -> void:
	proxima_eleicao_turno = intervalo_eleicoes
	var chance: float = apoio_popular / 100.0
	if randf() < chance:
		apoio_popular += 5
		estabilidade_politica += 10
	else:
		apoio_popular -= 20
		estabilidade_politica -= 15
	apoio_popular = clamp(apoio_popular, 0.0, 100.0)
	estabilidade_politica = clamp(estabilidade_politica, 0.0, 100.0)

# ─────────────────────────────────────────────────────────────────
# HISTÓRICO
# ─────────────────────────────────────────────────────────────────

func record_history() -> void:
	_push_hist("estabilidade", estabilidade_politica)
	_push_hist("apoio_popular", apoio_popular)
	_push_hist("corrupcao", corrupcao)
	_push_hist("felicidade", felicidade)
	_push_hist("burocracia", burocracia_eficiencia)
	var u: Dictionary = militar.get("unidades", {})
	_push_hist("poder_militar", militar.get("poder_militar_global", 0))
	_push_hist("orcamento_militar", militar.get("orcamento_militar_bilhoes", 0))
	_push_hist("infantaria", u.get("infantaria", 0))
	_push_hist("tanques", u.get("tanques", 0))
	_push_hist("avioes", u.get("avioes", 0))
	_push_hist("navios", u.get("navios", 0))
	_push_hist("pib", pib_bilhoes_usd)
	_push_hist("populacao", populacao / 1_000_000.0)
	_push_hist("tesouro", tesouro)
	_push_hist("inflacao", inflacao)

func _push_hist(key: String, value: float) -> void:
	var arr: Array = historico.get(key, [])
	arr.append(snappedf(value, 0.1))
	if arr.size() > HIST_MAX: arr.pop_front()
	historico[key] = arr
