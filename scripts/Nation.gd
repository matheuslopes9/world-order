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

# ── CONFIANÇA DO INVESTIDOR / IED (Investimento Estrangeiro Direto) ──
# 0-100: sobe com baixa corrupção + estabilidade + burocracia; cai com
# corrupção alta e guerra. Alta confiança = empresas ENTRAM (bônus de PIB);
# baixa = empresas SAEM (êxodo de capital, PIB encolhe).
var confianca_investidor: float = 50.0
var empresas_sairam: int = 0        # acumulado no jogo (p/ manchetes)
var tesouro_desviado_total: float = 0.0  # total roubado pela corrupção (p/ UI/eventos)

# Eleições
var proxima_eleicao_turno = null  # Variant: int ou null
var intervalo_eleicoes: int = 20

# Recursos & Militar (Dictionaries)
var recursos: Dictionary = {}
var militar: Dictionary = {}
var geografia: Dictionary = {}

# Pesquisa & Tech
var tecnologias_concluidas: Array = []
var pesquisa_atual = null  # LEGADO: { id, progresso } ou null — migrado p/ pesquisa_por_ministerio
var velocidade_pesquisa: float = 1.0

# ── GABINETE DE MINISTROS (6 pastas) ──
# Cada pasta: {nivel:1-5, xp:float, verba:float(P&D/turno)}
const MINISTERIOS := ["casa_civil", "fazenda", "seguranca", "saude", "educacao", "exterior"]
const MIN_NIVEL_MAX: int = 5
# Limiares de XP acumulado p/ chegar ao nível N (índice = nível-1)
const MIN_XP_LIMIARES := [0.0, 100.0, 300.0, 700.0, 1500.0]
var ministerios: Dictionary = {}
# Filas de pesquisa PARALELAS: pasta -> { id, progresso, tempo_total } (ou ausente)
var pesquisa_por_ministerio: Dictionary = {}

func _init_ministerios() -> void:
	ministerios.clear()
	for m in MINISTERIOS:
		ministerios[m] = {"nivel": 1, "xp": 0.0, "verba": 0.0}

## Nível atual (1-5) de uma pasta.
func ministry_level(pasta: String) -> int:
	if not ministerios.has(pasta):
		return 1
	return int(ministerios[pasta].get("nivel", 1))

## Multiplicador de força das ações da pasta pelo nível (nv1=1.0 … nv5≈1.6).
func ministry_action_mult(pasta: String) -> float:
	return 1.0 + 0.15 * float(ministry_level(pasta) - 1)

## Credita XP e re-avalia o nível (sobe ao cruzar limiar). Retorna true se subiu.
func add_ministry_xp(pasta: String, x: float) -> bool:
	if not ministerios.has(pasta):
		return false
	var d: Dictionary = ministerios[pasta]
	d["xp"] = float(d.get("xp", 0.0)) + x
	var nv: int = int(d.get("nivel", 1))
	var subiu := false
	while nv < MIN_NIVEL_MAX and float(d["xp"]) >= MIN_XP_LIMIARES[nv]:
		nv += 1
		subiu = true
	d["nivel"] = nv
	return subiu

## Quantas trilhas de pesquisa simultâneas — desbloqueadas pelo nível da Casa Civil.
## Nível 1→2 trilhas, crescendo até 6 no nível máximo. Investir na Casa Civil
## acelera TODA a agenda científica (mais ministérios pesquisando em paralelo),
## permitindo que uma nação focada em ciência complete a árvore e vire potência.
func research_slots() -> int:
	return clampi(ministry_level("casa_civil") + 1, 2, 6)

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

	# Gabinete de ministros (6 pastas, nível 1)
	_init_ministerios()

	# Confiança do investidor inicial: derivada das instituições de partida
	confianca_investidor = clamp(55.0 - corrupcao * 0.6 + (estabilidade_politica - 50.0) * 0.3, 10.0, 90.0)

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
	# Bônus acumulativo por techs concluídas: +0.5% cada, cap em +25% (50 techs)
	# Reflete vantagem permanente de progresso científico — Brasil que descobre cura
	# pra tetraplegia ganha bônus em saúde + biotecnologia daí em diante.
	var tech_bonus: float = clamp(tecnologias_concluidas.size() * 0.005, 0.0, 0.25)
	base *= (1.0 + tech_bonus)
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

# Receita de exportação de recursos (separada pra UI mostrar o breakdown
# e o efeito dos choques de commodities em tempo real)
func calc_receita_exportacao() -> float:
	var vals: Array = recursos.values() if recursos else []
	var avg_resource: float = 30.0
	if vals.size() > 0:
		var sum: float = 0.0
		for v in vals: sum += float(v)
		avg_resource = sum / vals.size()
	return pib_bilhoes_usd * (avg_resource / 100.0) * 0.02 / 4.0 * commodity_multiplier

func calc_receita() -> float:
	var tax_rate := calc_tax_rate()
	var impostos: float = (pib_bilhoes_usd * tax_rate / 4.0) + 5.0
	var export_bonus: float = calc_receita_exportacao()
	var bur_pct: float = (burocracia_eficiencia - 50.0) / 50.0
	var cor_pct: float = (50.0 - corrupcao) / 50.0
	var eficiencia: float = 1.0 + (bur_pct * 0.075) + (cor_pct * 0.075)
	var infl_penalty: float = max(0.0, (inflacao - 15.0) / 100.0)
	var infl_factor: float = max(0.5, 1.0 - infl_penalty * 0.6)
	return (impostos + export_bonus) * eficiencia * infl_factor

func calc_despesas() -> float:
	var mil_budget: float = float(militar.get("orcamento_militar_bilhoes", 0)) / 4.0
	# 8% do PIB (antes 10%): com 10%, potências com orçamento militar alto
	# (EUA) tinham déficit ESTRUTURAL e faliam até sem fazer nada
	var gov_spend: float = pib_bilhoes_usd * 0.08 / 4.0
	var interest: float = divida_publica * 0.025
	var social_sum: float = 0.0
	for v in gasto_social.values(): social_sum += float(v)
	var social_spend: float = social_sum / 4.0
	# Verba de P&D alocada aos ministérios (custo trimestral)
	var rd_spend: float = 0.0
	for m in ministerios.values():
		rd_spend += float(m.get("verba", 0.0))
	rd_spend /= 4.0
	return mil_budget + gov_spend + interest + social_spend + rd_spend

func calc_saldo() -> float:
	return calc_receita() - calc_despesas()

# PIB per capita em dólares (proxy de nível de desenvolvimento)
func pib_per_capita() -> float:
	if populacao <= 0:
		return 0.0
	return pib_bilhoes_usd * 1_000_000_000.0 / float(populacao)

# MODELO DE CRESCIMENTO POR CONVERGÊNCIA (economia real de catch-up):
# países longe da fronteira tecnológica mundial crescem MAIS rápido — SE
# tiverem instituições decentes (China 1990-2020, Coreia 1960-2000).
# Países já na fronteira crescem devagar (economias maduras).
# Isso substitui o antigo soft-cap sobre pib_inicial, que impedia qualquer
# nação de crescer mais que ~4-6× — matando a fantasia central do jogo
# ("investimentos corretos podem construir uma potência mundial").
# frontier_pib_pc é cacheado pelo GameEngine a cada turno.
var frontier_pib_pc: float = 0.0
# Multiplicador de preço das commodities (choques globais: crise energética
# dobra o valor de exportação de quem tem petróleo/gás; default 1.0)
var commodity_multiplier: float = 1.0

func update_pib(global_factor: float = 1.0) -> void:
	var stab: float = estabilidade_politica / 100.0
	var happy: float = felicidade / 100.0
	var corr: float = corrupcao / 100.0
	var bur: float = burocracia_eficiencia / 100.0
	var wars: int = em_guerra.size()
	# Base institucional (qualidade do governo determina o crescimento estrutural)
	var growth: float = 0.008 * global_factor * (0.5 + stab * 0.5 + happy * 0.3 + bur * 0.2 - corr * 0.4)
	# Convergência: bônus de catch-up proporcional à distância da fronteira
	# e à qualidade institucional — até +1.0%/trimestre (milagre econômico)
	if frontier_pib_pc > 0.0:
		var pc_ratio: float = clamp(pib_per_capita() / frontier_pib_pc, 0.0, 1.0)
		var gap: float = 1.0 - pc_ratio
		var inst_quality: float = clamp(stab * 0.5 + bur * 0.3 + (1.0 - corr) * 0.4 - 0.2, 0.0, 1.0)
		var conv: float = gap * 0.010 * inst_quality
		# ARMADILHA DA RENDA MÉDIA: na faixa 30-70% da fronteira o catch-up
		# enfraquece (até -60% no pico, aos 50%) — SALVO capacidade de
		# inovação: 25+ techs escapam da armadilha (Coreia escapou;
		# Brasil/México ficaram presos). Sem isto, "pobre + estável" era
		# milagre infinito: Iêmen cresceu 29.000× em playtest de 1000 jogos.
		if pc_ratio > 0.30 and pc_ratio < 0.70:
			var depth: float = clamp(1.0 - abs(pc_ratio - 0.5) / 0.2, 0.0, 1.0)
			var escape: float = clamp(tecnologias_concluidas.size() / 25.0, 0.0, 1.0)
			conv *= 1.0 - 0.6 * depth * (1.0 - escape)
		growth += conv
		# Na fronteira (gap < 15%): economia madura desacelera
		if gap < 0.15:
			growth *= 0.75
	growth -= wars * 0.005
	if inflacao > 15.0: growth -= (inflacao - 15.0) * 0.0008
	if tesouro <= 0.0: growth -= 0.003
	if divida_publica > pib_bilhoes_usd * 1.5: growth -= 0.004
	growth += min(0.005, tecnologias_concluidas.size() * 0.0003)
	# INVESTIMENTO ESTRANGEIRO (IED): confiança alta atrai capital (+cresc.),
	# baixa provoca ÊXODO de empresas (-cresc.). Centro em 50 (neutro):
	# confiança 100 → +0.4%/tri; confiança 0 → -0.5%/tri (fuga dói mais).
	var ied_delta: float = (confianca_investidor - 50.0) / 50.0  # -1 … +1
	if ied_delta >= 0.0:
		growth += ied_delta * 0.004
	else:
		growth += ied_delta * 0.005  # êxodo pesa mais que influxo
	growth = clamp(growth, -0.03, 0.035)
	pib_bilhoes_usd *= (1.0 + growth)

	# Crescimento populacional (transição demográfica: pobres crescem mais)
	if populacao > 0:
		var pop_rate: float = 0.004  # ~1.6%/ano em países pobres
		if frontier_pib_pc > 0.0:
			var wealth: float = clamp(pib_per_capita() / frontier_pib_pc, 0.0, 1.0)
			pop_rate = lerpf(0.004, 0.0003, wealth)  # ricos ~0.12%/ano
		populacao = int(populacao * (1.0 + pop_rate))

# Helper público: aplica multiplicador no PIB com retornos decrescentes
# perto da fronteira (estímulos rendem menos em economias já maduras).
# Perdas (fator <= 1.0) passam na íntegra.
func apply_pib_multiplier(fator: float) -> void:
	if fator <= 1.0:
		pib_bilhoes_usd *= fator
		return
	var growth_pct: float = fator - 1.0
	if frontier_pib_pc > 0.0:
		var gap: float = clamp(1.0 - pib_per_capita() / frontier_pib_pc, 0.0, 1.0)
		# gap 0 (fronteira) → 12% do efeito; gap ≥ 0.67 → efeito integral.
		# Piso duro: sem ele, spam de estímulos compunha PIB a +20%/ano
		# eternamente (Japão chegou a 309.000× no playtest automatizado)
		growth_pct *= lerpf(0.12, 1.0, clamp(gap * 1.5, 0.0, 1.0))
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
	# ── ROUBO DO TESOURO PELA CORRUPÇÃO ──
	# Acima de 50% de corrupção, uma fração do tesouro é DESVIADA a cada turno.
	# Escala de ~0% (aos 50%) até ~4%/turno (aos 100%). Reversível: baixar a
	# corrupção estanca a sangria. Dá ao jogador o "sinto o dinheiro sumindo".
	if corrupcao > 50.0 and tesouro > 0.0:
		var taxa_desvio: float = (corrupcao - 50.0) / 50.0 * 0.04  # 0 → 0.04
		var desviado: float = tesouro * taxa_desvio
		tesouro = max(0.0, tesouro - desviado)
		tesouro_desviado_total += desviado

	# Cap anti-acúmulo infinito, com PISO de $150B: sem o piso, o boost de
	# tesouro dado a nações pequenas (tier difícil) era apagado no 1º turno
	# (ex.: PIB $10B → cap $2.5B destruía os $200B+ de boost inicial).
	tesouro = min(tesouro, max(150.0, pib_bilhoes_usd * 0.25))

	# Inflação dinâmica
	var gdp_q: float = max(1.0, pib_bilhoes_usd / 4.0)
	var deficit_ratio: float = max(0.0, -saldo) / gdp_q
	var mil_pct: float = float(militar.get("orcamento_militar_bilhoes", 0)) / max(1.0, pib_bilhoes_usd) * 100.0
	var mil_pressure: float = max(0.0, mil_pct - 5.0)
	var war_pressure: float = em_guerra.size() * 3.0
	var social_sum: float = 0.0
	for v in gasto_social.values(): social_sum += float(v)
	# Pressão social suavizada (×4, antes ×10): com gasto social escalado ao PIB
	# a pressão vira um custo gerenciável, não uma sentença de hiperinflação
	var social_pressure: float = max(0.0, (social_sum / gdp_q) - 0.5)
	var inflacao_target: float = 2.0 + deficit_ratio * 25.0 + mil_pressure * 1.5 + war_pressure + social_pressure * 4.0
	# Perk "Banco Central Sólido": subidas de inflação são amortecidas em N%
	# (quedas passam na íntegra — o perk só protege contra alta)
	var decay_pct: float = float(get_meta("perk_inflation_decay", 0)) / 100.0
	if decay_pct > 0.0 and inflacao_target > inflacao:
		inflacao_target = inflacao + (inflacao_target - inflacao) * (1.0 - decay_pct)
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

	# CONFIANÇA DO INVESTIDOR: alvo puxado por instituições. Corrupção é o maior
	# repelente de capital; estabilidade e burocracia atraem. Guerra afugenta.
	var wars_ci: int = em_guerra.size()
	var conf_target: float = clamp(
		55.0
		- corrupcao * 0.75          # corrupção 70% já derruba ~52 pts
		+ (estabilidade_politica - 50.0) * 0.35
		+ (burocracia_eficiencia - 50.0) * 0.25
		- wars_ci * 8.0
		- max(0.0, inflacao - 15.0) * 0.4,
		0.0, 100.0)
	# Confiança se move devagar (capital tem inércia — decisões de anos)
	confianca_investidor = clamp(confianca_investidor * 0.88 + conf_target * 0.12, 0.0, 100.0)

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
# MILITAR
# ─────────────────────────────────────────────────────────────────

# Poder militar efetivo derivado dos DADOS REAIS (orçamento, unidades,
# arsenal). O campo "poder_militar_global" não existe em nations.json —
# antes só o jogador o populava via ações, distorcendo o ranking de poder.
func get_military_power() -> float:
	var explicit: float = float(militar.get("poder_militar_global", 0))
	var budget: float = float(militar.get("orcamento_militar_bilhoes", 0))
	var nukes: float = float(militar.get("armas_nucleares", 0))
	var carriers: float = float(militar.get("porta_avioes", 0))
	var u: Dictionary = militar.get("unidades", {})
	var units_score: float = (
		float(u.get("infantaria", 0)) / 100_000.0
		+ float(u.get("tanques", 0)) / 1_000.0
		+ float(u.get("avioes", 0)) / 500.0
		+ float(u.get("navios", 0)) / 100.0
	)
	return explicit + budget * 0.5 + nukes * 0.01 + carriers * 2.0 + units_score

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
		# Derrota eleitoral dói, mas não é sentença de morte
		# (antes -20/-15 criava espiral fatal para nações frágeis)
		apoio_popular -= 15
		estabilidade_politica -= 10
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
