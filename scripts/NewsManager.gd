class_name NewsManager
extends RefCounted
## Gerador procedural de notícias do mundo.
## Templates por categoria, tokens dinâmicos ({PAIS}, {N}), urgência.

const CATEGORIAS := {
	"tecnologia":  {"icon": "🔬", "color": Color(0.4, 0.85, 1)},
	"medicina":    {"icon": "🧬", "color": Color(0.6, 0.95, 0.6)},
	"militar":     {"icon": "⚔",  "color": Color(1, 0.4, 0.4)},
	"social":      {"icon": "👥", "color": Color(1, 0.85, 0.4)},
	"economia":    {"icon": "📈", "color": Color(0, 1, 0.5)},
	"politica":    {"icon": "🏛", "color": Color(0.85, 0.7, 1)},
	"clima":       {"icon": "🌍", "color": Color(0.4, 1, 0.85)},
	"descoberta":  {"icon": "💡", "color": Color(1, 0.9, 0.4)},
}

const TEMPLATES := {
	"tecnologia": [
		"{PAIS} apresenta novo chip de {N}nm e desafia liderança asiática.",
		"Empresa de {PAIS} alcança computação quântica de {N} qubits estáveis.",
		"Governo de {PAIS} investe US$ {N} bi em pesquisa de IA militar.",
		"Engenheiros de {PAIS} demonstram protótipo de drone-enxame autônomo.",
		"Startup em {PAIS} promete revolucionar baterias de estado sólido.",
		"Ministério de {PAIS} libera fundo de US$ {N} bi para foguetes reutilizáveis.",
		"Vazamento revela programa secreto de {PAIS} para hackear satélites rivais.",
	],
	"medicina": [
		"Vacina universal contra gripe sai de testes em {PAIS}.",
		"Pesquisadores de {PAIS} editam gene CRISPR pra tratar Alzheimer.",
		"Surto de doença respiratória atinge {PAIS} — OMS monitora.",
		"Transplante de coração impresso em 3D salva paciente em {PAIS}.",
		"Sistema único de saúde de {PAIS} é elogiado por cobertura universal.",
		"Antibiótico revolucionário desenvolvido em laboratório de {PAIS}.",
	],
	"militar": [
		"{PAIS} testa novo míssil hipersônico — alcance superior a {N} km.",
		"Exército de {PAIS} realiza maior exercício militar em décadas.",
		"Caças de {PAIS} interceptam aeronaves russas perto da fronteira.",
		"{PAIS} anuncia compra de {N} caças F-35 dos EUA.",
		"Submarino nuclear de {PAIS} entra em operação — rompe equilíbrio regional.",
		"Tensão sobe: {PAIS} mobiliza tropas em zona disputada.",
		"Drone de {PAIS} abatido em território vizinho — protestos diplomáticos.",
	],
	"social": [
		"Manifestações em {PAIS} reúnem mais de {N} mil pessoas.",
		"Greve geral paralisa serviços públicos em {PAIS} por {N} dias.",
		"Crise habitacional em {PAIS}: aluguel sobe {N}% no ano.",
		"Êxodo rural em {PAIS} cria inchaço urbano em capitais.",
		"Onda de violência em {PAIS} preocupa investidores estrangeiros.",
		"Movimento jovem em {PAIS} ganha força nas redes sociais.",
		"Censo aponta envelhecimento da população em {PAIS}.",
	],
	"economia": [
		"PIB de {PAIS} cresce {N}% — supera expectativas do mercado.",
		"Inflação em {PAIS} bate {N}% e Banco Central sobe juros.",
		"Bolsa de {PAIS} desaba {N}% após escândalo corporativo.",
		"{PAIS} anuncia abandono parcial do dólar em comércio bilateral.",
		"Reservas internacionais de {PAIS} atingem US$ {N} bi.",
		"Crise cambial em {PAIS} — moeda perde {N}% em uma semana.",
		"China e {PAIS} assinam mega-acordo de US$ {N} bi em commodities.",
	],
	"politica": [
		"Eleições em {PAIS} têm comparecimento recorde de {N}%.",
		"Presidente de {PAIS} sofre processo de impeachment.",
		"Coalizão governista em {PAIS} se rompe após votação polêmica.",
		"Oposição em {PAIS} convoca protestos contra reforma constitucional.",
		"{PAIS} anuncia reforma tributária — corta {N} impostos federais.",
		"ONU condena ações de {PAIS} em resolução não-vinculante.",
		"Diplomatas de {PAIS} expulsos após escândalo de espionagem.",
	],
	"clima": [
		"Furacão de categoria {N} se forma no Atlântico Norte.",
		"Onda de calor em {PAIS} bate recorde histórico de temperatura.",
		"Seca prolongada em {PAIS} ameaça produção agrícola.",
		"Branqueamento de coral em larga escala atinge {PAIS}.",
		"{PAIS} anuncia meta de neutralidade de carbono até 20{N}.",
		"Enchentes deixam {N} mil desabrigados em {PAIS}.",
		"Geleira de {PAIS} perde {N} km² em apenas um ano.",
	],
	"descoberta": [
		"Astrônomos de {PAIS} detectam exoplaneta com atmosfera de oxigênio.",
		"SETI registra sinal de rádio incomum vindo da constelação de Lyra.",
		"Paleontólogos de {PAIS} encontram fóssil de espécie inédita.",
		"Físicos de {PAIS} confirmam nova partícula subatômica.",
		"Submarino autônomo de {PAIS} mapeia abismo de {N} km no Pacífico.",
		"Arqueólogos descobrem cidade pré-histórica enterrada em {PAIS}.",
	],
}

var engine
var feed: Array = []  # últimas notícias geradas, max 50
const MAX_FEED: int = 50

func _init(eng) -> void:
	engine = eng

# Gera 3-5 notícias procedurais por turno
func generate_turn_news() -> Array:
	var generated: Array = []
	var num_news: int = randi_range(3, 5)
	# Em DEFCON baixo, tendência militar
	var militar_weight: float = 1.0
	if engine.defcon <= 2: militar_weight = 4.0
	elif engine.defcon <= 3: militar_weight = 2.5

	var weighted_cats: Array = []
	for cat in CATEGORIAS:
		var w: int = 1
		if cat == "militar": w = int(militar_weight)
		for i in range(w):
			weighted_cats.append(cat)

	for i in num_news:
		var cat: String = weighted_cats[randi() % weighted_cats.size()]
		var news = _generate_one(cat)
		if news.size() > 0:
			generated.append(news)
			feed.append(news)
	while feed.size() > MAX_FEED:
		feed.pop_front()
	return generated

func _generate_one(cat: String) -> Dictionary:
	var templates: Array = TEMPLATES.get(cat, [])
	if templates.is_empty(): return {}
	var template: String = templates[randi() % templates.size()]
	var text: String = template
	# Tokens
	if "{PAIS}" in text:
		text = text.replace("{PAIS}", _random_country_name())
	if "{N}" in text:
		text = text.replace("{N}", str(_random_number_for_template(template)))
	var meta: Dictionary = CATEGORIAS[cat]
	return {
		"category": cat,
		"icon": meta["icon"],
		"color": meta["color"],
		"text": text,
		"turn": engine.current_turn,
	}

func _random_country_name() -> String:
	var codes: Array = engine.nations.keys()
	if codes.is_empty(): return "—"
	# Pesa nações grandes (mais "noticiosas")
	var weighted: Array = []
	for code in codes:
		var n = engine.nations[code]
		var weight: int = 1
		if n.pib_bilhoes_usd >= 5000: weight = 6
		elif n.pib_bilhoes_usd >= 1000: weight = 4
		elif n.pib_bilhoes_usd >= 200: weight = 2
		for i in range(weight):
			weighted.append(code)
	var picked_code: String = weighted[randi() % weighted.size()]
	return engine.nations[picked_code].nome

func _random_number_for_template(template: String) -> int:
	# Heurísticas
	if "%" in template:
		return randi_range(1, 25)
	if "qubits" in template:
		return randi_range(50, 5000)
	if "nm" in template:
		return [3, 5, 7, 14][randi() % 4]
	if "categoria" in template:
		return randi_range(3, 5)
	if "km" in template:
		if "ciclone" in template or "geleira" in template:
			return randi_range(1, 10)
		return randi_range(500, 5000)
	if "mil pessoas" in template or "mil desabrigados" in template:
		return randi_range(5, 500)
	if "dias" in template:
		return randi_range(1, 14)
	if "20{N}" in template:  # ano
		return randi_range(30, 60)
	if "qubits" in template or "F-35" in template:
		return randi_range(20, 200)
	# default: bilhões
	return randi_range(1, 200)
