/**
 * EconomyManager — Sistema econômico global do World Order.
 *
 * Gerencia:
 *  1. Rotas comerciais reais entre nações (energia, alimentos, minerais, manufatura)
 *  2. Empresas ficcionais com mercado de ações por setor
 *  3. Criptomoedas com preços voláteis e carteira do jogador
 *
 * Integração: chamado a cada turno via engine.economy.processTurn()
 */
class EconomyManager {

    constructor(engine) {
        this.engine = engine;

        // ── Preços globais de commodities (índice 0-200, 100 = base) ─────────
        this.commodityPrices = {
            petroleo:       100,
            gas_natural:    100,
            minérios:       100,
            alimentos:      100,
            metais:         100,
            tecnologia:     100,
        };

        // ── Portfólio do jogador ──────────────────────────────────────────────
        // { companyId: { shares: N, avgCost: $B } }
        this.portfolio   = {};
        // { cryptoId: amount }
        this.cryptoWallet = {};

        // ── Inicializa dados estáticos ────────────────────────────────────────
        this.routes    = this._buildRoutes();
        this.companies = this._buildCompanies();
        this.cryptos   = this._buildCryptos();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // DADOS ESTÁTICOS
    // ═══════════════════════════════════════════════════════════════════════

    /** Rotas comerciais mundiais reais (simplificadas). */
    _buildRoutes() {
        // type: 'energia' | 'alimentos' | 'minerios' | 'manufatura' | 'financas'
        return [
            // ── ENERGIA — PETRÓLEO ──────────────────────────────────────────
            { id:'r01', from:'SA', to:'CN', commodity:'Petróleo',     type:'energia',   valor:52, desc:'Maior corredor de petróleo bruto do mundo' },
            { id:'r02', from:'SA', to:'JP', commodity:'Petróleo',     type:'energia',   valor:38, desc:'Rota histórica do Golfo ao Japão' },
            { id:'r03', from:'SA', to:'KR', commodity:'Petróleo',     type:'energia',   valor:28, desc:'Coreia importa 70% do seu petróleo do Golfo' },
            { id:'r04', from:'SA', to:'IN', commodity:'Petróleo',     type:'energia',   valor:44, desc:'Índia: maior comprador de crescimento rápido' },
            { id:'r05', from:'IQ', to:'IN', commodity:'Petróleo',     type:'energia',   valor:22, desc:'Iraque é o 2° fornecedor da Índia' },
            { id:'r06', from:'IQ', to:'CN', commodity:'Petróleo',     type:'energia',   valor:18, desc:'Iraque substitui Rússia no mercado chinês' },
            { id:'r07', from:'AE', to:'IN', commodity:'Petróleo',     type:'energia',   valor:17, desc:'EAU — Hub regional do Golfo' },
            { id:'r08', from:'NG', to:'IN', commodity:'Petróleo',     type:'energia',   valor:12, desc:'Petróleo nigeriano para refinarias indianas' },
            { id:'r09', from:'NG', to:'FR', commodity:'Petróleo',     type:'energia',   valor:10, desc:'Legado da influência francesa na África Ocidental' },
            { id:'r10', from:'NG', to:'IT', commodity:'Petróleo',     type:'energia',   valor:9,  desc:'Itália: principal destino europeu do petróleo nigeriano' },
            { id:'r11', from:'RU', to:'CN', commodity:'Petróleo/Gás', type:'energia',   valor:68, desc:'Poder Sibéria: pipeline recém-inaugurado' },
            { id:'r12', from:'RU', to:'DE', commodity:'Gás Natural',  type:'energia',   valor:35, desc:'Nord Stream: parcialmente suspenso (tensão geopolítica)' },
            { id:'r13', from:'RU', to:'TR', commodity:'Gás Natural',  type:'energia',   valor:22, desc:'TurkStream: rota alternativa via Turquia' },
            { id:'r14', from:'US', to:'EU', commodity:'GNL',          type:'energia',   valor:30, desc:'EUA supre déficit europeu pós-Rússia' },
            { id:'r15', from:'QA', to:'JP', commodity:'GNL',          type:'energia',   valor:25, desc:'Qatar: maior exportador de GNL do mundo' },
            { id:'r16', from:'QA', to:'IN', commodity:'GNL',          type:'energia',   valor:18, desc:'Qatar abastece crescimento energético da Índia' },
            { id:'r17', from:'AU', to:'JP', commodity:'GNL',          type:'energia',   valor:22, desc:'Austrália: 2ª maior exportadora de GNL' },
            { id:'r18', from:'AU', to:'CN', commodity:'Carvão',       type:'energia',   valor:35, desc:'Carvão térmico australiano para geração chinesa' },
            { id:'r19', from:'KZ', to:'CN', commodity:'Petróleo',     type:'energia',   valor:14, desc:'Pipeline Cazaquistão–China através da Ásia Central' },
            { id:'r20', from:'VE', to:'CN', commodity:'Petróleo',     type:'energia',   valor:10, desc:'Venezuela: parceiro estratégico da China (dívida/petróleo)' },

            // ── ALIMENTOS ──────────────────────────────────────────────────
            { id:'r21', from:'US', to:'CN', commodity:'Soja',         type:'alimentos', valor:18, desc:'EUA: maior exportador histórico de soja' },
            { id:'r22', from:'BR', to:'CN', commodity:'Soja',         type:'alimentos', valor:38, desc:'Brasil supera EUA: 60% da soja chinesa vem do Brasil' },
            { id:'r23', from:'BR', to:'EU', commodity:'Carne Bovina', type:'alimentos', valor:12, desc:'Frigoríficos brasileiros dominam cota europeia' },
            { id:'r24', from:'AR', to:'CN', commodity:'Soja/Milho',   type:'alimentos', valor:15, desc:'Argentina: graneleiro do Atlântico Sul' },
            { id:'r25', from:'AR', to:'EU', commodity:'Trigo/Soja',   type:'alimentos', valor:10, desc:'Argentina exporta para refinadores de óleo europeus' },
            { id:'r26', from:'UA', to:'EG', commodity:'Trigo',        type:'alimentos', valor:9,  desc:'Ucrânia abastecia 30% da importação egípcia' },
            { id:'r27', from:'UA', to:'TR', commodity:'Trigo',        type:'alimentos', valor:8,  desc:'Corredor do Mar Negro (acordo ONU periódico)' },
            { id:'r28', from:'US', to:'MX', commodity:'Milho',        type:'alimentos', valor:7,  desc:'USMCA: maior fluxo alimentar das Américas' },
            { id:'r29', from:'TH', to:'CN', commodity:'Arroz',        type:'alimentos', valor:6,  desc:'Tailândia: maior exportador de arroz do mundo' },
            { id:'r30', from:'AU', to:'CN', commodity:'Carne/Trigo',  type:'alimentos', valor:9,  desc:'Austrália: fazenda premium da Ásia-Pacífico' },
            { id:'r31', from:'IN', to:'BD', commodity:'Arroz/Trigo',  type:'alimentos', valor:4,  desc:'Corredor alimentar Sul Asiático' },
            { id:'r32', from:'NL', to:'EU', commodity:'Hortifrutis',  type:'alimentos', valor:16, desc:'Holanda: maior exportador de alimentos per capita' },
            { id:'r33', from:'CA', to:'US', commodity:'Trigo/Carne',  type:'alimentos', valor:14, desc:'USMCA: integração alimentar norte-americana' },

            // ── MINERAIS ───────────────────────────────────────────────────
            { id:'r34', from:'AU', to:'CN', commodity:'Minério de Ferro', type:'minerios', valor:55, desc:'Pilbara → Yangtze: espinha dorsal do aço chinês' },
            { id:'r35', from:'CL', to:'CN', commodity:'Cobre',        type:'minerios', valor:22, desc:'Chile detém 27% das reservas mundiais de cobre' },
            { id:'r36', from:'PE', to:'CN', commodity:'Cobre',        type:'minerios', valor:12, desc:'Peru: segundo maior produtor mundial' },
            { id:'r37', from:'CD', to:'CN', commodity:'Cobalto',      type:'minerios', valor:8,  desc:'Congo fornece 70% do cobalto global (baterias)' },
            { id:'r38', from:'ZA', to:'EU', commodity:'Platina',      type:'minerios', valor:9,  desc:'África do Sul: 70% das reservas de platina' },
            { id:'r39', from:'ZA', to:'CN', commodity:'Ouro',         type:'minerios', valor:7,  desc:'Corredor aurífero sul-africano para Xangai' },
            { id:'r40', from:'BR', to:'CN', commodity:'Minério Fe',   type:'minerios', valor:28, desc:'Carajás (PA): maior mina de ferro do mundo' },
            { id:'r41', from:'GN', to:'CN', commodity:'Bauxita',      type:'minerios', valor:6,  desc:'Guiné: 60% das reservas mundiais de bauxita' },
            { id:'r42', from:'RU', to:'CN', commodity:'Níquel/Alumínio', type:'minerios', valor:15, desc:'Rússia abastece siderurgia chinesa de não-ferrosos' },
            { id:'r43', from:'KZ', to:'EU', commodity:'Urânio',       type:'minerios', valor:5,  desc:'Cazaquistão: maior produtor mundial de urânio' },
            { id:'r44', from:'NA', to:'EU', commodity:'Urânio',       type:'minerios', valor:4,  desc:'Namíbia: urânio para reatores europeus (Rössing/Husab)' },

            // ── MANUFATURA / TECNOLOGIA ─────────────────────────────────────
            { id:'r45', from:'CN', to:'US', commodity:'Eletrônicos',  type:'manufatura', valor:95, desc:'Maior fluxo bilateral de bens manufaturados' },
            { id:'r46', from:'CN', to:'EU', commodity:'Manufaturados', type:'manufatura', valor:88, desc:'China supre déficit industrial europeu' },
            { id:'r47', from:'TW', to:'US', commodity:'Semicondutores', type:'manufatura', valor:42, desc:'TSMC: 90% dos chips avançados do mundo' },
            { id:'r48', from:'TW', to:'JP', commodity:'Semicondutores', type:'manufatura', valor:28, desc:'Taiwan–Japão: eixo tecnológico do Indo-Pacífico' },
            { id:'r49', from:'DE', to:'CN', commodity:'Máquinas/Carros', type:'manufatura', valor:30, desc:'BMW/Volkswagen: maior mercado externo é a China' },
            { id:'r50', from:'JP', to:'US', commodity:'Automóveis',   type:'manufatura', valor:25, desc:'Toyota e Honda: presença histórica nos EUA' },
            { id:'r51', from:'KR', to:'US', commodity:'Eletrônicos',  type:'manufatura', valor:20, desc:'Samsung e LG: parceria estratégica com os EUA' },
            { id:'r52', from:'IN', to:'EU', commodity:'Farmacêuticos', type:'manufatura', valor:12, desc:'Índia: farmácia do mundo em genéricos' },
            { id:'r53', from:'MX', to:'US', commodity:'Manufaturados', type:'manufatura', valor:35, desc:'Nearshoring: México capta indústria que migra da China' },
            { id:'r54', from:'VN', to:'US', commodity:'Manufaturados', type:'manufatura', valor:18, desc:'Vietnã: novo hub de montagem eletrônica asiático' },

            // ── FINANCEIRO ─────────────────────────────────────────────────
            { id:'r55', from:'US', to:'BR', commodity:'Inv. Financeiro', type:'financas', valor:22, desc:'Wall Street: maior origem de FDI no Brasil' },
            { id:'r56', from:'CN', to:'AF', commodity:'Inv. Infraestrutura', type:'financas', valor:30, desc:'Belt & Road: China investe em 50+ países africanos' },
            { id:'r57', from:'AE', to:'IN', commodity:'Remessas/FDI', type:'financas', valor:14, desc:'Dubai: hub financeiro entre Oriente e Sul Asiático' },
            { id:'r58', from:'SG', to:'SE_ASIA', commodity:'Capital/Banco', type:'financas', valor:18, desc:'Singapura: maior centro financeiro do Sudeste Asiático' },
        ];
    }

    /** Empresas ficcionais por setor (24 empresas, 3 por setor). */
    _buildCompanies() {
        const mk = (id, nome, setor, sIcone, pais, valorMercado, receita, margem, risco, desc) => ({
            id, nome, setor, sIcone, pais,
            valorMercado,           // Bilhões USD
            receita,                // Bilhões USD anuais
            margem,                 // % lucro
            risco,                  // 'baixo' | 'medio' | 'alto'
            desc,
            preco: +(valorMercado / 100).toFixed(2),  // preço por "ação" unitária (porcentagem)
            tendencia: 0,           // variação % no último turno
            fundada: 1990 + Math.floor(Math.random() * 30),
            totalShares: 1000,      // shares disponíveis no mercado
        });

        return [
            // ── Energia / Petróleo ──────────────────────────────────────────
            mk('E01','PetroGlobe Corp',         'Energia',      '⛽', 'BR', 340, 82,  18, 'medio', 'Maior conglomerado de exploração offshore do hemisfério sul. Opera plataformas em 12 países.'),
            mk('E02','HydraOil Industries',     'Energia',      '⛽', 'AE', 210, 64,  22, 'medio', 'Especializada em refino e distribuição de petróleo no Oriente Médio e Ásia.'),
            mk('E03','OceanDrill Ltd',          'Energia',      '⛽', 'NO', 95,  28,  14, 'alto',  'Ultra-deepwater drilling: prospecta em profundidades acima de 3.000m.'),

            // ── Mineração ──────────────────────────────────────────────────
            mk('M01','TerraMetals Group',       'Mineração',    '⛏', 'AU', 280, 58,  24, 'medio', 'Portfólio diversificado: ferro, cobre, lítio e terras raras em 8 continentes.'),
            mk('M02','IronCore Mining',         'Mineração',    '⛏', 'BR', 165, 40,  21, 'medio', 'Focada em minério de ferro de alta pureza para o mercado asiático.'),
            mk('M03','GoldRush International',  'Mineração',    '⛏', 'ZA', 88,  19,  17, 'alto',  'Extração de ouro e platina em ambientes geopoliticamente voláteis.'),

            // ── Agroalimentar ──────────────────────────────────────────────
            mk('A01','AgriWorld Corp',          'Agroalimentar','🌾', 'US', 195, 75,  12, 'baixo', 'Trader global de grãos: soja, milho e trigo em mais de 60 países.'),
            mk('A02','GreenHarvest Ltd',        'Agroalimentar','🌾', 'NL', 110, 38,  15, 'baixo', 'Agrotecnologia de precisão: sementes OGM e fertilizantes de nova geração.'),
            mk('A03','FoodFusion Inc',          'Agroalimentar','🌾', 'SG', 72,  28,  18, 'medio', 'Processamento e distribuição de proteína alternativa para mercados asiáticos.'),

            // ── Tecnologia ─────────────────────────────────────────────────
            mk('T01','NexTech Systems',         'Tecnologia',   '💻', 'US', 820, 180, 28, 'baixo', 'Cloud, IA e semicondutores: ecossistema integrado de serviços B2B.'),
            mk('T02','QuantumLogic Corp',       'Tecnologia',   '💻', 'JP', 340, 90,  24, 'medio', 'Pioneira em chips quânticos para computação e criptografia governamental.'),
            mk('T03','CyberNova Industries',    'Tecnologia',   '💻', 'KR', 175, 55,  20, 'medio', 'Eletrônicos de consumo e redes 6G para mercados emergentes.'),

            // ── Defesa ────────────────────────────────────────────────────
            mk('D01','ArmaTech Industries',     'Defesa',       '🔫', 'US', 460, 95,  19, 'medio', 'Sistemas de armas, mísseis guiados e plataformas aéreas não-tripuladas.'),
            mk('D02','ShieldForce Corp',        'Defesa',       '🔫', 'GB', 220, 48,  16, 'medio', 'Cibersegurança, inteligência de sinais e sistemas de defesa balística.'),
            mk('D03','SteelGuard Systems',      'Defesa',       '🔫', 'DE', 130, 32,  14, 'alto',  'Blindados de nova geração e sistemas antidrone de gestão de área.'),

            // ── Finanças ──────────────────────────────────────────────────
            mk('F01','GlobalBank Trust',        'Finanças',     '🏦', 'US', 580, 140, 22, 'baixo', 'Banco de investimento com presença em 80 países e $6T em ativos sob gestão.'),
            mk('F02','CapitalNexus Group',      'Finanças',     '🏦', 'CH', 290, 70,  25, 'baixo', 'Gestora de fortunas soberanas e fundos de hedge com estratégia macro global.'),
            mk('F03','WealthStream Financial',  'Finanças',     '🏦', 'SG', 140, 42,  28, 'medio', 'Fintech de pagamentos transfronteiriços: domina corredores Ásia-África.'),

            // ── Farmacêutica ──────────────────────────────────────────────
            mk('P01','BioLife Labs',            'Farmacêutica', '💊', 'US', 390, 85,  30, 'medio', 'Pipeline de oncologia e medicina genômica: 15 moléculas em fase 3.'),
            mk('P02','PharmaCore International','Farmacêutica', '💊', 'DE', 250, 62,  26, 'baixo', 'Líder em genéricos e vacinas para mercados de renda média e baixa.'),
            mk('P03','MediSync Corp',           'Farmacêutica', '💊', 'IN', 95,  28,  20, 'medio', 'Biossimilares e APIs: abastece 60% dos mercados emergentes em genéricos.'),

            // ── Telecom ───────────────────────────────────────────────────
            mk('C01','ConnectWorld Inc',        'Telecom',      '📡', 'US', 310, 88,  21, 'baixo', 'Satélites LEO e fibra intercontinental: 1.2B de usuários em 90 países.'),
            mk('C02','NetPulse Corp',           'Telecom',      '📡', 'CN', 265, 78,  19, 'medio', 'Maior operadora de 5G da Ásia; expansão agressiva na África e América Latina.'),
            mk('C03','SignalPeak Communications','Telecom',     '📡', 'SE', 98,  30,  22, 'baixo', 'Soluções de conectividade para regiões remotas via satélite geoestacionário.'),
        ];
    }

    /** Criptomoedas ficcionais. */
    _buildCryptos() {
        return [
            {
                id: 'WLC', nome: 'WorldCoin', simbolo: 'WLC', icone: '🌐',
                preco: 45200, supply: 21000000,
                volatilidade: 0.04, // % por turno
                correlacoes: { economia: 0.6, estabilidade: 0.4 },
                desc: 'Reserve crypto global. Alta adoção institucional e correlação positiva com estabilidade econômica.',
                cor: '#00d2ff',
            },
            {
                id: 'PTC', nome: 'PetroCoin', simbolo: 'PTC', icone: '🛢',
                preco: 2850, supply: 100000000,
                volatilidade: 0.07,
                correlacoes: { petroleo: 0.8, conflito: -0.3 },
                desc: 'Lastreado em barris de petróleo tokenizados. Sobe com o preço do crude.',
                cor: '#ffaa00',
            },
            {
                id: 'MLC', nome: 'MiliChain', simbolo: 'MLC', icone: '⚔',
                preco: 920, supply: 500000000,
                volatilidade: 0.12,
                correlacoes: { conflito: 0.7, defcon: -0.5 },
                desc: 'Utilizado em contratos de defesa descentralizados. Dispara em conflitos.',
                cor: '#ff4444',
            },
            {
                id: 'AGC', nome: 'AgroCoin', simbolo: 'AGC', icone: '🌾',
                preco: 345, supply: 2000000000,
                volatilidade: 0.05,
                correlacoes: { alimentos: 0.7, clima: -0.4 },
                desc: 'Token de commodities agrícolas. Correlacionado com preços globais de grãos.',
                cor: '#22c55e',
            },
            {
                id: 'TTK', nome: 'TechToken', simbolo: 'TTK', icone: '💻',
                preco: 12800, supply: 50000000,
                volatilidade: 0.09,
                correlacoes: { tecnologia: 0.8, estabilidade: 0.2 },
                desc: 'Token do ecossistema de inovação tecnológica. Cresce com pesquisa e P&D.',
                cor: '#a78bfa',
            },
            {
                id: 'DNC', nome: 'DarkNet Coin', simbolo: 'DNC', icone: '🕵',
                preco: 185, supply: 10000000000,
                volatilidade: 0.20,
                correlacoes: { sancoes: 0.9, instabilidade: 0.6 },
                desc: 'Altamente volátil e anônimo. Preferido para evasão de sanções. Risco extremo.',
                cor: '#6b7280',
            },
            {
                id: 'GVC', nome: 'GovChain', simbolo: 'GVC', icone: '🏛',
                preco: 8400, supply: 300000000,
                volatilidade: 0.02,
                correlacoes: { estabilidade: 0.5, governanca: 0.7 },
                desc: 'CBDC sintética: cesta de moedas soberanas digitais. Baixíssima volatilidade.',
                cor: '#fbbf24',
            },
        ];
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PROCESSAMENTO POR TURNO
    // ═══════════════════════════════════════════════════════════════════════

    processTurn() {
        this._updateCommodityPrices();
        this._processTradeIncome();
        this._updateCompanyPrices();
        this._updateCryptoPrices();
    }

    /** Oscila preços globais de commodities com base em eventos do jogo. */
    _updateCommodityPrices() {
        const defcon = this.engine.state.defcon || 5;

        // Base: random walk suave
        for (const k in this.commodityPrices) {
            const delta = (Math.random() - 0.48) * 4; // drift ligeiramente positivo
            this.commodityPrices[k] = Math.max(40, Math.min(250, this.commodityPrices[k] + delta));
        }

        // Conflito eleva energia e metais
        if (defcon <= 2) {
            this.commodityPrices.petroleo   = Math.min(250, this.commodityPrices.petroleo   + 8);
            this.commodityPrices.minérios   = Math.min(250, this.commodityPrices.minérios   + 5);
        } else if (defcon <= 3) {
            this.commodityPrices.petroleo   = Math.min(250, this.commodityPrices.petroleo   + 3);
        }
    }

    /** Distribui receita de exportação para cada nação via rotas comerciais. */
    _processTradeIncome() {
        const nations = this.engine.data.nations;

        this.routes.forEach(route => {
            const exporter = nations[route.from];
            if (!exporter) return;

            // Verifica se a rota está ativa (relações mínimas entre os países)
            const importer = nations[route.to];
            if (importer) {
                const rel = exporter.relacoes?.[route.to] ?? 0;
                if (rel < -80) return; // sanções severas interrompem rota
            }

            // Multiplicador de preço da commodity correspondente
            const priceIdx = this.commodityPrices[this._commodityKey(route.type)] / 100;

            // Receita trimestral para o exportador: 3.5% do valor da rota
            const income = route.valor * 0.035 * priceIdx;
            exporter.tesouro = Math.min(
                exporter.pib_bilhoes_usd * 0.25,
                (exporter.tesouro || 0) + income
            );

            // Notifica eventos de notícias sobre rotas importantes (ocasional)
            if (Math.random() < 0.02 && income > 1) {
                this.engine.state.recentGameEvents = this.engine.state.recentGameEvents || [];
                this.engine.state.recentGameEvents.push({
                    cat: 'economia',
                    headline: `Rota ${route.commodity} ${exporter.nome}→${importer?.nome ?? route.to} gera $${income.toFixed(1)}B este trimestre`,
                    body: route.desc,
                    urgency: 'normal',
                });
            }
        });
    }

    _commodityKey(type) {
        const map = { energia: 'petroleo', alimentos: 'alimentos', minerios: 'minérios', manufatura: 'tecnologia', financas: 'metais' };
        return map[type] || 'tecnologia';
    }

    /** Atualiza preços das empresas com base em commodities e performance. */
    _updateCompanyPrices() {
        this.companies.forEach(co => {
            const baseVol = co.risco === 'alto' ? 0.06 : co.risco === 'medio' ? 0.03 : 0.015;
            let delta = (Math.random() - 0.47) * baseVol; // slight upward drift

            // Correlação com commodities por setor
            const cpIdx = (k) => (this.commodityPrices[k] - 100) / 100;
            if (co.setor === 'Energia')      delta += cpIdx('petroleo') * 0.05;
            if (co.setor === 'Mineração')    delta += cpIdx('minérios') * 0.04;
            if (co.setor === 'Agroalimentar')delta += cpIdx('alimentos') * 0.04;
            if (co.setor === 'Tecnologia')   delta += cpIdx('tecnologia') * 0.04;
            if (co.setor === 'Defesa') {
                const defcon = this.engine.state.defcon || 5;
                delta += (5 - defcon) * 0.015;
            }

            co.tendencia     = +(delta * 100).toFixed(2);
            co.valorMercado  = Math.max(10, co.valorMercado * (1 + delta));
            co.preco         = +(co.valorMercado / 100).toFixed(2);
        });
    }

    /** Atualiza preços das criptomoedas. */
    _updateCryptoPrices() {
        const defcon = this.engine.state.defcon || 5;

        this.cryptos.forEach(c => {
            let delta = (Math.random() - 0.48) * c.volatilidade;

            // Correlações temáticas
            if (c.id === 'PTC') delta += (this.commodityPrices.petroleo - 100) / 100 * 0.08;
            if (c.id === 'MLC') delta += ((5 - defcon) * 0.025);
            if (c.id === 'AGC') delta += (this.commodityPrices.alimentos - 100) / 100 * 0.06;
            if (c.id === 'TTK') delta += (this.commodityPrices.tecnologia - 100) / 100 * 0.07;
            if (c.id === 'DNC' && defcon <= 2) delta += 0.15; // conflito → DNC dispara

            c.tendencia = +(delta * 100).toFixed(2);
            c.preco     = Math.max(1, c.preco * (1 + delta));
        });
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ROTAS
    // ═══════════════════════════════════════════════════════════════════════

    /** Retorna rotas que envolvem a nação (como exportador ou importador). */
    getRoutesForNation(iso) {
        return this.routes.filter(r => r.from === iso || r.to === iso);
    }

    getRoutesByType(type) {
        return this.routes.filter(r => r.type === type);
    }

    /** Renda trimestral de exportações de uma nação. */
    getExportIncome(iso) {
        return this.routes
            .filter(r => r.from === iso)
            .reduce((sum, r) => sum + r.valor * 0.035 * (this.commodityPrices[this._commodityKey(r.type)] / 100), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // EMPRESAS — INVESTIMENTO
    // ═══════════════════════════════════════════════════════════════════════

    getCompany(id)      { return this.companies.find(c => c.id === id); }
    getCompaniesBySector(setor) { return setor === 'all' ? this.companies : this.companies.filter(c => c.setor === setor); }
    get sectors() { return [...new Set(this.companies.map(c => c.setor))]; }

    /** Investe X bilhões em uma empresa. Retorna { ok, msg }. */
    invest(companyId, investBillions) {
        const playerNation = this.engine.state.playerNation;
        if (!playerNation) return { ok: false, msg: 'Nenhuma nação selecionada.' };

        const co = this.getCompany(companyId);
        if (!co) return { ok: false, msg: 'Empresa não encontrada.' };

        const cost = +investBillions;
        if (isNaN(cost) || cost <= 0) return { ok: false, msg: 'Valor inválido.' };
        if (playerNation.tesouro < cost) return { ok: false, msg: `Tesouro insuficiente. Disponível: $${playerNation.tesouro.toFixed(0)}B` };

        // Deduz do tesouro
        playerNation.tesouro -= cost;

        // Registra no portfólio
        const port = this.portfolio[companyId] || { shares: 0, totalInvested: 0 };
        port.shares        += cost / co.preco;  // "shares" proporcionais
        port.totalInvested += cost;
        this.portfolio[companyId] = port;

        // Pequeno boost no valor da empresa (liquidez)
        co.valorMercado  += cost * 0.5;
        co.preco          = +(co.valorMercado / 100).toFixed(2);

        return { ok: true, msg: `Investido $${cost.toFixed(1)}B em ${co.nome}.` };
    }

    /** Vende participação em uma empresa. */
    divest(companyId, sellPct) {
        const playerNation = this.engine.state.playerNation;
        if (!playerNation) return { ok: false, msg: 'Nenhuma nação selecionada.' };

        const port = this.portfolio[companyId];
        if (!port || port.shares <= 0) return { ok: false, msg: 'Sem posição nesta empresa.' };

        const co = this.getCompany(companyId);
        const pct = Math.min(1, Math.max(0.01, sellPct / 100));
        const sharesToSell = port.shares * pct;
        const revenue      = sharesToSell * co.preco;

        playerNation.tesouro  += revenue;
        port.shares           -= sharesToSell;
        port.totalInvested    *= (1 - pct);
        if (port.shares < 0.001) delete this.portfolio[companyId];

        return { ok: true, msg: `Vendido ${(pct*100).toFixed(0)}% — recebido $${revenue.toFixed(1)}B.` };
    }

    /** Valor atual do portfólio do jogador. */
    get portfolioValue() {
        return Object.entries(this.portfolio).reduce((sum, [id, pos]) => {
            const co = this.getCompany(id);
            return sum + (co ? pos.shares * co.preco : 0);
        }, 0);
    }

    /** Retorno % do portfólio. */
    get portfolioReturn() {
        const invested = Object.values(this.portfolio).reduce((s, p) => s + p.totalInvested, 0);
        const current  = this.portfolioValue;
        if (invested === 0) return 0;
        return ((current - invested) / invested) * 100;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // CRIPTO
    // ═══════════════════════════════════════════════════════════════════════

    getCrypto(id)  { return this.cryptos.find(c => c.id === id); }

    /** Compra cripto com tesouro nacional. Retorna { ok, msg }. */
    buyCrypto(cryptoId, spendBillions) {
        const playerNation = this.engine.state.playerNation;
        if (!playerNation) return { ok: false, msg: 'Nenhuma nação selecionada.' };

        const crypto = this.getCrypto(cryptoId);
        if (!crypto) return { ok: false, msg: 'Criptomoeda não encontrada.' };

        const cost = +spendBillions;
        if (isNaN(cost) || cost <= 0) return { ok: false, msg: 'Valor inválido.' };
        if (playerNation.tesouro < cost) return { ok: false, msg: `Tesouro insuficiente: $${playerNation.tesouro.toFixed(0)}B` };

        const coins = (cost * 1e9) / crypto.preco;
        playerNation.tesouro -= cost;
        this.cryptoWallet[cryptoId] = (this.cryptoWallet[cryptoId] || 0) + coins;

        // Grande compra empurra preço para cima
        crypto.preco = crypto.preco * (1 + cost * 0.003);

        return { ok: true, msg: `Comprado ${coins.toFixed(2)} ${crypto.simbolo} por $${cost.toFixed(1)}B` };
    }

    /** Vende cripto por tesouro nacional. */
    sellCrypto(cryptoId, sellPct) {
        const playerNation = this.engine.state.playerNation;
        if (!playerNation) return { ok: false, msg: 'Nenhuma nação selecionada.' };

        const holding = this.cryptoWallet[cryptoId] || 0;
        if (holding <= 0) return { ok: false, msg: 'Sem saldo nesta criptomoeda.' };

        const crypto  = this.getCrypto(cryptoId);
        const pct     = Math.min(1, Math.max(0.01, sellPct / 100));
        const coins   = holding * pct;
        const revenue = (coins * crypto.preco) / 1e9; // em bilhões

        playerNation.tesouro += revenue;
        this.cryptoWallet[cryptoId] = holding - coins;

        // Venda pressiona preço para baixo
        crypto.preco = crypto.preco * (1 - revenue * 0.002);

        return { ok: true, msg: `Vendido ${(pct*100).toFixed(0)}% — recebido $${revenue.toFixed(2)}B` };
    }

    get walletValue() {
        return Object.entries(this.cryptoWallet).reduce((sum, [id, coins]) => {
            const c = this.getCrypto(id);
            return sum + (c ? (coins * c.preco) / 1e9 : 0);
        }, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // HELPERS DE FORMATAÇÃO
    // ═══════════════════════════════════════════════════════════════════════

    fmtPrice(val) {
        if (val >= 1000) return `$${(val/1000).toFixed(1)}k`;
        return `$${val.toFixed(0)}`;
    }

    fmtBillions(val) {
        if (val >= 1000) return `$${(val/1000).toFixed(1)}T`;
        return `$${val.toFixed(1)}B`;
    }

    trendArrow(t) {
        if (t > 0.5)  return `<span style="color:#00ff88">▲ +${t.toFixed(2)}%</span>`;
        if (t < -0.5) return `<span style="color:#ff4444">▼ ${t.toFixed(2)}%</span>`;
        return `<span style="color:#8b949e">— ${t.toFixed(2)}%</span>`;
    }

    typeLabel(type) {
        const m = { energia:'Energia', alimentos:'Alimentos', minerios:'Minerais', manufatura:'Manufatura', financas:'Financeiro' };
        return m[type] || type;
    }

    typeColor(type) {
        const m = { energia:'#ffaa00', alimentos:'#22c55e', minerios:'#a78bfa', manufatura:'#00d2ff', financas:'#fbbf24' };
        return m[type] || '#8b949e';
    }

    riskColor(r) {
        return r === 'alto' ? '#ff4444' : r === 'medio' ? '#ffaa00' : '#00ff88';
    }
}
