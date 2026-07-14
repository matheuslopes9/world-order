class_name PortraitView
extends Control
## Retratos vetoriais flat gerados proceduralmente — o "elenco" do jogo.
##
## Cada nação tem um gabinete próprio e determinístico (mesmo rosto sempre):
## presidente, general, ministro(a) da economia, chanceler, chefe de intel e
## âncora do noticiário WON. Tom de pele, cabelo, vestimenta e acessórios
## seguem distribuições etno-regionais (15 regiões) para representar a
## diversidade real de cada povo — sem caricatura: estilo geométrico flat.
##
## Uso:  var pv := PortraitView.make("BR", "general", "bravo", 128)
##       add_child(pv)   # ou pv.set_expression("feliz") depois

# ───────────────────────────── DADOS ─────────────────────────────

const SKIN := ["f7d9c4", "f0c8a8", "e6b48e", "d9a26b", "c98a52", "aa6f43", "8d5a2f", "70452a", "573520", "3f281a"]
const HAIRC := ["17161a", "3b2a1e", "5d4430", "c9a35a", "8e4a2c"]  # preto, cast.escuro, castanho, loiro, ruivo
const GREYC := ["9b9b9b", "d8d8d8", "6f6f74"]

## 15 regiões etno-culturais — cobre as 195 nações do jogo.
const REGIONS := {
	"europa_norte": "DK FI IS NO SE EE LV LT IE GB NL DE BE LU AT CH LI",
	"europa_sul": "PT ES IT GR MT CY AD MC SM VA HR SI BA ME MK AL XK RS FR",
	"europa_leste": "PL CZ SK HU RO BG BY UA MD RU",
	"cauca": "AM AZ GE TR",
	"africa_norte": "DZ EG LY MA TN MR SD",
	"africa_sub": "AO BF BI BJ BW CD CF CG CI CM CV DJ ER ET GH GM GN GQ KE KM LR LS MG ML MU MW MZ NA NE NG RW SC SL SN SO SS ST SZ TD TG TZ UG ZA ZM ZW",
	"oriente_medio": "AE BH IL IQ IR JO KW LB OM PS QA SA SY YE",
	"asia_central": "KZ KG TJ TM UZ MN AF",
	"asia_sul": "IN PK BD LK NP BT MV",
	"asia_leste": "CN JP KP KR TW",
	"asia_sudeste": "ID MY PH TH VN KH LA MM BN SG TL",
	"caribe": "AG BB BS CU DM DO GD HT JM KN LC TT VC BZ GY SR",
	"latam": "AR BO BR CL CO CR EC GT HN MX NI PA PE PY SV UY VE",
	"anglo": "US CA AU NZ",
	"pacifico": "FJ FM KI MH NR PG PW SB TO TV VU WS",
}

## Pesos dos 10 tons de pele por região (90% regional + 10% uniforme p/ inclusão).
const TONE_W := {
	"europa_norte": [26, 30, 22, 10, 3, 2, 2, 2, 2, 1],
	"europa_sul": [10, 22, 28, 20, 8, 4, 3, 2, 2, 1],
	"europa_leste": [22, 30, 24, 12, 4, 2, 2, 2, 1, 1],
	"cauca": [8, 18, 28, 24, 10, 5, 3, 2, 1, 1],
	"africa_norte": [1, 3, 8, 18, 24, 20, 14, 7, 3, 2],
	"africa_sub": [0, 1, 1, 2, 4, 8, 16, 24, 24, 20],
	"oriente_medio": [2, 6, 14, 22, 24, 16, 9, 4, 2, 1],
	"asia_central": [4, 12, 24, 26, 16, 9, 5, 2, 1, 1],
	"asia_sul": [0, 2, 5, 12, 20, 24, 18, 11, 5, 3],
	"asia_leste": [10, 30, 34, 18, 5, 1, 1, 1, 0, 0],
	"asia_sudeste": [2, 8, 18, 26, 22, 12, 7, 3, 1, 1],
	"caribe": [1, 3, 5, 8, 10, 12, 16, 18, 15, 12],
	"latam": [4, 10, 16, 18, 16, 12, 10, 7, 4, 3],
	"anglo": [14, 16, 14, 10, 8, 8, 8, 8, 7, 7],
	"pacifico": [0, 2, 4, 8, 14, 20, 22, 16, 9, 5],
}

## Pesos de cor de cabelo [preto, cast.escuro, castanho, loiro, ruivo].
const HAIR_W := {
	"europa_norte": [6, 18, 26, 34, 16],
	"europa_sul": [30, 34, 24, 9, 3],
	"europa_leste": [16, 30, 30, 18, 6],
	"cauca": [42, 34, 18, 4, 2],
	"africa_norte": [60, 30, 8, 1, 1],
	"africa_sub": [86, 12, 1, 0, 1],
	"oriente_medio": [62, 28, 8, 1, 1],
	"asia_central": [55, 30, 12, 2, 1],
	"asia_sul": [75, 20, 4, 0, 1],
	"asia_leste": [80, 17, 2, 0, 1],
	"asia_sudeste": [78, 18, 3, 0, 1],
	"caribe": [70, 22, 6, 1, 1],
	"latam": [40, 30, 20, 7, 3],
	"anglo": [25, 25, 25, 18, 7],
	"pacifico": [70, 24, 4, 1, 1],
}

## Probabilidade de cabelo crespo/cacheado por região.
const AFRO_P := {
	"africa_sub": 0.85, "caribe": 0.70, "pacifico": 0.50, "anglo": 0.25,
	"latam": 0.30, "africa_norte": 0.25, "oriente_medio": 0.12, "asia_sul": 0.10,
}

## Nações de maioria muçulmana — habilita hijab (opcional) no elenco feminino.
const MUSLIM := "DZ BH BD BN BF TD KM DJ EG GM GN ID IR IQ JO KZ KW KG LB LY MY MV ML MR MA NE OM PK PS QA SA SN SL SO SD SY TJ TM TN TR AE UZ YE AF AZ AL XK BA"

## Configuração visual de cada papel do elenco.
const ROLES := {
	"presidente": {"suit": "1e2f4d", "shirt": "f2f2f2", "tie": true, "bg": "263450", "idade": "velho", "pin": true},
	"general": {"suit": "4a5230", "shirt": "3a4126", "tie": false, "bg": "2c301f", "idade": "velho", "cap": true, "epaulettes": true},
	"economia": {"suit": "5b2333", "shirt": "f2f2f2", "tie": true, "bg": "38222e", "idade": "medio", "glasses_p": 0.6, "pin": true},
	"chanceler": {"suit": "39434f", "shirt": "f2f2f2", "tie": true, "bg": "223640", "idade": "medio", "pin": true},
	"intel": {"suit": "23262b", "shirt": "15161a", "tie": false, "bg": "191b1f", "idade": "medio", "sunglasses": true},
	"ancora": {"suit": "2464a4", "shirt": "f2f2f2", "tie": true, "bg": "142c47", "idade": "jovem", "mic": true, "glasses_p": 0.25},
	# ── Gabinete (6 pastas) ──
	"casa_civil": {"suit": "3a3f47", "shirt": "f2f2f2", "tie": true, "bg": "20242b", "idade": "medio", "pin": true, "glasses_p": 0.35},
	"seguranca": {"suit": "1c2733", "shirt": "10151c", "tie": false, "bg": "141b24", "idade": "velho", "badge": true, "epaulettes": true},
	"saude": {"suit": "e8ecef", "shirt": "f7f9fa", "tie": true, "bg": "1c2e33", "idade": "medio", "coat": true, "glasses_p": 0.45},
	"educacao": {"suit": "2e3a55", "shirt": "f2f2f2", "tie": true, "bg": "202838", "idade": "medio", "glasses_p": 0.7, "pin": true},
}

const TIE_PALETTE := ["a32638", "2b4a6f", "6e2f5d", "1f6e5a", "b07020", "394252", "7a1f2b", "23557d"]

static var _region_lookup: Dictionary = {}
static var _flag_cache: Dictionary = {}

# ─────────────────────────── ESTADO ───────────────────────────

var iso: String = "BR"
var role: String = "presidente"
var expression: String = "neutro"  # neutro | feliz | preocupado | bravo | urgente
var f: Dictionary = {}

# ─────────────────────────── API ───────────────────────────

static func make(p_iso: String, p_role: String, p_expr: String = "neutro", px: float = 128.0) -> PortraitView:
	var pv := PortraitView.new()
	pv.custom_minimum_size = Vector2(px, px * 1.2)
	pv.setup(p_iso, p_role, p_expr)
	return pv

func setup(p_iso: String, p_role: String, p_expr: String = "neutro") -> void:
	iso = p_iso
	role = p_role if ROLES.has(p_role) else "presidente"
	expression = p_expr
	f = features_for(iso, role)
	queue_redraw()

func set_expression(e: String) -> void:
	if e != expression:
		expression = e
		queue_redraw()

static func region_of(p_iso: String) -> String:
	if _region_lookup.is_empty():
		for reg in REGIONS:
			for code in String(REGIONS[reg]).split(" ", false):
				_region_lookup[code] = reg
	return _region_lookup.get(p_iso, "anglo")

## Gera as feições de forma DETERMINÍSTICA: mesma nação+papel = mesmo rosto.
static func features_for(p_iso: String, p_role: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(p_iso + "|" + p_role + "|v1")
	var reg := region_of(p_iso)
	var rc: Dictionary = ROLES.get(p_role, ROLES["presidente"])
	var ft := {"region": reg}

	ft["female"] = rng.randf() < 0.45
	# tom de pele: 90% distribuição regional + 10% uniforme (gabinetes diversos)
	var tone: int
	if rng.randf() < 0.10:
		tone = rng.randi_range(0, 9)
	else:
		tone = _wpick(rng, TONE_W[reg])
	ft["tone"] = tone
	ft["skin"] = Color(SKIN[tone])

	var idade: String = rc.get("idade", "medio")
	ft["velho"] = idade == "velho"
	ft["hair_color"] = Color(HAIRC[_wpick(rng, HAIR_W[reg])])
	var grey_p: float = {"velho": 0.55, "medio": 0.18, "jovem": 0.03}[idade]
	if rng.randf() < grey_p:
		ft["hair_color"] = Color(GREYC[rng.randi_range(0, 2)])

	# estilo de cabelo
	var afro_p: float = AFRO_P.get(reg, 0.05)
	var muslim := (" " + MUSLIM + " ").contains(" " + p_iso + " ")
	var style := "curto"
	if ft["female"]:
		if muslim and rng.randf() < 0.55:
			style = "hijab"
		else:
			style = _wpick_named(rng,
				["longo", "coque", "curto", "ondulado", "cacheado", "afro"],
				[28, 22, 14, 14, 22.0 * afro_p + 6.0, 30.0 * afro_p])
	else:
		if p_iso == "IN" and rng.randf() < 0.12:
			style = "turbante"
		else:
			style = _wpick_named(rng,
				["curto", "raspado", "risca", "ondulado", "careca", "cacheado", "afro"],
				[30, 15, 15, 10, 8.0 + (12.0 if ft["velho"] else 0.0), 25.0 * afro_p + 5.0, 22.0 * afro_p])
	ft["hair"] = style
	ft["cloth_color"] = Color(["8a4a5e", "3f6274", "5a4a7a", "2f6b57", "9a6a2f"][rng.randi_range(0, 4)])

	# barba (masculino)
	ft["facial"] = "nada"
	if not ft["female"] and style != "turbante":
		var beard_bump: float = 18.0 if (muslim or reg == "oriente_medio" or reg == "asia_sul") else 0.0
		ft["facial"] = _wpick_named(rng, ["nada", "bigode", "cavanhaque", "barba"],
			[52, 14, 14, 14 + beard_bump])
	elif style == "turbante":
		ft["facial"] = "barba"

	# olhos
	var iris_opts := ["3b2a1e", "1c1c1c", "2e5b8a", "4a6b3a"]
	var iris_w := [50, 30, 4, 3]
	if reg == "europa_norte":
		iris_w = [22, 8, 45, 18]
	elif reg in ["europa_sul", "europa_leste", "anglo", "cauca"]:
		iris_w = [40, 15, 24, 12]
	ft["iris"] = Color(iris_opts[_wpick(rng, iris_w)])
	ft["eye_h"] = rng.randf_range(3.2, 5.0)
	ft["brow_th"] = rng.randf_range(2.6, 4.2)

	# formas
	ft["jaw"] = rng.randf_range(0.78, 1.0)
	ft["nose_w"] = rng.randf_range(3.0, 6.0)
	ft["mouth_w"] = rng.randf_range(8.0, 11.5)

	# acessórios
	ft["sunglasses"] = rc.get("sunglasses", false)
	ft["glasses"] = (not ft["sunglasses"]) and rng.randf() < float(rc.get("glasses_p", 0.16))
	ft["earrings"] = ft["female"] and style != "hijab" and rng.randf() < 0.55
	ft["lipstick"] = ft["female"] and rng.randf() < 0.6
	ft["tie_color"] = Color(TIE_PALETTE[rng.randi_range(0, TIE_PALETTE.size() - 1)])
	return ft

static func _wpick(rng: RandomNumberGenerator, weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	var roll := rng.randf() * maxf(total, 0.001)
	for i in weights.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			return i
	return weights.size() - 1

static func _wpick_named(rng: RandomNumberGenerator, names: Array, weights: Array) -> String:
	return names[_wpick(rng, weights)]

static func _flag_tex(p_iso: String) -> Texture2D:
	var key := p_iso.to_lower()
	if not _flag_cache.has(key):
		var path := "res://flags/%s.svg" % key
		_flag_cache[key] = load(path) if ResourceLoader.exists(path) else null
	return _flag_cache[key]

# ─────────────────────────── DESENHO ───────────────────────────
# Canvas lógico 200×240, escalado ao tamanho do Control.

func _draw() -> void:
	if f.is_empty():
		return
	var sc := minf(size.x / 200.0, size.y / 240.0)
	if sc <= 0.0:
		return
	var off := Vector2((size.x - 200.0 * sc) * 0.5, (size.y - 240.0 * sc) * 0.5)
	draw_set_transform(off, 0.0, Vector2(sc, sc))

	var rc: Dictionary = ROLES[role]
	var skin: Color = f["skin"]
	var skin_dark := skin.darkened(0.22)
	var hair: Color = f["hair_color"]
	var head_c := Vector2(100, 102)
	var rx := 40.0
	var ry := 48.0

	# fundo
	var bg := Color(String(rc["bg"]))
	draw_rect(Rect2(0, 0, 200, 240), bg)
	draw_circle(Vector2(100, 96), 74.0, bg.lightened(0.10))

	# pescoço (antes do paletó — o colarinho cobre a base)
	draw_rect(Rect2(88, 128, 24, 52), skin_dark)

	# ombros / paletó
	var suit := Color(String(rc["suit"]))
	var suit_dark := suit.darkened(0.25)
	draw_colored_polygon(PackedVector2Array([
		Vector2(28, 240), Vector2(40, 192), Vector2(66, 172), Vector2(134, 172),
		Vector2(160, 192), Vector2(172, 240)]), suit)
	# camisa
	draw_colored_polygon(PackedVector2Array([
		Vector2(84, 172), Vector2(116, 172), Vector2(100, 210)]), Color(String(rc["shirt"])))
	# lapelas
	draw_colored_polygon(PackedVector2Array([
		Vector2(84, 172), Vector2(100, 182), Vector2(88, 212), Vector2(72, 194)]), suit_dark)
	draw_colored_polygon(PackedVector2Array([
		Vector2(116, 172), Vector2(100, 182), Vector2(112, 212), Vector2(128, 194)]), suit_dark)
	# gravata
	if bool(rc.get("tie", false)):
		var tie: Color = f["tie_color"]
		draw_colored_polygon(PackedVector2Array([
			Vector2(96, 180), Vector2(104, 180), Vector2(106, 214),
			Vector2(100, 226), Vector2(94, 214)]), tie)
		draw_rect(Rect2(95, 176, 10, 6), tie.darkened(0.2))
	# dragonas do general
	if bool(rc.get("epaulettes", false)):
		for ex in [44.0, 132.0]:
			draw_rect(Rect2(ex, 180, 24, 9), Color("b08a2e"))
			draw_circle(Vector2(ex + 12, 184.5), 2.6, Color("f2d06b"))
	# pin de bandeira na lapela — a nação no peito
	if bool(rc.get("pin", false)):
		var tex := _flag_tex(iso)
		if tex != null:
			draw_rect(Rect2(63, 196, 20, 14), Color("111111"))
			draw_texture_rect(tex, Rect2(64, 197, 18, 12), false)
	# microfone de lapela (âncora)
	if bool(rc.get("mic", false)):
		draw_line(Vector2(128, 206), Vector2(133, 196), Color("222222"), 2.0)
		draw_circle(Vector2(134, 194), 3.4, Color("333333"))
	# distintivo/estrela do Min. da Justiça & Segurança (segurança + defesa)
	if bool(rc.get("badge", false)):
		var star_c := Vector2(66, 200)
		var star := PackedVector2Array()
		for i in 10:
			var a := -PI / 2.0 + TAU * i / 10.0
			var r := 8.0 if i % 2 == 0 else 3.4
			star.append(star_c + Vector2(cos(a) * r, sin(a) * r))
		draw_colored_polygon(star, Color("d9c56a"))
		draw_circle(star_c, 2.2, Color("8a6f1e"))
	# estetoscópio do Min. da Saúde (jaleco branco + gravata já vêm do suit)
	if bool(rc.get("coat", false)):
		var steth := Color("2b6c8a")
		draw_arc(Vector2(100, 176), 30.0, PI * 0.15, PI * 0.85, 22, steth, 3.0)
		draw_line(Vector2(77, 190), Vector2(72, 212), steth, 3.0)
		draw_circle(Vector2(72, 214), 4.2, steth)
		draw_line(Vector2(123, 190), Vector2(128, 210), steth, 3.0)

	# cabelo "de trás" (cai sobre o paletó)
	match String(f["hair"]):
		"longo":
			# mechas laterais atrás da cabeça — deixa a testa e o rosto livres
			draw_rect(Rect2(100 - rx - 8, 96, 14, 84), hair)
			draw_rect(Rect2(100 + rx - 6, 96, 14, 84), hair)
			_ellipse(Vector2(100, 96), rx + 7, ry - 4, hair)
		"afro":
			draw_circle(head_c + Vector2(0, -ry * 0.42), rx + 17, hair)
		"hijab":
			var cloth: Color = f["cloth_color"]
			_ellipse(head_c, rx + 14, ry + 15, cloth)
			draw_rect(Rect2(100 - rx - 13, head_c.y, (rx + 13) * 2, 92), cloth)
		"coque":
			draw_circle(Vector2(100, head_c.y - ry - 4), 11.0, hair)

	# cabeça
	_head(head_c, rx, ry, float(f["jaw"]), skin)
	# orelhas (hijab cobre)
	if String(f["hair"]) != "hijab":
		draw_circle(Vector2(head_c.x - rx + 1, head_c.y + 6), 7.0, skin)
		draw_circle(Vector2(head_c.x + rx - 1, head_c.y + 6), 7.0, skin)
		if bool(f["earrings"]):
			draw_circle(Vector2(head_c.x - rx + 1, head_c.y + 14), 2.6, Color("e8c24a"))
			draw_circle(Vector2(head_c.x + rx - 1, head_c.y + 14), 2.6, Color("e8c24a"))

	# cabelo frontal
	var use_cap := bool(rc.get("cap", false))
	if not use_cap:
		match String(f["hair"]):
			"careca":
				pass
			"raspado":
				_hair_top(head_c, rx + 1, ry + 1, head_c.y - 22, hair.darkened(0.1), 0.0, 0)
			"curto", "coque":
				_hair_top(head_c, rx + 4, ry + 5, head_c.y - 16, hair, 0.0, 0)
			"longo":
				_hair_top(head_c, rx + 3, ry + 4, head_c.y - 22, hair, 0.0, 0)
			"risca":
				_hair_top(head_c, rx + 4, ry + 5, head_c.y - 16, hair, 0.0, 0)
				draw_line(Vector2(head_c.x - 14, head_c.y - ry - 3),
					Vector2(head_c.x - 20, head_c.y - 18), skin, 2.0)
			"ondulado":
				_hair_top(head_c, rx + 5, ry + 6, head_c.y - 15, hair, 0.10, 7)
			"cacheado":
				_hair_top(head_c, rx + 7, ry + 8, head_c.y - 14, hair, 0.16, 9)
			"afro":
				_hair_top(head_c, rx + 6, ry + 7, head_c.y - 16, hair, 0.12, 8)
			"hijab":
				_hair_top(head_c, rx + 6, ry + 7, head_c.y - 20, Color(f["cloth_color"]).darkened(0.12), 0.0, 0)
			"turbante":
				_ellipse(Vector2(head_c.x, head_c.y - ry + 6), rx + 8, 19, Color(f["cloth_color"]))
				_ellipse(Vector2(head_c.x, head_c.y - ry - 6), 12, 9, Color(f["cloth_color"]).lightened(0.15))
	else:
		# quepe militar
		var cap_col := suit.darkened(0.15)
		_hair_top(head_c, rx + 8, ry + 9, head_c.y - 24, cap_col, 0.0, 0)
		draw_rect(Rect2(head_c.x - rx - 7, head_c.y - 30, (rx + 7) * 2, 8), suit_dark)
		_ellipse(Vector2(head_c.x, head_c.y - 21), rx + 5, 5.5, Color("15161a"))
		draw_circle(Vector2(head_c.x, head_c.y - 38), 5.0, Color("f2d06b"))

	# rugas de idade
	if bool(f["velho"]):
		var wr := skin_dark
		wr.a = 0.55
		draw_line(Vector2(head_c.x - 22, head_c.y + 26), Vector2(head_c.x - 16, head_c.y + 32), wr, 1.4)
		draw_line(Vector2(head_c.x + 22, head_c.y + 26), Vector2(head_c.x + 16, head_c.y + 32), wr, 1.4)
		draw_line(Vector2(head_c.x - 12, head_c.y - 28), Vector2(head_c.x + 12, head_c.y - 28), wr, 1.2)

	# olhos + sobrancelhas + expressão
	_face(head_c, skin_dark, hair)

	# barba
	var fh := hair.darkened(0.08)
	match String(f["facial"]):
		"bigode":
			_ellipse(Vector2(head_c.x, head_c.y + 30), 12, 3.4, fh)
		"cavanhaque":
			_ellipse(Vector2(head_c.x, head_c.y + 30), 11, 3.0, fh)
			_ellipse(Vector2(head_c.x, head_c.y + 42), 9, 6.0, fh)
		"barba":
			var pts := PackedVector2Array()
			for i in 25:
				var a := PI * 0.12 + (PI * 0.76) * i / 24.0
				pts.append(head_c + Vector2(cos(a) * (rx - 2), sin(a) * (ry - 1)))
			pts.append(head_c + Vector2(rx * 0.62, 8))
			pts.append(head_c + Vector2(-rx * 0.62, 8))
			draw_colored_polygon(pts, fh)
			_ellipse(Vector2(head_c.x, head_c.y + 30), 12, 3.2, fh)
			# reabre a boca por cima da barba
			_mouth(head_c, skin_dark)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _head(c: Vector2, rx: float, ry: float, jaw: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		var a := TAU * i / 48.0
		var px := cos(a) * rx
		var py := sin(a) * ry
		if py > 0.0:  # abaixo do centro: afunila pelo queixo
			px *= lerpf(1.0, jaw, py / ry)
		pts.append(c + Vector2(px, py))
	draw_colored_polygon(pts, col)

func _hair_top(c: Vector2, rx: float, ry: float, hairline_y: float, col: Color, bump: float, freq: int) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := PI + PI * i / 32.0
		var r_mod := 1.0 + (bump * sin(freq * a) if bump > 0.0 else 0.0)
		var p := c + Vector2(cos(a) * rx * r_mod, sin(a) * ry * r_mod)
		pts.append(p)
	pts.append(Vector2(c.x + rx, hairline_y))
	pts.append(Vector2(c.x - rx, hairline_y))
	draw_colored_polygon(pts, col)

func _face(c: Vector2, skin_dark: Color, hair: Color) -> void:
	var eye_h: float = f["eye_h"]
	var brow_th: float = f["brow_th"]
	var ex := 16.0
	var ey := c.y - 2.0
	# sobrancelhas: inclinação define a emoção
	var tilt := 0.0
	var brow_y := ey - 12.0
	match expression:
		"bravo": tilt = 0.30
		"preocupado": tilt = -0.28
		"feliz": brow_y -= 2.0
		"urgente": brow_y -= 4.0
	for side: float in [-1.0, 1.0]:
		var bx: float = c.x + side * ex
		var half := 7.0
		var dy: float = tilt * side * half
		draw_line(Vector2(bx - half, brow_y + dy), Vector2(bx + half, brow_y - dy), hair.darkened(0.15), brow_th)
	# olhos
	for side: float in [-1.0, 1.0]:
		var p := Vector2(c.x + side * ex, ey)
		if bool(f["sunglasses"]):
			continue
		_ellipse(p, 6.0, eye_h, Color.WHITE)
		draw_circle(p, minf(eye_h - 0.6, 3.0), Color(f["iris"]))
		draw_circle(p, 1.2, Color("101014"))
	# óculos
	if bool(f["sunglasses"]):
		for side: float in [-1.0, 1.0]:
			_ellipse(Vector2(c.x + side * ex, ey), 9.5, 7.0, Color("17181c"))
		draw_line(Vector2(c.x - 7, ey - 2), Vector2(c.x + 7, ey - 2), Color("17181c"), 2.2)
	elif bool(f["glasses"]):
		for side: float in [-1.0, 1.0]:
			draw_arc(Vector2(c.x + side * ex, ey), 9.5, 0, TAU, 24, Color("2c2c30"), 1.8)
		draw_line(Vector2(c.x - 6.5, ey - 2), Vector2(c.x + 6.5, ey - 2), Color("2c2c30"), 1.8)
	# nariz
	var nw: float = f["nose_w"]
	draw_line(Vector2(c.x - 1, c.y + 2), Vector2(c.x - nw * 0.5, c.y + 16), skin_dark, 1.6)
	draw_line(Vector2(c.x - nw * 0.5, c.y + 16), Vector2(c.x + nw * 0.5, c.y + 17), skin_dark, 1.6)
	# boca
	_mouth(c, skin_dark)

func _mouth(c: Vector2, skin_dark: Color) -> void:
	var mw: float = f["mouth_w"]
	var mc := Vector2(c.x, c.y + 30)
	var col := Color("8a4a44") if bool(f["lipstick"]) else skin_dark
	if bool(f["lipstick"]):
		col = Color("b0475a")
	match expression:
		"feliz":
			draw_arc(mc + Vector2(0, -3), mw, PI * 0.18, PI * 0.82, 20, col, 2.6)
		"bravo", "preocupado":
			draw_arc(mc + Vector2(0, mw * 0.7), mw, PI * 1.2, PI * 1.8, 20, col, 2.4)
		"urgente":
			_ellipse(mc, mw * 0.5, 4.6, col.darkened(0.25))
		_:
			draw_line(mc + Vector2(-mw * 0.7, 0), mc + Vector2(mw * 0.7, 0), col, 2.4)

func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)
