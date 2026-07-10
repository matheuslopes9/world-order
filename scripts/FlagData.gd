extends RefCounted
## Cores oficiais (aproximadas) das bandeiras dos países, por ISO-2.
## Cada entrada: array de Colors (2-3 listras horizontais OU verticais).
## Layout determinado por flag_layout (default = HORIZONTAL).
## Pra países sem entrada explícita, usa-se fallback baseado no continente.

# Cores comuns reutilizadas
const RED        := Color(0.85, 0.10, 0.15)
const DARK_RED   := Color(0.65, 0.08, 0.12)
const BLUE       := Color(0.10, 0.25, 0.65)
const DARK_BLUE  := Color(0.05, 0.15, 0.45)
const GREEN      := Color(0.10, 0.55, 0.25)
const DARK_GREEN := Color(0.05, 0.40, 0.18)
const YELLOW     := Color(1.00, 0.85, 0.10)
const ORANGE     := Color(1.00, 0.55, 0.10)
const WHITE      := Color(0.95, 0.95, 0.95)
const BLACK      := Color(0.10, 0.10, 0.10)
const NAVY       := Color(0.0, 0.13, 0.40)
const LIGHT_BLUE := Color(0.30, 0.65, 0.95)

# Layouts: "h" = listras horizontais, "v" = listras verticais
const FLAGS := {
	# Américas
	"US": {"layout": "h", "colors": [RED, WHITE, RED, WHITE, RED, WHITE, RED]},
	"BR": {"layout": "h", "colors": [GREEN, YELLOW, BLUE, YELLOW, GREEN]},
	"CA": {"layout": "v", "colors": [RED, WHITE, RED]},
	"MX": {"layout": "v", "colors": [GREEN, WHITE, RED]},
	"AR": {"layout": "h", "colors": [LIGHT_BLUE, WHITE, LIGHT_BLUE]},
	"CL": {"layout": "h", "colors": [WHITE, RED]},
	"CO": {"layout": "h", "colors": [YELLOW, YELLOW, BLUE, RED]},
	"PE": {"layout": "v", "colors": [RED, WHITE, RED]},
	"VE": {"layout": "h", "colors": [YELLOW, BLUE, RED]},
	"UY": {"layout": "h", "colors": [WHITE, BLUE, WHITE, BLUE, WHITE]},
	"EC": {"layout": "h", "colors": [YELLOW, YELLOW, BLUE, RED]},
	"BO": {"layout": "h", "colors": [RED, YELLOW, GREEN]},
	"PY": {"layout": "h", "colors": [RED, WHITE, BLUE]},
	"CU": {"layout": "h", "colors": [BLUE, WHITE, BLUE, WHITE, BLUE]},

	# Europa
	"GB": {"layout": "h", "colors": [DARK_BLUE, WHITE, RED, WHITE, DARK_BLUE]},
	"FR": {"layout": "v", "colors": [BLUE, WHITE, RED]},
	"DE": {"layout": "h", "colors": [BLACK, RED, YELLOW]},
	"IT": {"layout": "v", "colors": [GREEN, WHITE, RED]},
	"ES": {"layout": "h", "colors": [RED, YELLOW, YELLOW, RED]},
	"PT": {"layout": "v", "colors": [GREEN, RED, RED]},
	"NL": {"layout": "h", "colors": [RED, WHITE, BLUE]},
	"BE": {"layout": "v", "colors": [BLACK, YELLOW, RED]},
	"CH": {"layout": "h", "colors": [RED, WHITE, RED]},
	"AT": {"layout": "h", "colors": [RED, WHITE, RED]},
	"SE": {"layout": "h", "colors": [BLUE, YELLOW, BLUE]},
	"NO": {"layout": "h", "colors": [RED, WHITE, BLUE, WHITE, RED]},
	"FI": {"layout": "h", "colors": [WHITE, BLUE, WHITE]},
	"DK": {"layout": "h", "colors": [RED, WHITE, RED]},
	"PL": {"layout": "h", "colors": [WHITE, RED]},
	"GR": {"layout": "h", "colors": [BLUE, WHITE, BLUE, WHITE, BLUE]},
	"IE": {"layout": "v", "colors": [GREEN, WHITE, ORANGE]},
	"RO": {"layout": "v", "colors": [BLUE, YELLOW, RED]},
	"HU": {"layout": "h", "colors": [RED, WHITE, GREEN]},
	"CZ": {"layout": "h", "colors": [WHITE, RED]},
	"SK": {"layout": "h", "colors": [WHITE, BLUE, RED]},
	"BG": {"layout": "h", "colors": [WHITE, GREEN, RED]},
	"RU": {"layout": "h", "colors": [WHITE, BLUE, RED]},
	"UA": {"layout": "h", "colors": [BLUE, YELLOW]},
	"BY": {"layout": "h", "colors": [RED, GREEN]},
	"LT": {"layout": "h", "colors": [YELLOW, GREEN, RED]},
	"LV": {"layout": "h", "colors": [DARK_RED, WHITE, DARK_RED]},
	"EE": {"layout": "h", "colors": [BLUE, BLACK, WHITE]},
	"HR": {"layout": "h", "colors": [RED, WHITE, BLUE]},
	"RS": {"layout": "h", "colors": [RED, BLUE, WHITE]},
	"SI": {"layout": "h", "colors": [WHITE, BLUE, RED]},
	"BA": {"layout": "h", "colors": [BLUE, YELLOW, BLUE]},
	"MD": {"layout": "v", "colors": [BLUE, YELLOW, RED]},
	"AL": {"layout": "h", "colors": [RED, RED]},
	"MK": {"layout": "h", "colors": [RED, YELLOW, RED]},
	"IS": {"layout": "h", "colors": [BLUE, WHITE, RED, WHITE, BLUE]},

	# Ásia
	"CN": {"layout": "h", "colors": [RED, RED]},
	"JP": {"layout": "h", "colors": [WHITE, WHITE, RED, WHITE, WHITE]},  # bola vermelha simulada
	"IN": {"layout": "h", "colors": [ORANGE, WHITE, GREEN]},
	"KR": {"layout": "h", "colors": [WHITE, WHITE, WHITE]},
	"KP": {"layout": "h", "colors": [BLUE, WHITE, RED, WHITE, BLUE]},
	"VN": {"layout": "h", "colors": [RED, RED]},
	"TH": {"layout": "h", "colors": [RED, WHITE, BLUE, WHITE, RED]},
	"ID": {"layout": "h", "colors": [RED, WHITE]},
	"MY": {"layout": "h", "colors": [RED, WHITE, RED, WHITE, RED, WHITE, RED]},
	"PH": {"layout": "h", "colors": [BLUE, RED]},
	"SG": {"layout": "h", "colors": [RED, WHITE]},
	"PK": {"layout": "v", "colors": [WHITE, GREEN, GREEN]},
	"BD": {"layout": "h", "colors": [GREEN, GREEN, GREEN]},
	"LK": {"layout": "v", "colors": [YELLOW, ORANGE, GREEN]},
	"MM": {"layout": "h", "colors": [YELLOW, GREEN, RED]},
	"KH": {"layout": "h", "colors": [BLUE, RED, BLUE]},
	"LA": {"layout": "h", "colors": [RED, BLUE, RED]},
	"NP": {"layout": "h", "colors": [DARK_RED, DARK_RED]},
	"AF": {"layout": "v", "colors": [BLACK, RED, GREEN]},
	"IR": {"layout": "h", "colors": [GREEN, WHITE, RED]},
	"IQ": {"layout": "h", "colors": [RED, WHITE, BLACK]},
	"SA": {"layout": "h", "colors": [DARK_GREEN, DARK_GREEN]},
	"AE": {"layout": "h", "colors": [GREEN, WHITE, BLACK]},
	"IL": {"layout": "h", "colors": [WHITE, BLUE, WHITE, BLUE, WHITE]},
	"TR": {"layout": "h", "colors": [RED, RED]},
	"SY": {"layout": "h", "colors": [RED, WHITE, BLACK]},
	"JO": {"layout": "h", "colors": [BLACK, WHITE, GREEN]},
	"LB": {"layout": "h", "colors": [RED, WHITE, RED]},
	"YE": {"layout": "h", "colors": [RED, WHITE, BLACK]},
	"OM": {"layout": "h", "colors": [WHITE, RED, GREEN]},
	"QA": {"layout": "h", "colors": [DARK_RED, DARK_RED]},
	"KW": {"layout": "h", "colors": [GREEN, WHITE, RED]},
	"BH": {"layout": "h", "colors": [WHITE, RED]},
	"KZ": {"layout": "h", "colors": [LIGHT_BLUE, LIGHT_BLUE]},
	"UZ": {"layout": "h", "colors": [LIGHT_BLUE, WHITE, GREEN]},
	"TM": {"layout": "h", "colors": [GREEN, GREEN]},
	"KG": {"layout": "h", "colors": [RED, RED]},
	"TJ": {"layout": "h", "colors": [RED, WHITE, GREEN]},
	"AZ": {"layout": "h", "colors": [LIGHT_BLUE, RED, GREEN]},
	"AM": {"layout": "h", "colors": [RED, BLUE, ORANGE]},
	"GE": {"layout": "h", "colors": [WHITE, WHITE, WHITE]},
	"MN": {"layout": "v", "colors": [RED, BLUE, RED]},
	"BT": {"layout": "h", "colors": [YELLOW, ORANGE]},

	# África
	"ZA": {"layout": "h", "colors": [GREEN, BLUE, RED]},
	"EG": {"layout": "h", "colors": [RED, WHITE, BLACK]},
	"NG": {"layout": "v", "colors": [GREEN, WHITE, GREEN]},
	"KE": {"layout": "h", "colors": [BLACK, RED, GREEN]},
	"ET": {"layout": "h", "colors": [GREEN, YELLOW, RED]},
	"GH": {"layout": "h", "colors": [RED, YELLOW, GREEN]},
	"MA": {"layout": "h", "colors": [RED, RED]},
	"DZ": {"layout": "v", "colors": [GREEN, WHITE, RED]},
	"TN": {"layout": "h", "colors": [RED, RED]},
	"LY": {"layout": "h", "colors": [RED, BLACK, GREEN]},
	"SD": {"layout": "h", "colors": [RED, WHITE, BLACK]},
	"SS": {"layout": "h", "colors": [BLACK, RED, GREEN]},
	"AO": {"layout": "h", "colors": [RED, BLACK]},
	"MZ": {"layout": "h", "colors": [GREEN, BLACK, YELLOW]},
	"TZ": {"layout": "h", "colors": [GREEN, YELLOW, BLUE]},
	"UG": {"layout": "h", "colors": [BLACK, YELLOW, RED, BLACK, YELLOW, RED]},
	"ZW": {"layout": "h", "colors": [GREEN, YELLOW, RED, BLACK, RED, YELLOW, GREEN]},
	"ZM": {"layout": "h", "colors": [GREEN, GREEN, GREEN]},
	"NA": {"layout": "h", "colors": [BLUE, RED, GREEN]},
	"BW": {"layout": "h", "colors": [LIGHT_BLUE, BLACK, LIGHT_BLUE]},
	"SN": {"layout": "v", "colors": [GREEN, YELLOW, RED]},
	"CI": {"layout": "v", "colors": [ORANGE, WHITE, GREEN]},
	"ML": {"layout": "v", "colors": [GREEN, YELLOW, RED]},
	"BF": {"layout": "h", "colors": [RED, GREEN]},
	"NE": {"layout": "h", "colors": [ORANGE, WHITE, GREEN]},
	"TD": {"layout": "v", "colors": [BLUE, YELLOW, RED]},
	"CM": {"layout": "v", "colors": [GREEN, RED, YELLOW]},
	"CF": {"layout": "h", "colors": [BLUE, WHITE, GREEN, YELLOW]},
	"CG": {"layout": "h", "colors": [GREEN, YELLOW, RED]},
	"CD": {"layout": "h", "colors": [LIGHT_BLUE, LIGHT_BLUE]},
	"GA": {"layout": "h", "colors": [GREEN, YELLOW, BLUE]},
	"GN": {"layout": "v", "colors": [RED, YELLOW, GREEN]},
	"GW": {"layout": "h", "colors": [YELLOW, GREEN]},
	"BJ": {"layout": "h", "colors": [GREEN, YELLOW, RED]},
	"TG": {"layout": "h", "colors": [GREEN, YELLOW, GREEN, YELLOW, RED]},
	"SL": {"layout": "h", "colors": [GREEN, WHITE, BLUE]},
	"LR": {"layout": "h", "colors": [RED, WHITE, RED, WHITE, RED, WHITE]},
	"GQ": {"layout": "h", "colors": [GREEN, WHITE, RED]},
	"DJ": {"layout": "h", "colors": [LIGHT_BLUE, GREEN]},
	"SO": {"layout": "h", "colors": [LIGHT_BLUE, LIGHT_BLUE]},
	"ER": {"layout": "h", "colors": [RED, RED]},
	"RW": {"layout": "h", "colors": [LIGHT_BLUE, YELLOW, GREEN]},
	"BI": {"layout": "h", "colors": [RED, WHITE, GREEN]},
	"MW": {"layout": "h", "colors": [BLACK, RED, GREEN]},
	"LS": {"layout": "h", "colors": [BLUE, WHITE, GREEN]},
	"SZ": {"layout": "h", "colors": [BLUE, YELLOW, RED, YELLOW, BLUE]},
	"MG": {"layout": "h", "colors": [WHITE, RED, GREEN]},
	"MU": {"layout": "h", "colors": [RED, BLUE, YELLOW, GREEN]},
	"GM": {"layout": "h", "colors": [RED, WHITE, BLUE, WHITE, GREEN]},
	"CV": {"layout": "h", "colors": [BLUE, WHITE, RED, WHITE, BLUE]},
	"MR": {"layout": "h", "colors": [GREEN, GREEN]},
	"KM": {"layout": "h", "colors": [YELLOW, WHITE, RED, BLUE]},
	"ST": {"layout": "h", "colors": [GREEN, YELLOW, GREEN]},
	"SC": {"layout": "h", "colors": [BLUE, YELLOW, RED]},

	# Oceania
	"AU": {"layout": "h", "colors": [DARK_BLUE, DARK_BLUE]},
	"NZ": {"layout": "h", "colors": [DARK_BLUE, DARK_BLUE]},
	"PG": {"layout": "h", "colors": [BLACK, RED]},
	"FJ": {"layout": "h", "colors": [LIGHT_BLUE, LIGHT_BLUE]},

	# Outros / Caribe
	"JM": {"layout": "h", "colors": [GREEN, BLACK, GREEN]},
	"HT": {"layout": "h", "colors": [BLUE, RED]},
	"DO": {"layout": "h", "colors": [BLUE, RED]},
	"PA": {"layout": "h", "colors": [WHITE, RED, BLUE, WHITE]},
	"CR": {"layout": "h", "colors": [BLUE, WHITE, RED, WHITE, BLUE]},
	"NI": {"layout": "h", "colors": [BLUE, WHITE, BLUE]},
	"HN": {"layout": "h", "colors": [BLUE, WHITE, BLUE]},
	"GT": {"layout": "v", "colors": [LIGHT_BLUE, WHITE, LIGHT_BLUE]},
	"SV": {"layout": "h", "colors": [BLUE, WHITE, BLUE]},
	"BZ": {"layout": "h", "colors": [BLUE, RED, BLUE]},
	"TT": {"layout": "h", "colors": [RED, RED]},
	"BS": {"layout": "h", "colors": [LIGHT_BLUE, YELLOW, LIGHT_BLUE]},
	"BB": {"layout": "v", "colors": [BLUE, YELLOW, BLUE]},
}

# Continente fallback (genérico, ainda colorido)
const CONTINENT_FALLBACK := {
	"Europa": [BLUE, WHITE, RED],
	"América": [RED, WHITE, BLUE],
	"Ásia": [RED, WHITE, GREEN],
	"África": [GREEN, YELLOW, RED],
	"Oceania": [BLUE, WHITE, RED],
}

const NEUTRAL_FALLBACK := [Color(0.3, 0.4, 0.5), Color(0.5, 0.6, 0.7), Color(0.4, 0.5, 0.6)]

static func get_flag(iso2: String, continente: String = "") -> Dictionary:
	if FLAGS.has(iso2):
		return FLAGS[iso2]
	if CONTINENT_FALLBACK.has(continente):
		return {"layout": "h", "colors": CONTINENT_FALLBACK[continente]}
	return {"layout": "h", "colors": NEUTRAL_FALLBACK}
