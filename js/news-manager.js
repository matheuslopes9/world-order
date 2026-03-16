/**
 * NewsManager — Gerador de notícias mundiais para o World Order.
 *
 * Mantém um feed rolante de notícias geradas a cada turno,
 * categorizadas por tema com textos variados e contextualização
 * de dados reais do estado do jogo.
 */
class NewsManager {
    constructor() {
        this.feed = [];          // array de notícias (mais recente primeiro)
        this.maxFeed = 80;       // limite do feed
    }

    // ─── Categorias ────────────────────────────────────────────────────────
    static get CATEGORIES() {
        return {
            tecnologia: { label: 'Tecnologia', icon: '🔬', color: '#00d2ff', bg: 'rgba(0,210,255,0.12)' },
            medicina:   { label: 'Medicina',   icon: '🧬', color: '#00ff88', bg: 'rgba(0,255,136,0.12)' },
            militar:    { label: 'Militar',    icon: '⚔️', color: '#ff4444', bg: 'rgba(255,68,68,0.12)' },
            social:     { label: 'Social',     icon: '👥', color: '#ffaa00', bg: 'rgba(255,170,0,0.12)' },
            economia:   { label: 'Economia',   icon: '📈', color: '#22c55e', bg: 'rgba(34,197,94,0.12)' },
            politica:   { label: 'Política',   icon: '🏛',  color: '#a78bfa', bg: 'rgba(167,139,250,0.12)' },
            clima:      { label: 'Clima',      icon: '🌍',  color: '#4fc3f7', bg: 'rgba(79,195,247,0.12)' },
            descoberta: { label: 'Descoberta', icon: '💡',  color: '#fbbf24', bg: 'rgba(251,191,36,0.12)' },
        };
    }

    // ─── Pool de templates ──────────────────────────────────────────────────
    static get TEMPLATES() {
        return {
            tecnologia: [
                { h: 'Novo processador quântico supera barreira dos {X} qubits operacionais', b: 'Pesquisadores anunciam avanço que pode transformar criptografia global.', u: 'high' },
                { h: 'Empresa lança bateria de estado sólido com {X}x mais capacidade que Li-Ion', b: 'Autonomia de veículos elétricos pode chegar a 2.000 km por carga.', u: 'normal' },
                { h: 'IA desenvolvida por consórcio resolve proteínas desconhecidas em horas', b: 'Modelagem proteica pode acelerar descoberta de fármacos em décadas.', u: 'high' },
                { h: 'Primeira impressora 3D de órgãos humanos vascularizados aprovada para testes', b: 'Rins funcionais impressos com células-tronco do próprio paciente.', u: 'high' },
                { h: 'Satélite de comunicações quânticas estabelece link de {X}.000 km sem interceptação', b: 'Tecnologia QKD promete rede inquebrável de comunicações governamentais.', u: 'normal' },
                { h: 'Supercomputador atinge {X} exaflops, recorde mundial absoluto', b: 'Capacidade equivale a 10 bilhões de computadores pessoais operando simultaneamente.', u: 'normal' },
                { h: 'Empresa de defesa apresenta exoesqueleto robótico para uso em combate', b: 'Soldado com o dispositivo carrega 150 kg e opera por 8 horas com bateria de hidrogênio.', u: 'high' },
                { h: 'Redes neurais superam humanos em leitura de imagens médicas com 99,{X}% de precisão', b: 'Sistema detecta cânceres em estágio 0, antes de qualquer sintoma.', u: 'high' },
                { h: 'Piloto automático de 5ª geração substitui pilotos em voos comerciais de teste', b: 'Autoridades de aviação debatem regulação para adoção em larga escala.', u: 'normal' },
                { h: 'Nanorrobôs entram em fase 2 de testes: eliminam células tumorais in vivo', b: 'Partículas de 200nm guiadas por campos magnéticos atacam tumores com precisão cirúrgica.', u: 'critical' },
                { h: 'Fusão nuclear a laser atinge ganho de energia de {X}00% pela primeira vez', b: 'Instituto de pesquisa confirma reação que gerou mais energia do que consumiu.', u: 'critical' },
                { h: 'Computação molecular: DNA usado como disco rígido armazena {X} petabytes por grama', b: 'Dados preservados por séculos sem degradação, segundo pesquisadores.', u: 'normal' },
            ],
            medicina: [
                { h: 'Vacina mRNA eficaz contra {X} cepas de influenza entra em fase 3', b: 'Uma única dose anual substituiria as vacinas sazonais actuais.', u: 'high' },
                { h: 'Terapia genética CRISPR cura hemofilia severa em {X}0 pacientes adultos', b: 'Primeiro tratamento definitivo da doença hematológica sem transfusões periódicas.', u: 'critical' },
                { h: 'Novo antibiótico derivado de fungo antártico elimina superbactérias resistentes', b: 'Descoberta pode reverter crise global de resistência antimicrobiana.', u: 'critical' },
                { h: 'Transplante de retina artificial restaura visão em pacientes com cegueira total', b: 'Chip de 1024 pixels implantado conecta-se diretamente ao nervo óptico.', u: 'high' },
                { h: 'Pesquisadores mapeiam mecanismo de alzheimer e testam reversão em modelos animais', b: 'Proteína Tau identificada como alvo terapêutico viável em primatas.', u: 'high' },
                { h: 'Pandemia de gripe aviária H{X}N{X} declarada em 3 países; OMS em alerta máximo', b: 'Taxa de mortalidade de {X}% em humanos preocupa autoridades sanitárias.', u: 'critical' },
                { h: 'Injeção anual substitui insulina diária para {X} milhões de diabéticos tipo 1', b: 'Nanocápsulas de liberação controlada mantêm glicose estável por 30 dias.', u: 'high' },
                { h: 'Surto de doença hemorrágica desconhecida isolado; equipes de contenção no local', b: 'OMS envia especialistas para investigar casos em região remota.', u: 'critical' },
                { h: 'Cura funcional para HIV: {X}0 pacientes sem vírus detectável há 5 anos', b: 'Terapia de edição genômica permanece testada em longa duração.', u: 'critical' },
                { h: 'Impressão 3D de pele humana vascularizada viabiliza transplantes sem doadores', b: 'Técnica testada com sucesso em queimaduras de grau 3.', u: 'high' },
                { h: 'Composto derivado de cogumelo estabiliza progressão do Parkinson em ensaio clínico', b: 'Redução de tremores em 60% dos pacientes após 6 meses de tratamento.', u: 'high' },
                { h: 'IA detecta Covid-{X}0 variante antes de sintomas, com 4 dias de antecedência', b: 'Algoritmo treinado em biossensores de respiração identifica padrão único.', u: 'normal' },
            ],
            militar: [
                { h: '{PAIS} realiza teste de míssil hipersônico de alcance de {X}.000 km', b: 'Veículo planejante viaja a Mach 25 e manobra para evitar sistemas de defesa.', u: 'critical' },
                { h: 'Drone enxame autônomo de {PAIS} destrói {X}0 alvos em manobra de 90 segundos', b: 'Coordenação por IA sem intervenção humana levanta debate sobre direito internacional.', u: 'high' },
                { h: 'Novo porta-aviões de propulsão nuclear de {PAIS} entra em serviço operacional', b: 'Embarcação de 100.000 toneladas redimensiona equilíbrio de poder marítimo regional.', u: 'high' },
                { h: 'Sistema de laser de alta energia derruba 10 drones simultâneos em teste de {PAIS}', b: 'Custo de interceptação de US$ 3 por alvo frente a US$ 30.000 dos mísseis convencionais.', u: 'normal' },
                { h: 'Conflito armado entre facções paramilitares deixa {X}00 mortos em {X} dias', b: 'ONU solicita cessar-fogo imediato e corredor humanitário.', u: 'critical' },
                { h: '{PAIS} ativa reservistas e mobiliza {X}0.000 soldados na fronteira norte', b: 'Tensão escala após incidentes fronteiriços não resolvidos.', u: 'critical' },
                { h: 'Ciberataque à infraestrutura crítica de {PAIS} atribuído a grupo estatal', b: 'Redes elétricas e hospitais afetados por 6 horas; governo nega envolvimento.', u: 'critical' },
                { h: 'Novo submarino furtivo de {PAIS} opera sem reabastecimento por {X} meses', b: 'Propulsão de célula de combustível de hidrogênio elimina necessidade de schnorkel.', u: 'high' },
                { h: 'Tratado de controle de armas nucleares expira sem renovação entre potências', b: 'Analistas alertam para novo ciclo de corrida armamentista.', u: 'critical' },
                { h: 'Robôs de combate terrestre de {PAIS} testados em zona de conflito ativo pela 1ª vez', b: 'Plataforma autônoma armada patrulha área de 200 km² sem baixas humanas aliadas.', u: 'high' },
                { h: '{PAIS} conduz exercício naval com {X} navios de guerra no Mar da China', b: 'Manobras vistas como demonstração de força por nações vizinhas.', u: 'high' },
                { h: 'Unidade de guerra eletrônica neutraliza comunicações de {PAIS} por 2 horas', b: 'Incidente classificado como ato de guerra por autoridades do país afetado.', u: 'critical' },
            ],
            social: [
                { h: 'Protestos em massa em {X} cidades exigem reforma do sistema de saúde pública', b: 'Movimento reúne {X} milhões nas ruas em maior onda de manifestações da década.', u: 'high' },
                { h: 'Greve geral paralisa {PAIS} por {X} dias; perdas econômicas estimadas em $30B', b: 'Sindicatos exigem aumento de 25% no salário mínimo e redução da jornada.', u: 'high' },
                { h: 'Taxa de natalidade global cai a 1,6 filhos por mulher, mínimo histórico', b: 'Declínio acelerado em países industrializados levanta alerta para crise demográfica.', u: 'normal' },
                { h: 'Êxodo urbano inverte tendência: {X} milhões retornam ao interior após pandemia', b: 'Trabalho remoto e custo de vida impulsionam migração para cidades menores.', u: 'normal' },
                { h: 'Movimento antitecnologia cresce em {X} países: protestos contra automação e IA', b: 'Trabalhadores de setores industriais temem substituição em massa por robôs.', u: 'high' },
                { h: 'Crise de habitação: {X}% da população urbana gasta mais de 50% da renda com moradia', b: 'ONU alerta para risco de explosão social nas 20 maiores cidades do mundo.', u: 'high' },
                { h: 'Pesquisa revela que {X}0% dos jovens entre 18-25 anos preferem trabalho remoto integral', b: 'Empresas disputam talentos com pacotes flexíveis em contexto de escassez global.', u: 'normal' },
                { h: 'Conflito religioso deixa {X}00 mortos em região historicamente volátil', b: 'Mediadores internacionais convocados para negociação de emergência.', u: 'critical' },
                { h: 'Crise migratória: {X}00 mil refugiados cruzam fronteiras em {X} semanas', b: 'Países receptores declaram estado de emergência humanitária.', u: 'critical' },
                { h: 'Índice de felicidade global declina pelo {X}º ano consecutivo, revela ONU', b: 'Insegurança econômica e polarização política apontados como fatores principais.', u: 'normal' },
            ],
            economia: [
                { h: '{PAIS} anuncia abandono do dólar em acordos bilaterais com {X} países', b: 'Alternativa baseada em cesta de moedas representa desafio à hegemonia do USD.', u: 'high' },
                { h: 'Inflação em {PAIS} atinge {X}% ao ano, maior nível em 30 anos', b: 'Banco central eleva taxa básica de juros pela {X}ª vez consecutiva.', u: 'high' },
                { h: 'Bolsas globais despencam {X}% após dados de recessão sincronizada em G7', b: 'Fuga para ativos de refúgio; ouro atinge máxima histórica de $3.{X}00/oz.', u: 'critical' },
                { h: 'Criptomoeda estatal de {PAIS} adotada como moeda oficial complementar', b: 'CBDC integra sistema de pagamentos e permite rastreamento de transações em tempo real.', u: 'normal' },
                { h: 'Desemprego estrutural causado por IA atinge {X}0% em setores de serviços', b: 'Economistas debatem renda básica universal como resposta a nível global.', u: 'high' },
                { h: 'Fusão megacorporativa cria empresa com valor de mercado superior ao PIB de {X}0 países', b: 'Reguladores antitruste de {X} jurisdições investigam concentração de poder.', u: 'high' },
                { h: 'Preço do petróleo colapsa {X}0% após cartel OPEP+ anuncia aumento de produção', b: 'Países exportadores enfrentam déficits orçamentários de emergência.', u: 'critical' },
                { h: 'Terras raras: {PAIS} descobre reserva de {X} bilhões de toneladas em profundidade oceânica', b: 'Descoberta pode reequilibrar mercado global dominado por poucos produtores.', u: 'high' },
                { h: 'Dívida soberana de {PAIS} rebaixada a junk; risco de default declarado', b: 'FMI convoca reunião de emergência com credores internacionais.', u: 'critical' },
                { h: 'Corrida por minério de lítio impulsiona investimentos de $500B em {X} anos', b: 'Demanda explosiva por baterias pressiona países produtores do Triângulo do Lítio.', u: 'normal' },
            ],
            politica: [
                { h: 'Golpe de estado em {PAIS}: militares assumem governo após dissolução do parlamento', b: 'Constituição suspensa; líderes de oposição detidos nas primeiras horas.', u: 'critical' },
                { h: 'Eleições em {PAIS}: partido de oposição vence com {X}% dos votos', b: 'Analistas apontam inflação e corrupção como fatores decisivos na derrota do governo.', u: 'high' },
                { h: 'ONU vota resolução sobre crise humanitária com placar de {X}0-{X} votos', b: 'Veto de membro permanente bloqueia ação mais robusta do Conselho de Segurança.', u: 'high' },
                { h: 'Presidente de {PAIS} declara estado de emergência nacional por 90 dias', b: 'Medida suspende liberdades civis e concentra poder no executivo.', u: 'critical' },
                { h: 'Aliança regional entre {X} nações desafia arquitetura de segurança ocidental', b: 'Novo pacto prevê defesa mútua e integração econômica acelerada.', u: 'high' },
                { h: 'Escândalo de espionagem: {PAIS} acusa {PAIS} de infiltração em ministérios-chave', b: 'Embaixador expulso; relações diplomáticas rebaixadas a nível mínimo.', u: 'critical' },
                { h: 'Referendo de independência em região separatista aprova secessão com {X}% dos votos', b: 'Governo central não reconhece resultado; tensão escala com presença militar.', u: 'critical' },
                { h: 'Tribunal Internacional condena líder de {PAIS} por crimes contra a humanidade', b: 'Mandado de prisão emitido; país rejeita jurisdição e se recusa a extraditar.', u: 'critical' },
                { h: 'Cúpula de {X}0 líderes mundiais fracassa sem acordo sobre crise climática', b: 'Países em desenvolvimento exigem fundo de compensação bilionário como condição.', u: 'high' },
                { h: 'Partido de extrema direita conquista maioria parlamentar em {PAIS}', b: 'Plataforma anti-imigração e revisão de tratados multilaterais alarma parceiros.', u: 'high' },
            ],
            clima: [
                { h: 'Temperatura global de {MES} bate recorde pelo {X}º mês consecutivo', b: 'Média 1,8°C acima da era pré-industrial acelera discussões de emergência climática.', u: 'high' },
                { h: 'Furacão de categoria 6 devasta costa de {PAIS}: {X}00 mil desalojados', b: 'Ventos de 350 km/h são os maiores já registrados no Atlântico Norte.', u: 'critical' },
                { h: 'Seca histórica na bacia do Rio Nilo ameaça abastecimento de {X}0 milhões', b: 'Tensão entre países ribeirinhos eleva risco de conflito por água.', u: 'critical' },
                { h: 'Plataforma de gelo da Antártida do tamanho da {PAIS} se desprende em {X} horas', b: 'Especialistas alertam para elevação do nível do mar de até 3m até 2100.', u: 'critical' },
                { h: 'Onda de calor em {PAIS} mata {X}.000 pessoas em duas semanas', b: 'Recordes absolutos de temperatura quebrados em {X}0 estações meteorológicas.', u: 'critical' },
                { h: 'Corais de 30% das barreiras de recife do planeta morrem em evento de branqueamento', b: 'Ecossistema marinho vital para {X} bilhões de pessoas em risco iminente.', u: 'high' },
                { h: 'Incêndios florestais consomem {X} milhões de hectares em {X} dias', b: 'Fumaça cobre área de 5 milhões de km² e afeta qualidade do ar em 3 continentes.', u: 'critical' },
                { h: 'Novo modelo climático prevê ponto de não retorno em {X} anos sem ação imediata', b: 'Relatório do IPCC: descarbonização total necessária antes de 2045.', u: 'high' },
                { h: 'Geoengenharia solar testada: aerossóis na estratosfera reduzem temperatura 0,{X}°C', b: 'Experimento controverso divide cientistas sobre riscos e governança.', u: 'high' },
                { h: 'Dessertificação avança {X} km/ano no Sahel; {X} nações em risco de colapso agrícola', b: 'Programas de reflorestamento emergencial lançados por consórcio internacional.', u: 'high' },
            ],
            descoberta: [
                { h: 'Astrônomos detectam sinal de rádio repetitivo a {X}00 anos-luz: origem desconhecida', b: 'Sinal em padrão não-natural levanta hipóteses de origem artificial.', u: 'high' },
                { h: 'Nova espécie de primata inteligente descoberta em floresta tropical; usa ferramentas complexas', b: 'Pesquisadores registram comportamento de manufatura de abrigo e cultivo básico.', u: 'normal' },
                { h: 'Fóssil de {X}00 milhões de anos revela forma de vida multicelular mais antiga conhecida', b: 'Descoberta reescreve linha do tempo da evolução de organismos complexos.', u: 'normal' },
                { h: 'Telescópio espacial capta atmosfera com oxigênio e metano em exoplaneta habitable', b: 'Biossinatura potencial a {X}0 anos-luz levanta debate científico global.', u: 'critical' },
                { h: 'Arqueólogos encontram cidade submersa de {X}.000 anos com escrita não decifrada', b: 'Complexo de {X} km² desafia narrativas sobre origem das civilizações.', u: 'high' },
                { h: 'Material superconductor à temperatura ambiente sintetizado em laboratório', b: 'Se reproduzido em escala, poderia eliminar perdas em toda a rede elétrica global.', u: 'critical' },
                { h: 'Partícula subatômica desconhecida detectada em colisão: modelo padrão em xeque', b: 'Física além do modelo padrão abriria caminho para novas formas de energia.', u: 'high' },
                { h: 'Fungos de profundidade marinha produzem antibiótico inédito de alto espectro', b: 'Composto ativo contra {X}0 cepas resistentes em testes preliminares.', u: 'high' },
                { h: 'Telescópio registra explosão cósmica {X}.000 vezes mais brilhante que galáxia inteira', b: 'Hipernova a {X} bilhões de anos-luz é o evento mais energético já observado.', u: 'normal' },
                { h: 'Linguagem de polvos: pesquisa decifra {X}00 padrões de comunicação cromatofórica', b: 'Cefalópodes podem possuir sistema linguístico comparável ao de primatas.', u: 'normal' },
            ],
        };
    }

    // ─── Geração de notícias por turno ─────────────────────────────────────

    generateTurnNews(engine) {
        const state   = engine.state;
        const nations = engine.data.nations;
        const codes   = Object.keys(nations);

        // Escolhe países para contextualizar notícias
        const rndNation = () => {
            const n = nations[codes[Math.floor(Math.random() * codes.length)]];
            return n ? n.nome : 'País Desconhecido';
        };

        const cats  = Object.keys(NewsManager.TEMPLATES);
        const count = 3 + Math.floor(Math.random() * 3); // 3–5 notícias por turno
        const generated = [];

        for (let i = 0; i < count; i++) {
            // Peso extra para notícias militares se DEFCON alto
            let cat;
            if (state.defcon <= 2 && Math.random() < 0.5) {
                cat = 'militar';
            } else if (state.defcon <= 3 && Math.random() < 0.3) {
                cat = Math.random() < 0.5 ? 'militar' : 'politica';
            } else {
                cat = cats[Math.floor(Math.random() * cats.length)];
            }

            const pool     = NewsManager.TEMPLATES[cat];
            const template = pool[Math.floor(Math.random() * pool.length)];
            const catDef   = NewsManager.CATEGORIES[cat];

            // Substitui tokens
            const x1 = Math.floor(Math.random() * 8) + 2;
            const x2 = Math.floor(Math.random() * 9) + 1;
            const meses = ['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];
            const mes   = meses[Math.floor(Math.random() * 12)];

            const replace = str => str
                .replace(/\{X\}/g, () => Math.floor(Math.random() * 900 + 10))
                .replace(/\{PAIS\}/g, rndNation)
                .replace(/\{MES\}/g, mes);

            generated.push({
                id:       `news_${Date.now()}_${i}`,
                cat:      cat,
                catLabel: catDef.label,
                catIcon:  catDef.icon,
                catColor: catDef.color,
                catBg:    catDef.bg,
                headline: replace(template.h),
                body:     replace(template.b),
                urgency:  template.u,  // 'normal' | 'high' | 'critical'
                date:     `T${state.currentTurn} — ${this._quarterLabel(state.date)}`,
                turn:     state.currentTurn,
                isNew:    true,
            });
        }

        // Adiciona notícias de eventos do jogo (ações do player / AI)
        const gameEvents = engine.state.recentGameEvents || [];
        gameEvents.forEach(ev => {
            generated.push({
                id:       `gev_${Date.now()}_${Math.random()}`,
                cat:      ev.cat || 'politica',
                catLabel: NewsManager.CATEGORIES[ev.cat || 'politica'].label,
                catIcon:  NewsManager.CATEGORIES[ev.cat || 'politica'].icon,
                catColor: NewsManager.CATEGORIES[ev.cat || 'politica'].color,
                catBg:    NewsManager.CATEGORIES[ev.cat || 'politica'].bg,
                headline: ev.headline,
                body:     ev.body || '',
                urgency:  ev.urgency || 'high',
                date:     `T${state.currentTurn} — ${this._quarterLabel(state.date)}`,
                turn:     state.currentTurn,
                isNew:    true,
                isGameEvent: true,
            });
        });
        engine.state.recentGameEvents = []; // limpa eventos consumidos

        // Prepend ao feed (mais recente primeiro)
        this.feed = [...generated, ...this.feed].slice(0, this.maxFeed);
        return generated;
    }

    _quarterLabel(date) {
        return `Q${date.quarter} ${date.year}`;
    }

    /** Retorna últimas N notícias, opcionalmente filtradas por categoria */
    getNews(limit = 40, cat = 'all') {
        let list = this.feed;
        if (cat !== 'all') list = list.filter(n => n.cat === cat);
        return list.slice(0, limit);
    }

    /** Retorna as últimas N para o ticker (apenas headlines) */
    getTickerItems(limit = 20) {
        return this.feed.slice(0, limit);
    }

    /** Marca todas como vistas */
    markAllRead() {
        this.feed.forEach(n => { n.isNew = false; });
    }

    /** Conta notícias novas */
    get unreadCount() {
        return this.feed.filter(n => n.isNew).length;
    }
}
