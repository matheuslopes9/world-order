class_name AdvisorManager
extends RefCounted
## Sistema de Conselheiros — 4 figuras que dão input em decisões históricas.
##
## Cada conselheiro tem um viés (peso por categoria) que define qual choice
## ele recomenda. Aparece no modal de decisão histórica como "💬 X recomenda:..."
##
## Não é um sistema de IA inteligente — é heurístico baseado em palavras-chave
## das choices (custo militar, palavra "guerra", "paz", "sanção", etc).

# Definições dos 4 conselheiros
const ADVISORS := [
	{
		"id": "chanceler",
		"name": "Chanceler",
		"icon": "🤵",
		"bias": "diplomatico",
		"color": Color(0.3, 0.7, 1, 1),
		"intro": "Pondera consequências diplomáticas e relações internacionais.",
	},
	{
		"id": "general",
		"name": "General",
		"icon": "🎖",
		"bias": "militar",
		"color": Color(1, 0.4, 0.4, 1),
		"intro": "Avalia ameaças e preconiza força quando necessário.",
	},
	{
		"id": "economista",
		"name": "Economista",
		"icon": "💼",
		"bias": "economico",
		"color": Color(0.3, 1, 0.6, 1),
		"intro": "Foca em custos, ROI e estabilidade fiscal.",
	},
	{
		"id": "midia",
		"name": "Chefe de Imprensa",
		"icon": "📺",
		"bias": "popular",
		"color": Color(1, 0.78, 0.3, 1),
		"intro": "Calcula impacto na opinião pública e narrativa.",
	},
]

# Recomenda 1 choice de uma lista (com base no bias do conselheiro)
# Retorna: { advisor: id, choice_id: id, confidence: 0-1, reason: text }
static func recommend(advisor_bias: String, choices: Array, event: Dictionary) -> Dictionary:
	if choices.is_empty():
		return {"choice_id": "", "confidence": 0, "reason": ""}
	var best_idx: int = 0
	var best_score: float = -999.0
	for i in choices.size():
		var ch: Dictionary = choices[i]
		var score: float = _score_choice(advisor_bias, ch, event)
		if score > best_score:
			best_score = score
			best_idx = i
	var winner: Dictionary = choices[best_idx]
	return {
		"choice_id": winner.get("id", ""),
		"choice_label": winner.get("label", ""),
		"confidence": clamp(best_score / 10.0, 0.1, 1.0),
		"reason": _explain_recommendation(advisor_bias, winner, event),
	}

static func _score_choice(bias: String, choice: Dictionary, event: Dictionary) -> float:
	var label: String = String(choice.get("label", "")).to_lower()
	var effects: Dictionary = choice.get("effects", {})
	var player_eff: Dictionary = effects.get("_player", {})
	var score: float = 0.0
	# Sinais textuais
	var has_war: bool = "guerra" in label or "militar" in label or "tropa" in label or "invasao" in label or "ataque" in label
	var has_peace: bool = "paz" in label or "diplomac" in label or "negocia" in label or "acordo" in label or "tratado" in label
	var has_econ: bool = "tesouro" in label or "investi" in label or "custo" in label or "ec" in label
	var has_neutral: bool = "neutral" in label or "esperar" in label or "wait" in label or "absorver" in label
	# Pesos por bias
	match bias:
		"diplomatico":
			if has_peace: score += 6.0
			if has_war: score -= 5.0
			if has_neutral: score += 3.0
			# Penaliza efeitos negativos em apoio popular (instabilidade externa)
			if float(player_eff.get("apoio_popular", 0)) < 0:
				score -= 1.0
		"militar":
			if has_war: score += 6.0
			if has_peace: score -= 4.0
			if has_neutral: score -= 3.0
			# Bônus por eventos de DEFCON baixo
			if event.get("categories", []).has("guerra"):
				score += 2.0
		"economico":
			# Foca em custo
			var tesouro_delta: float = float(player_eff.get("tesouro", 0))
			score += tesouro_delta * 0.05  # quanto menos perda, melhor
			var pib_factor: float = float(player_eff.get("pib_fator", 1.0))
			score += (pib_factor - 1.0) * 50.0  # bônus se ganha PIB
			if has_war: score -= 4.0  # guerras são caras
			if has_neutral: score += 2.0
		"popular":
			score += float(player_eff.get("apoio_popular", 0)) * 1.5
			score += float(player_eff.get("felicidade", 0)) * 1.0
			score += float(player_eff.get("estabilidade_fator", 0)) * 0.5
			if has_neutral: score -= 1.0  # mídia não gosta de "ficar em cima do muro"
	return score

static func _explain_recommendation(bias: String, choice: Dictionary, _event: Dictionary) -> String:
	var label: String = String(choice.get("label", ""))
	match bias:
		"diplomatico":
			return "Esta opção preserva nossas alianças e abre canais diplomáticos."
		"militar":
			return "Demonstra força e disuade adversários. Nossa segurança depende disso."
		"economico":
			var eff: Dictionary = choice.get("effects", {}).get("_player", {})
			var tesouro: float = float(eff.get("tesouro", 0))
			if tesouro < -100:
				return "Atenção ao custo elevado, mas pode trazer retorno fiscal."
			return "É a opção mais viável fiscalmente. Mantém o tesouro estável."
		"popular":
			return "Esta escolha tem o melhor impacto na opinião pública e legado."
	return "Recomendado."

# Retorna recomendações de TODOS os 4 conselheiros para um evento
static func get_all_recommendations(choices: Array, event: Dictionary) -> Array:
	var out: Array = []
	for advisor in ADVISORS:
		var rec: Dictionary = recommend(advisor.get("bias", ""), choices, event)
		out.append({
			"advisor_id": advisor.get("id"),
			"advisor_name": advisor.get("name"),
			"advisor_icon": advisor.get("icon"),
			"advisor_color": advisor.get("color"),
			"recommendation": rec,
		})
	return out
