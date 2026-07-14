# 💰 PLANO ECONÔMICO — Comércio, Finanças e Mercados

Roadmap em 4 fases. Decisões travadas com o usuário:
- **Começar pela balança comercial import/export** (a base de tudo)
- **Bolsa/cripto complementares, não dominantes** — governar bem > especular;
  não dá pra "vencer só no day-trade". Mantém o foco de simulador geopolítico.

---

## 🗺 ROADMAP

| Fase | Sistema | Status |
|---|---|---|
| **1** | Balança comercial (import/export por setor, superávit/déficit) | ← AGORA |
| 2 | Empréstimos proativos + tesouro ativo (alavancagem estratégica) | próxima |
| 3 | Mercado de ações (índice nacional + global) | depois |
| 4 | Criptomoedas (ativo volátil, ciclos, adoção) | por último |

Cada fase é testada (SystemsCheck + MegaSim) e commitada antes da seguinte.

---

## 📦 FASE 1 — BALANÇA COMERCIAL (detalhada)

Hoje "exportação" é uma **média genérica** dos recursos (`calc_receita_exportacao`).
A Fase 1 transforma isso numa **balança comercial real**: o que cada nação
exporta E importa, com saldo que afeta tesouro, PIB e vulnerabilidade.

### Conceito
Cada nação tem um **perfil comercial** derivado dos seus recursos e do seu
desenvolvimento:
- **Exporta** o que tem em abundância (petróleo, soja, minério, manufatura…)
- **Importa** o que lhe falta (uma nação sem tech importa eletrônicos; sem
  terras aráveis importa comida; sem energia importa combustível)
- **Saldo comercial** = exportações − importações → superávit (entra $) ou
  déficit (sai $, pressiona a moeda/inflação)

### Modelagem (em `Nation`)
```
exportacoes: Dictionary   # setor -> $B/ano  (derivado dos recursos altos)
importacoes: Dictionary   # setor -> $B/ano  (derivado das carências)
func calc_balanca_comercial() -> float   # exportações − importações (trimestral)
```
- **Exportações**: para cada recurso ≥ 60/100, gera exportação proporcional ao
  PIB × nível do recurso × preço global da commodity (choques energéticos já
  mexem nisso via `commodity_multiplier`)
- **Importações**: carências estruturais geram importação:
  - poucas `terras_araveis`/`agricultura` → importa **alimentos**
  - pouca `tecnologia`/`manufatura` → importa **bens industriais/eletrônicos**
  - pouco `petroleo`/`gas`/`energias_renovaveis` → importa **energia**
  - o volume de importação cresce com o PIB (economia grande consome mais)
- **Saldo** entra na receita (substitui o `export_bonus` genérico por algo real)

### Efeitos de gameplay
- **Superávit comercial** → entrada de divisas, fortalece tesouro e IED
- **Déficit comercial** → saída de divisas; déficit grande pressiona inflação
  e drena reservas (realista: crises cambiais)
- **Dependência de importação** → nação que importa energia/comida fica
  **vulnerável a choques** (crise energética dói mais em quem importa energia)
  e a **bloqueios/sanções** (já existem no jogo — agora com dente econômico)
- **Diversificação** → exportar muitos setores diferentes = economia resiliente;
  depender de 1 commodity (petro-estado) = frágil a choques daquele setor

### Conexões com o que já existe
- **Choques globais**: crise energética já dobra valor de exportação de
  petróleo — agora TAMBÉM encarece a importação de quem depende de energia
- **Comércio bilateral** (`active_trades`): acordos entre nações passam a
  reduzir a importação do importador e somar à exportação do exportador
- **Sanções/guerra**: cortam rotas comerciais → choque no saldo do alvo
- **Corrupção/IED**: economia aberta e confiável atrai mais comércio

### UI (painel Fazenda)
```
■ BALANÇA COMERCIAL (ano)
  Exportações   +$142B   petróleo, soja, minério
  Importações   −$98B    eletrônicos, energia, remédios
  Saldo         +$44B  ▲ superávit
  Dependência:  ⚠ importa 60% da energia (vulnerável a choques)
```

### Testes
- SystemsCheck: petro-estado tem superávit; nação sem tech importa
  industriais; saldo entra no tesouro; choque energético pune importador
- MegaSim: balança não quebra finanças; superavitários crescem mais;
  petro-estados sofrem em crise; 0 anomalias

---

## 🏦 FASE 2 — Empréstimos proativos + tesouro ativo (resumo)
- Jogador ESCOLHE pegar empréstimo (não só FMI em crise) para investir cedo
- Diferentes credores: mercado (juro por rating), bilateral (aliado), FMI
- Rating de crédito derivado de dívida/PIB, estabilidade, histórico de default
- Alavancagem: dívida barata p/ investir em infra/tech pode acelerar — ou
  afundar se mal administrada

## 📈 FASE 3 — Mercado de ações (resumo)
- Índice nacional (reflete a saúde da própria economia) + índice global
- Jogador investe tesouro OCIOSO; retorno ≤ ~15% do crescimento total possível
  (complementar, não dominante)
- Ciclos de alta/baixa ligados a choques globais e ao estado do mundo

## ₿ FASE 4 — Criptomoedas (resumo)
- Ativo de altíssima volatilidade, ciclos bull/bear, risco de colapso
- Decisão soberana: adotar como moeda legal (El Salvador) — bônus e riscos
- Nações sob sanção podem usar cripto p/ driblar bloqueios (realista)

---

## Princípio geral
A riqueza de uma nação vem de **governar bem** — indústria, tecnologia,
instituições, comércio equilibrado. Bolsa e cripto são temperos de risco
para tesouro ocioso, nunca o caminho principal. O simulador continua sério.
