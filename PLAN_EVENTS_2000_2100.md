# WORLD ORDER — Cronograma de Eventos 2000-2100

**Status:** Planejamento. Implementação em fases.
**Modos:** `livre` (eventos disparam aleatoriamente, sem âncora histórica) | `inspirado` (eventos disparam em janelas históricas reais)

---

## Estrutura de dados proposta

```jsonc
// data/events_timeline.json
{
  "id": "ny_911",
  "year": 2001,
  "quarter": 3,                       // 1-4 (JAN/ABR/JUL/OUT)
  "year_window": [2001, 2002],        // tolerância em modo "inspirado"
  "scope": "global",                  // global | regional | national | bilateral
  "categories": ["terrorismo", "geopolitica"],
  "trigger": {
    "primary_country": "US",
    "involves": ["US"],
    "region": ""                      // ou continente se regional
  },
  "headline": "Ataques de 11 de setembro nos EUA",
  "body": "Aviões comerciais sequestrados são lançados contra alvos em Nova York e Washington.",
  "effects_immediate": {
    "US": {"defcon": -2, "estab": -10, "apoio": +15},
    "global": {"market": -5}
  },
  "modal_decision": true,             // se true, abre modal pra escolher resposta
  "choices": [
    {"id": "war_terror", "label": "Declarar Guerra ao Terror", "effects": {...}},
    {"id": "diplomatic", "label": "Resposta diplomática", "effects": {...}}
  ],
  "follow_ups": ["afghan_invasion_2001", "iraq_war_2003"],   // dispara cascata
  "tags": ["historic", "decision", "watershed"]
}
```

---

## CATÁLOGO COMPLETO 2000-2024 (~780 eventos)

### Convenções
- **★** = evento âncora (modal de decisão se afeta jogador)
- **▣** = evento de cascata (segue de outro)
- **○** = evento secundário (efeito direto, sem modal)
- **G/R/N/B** = scope: Global/Regional/Nacional/Bilateral

---

### 2000 — Virada do Milênio

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 1 | ★ G | 2000 Q1 | global | Bug do Milênio (Y2K) — gasto global em TI massivo |
| 2 | ○ N | 2000 Q1 | RU | Putin assume presidência da Rússia |
| 3 | ○ N | 2000 Q3 | YU | Sérvia: queda de Milošević após protestos |
| 4 | ○ N | 2000 Q3 | MX | Eleição de Vicente Fox (PRI perde após 71 anos) |
| 5 | ○ N | 2000 Q4 | US | Eleição contestada Bush vs Gore (Florida recount) |
| 6 | ○ G | 2000 Q4 | global | Estouro da bolha .com — Nasdaq -50% |
| 7 | ○ R | 2000 Q4 | OrienteMédio | Segunda Intifada Palestina |
| 8 | ○ N | 2000 Q2 | BR | FHC privatiza Eletropaulo |
| 9 | ○ N | 2000 Q3 | KR | Cúpula Coreia do Norte-Sul (Kim Dae-jung) |
| 10 | ○ N | 2000 Q1 | JP | Recessão prolongada continua (década perdida) |

### 2001 — 11/9 e Guerra ao Terror

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 11 | ★ G | 2001 Q3 | US, AF, global | **11/9 — Ataques às Torres Gêmeas** (modal: resposta militar/diplomática) |
| 12 | ▣ N | 2001 Q4 | AF, US | Invasão do Afeganistão (Operation Enduring Freedom) |
| 13 | ○ G | 2001 Q4 | global | Patriot Act — vigilância massiva |
| 14 | ○ N | 2001 Q4 | AR | Argentina: corralito, default da dívida |
| 15 | ○ R | 2001 Q4 | AR, UY, BR | Crise contagia Cone Sul |
| 16 | ○ G | 2001 Q1 | global | China entra na OMC |
| 17 | ○ R | 2001 Q3 | EU | Euro entra em vigor (12 países) |
| 18 | ○ N | 2001 Q2 | NL | Holanda: 1º país com casamento gay legal |
| 19 | ○ N | 2001 Q4 | TR | Crise bancária turca |

### 2002 — Pós-11/9

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 20 | ○ G | 2002 Q1 | global | Bush nomeia "Eixo do Mal": Irã, Iraque, Coreia do Norte |
| 21 | ○ N | 2002 Q4 | BR | Lula eleito presidente do Brasil |
| 22 | ○ N | 2002 Q3 | DE | Alemanha: governo Schröder reeleito |
| 23 | ○ N | 2002 Q2 | VE | Tentativa de golpe contra Chávez (falhada) |
| 24 | ○ R | 2002 Q4 | África | Conflito em Darfur escala |
| 25 | ○ N | 2002 Q3 | KP | Kim Jong-il admite programa nuclear secreto |
| 26 | ○ N | 2002 Q4 | KR | Roh Moo-hyun eleito |
| 27 | ○ N | 2002 Q1 | EUR | Euro começa circular fisicamente |
| 28 | ○ N | 2002 Q3 | ID | Atentado em Bali — 202 mortos |

### 2003 — Iraque

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 29 | ★ G | 2003 Q1 | US, GB, IQ, global | **Invasão do Iraque** (modal: apoiar/condenar/neutro) |
| 30 | ▣ N | 2003 Q1 | IQ | Saddam Hussein deposto |
| 31 | ○ G | 2003 Q1 | global | Manifestações anti-guerra em 600 cidades |
| 32 | ○ N | 2003 Q2 | CN | Epidemia de SARS |
| 33 | ○ N | 2003 Q3 | LR | Charles Taylor renuncia, exílio |
| 34 | ○ N | 2003 Q4 | GE | Geórgia: Revolução das Rosas |
| 35 | ○ N | 2003 Q4 | IQ | Saddam capturado |
| 36 | ○ R | 2003 Q3 | África | UA cria Conselho de Paz |
| 37 | ○ N | 2003 Q1 | BR | Plano Fome Zero lançado |

### 2004 — Tsunami e Expansões

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 38 | ★ G | 2004 Q4 | ID, TH, LK, IN, global | **Tsunami do Oceano Índico** — 230k mortos (modal: ajuda humanitária) |
| 39 | ○ G | 2004 Q2 | EU | UE expande pra 25 (Polônia, Tcheca, etc) |
| 40 | ○ N | 2004 Q4 | UA | Ucrânia: Revolução Laranja |
| 41 | ○ N | 2004 Q1 | ES | Madri: atentado nos trens — 191 mortos |
| 42 | ○ N | 2004 Q3 | RU | Beslan: massacre na escola — 334 mortos |
| 43 | ○ N | 2004 Q1 | HT | Haiti: golpe contra Aristide |
| 44 | ○ R | 2004 Q3 | África | Crise em Darfur classificada como genocídio |
| 45 | ○ N | 2004 Q4 | US | Bush reeleito |
| 46 | ○ N | 2004 Q3 | AR | Recuperação econômica pós-default |

### 2005 — Furacões e Vermelho-Verde

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 47 | ★ N | 2005 Q3 | US | **Furacão Katrina** — Nova Orleans destruída (modal: resposta governo) |
| 48 | ○ N | 2005 Q4 | DE | Angela Merkel torna-se chanceler |
| 49 | ○ N | 2005 Q3 | IL | Retirada israelense de Gaza |
| 50 | ○ N | 2005 Q1 | LB | Beirute: assassinato de Hariri, Revolução do Cedro |
| 51 | ○ R | 2005 Q1 | EU | França e Holanda rejeitam Constituição da UE |
| 52 | ○ N | 2005 Q4 | BO | Evo Morales eleito (1º indígena presidente) |
| 53 | ○ N | 2005 Q4 | IR | Ahmadinejad eleito presidente |
| 54 | ○ N | 2005 Q1 | UA | Yushchenko presidente após Revolução Laranja |
| 55 | ○ N | 2005 Q4 | LR | Ellen Johnson Sirleaf — 1ª presidenta africana |

### 2006 — Tensão Nuclear

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 56 | ★ N | 2006 Q4 | KP, global | **Coreia do Norte testa 1ª arma nuclear** (modal: sanções/diplomacia/militar) |
| 57 | ○ N | 2006 Q4 | IQ | Saddam executado |
| 58 | ○ R | 2006 Q3 | LB, IL | Guerra Líbano-Israel (33 dias) |
| 59 | ○ N | 2006 Q4 | RU | Litvinenko envenenado em Londres |
| 60 | ○ N | 2006 Q4 | TM | Niyazov morre, fim do regime "Turkmenbashi" |
| 61 | ○ N | 2006 Q4 | TH | Golpe militar derruba Thaksin |
| 62 | ○ N | 2006 Q4 | BR | Lula reeleito |
| 63 | ○ N | 2006 Q4 | NI | Daniel Ortega volta ao poder |
| 64 | ○ N | 2006 Q4 | MX | Felipe Calderón eleito por margem mínima |

### 2007 — Pré-crise

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 65 | ○ G | 2007 Q3 | global | Crise do subprime começa nos EUA |
| 66 | ○ N | 2007 Q4 | RU | Putin "elege" Medvedev como sucessor |
| 67 | ○ N | 2007 Q4 | PK | Bhutto assassinada |
| 68 | ○ N | 2007 Q1 | RO, BG | Romênia e Bulgária entram na UE |
| 69 | ○ N | 2007 Q2 | FR | Sarkozy eleito presidente |
| 70 | ○ N | 2007 Q4 | KE | Quênia: violência pós-eleitoral |
| 71 | ○ N | 2007 Q3 | MM | Mianmar: Revolução Açafrão reprimida |
| 72 | ○ N | 2007 Q1 | EE | Estônia: 1º país a permitir voto online nacional |
| 73 | ○ N | 2007 Q2 | AU | Kevin Rudd eleito |

### 2008 — A Grande Crise

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 74 | ★ G | 2008 Q3 | global | **Quebra do Lehman Brothers — Crise Financeira Global** (modal: bailout/austeridade/intervenção) |
| 75 | ▣ G | 2008 Q4 | global | G20 emerge como fórum econômico chefe |
| 76 | ★ B | 2008 Q3 | RU, GE | **Guerra Rússia-Geórgia** — Ossétia do Sul |
| 77 | ○ G | 2008 Q3 | global | Olimpíadas de Pequim |
| 78 | ○ N | 2008 Q4 | US | Obama eleito 1º presidente negro |
| 79 | ○ N | 2008 Q1 | KE | Acordo de paz pós-violência |
| 80 | ○ N | 2008 Q4 | IN | Mumbai: ataques terroristas — 175 mortos |
| 81 | ○ N | 2008 Q1 | XK | Kosovo declara independência |
| 82 | ○ N | 2008 Q1 | CU | Raúl Castro substitui Fidel |
| 83 | ○ N | 2008 Q4 | TH | Crise política, fechamento aeroporto |

### 2009 — Recuperação e Tensão

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 84 | ○ G | 2009 Q1 | global | China supera Alemanha como maior exportador |
| 85 | ○ N | 2009 Q1 | US | Obama assume, pacote de estímulo $787B |
| 86 | ○ N | 2009 Q1 | LK | Sri Lanka: fim da guerra civil (Tigres derrotados) |
| 87 | ○ N | 2009 Q4 | IR | Eleição contestada Ahmadinejad — Movimento Verde |
| 88 | ○ N | 2009 Q3 | DE | Merkel reeleita |
| 89 | ○ N | 2009 Q2 | MX | Epidemia H1N1 começa no México |
| 90 | ○ N | 2009 Q4 | BR | Brasil ganha sede Olimpíada 2016 |
| 91 | ○ R | 2009 Q1 | EU | Crise grega revelada |
| 92 | ○ N | 2009 Q4 | HN | Honduras: golpe contra Zelaya |

### 2010 — Primavera Próxima

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 93 | ★ G | 2010 Q4 | TN, global | **Revolução de Jasmim — início da Primavera Árabe** (modal: apoiar/neutro/condenar) |
| 94 | ○ G | 2010 Q1 | global | Crise da dívida da Zona do Euro |
| 95 | ○ N | 2010 Q1 | HT | Terremoto Haiti — 230k mortos |
| 96 | ○ N | 2010 Q3 | CL | Resgate de 33 mineiros |
| 97 | ○ N | 2010 Q1 | RU | Acordo START com EUA |
| 98 | ○ N | 2010 Q4 | BR | Dilma eleita presidenta |
| 99 | ○ N | 2010 Q3 | PK | Inundações afetam 20M |
| 100 | ○ G | 2010 Q2 | global | Vazamento Deepwater Horizon |
| 101 | ○ N | 2010 Q4 | KP | Kim Jong-un anunciado sucessor |

### 2011 — Primavera Árabe e Fukushima

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 102 | ★ R | 2011 Q1 | EG, TN, LY, SY, YE | **Primavera Árabe explode** (multi-país, modal por nação) |
| 103 | ★ N | 2011 Q1 | JP | **Fukushima — terremoto+tsunami+desastre nuclear** (modal: política nuclear) |
| 104 | ▣ N | 2011 Q1 | EG | Mubarak cai |
| 105 | ▣ N | 2011 Q3 | LY | Gaddafi morto, fim do regime |
| 106 | ▣ N | 2011 Q1 | YE | Saleh renuncia |
| 107 | ○ N | 2011 Q2 | US | Bin Laden morto no Paquistão |
| 108 | ○ N | 2011 Q3 | US | S&P rebaixa rating EUA |
| 109 | ○ N | 2011 Q4 | KP | Kim Jong-il morre, Kim Jong-un assume |
| 110 | ○ N | 2011 Q3 | NO | Ataque de Breivik — 77 mortos |
| 111 | ○ N | 2011 Q3 | SS | Sudão do Sul independente |

### 2012 — Eleições e Tensões

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 112 | ○ N | 2012 Q1 | RU | Putin reeleito (3º mandato) |
| 113 | ○ N | 2012 Q4 | US | Obama reeleito |
| 114 | ○ N | 2012 Q2 | FR | Hollande eleito presidente |
| 115 | ○ N | 2012 Q4 | CN | Xi Jinping assume liderança PCC |
| 116 | ○ N | 2012 Q1 | EG | Morsi eleito presidente |
| 117 | ○ N | 2012 Q1 | NL | Países Baixos: governo cai por crise |
| 118 | ○ N | 2012 Q4 | JP | Abe volta como PM |
| 119 | ○ R | 2012 Q3 | África | Mali: golpe e tomada islamista do norte |
| 120 | ○ N | 2012 Q4 | KR | Park Geun-hye eleita 1ª presidenta SK |

### 2013 — Snowden e Conclaves

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 121 | ★ G | 2013 Q2 | US, RU, global | **Vazamentos Snowden — espionagem da NSA exposta** (modal: extradição/asilo) |
| 122 | ○ N | 2013 Q1 | VA | Papa Bento XVI renuncia, Francisco eleito |
| 123 | ○ N | 2013 Q3 | EG | Sisi derruba Morsi |
| 124 | ○ N | 2013 Q1 | VE | Chávez morre, Maduro assume |
| 125 | ○ N | 2013 Q3 | BR | Manifestações de junho |
| 126 | ○ N | 2013 Q4 | UA | Maidan — protestos pró-UE |
| 127 | ○ R | 2013 Q3 | África | Boko Haram intensifica ataques |
| 128 | ○ N | 2013 Q4 | DE | Merkel reeleita (3º mandato) |

### 2014 — Crimea e Estado Islâmico

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 129 | ★ G | 2014 Q1 | RU, UA, global | **Anexação russa da Crimeia** (modal: sanções/militar/neutro) |
| 130 | ★ R | 2014 Q3 | IQ, SY, global | **Estado Islâmico declara califado** (modal: coalizão militar) |
| 131 | ○ N | 2014 Q3 | UA | Voo MH17 derrubado sobre Donbass |
| 132 | ○ N | 2014 Q1 | UA | Yanukovych foge, Maidan vence |
| 133 | ○ R | 2014 Q1 | África | Surto de Ebola na África Ocidental |
| 134 | ○ N | 2014 Q4 | BR | Dilma reeleita por margem fina |
| 135 | ○ N | 2014 Q3 | HK | Hong Kong: Movimento dos Guarda-chuvas |
| 136 | ○ N | 2014 Q1 | TH | Tailândia: golpe militar |
| 137 | ○ N | 2014 Q2 | IN | Modi eleito |
| 138 | ○ N | 2014 Q1 | TR | Erdoğan eleito presidente |

### 2015 — Acordos e Migração

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 139 | ★ G | 2015 Q4 | global | **Acordo de Paris sobre Clima** (modal: assinar/não/parcial) |
| 140 | ★ R | 2015 Q3 | DE, EU, SY | **Crise migratória europeia** (modal: abrir fronteiras/fechar) |
| 141 | ★ G | 2015 Q3 | IR, US, global | **Acordo Nuclear com Irã (JCPOA)** (modal: apoiar/oposição) |
| 142 | ○ N | 2015 Q1 | FR | Atentado Charlie Hebdo |
| 143 | ○ N | 2015 Q4 | FR | Atentados em Paris (Bataclan) — 130 mortos |
| 144 | ○ N | 2015 Q4 | TR | Avião russo derrubado pela Turquia |
| 145 | ○ N | 2015 Q4 | AR | Macri eleito |
| 146 | ○ N | 2015 Q2 | NP | Terremoto no Nepal — 9000 mortos |
| 147 | ○ N | 2015 Q4 | MM | Suu Kyi vence eleições |

### 2016 — Brexit e Trump

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 148 | ★ G | 2016 Q2 | GB, EU, global | **Brexit — Reino Unido vota sair da UE** (modal: aproximação/distanciamento) |
| 149 | ★ G | 2016 Q4 | US, global | **Trump eleito presidente dos EUA** (modal: postura diplomática) |
| 150 | ○ N | 2016 Q3 | TR | Tentativa de golpe na Turquia falhada |
| 151 | ○ N | 2016 Q3 | BR | Dilma sofre impeachment |
| 152 | ○ R | 2016 Q3 | África | Crises Boko Haram em Nigéria/Camarões |
| 153 | ○ N | 2016 Q1 | IS | Panama Papers vazam |
| 154 | ○ N | 2016 Q3 | ZA | Zuma sob ataque por corrupção |
| 155 | ○ N | 2016 Q4 | IT | Renzi cai após referendo |
| 156 | ○ N | 2016 Q3 | CO | Acordo de paz com FARC |
| 157 | ○ N | 2016 Q4 | KR | Park sofre impeachment |
| 158 | ○ N | 2016 Q4 | CU | Fidel Castro morre |

### 2017 — Trump assume

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 159 | ○ N | 2017 Q1 | US | Trump assume, ordem executiva muçulmanos |
| 160 | ○ N | 2017 Q2 | FR | Macron eleito (En Marche) |
| 161 | ○ R | 2017 Q3 | KP, US | Tensão nuclear coreana — testes ICBM |
| 162 | ○ G | 2017 Q4 | global | Trump retira EUA do Acordo de Paris |
| 163 | ○ N | 2017 Q3 | ES | Catalunha: referendo de independência reprimido |
| 164 | ○ R | 2017 Q4 | SA, QA | Crise diplomática Catar |
| 165 | ○ N | 2017 Q4 | ZW | Mugabe afastado por militares |
| 166 | ○ R | 2017 Q3 | MM | Crise rohingya — limpeza étnica |
| 167 | ○ N | 2017 Q4 | DE | Merkel reeleita (4º mandato) com dificuldade |

### 2018 — Polarização

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 168 | ○ B | 2018 Q2 | KP, US | Trump-Kim cúpula em Singapura |
| 169 | ○ N | 2018 Q4 | BR | Bolsonaro eleito |
| 170 | ○ G | 2018 Q3 | US, CN, global | Guerra comercial EUA-China escala |
| 171 | ○ N | 2018 Q3 | AR | Crise cambial argentina, FMI |
| 172 | ○ N | 2018 Q3 | TR | Crise da lira |
| 173 | ○ N | 2018 Q4 | MX | AMLO eleito |
| 174 | ○ N | 2018 Q4 | SA | Khashoggi assassinado em Istambul |
| 175 | ○ N | 2018 Q1 | SY | Ataque químico Douma + retaliação ocidental |
| 176 | ○ N | 2018 Q3 | IT | Governo Conte (Lega+M5S) |

### 2019 — Hong Kong e Climate Strike

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 177 | ★ N | 2019 Q3 | HK, CN | **Protestos massivos em Hong Kong** (modal: posicionamento global) |
| 178 | ○ G | 2019 Q3 | global | Greta Thunberg + Climate Strikes globais |
| 179 | ○ N | 2019 Q4 | UA | Zelensky eleito presidente |
| 180 | ○ N | 2019 Q4 | BO | Evo Morales renuncia, vai ao exílio |
| 181 | ○ N | 2019 Q4 | CL | Protestos massivos no Chile |
| 182 | ○ N | 2019 Q4 | IR | Protestos por gasolina reprimidos |
| 183 | ○ N | 2019 Q4 | GB | Boris Johnson PM, Brexit aprovado |
| 184 | ○ N | 2019 Q4 | IN | Modi reeleito |
| 185 | ○ R | 2019 Q4 | África | Sudão: queda de Bashir |
| 186 | ○ N | 2019 Q4 | VE | Crise Maduro vs Guaidó |

### 2020 — COVID-19

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 187 | ★ G | 2020 Q1 | CN, global | **COVID-19 declarada pandemia** (modal: lockdown/aberto/intermediário) |
| 188 | ▣ G | 2020 Q2 | global | Lockdowns globais, recessão |
| 189 | ▣ G | 2020 Q4 | global | Vacinas aprovadas (Pfizer, Moderna) |
| 190 | ★ G | 2020 Q2 | US, global | **George Floyd / Black Lives Matter** (modal: postura) |
| 191 | ○ N | 2020 Q4 | US | Biden eleito, Trump contesta |
| 192 | ○ N | 2020 Q3 | BY | Belarus: protestos contra Lukashenko |
| 193 | ○ B | 2020 Q4 | AM, AZ | Guerra de Nagorno-Karabakh II |
| 194 | ○ N | 2020 Q3 | LB | Beirute: explosão no porto |
| 195 | ○ N | 2020 Q4 | ET | Etiópia: guerra do Tigré começa |

### 2021 — Vacinas e Talibãs

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 196 | ★ N | 2021 Q3 | AF, US, global | **Talibãs retomam Afeganistão / saída EUA** (modal: refugiados/sanções) |
| 197 | ○ N | 2021 Q1 | US | 6 de janeiro: invasão do Capitólio |
| 198 | ○ G | 2021 Q1 | global | Campanhas de vacinação aceleram |
| 199 | ○ N | 2021 Q4 | DE | Scholz substitui Merkel após 16 anos |
| 200 | ○ N | 2021 Q3 | MM | Mianmar: golpe militar |
| 201 | ○ R | 2021 Q1 | EU | Crise de fronteira Belarus-Polônia |
| 202 | ○ G | 2021 Q1 | global | Canal de Suez bloqueado pelo Ever Given |
| 203 | ○ N | 2021 Q1 | NI | Daniel Ortega prende oposição |
| 204 | ○ R | 2021 Q4 | África | Golpes em Mali, Guiné, Burkina Faso |

### 2022 — Ucrânia

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 205 | ★ G | 2022 Q1 | RU, UA, global | **Rússia invade Ucrânia** (modal: sanções pesadas/leves/neutro) |
| 206 | ▣ G | 2022 Q1 | global | Maior pacote de sanções da história contra Rússia |
| 207 | ▣ G | 2022 Q2 | global | Crise energética europeia + crise de grãos |
| 208 | ▣ G | 2022 Q2 | SE, FI | Suécia e Finlândia pedem entrada na OTAN |
| 209 | ○ N | 2022 Q1 | LK | Sri Lanka: default, Rajapaksa foge |
| 210 | ○ N | 2022 Q3 | IR | Protestos Mahsa Amini |
| 211 | ○ N | 2022 Q4 | BR | Lula vence Bolsonaro |
| 212 | ○ N | 2022 Q4 | CN | Xi Jinping garante 3º mandato |
| 213 | ○ N | 2022 Q3 | GB | Liz Truss cai em 49 dias |
| 214 | ○ N | 2022 Q3 | IT | Meloni eleita PM |
| 215 | ○ G | 2022 Q4 | global | ChatGPT lançado — corrida da AI generativa |

### 2023 — Israel-Hamas e AI

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 216 | ★ R | 2023 Q4 | IL, PS, global | **Hamas ataca Israel — guerra em Gaza** (modal: posicionamento) |
| 217 | ○ G | 2023 Q1 | global | AI generativa explode (GPT-4, Bard, Llama) |
| 218 | ○ N | 2023 Q1 | TR | Terremoto Turquia-Síria — 50k mortos |
| 219 | ○ N | 2023 Q2 | RU | Wagner: motim de Prigozhin |
| 220 | ○ N | 2023 Q3 | RU | Prigozhin morre em queda de avião |
| 221 | ○ N | 2023 Q3 | NE | Níger: golpe |
| 222 | ○ N | 2023 Q4 | AR | Milei eleito (libertário) |
| 223 | ○ N | 2023 Q4 | BR | Brasil G20/COP — protagonismo climático |
| 224 | ○ N | 2023 Q3 | EC | Equador: ondas de violência narco |
| 225 | ○ N | 2023 Q4 | DE | Crise da Volkswagen + indústria |

### 2024 — Eleições e Conflitos

| # | Tipo | Ano/Q | Países | Evento |
|---|------|-------|--------|--------|
| 226 | ★ G | 2024 Q4 | US, global | **Eleição EUA 2024 — Trump retorna** (modal: postura) |
| 227 | ○ N | 2024 Q3 | FR | Macron dissolve parlamento, instabilidade |
| 228 | ○ R | 2024 Q4 | OrienteMédio | Tensão Israel-Líbano-Irã escala |
| 229 | ○ N | 2024 Q3 | VE | Maduro "vence" eleição contestada |
| 230 | ○ N | 2024 Q1 | RU | Navalny morre na prisão |
| 231 | ○ N | 2024 Q3 | BD | Bangladesh: protestos derrubam Hasina |
| 232 | ○ N | 2024 Q4 | KR | Coreia do Sul: tentativa lei marcial Yoon |
| 233 | ○ R | 2024 Q4 | África | Sudão: guerra civil escala |

---

### EVENTOS POR PAÍS (lista expandida — 4 eventos médios por país)

Lista até aqui cobre **~233 eventos âncora globais e regionais**. Pra chegar nos ~780, planejados **~3 eventos secundários por país** cobrindo: nascimento de líder marcante, crise econômica local, desastre natural local, evento cultural/esportivo, transição política. Vou listar abaixo apenas a estrutura — implementação em fase posterior, gerada parametrizada.

**Total estimado:**
- 233 eventos âncora detalhados acima
- 195 países × 3 = **585 eventos secundários** (gerados via templates parametrizados, ex: "{PAIS} sofre crise hídrica em {ANO}", "{PAIS} elege {LÍDER_TIPO}")
- **Total: 818 eventos** (passa dos 780 pedidos)

Templates de eventos secundários por categoria (cada país recebe 3):
- **Político** (eleição/transição/escândalo)
- **Econômico** (crise/boom/reforma)
- **Social** (protesto/conquista civil/marco cultural)
- **Natural** (desastre/clima/epidemia local)
- **Esportivo** (Copa/Olimpíada/título)
- **Tecnológico** (descoberta/lançamento/marco)

---

## CATÁLOGO MEGATRENDS 2025-2100

Eventos pós-2025 são **disparados por gatilhos de ano + estado global**, não datas fixas. Cada megatrend tem janela de probabilidade crescente.

### Década 2025-2034 — Era da AI e Pós-pandemia

- **AGI breakthrough** (gatilho: turno aleatório 2025-2032, prob crescente) — mudança paradigmática produtividade
- **Crise hídrica regional** (Mediterrâneo/Sul Asiático) com escassez
- **Pandemia leve** (lições do COVID, resposta rápida)
- **Polarização EUA-China** chega ao auge ou trégua
- **Decline do dólar** começa, BRICS lança moeda
- **Energia: solar+bateria** atingem paridade com fóssil
- **Primeiros refugiados climáticos em massa** (Bangladesh, Pacífico)
- **Robotização industrial** elimina ~20% empregos manufatura

### Década 2035-2044 — Ponto de Inflexão Climático

- **Geoengenharia solar** desperada (modal: aprovar/proibir)
- **Onda de calor letal** Sul Asiático/Oriente Médio (40k+ mortes)
- **Neve permanente desaparece** no Quilimanjaro/Andes baixos
- **Migração climática 100M pessoas** (modal: receber/fechar)
- **Extinção de coral** total Grande Barreira
- **AGI passa Turing test consistente**, debates regulatórios
- **Primeira interface cérebro-computador** comercial
- **Carros autônomos** dominam grandes cidades
- **Crise demográfica** Japão/Coreia/Itália: pop -10%
- **África ultrapassa 2 bilhões** de habitantes

### Década 2045-2054 — Reorganização Global

- **Colapso pesqueiro** Atlântico Norte
- **Furacões cat-6** se tornam comuns
- **Cidades costeiras** (Miami, Veneza, Jakarta) perdem áreas
- **Energia fusão** finalmente comercial (mudança PIB global)
- **Vida estendida** (terapias gênicas) — dilema de classe
- **Economia espacial** (mineração asteroides) decolar
- **China passa EUA em PIB** (ou vice-versa)
- **Nova ordem multipolar**: BRICS+ vs G7+
- **Primeiro ataque ciber** que derruba grid nacional
- **Bilionários crescem 10x** desigualdade no auge

### Década 2055-2064 — Ajuste Civilizacional

- **Renda Básica Universal** em 30+ países
- **Maioria do trabalho substituído** por AI/robôs
- **Movimentos contra automação** (luddismo 2.0)
- **Acordos climáticos forçados** sob pena de tarifas
- **Fim da era do petróleo** comercial (uso só petroquímica)
- **Cidades flutuantes** experimentais (Maldivas, Tuvalu)
- **Novo sistema monetário** baseado em recursos+energia
- **Primeira eleição** com candidato AI permitido

### Década 2065-2074 — Renascimento ou Decadência

- **Colônia lunar permanente** estabelecida
- **Primeiros humanos em Marte** (modal: que país lidera?)
- **Tratado de governança AI** global (modal: aderir)
- **Recuperação ambiental** começa a mostrar sinais
- **Reflorestamento** Amazônia/Sahel restaura biomas
- **Turismo espacial** popular (classe média alta)
- **Crise demográfica resolve-se** com longevidade
- **Identidade nacional desafiada** por nações virtuais

### Década 2075-2084 — Era da Abundância (?)

- **Energia praticamente livre** para 80% mundo
- **Doenças virais quase erradicadas** (mRNA universal)
- **Fim da escassez alimentar** (carne lab + agricultura vertical)
- **Maioria mundo** com acesso AI personal
- **Línguas pequenas** desaparecem (90% falam top-10)
- **Megaprojetos** (canal seco, ponte estreito Bering)
- **Conflitos agora** por água/dados, não terra/petróleo
- **Sistema multi-planeta** ONU

### Década 2085-2094 — Pré-Centenário

- **Vida média 100+ anos** em países desenvolvidos
- **População global pico** ~10.4B então declina
- **Singularidade tecnológica** (real ou plateau)
- **Primeira nação cyborg** com modificações generalizadas
- **Disputas pelo Ártico** descongelado
- **Recuperação Antártica** após colapso da camada
- **Reformulação da ONU** ou substituição

### Década 2095-2100 — Endgame

- **Centenário milênio** → balanço civilizacional
- **Primeiro contato extraterrestre** (gatilho ultra raro, modal)
- **Transição pós-humana** debate filosófico/político
- **Civilização tipo I** (Kardashev) atingida ou não
- **Final score do jogador** baseado em 100 anos jogados

---

## DADOS DAS NAÇÕES EM 2000 (resumo)

Vou criar `data/nations_2000.json` com snapshot do ano 2000. Diferenças críticas vs 2024:

### Top 20 PIB em 2000 (vs 2024)
| País | PIB 2000 | PIB 2024 | Mudança |
|------|----------|----------|---------|
| US | $10.3T | $25.5T | +148% |
| JP | $4.9T | $4.2T | -14% |
| DE | $1.9T | $4.1T | +115% |
| GB | $1.6T | $3.1T | +93% |
| FR | $1.4T | $2.8T | +100% |
| CN | $1.2T | $18.3T | +1425% |
| IT | $1.1T | $2.1T | +90% |
| CA | $740B | $2.1T | +183% |
| BR | $657B | $2.2T | +234% |
| MX | $683B | $1.7T | +148% |
| ES | $580B | $1.6T | +176% |
| KR | $560B | $1.7T | +204% |
| IN | $470B | $3.7T | +687% |
| AU | $410B | $1.7T | +315% |
| RU | $260B | $2.2T | +746% |
| TR | $270B | $1.0T | +270% |
| AR | $284B | $487B | +71% |

### Mudanças geopolíticas chave em 2000
- **Putin acabou de assumir** Rússia (estab baixa)
- **Talibã** controla Afeganistão
- **Saddam** governa Iraque
- **Mubarak** Egito, **Gaddafi** Líbia, **Ben Ali** Tunísia (todos cairão)
- **URSS** já caiu há 9 anos, repúblicas instáveis
- **Iugoslávia** ainda existe (cai em 2003)
- **Sudão do Sul** não existe (independente em 2011)
- **Kosovo** não independente
- **Tcheca/Polônia** etc não estão na UE ainda
- **Euro** acabou de entrar em vigor (1999, dinheiro 2002)
- **EUR** com 11 membros, expandirá pra 27

### Tecnologias disponíveis em 2000
Limitar `tecnologias_concluidas` a:
- Internet básica (não mobile generalizado)
- GPS militar (civil limitado)
- DNA (acabou de ser sequenciado humano em 2000)
- **Sem:** smartphone, redes sociais, AI, blockchain, mRNA, energia solar barata, edição genética CRISPR, etc

### Estabilidade ajustada em 2000
- **EUA**: estab 80 (paz, Clinton legado)
- **Europa Ocidental**: 75-85 (paz pós-fria)
- **Rússia**: 35 (Putin acabando consolidar, pós-1998)
- **China**: 65 (crescendo, pré-OMC)
- **Brasil**: 55 (FHC fim do mandato)
- **Argentina**: 30 (vai colapsar 2001)
- **Iraque/Afeganistão/Síria**: 30-50 (pré-invasões)
- **Venezuela**: 60 (Chávez recém-eleito)

---

## ARQUITETURA DA IMPLEMENTAÇÃO

### Arquivos novos a criar
1. `data/events_timeline.json` — catálogo dos 233 eventos âncora
2. `data/events_per_country.json` — 585 eventos por país (gerados parametrizados)
3. `data/megatrends_2025_2100.json` — gatilhos pós-2024
4. `data/nations_2000.json` — snapshot 2000
5. `scripts/EventTimeline.gd` — gerencia disparos baseados em ano+quarter+condições
6. `scripts/HistoricalDecisionModal.gd` — modal especial pra eventos com escolha
7. `scripts/MegatrendEngine.gd` — gera eventos pós-2025 com prob crescente

### Modificações em arquivos existentes
- `GameEngine.gd`: ano inicial 2000, settings.mode = "livre"|"inspirado", chamar EventTimeline.process_turn()
- `MainMenu.gd`: opção de modo na tela inicial
- `WorldMap.gd`: handler pra modais de decisão histórica
- `Nation.gd`: from_dict aceita year_snapshot pra carregar 2000

### Sistema de modos
**Modo "Inspirado":**
- Eventos âncora disparam exatamente em year_window
- Modal de decisão pro jogador (se afetado)
- Stats das outras nações ajustados pra "seguir" história mesmo se jogador divergir

**Modo "Livre":**
- Eventos âncora disparam aleatório dentro de janela 5x maior
- Outras nações reagem livremente sem constraint histórico
- Megatrends ainda funcionam por gatilho de turno

---

## PLANO DE EXECUÇÃO (FASES)

### ✅ FASE 0 — Catálogo (este documento)
Listar tudo. Concluída.

### 🔧 FASE 1 — Infra básica (PRÓXIMA)
- Mudar ano inicial 2000
- Criar settings.mode (livre/inspirado)
- Adicionar opção "modo de jogo" na tela inicial
- EventTimeline.gd com process_turn vazio (skeleton)

### 🔧 FASE 2 — Reset stats 2000
- Criar nations_2000.json com PIB/pop/regime/estab ajustados
- Reset tecnologias_concluidas (lista pré-2000)
- GameEngine carrega nations_2000 quando ano==2000

### 🔧 FASE 3 — Eventos âncora 2000-2024
- Criar events_timeline.json com primeiros 30 (mais marcantes)
- EventTimeline disparando por ano+quarter
- Aplicar effects_immediate (sem modal ainda)

### 🔧 FASE 4 — Modais de decisão
- HistoricalDecisionModal.gd
- Gatilho: evento com modal_decision=true e jogador é primary_country
- Aplicar choices.effects

### 🔧 FASE 5 — Eventos secundários por país (em batches)
- Templates parametrizados
- Gerar 3 eventos por país via script (seed determinístico)
- Cobrir os 195 países

### 🔧 FASE 6 — Megatrends 2025-2100
- MegatrendEngine.gd
- Gatilhos por década com prob crescente
- Gerar eventos sintéticos plausíveis

### 🔧 FASE 7 — Polish
- Histórico de decisões salvas no save
- Notificações de "evento histórico próximo"
- Estatísticas de divergência (jogador vs história real)

---

## STATUS

| Fase | Status |
|------|--------|
| 0 — Catálogo | ✅ ESTE DOCUMENTO |
| 1 — Infra básica | 🔜 Próxima |
| 2 — Reset stats 2000 | ⏳ |
| 3 — Eventos âncora | ⏳ |
| 4 — Modais decisão | ⏳ |
| 5 — Eventos por país | ⏳ |
| 6 — Megatrends | ⏳ |
| 7 — Polish | ⏳ |
