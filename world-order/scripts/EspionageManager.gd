class_name EspionageManager
extends RefCounted
## Sistema de espionagem com 8 operações.
## Calcula taxa de êxito baseado em intel vs segurança alvo.

const OPS := {
	"infiltrar_governo": {
		"nome": "Infiltrar Governo",
		"icon": "🏛",
		"custo": 30,
		"base_success": 0.65,
		"tipo": "intel",
		"descricao": "Espião revela dados clasificados do alvo (estabilidade, apoio, etc.)",
	},
	"infiltrar_militar": {
		"nome": "Infiltrar Forças Armadas",
		"icon": "🎖",
		"custo": 45,
		"base_success": 0.55,
		"tipo": "intel",
		"descricao": "Coleta dados militares (unidades, orçamento, base).",
	},
	"roubar_tecnologia": {
		"nome": "Roubo de Tecnologia",
		"icon": "💾",
		"custo": 70,
		"base_success": 0.40,
		"tipo": "tech",
		"descricao": "Tenta roubar uma tecnologia já pesquisada pelo alvo.",
	},
	"campanha_desinformacao": {
		"nome": "Desinformação",
		"icon": "📡",
		"custo": 25,
		"base_success": 0.75,
		"tipo": "influencia",
		"descricao": "Reduz apoio popular do alvo em -8%.",
	},
	"fomentar_protestos": {
		"nome": "Fomentar Protestos",
		"icon": "✊",
		"custo": 35,
		"base_success": 0.60,
		"tipo": "influencia",
		"descricao": "Reduz estabilidade e apoio do alvo (-5 ambos).",
	},
	"sabotar_infraestrutura": {
		"nome": "Sabotagem Industrial",
		"icon": "💥",
		"custo": 55,
		"base_success": 0.50,
		"tipo": "sabotagem",
		"descricao": "Danos econômicos: -3% do PIB do alvo.",
	},
	"assassinato_lider": {
		"nome": "Neutralização de Líder",
		"icon": "🎯",
		"custo": 90,
		"base_success": 0.30,
		"tipo": "sabotagem",
		"descricao": "Risco extremo. -15 estabilidade no alvo, +30 ódio.",
	},
	"tentar_golpe": {
		"nome": "Apoiar Golpe de Estado",
		"icon": "⚡",
		"custo": 130,
		"base_success": 0.20,
		"tipo": "golpe",
		"descricao": "Drástico. Estabilidade do alvo -25, apoio -20.",
	},
}

var engine

func _init(eng) -> void:
	engine = eng

# ─────────────────────────────────────────────────────────────────
# EXECUTAR OP
# ─────────────────────────────────────────────────────────────────

func execute(operator_code: String, op_id: String, target_code: String) -> Dictionary:
	var operator = engine.nations.get(operator_code)
	var target = engine.nations.get(target_code)
	if operator == null or target == null:
		return {"ok": false, "msg": "Alvo inválido"}
	if operator_code == target_code:
		return {"ok": false, "msg": "Não pode espionar a si mesmo"}
	if not OPS.has(op_id):
		return {"ok": false, "msg": "Operação inválida"}
	var op: Dictionary = OPS[op_id]
	var cost: int = int(op["custo"])
	if operator.tesouro < cost:
		return {"ok": false, "msg": "Tesouro insuficiente: $%dB" % cost}
	operator.tesouro -= cost
	# Taxa de sucesso ajustada por intel diff
	var intel_diff: float = (operator.intel_score - target.seguranca_intel * 5) * 0.02
	var chance: float = clamp(float(op["base_success"]) + intel_diff, 0.05, 0.95)
	var success: bool = randf() < chance
	var result := {"ok": true, "success": success, "op": op_id, "chance": chance}
	if success:
		result["msg"] = _apply_success(operator, target, op_id)
	else:
		result["msg"] = _apply_failure(operator, target, op_id)
	# Log
	if not operator.has_method("get"):
		operator.spy_ops_log = []
	operator.spy_ops_log.append({
		"turn": engine.current_turn,
		"target": target_code,
		"op": op_id,
		"success": success,
	})
	return result

func _apply_success(operator, target, op_id: String) -> String:
	match op_id:
		"infiltrar_governo":
			operator.intel_score += 8
			return "Dossiê do governo de %s desbloqueado." % target.nome
		"infiltrar_militar":
			operator.intel_score += 12
			return "Dossiê militar de %s desbloqueado." % target.nome
		"roubar_tecnologia":
			# Rouba uma tech aleatória
			var possessed: Array = target.tecnologias_concluidas
			var stealable: Array = []
			for t in possessed:
				if not (t in operator.tecnologias_concluidas):
					stealable.append(t)
			if stealable.is_empty():
				return "Alvo não tem tecnologia nova para roubar."
			var stolen: String = stealable[randi() % stealable.size()]
			operator.tecnologias_concluidas.append(stolen)
			return "Tecnologia roubada: %s" % stolen
		"campanha_desinformacao":
			target.apoio_popular = max(0.0, target.apoio_popular - 8)
			return "%s perdeu 8 pontos de apoio popular." % target.nome
		"fomentar_protestos":
			target.estabilidade_politica = max(0.0, target.estabilidade_politica - 5)
			target.apoio_popular = max(0.0, target.apoio_popular - 5)
			return "Protestos eclodem em %s. -5 estab, -5 apoio." % target.nome
		"sabotar_infraestrutura":
			target.pib_bilhoes_usd *= 0.97
			return "Sabotagem em %s. PIB -3%%." % target.nome
		"assassinato_lider":
			target.estabilidade_politica = max(0.0, target.estabilidade_politica - 15)
			operator.relacoes[target.codigo_iso] = clamp(float(operator.relacoes.get(target.codigo_iso, 0)) - 30, -100, 100)
			target.relacoes[operator.codigo_iso] = clamp(float(target.relacoes.get(operator.codigo_iso, 0)) - 30, -100, 100)
			return "Líder de %s neutralizado. Caos instalado." % target.nome
		"tentar_golpe":
			target.estabilidade_politica = max(0.0, target.estabilidade_politica - 25)
			target.apoio_popular = max(0.0, target.apoio_popular - 20)
			return "Golpe apoiado em %s. -25 estab, -20 apoio." % target.nome
	return "Operação bem-sucedida."

func _apply_failure(operator, target, op_id: String) -> String:
	# Penalidade: descoberta diplomática
	target.relacoes[operator.codigo_iso] = clamp(float(target.relacoes.get(operator.codigo_iso, 0)) - 20, -100, 100)
	operator.relacoes[target.codigo_iso] = clamp(float(operator.relacoes.get(target.codigo_iso, 0)) - 5, -100, 100)
	if op_id == "assassinato_lider" or op_id == "tentar_golpe":
		# Crise grave
		target.relacoes[operator.codigo_iso] = clamp(float(target.relacoes.get(operator.codigo_iso, 0)) - 30, -100, 100)
		return "Operação fracassou e foi exposta. Crise diplomática."
	return "Espião capturado. Relações com %s deterioram." % target.nome

# Helpers de UI
func get_op_with_chance(operator, target, op_id: String) -> Dictionary:
	var op: Dictionary = OPS.get(op_id, {}).duplicate()
	if op.is_empty(): return op
	var intel_diff: float = (operator.intel_score - target.seguranca_intel * 5) * 0.02
	op["chance_real"] = clamp(float(op["base_success"]) + intel_diff, 0.05, 0.95)
	return op
