/**
 * AllianceManager — Gerencia alianças reais de 2024, defesa coletiva,
 * benefícios de membros e reações a agressões.
 */
class AllianceManager {
    constructor(engine) {
        this.engine   = engine;
        this.alliances = [];
        this._initialized = false;
    }

    async loadAlliances() {
        try {
            const res  = await fetch('data/alliances.json');
            const data = await res.json();
            this.alliances = data.alliances || [];
            // Inicializa os conflitos ativos de 2024
            this._initActiveConflicts(data.conflitos_ativos_2024 || []);
            this._initialized = true;
            console.log(`> ${this.alliances.length} alianças geopolíticas carregadas.`);
        } catch(e) {
            console.warn('AllianceManager: falha ao carregar alianças', e);
            this.alliances = [];
        }
    }

    _initActiveConflicts(conflicts) {
        conflicts.forEach(c => {
            const attacker = this.engine.data.nations[c.atacante];
            const defender = this.engine.data.nations[c.defensor];
            if (!attacker || !defender) return;

            // Marca como em guerra
            if (!attacker.em_guerra) attacker.em_guerra = [];
            if (!defender.em_guerra) defender.em_guerra = [];
            if (!attacker.em_guerra.includes(c.defensor)) attacker.em_guerra.push(c.defensor);
            if (!defender.em_guerra.includes(c.atacante))  defender.em_guerra.push(c.atacante);

            // Piora relações
            attacker.relacoes = attacker.relacoes || {};
            defender.relacoes = defender.relacoes || {};
            attacker.relacoes[c.defensor] = -100;
            defender.relacoes[c.atacante] = -100;
        });
    }

    // ── Consulta ────────────────────────────────────────────────────────────

    getAlliancesForNation(code) {
        return this.alliances.filter(a => a.membros.includes(code));
    }

    getPlayerAlliances() {
        const code = this.engine.state.playerNation?.codigo_iso;
        return code ? this.getAlliancesForNation(code) : [];
    }

    areAllied(codeA, codeB) {
        return this.alliances.some(a => a.membros.includes(codeA) && a.membros.includes(codeB));
    }

    getSharedAlliances(codeA, codeB) {
        return this.alliances.filter(a => a.membros.includes(codeA) && a.membros.includes(codeB));
    }

    // ── Defesa Coletiva ──────────────────────────────────────────────────────

    /**
     * Chamado quando attackerCode declara guerra a defenderCode.
     * Verifica alianças de defesa coletiva do defensor e aciona respostas.
     * Retorna lista de nações que entraram na guerra.
     */
    onWarDeclared(attackerCode, defenderCode) {
        if (!this._initialized) return [];

        const defenderAlliances = this.getAlliancesForNation(defenderCode);
        const responders        = [];
        const warMessages       = [];

        defenderAlliances.forEach(alliance => {
            if (!alliance.artigo_defesa && alliance.reacao_agressao.chance_intervencao < 0.5) {
                // Aliança não-defensiva: apenas penalidade diplomática
                this._applyDiplomaticPenalty(attackerCode, alliance);
                return;
            }

            const reaction = alliance.reacao_agressao;
            let allianceActivated = false;

            alliance.membros.forEach(memberCode => {
                if (memberCode === defenderCode || memberCode === attackerCode) return;
                const member = this.engine.data.nations[memberCode];
                if (!member) return;

                // Cálculo de chance baseado na personalidade do membro
                const personality = this.engine.aiManager?.getPersonality(member);
                const aggression  = personality?.agressividade ?? 0.5;
                const reacaoTipo  = personality?.reacao_aliado_atacado || 'dependente_de_custo';

                let chance = reaction.chance_intervencao;

                // Ajuste por personalidade
                if (reacaoTipo === 'defesa_imediata')     chance *= 1.4;
                if (reacaoTipo === 'pressao_diplomatica') chance *= 0.5;
                if (reacaoTipo === 'neutro')              chance *= 0.1;
                if (reacaoTipo === 'dependente_de_custo') chance *= (0.5 + aggression * 0.5);

                // Ajuste por relação com o atacante
                const relWithAttacker = member.relacoes?.[attackerCode] || 0;
                if (relWithAttacker > 20)  chance *= 0.4; // amigos hesitam
                if (relWithAttacker < -50) chance *= 1.3; // inimigos aproveitam

                chance = Math.min(0.95, chance);

                if (Math.random() < chance) {
                    // Entra na guerra
                    if (!member.em_guerra) member.em_guerra = [];
                    if (!member.em_guerra.includes(attackerCode)) {
                        member.em_guerra.push(attackerCode);
                        responders.push(memberCode);
                        allianceActivated = true;
                    }
                    // Atacante passa a estar em guerra com esse membro também
                    const attacker = this.engine.data.nations[attackerCode];
                    if (attacker && !attacker.em_guerra.includes(memberCode)) {
                        attacker.em_guerra.push(memberCode);
                    }
                }

                // Penalidade de relações sempre ocorre para aliança de defesa
                if (alliance.artigo_defesa) {
                    if (!member.relacoes) member.relacoes = {};
                    member.relacoes[attackerCode] = Math.max(-100,
                        (member.relacoes[attackerCode] || 0) + reaction.reducao_relacoes);
                }
            });

            if (allianceActivated && reaction.mensagem) {
                const msg = reaction.mensagem
                    .replace('{defensor}', this.engine.data.nations[defenderCode]?.nome || defenderCode);
                warMessages.push(`[${alliance.nome}] ${msg}`);
            }

            // DEFCON
            if (allianceActivated && reaction.escalada_defcon > 0) {
                this.engine.state.defcon = Math.max(1,
                    this.engine.state.defcon - reaction.escalada_defcon);
            }
        });

        // Notificar jogador
        if (responders.length > 0 && this.engine.ui) {
            const names = responders.map(c => this.engine.data.nations[c]?.nome || c).join(', ');
            this.engine.ui.showNotification(
                `⚠️ RESPOSTA DE ALIANÇA: ${names} entraram na guerra!`, 'threat');
        }
        warMessages.forEach(msg => {
            setTimeout(() => this.engine.ui?.showNotification(msg, 'threat'), 1500);
        });

        return responders;
    }

    _applyDiplomaticPenalty(attackerCode, alliance) {
        const attacker = this.engine.data.nations[attackerCode];
        if (!attacker) return;
        alliance.membros.forEach(memberCode => {
            if (memberCode === attackerCode) return;
            const m = this.engine.data.nations[memberCode];
            if (m?.relacoes) {
                m.relacoes[attackerCode] = Math.max(-100,
                    (m.relacoes[attackerCode] || 0) + (alliance.reacao_agressao.reducao_relacoes || -15));
            }
        });
    }

    // ── Benefícios por turno ─────────────────────────────────────────────────

    processTurn() {
        const playerCode = this.engine.state.playerNation?.codigo_iso;
        if (!playerCode) return;

        const player   = this.engine.data.nations[playerCode];
        const myAlliances = this.getPlayerAlliances();

        myAlliances.forEach(alliance => {
            const bonus = alliance.bonus_membro || {};

            if (bonus.intel_compartilhada || bonus.intel_cinco_olhos) {
                player.intel_score = Math.min(100, (player.intel_score || 0) + 3);
            }
            if (bonus.reducao_custo_defesa) {
                // Desconto no orçamento militar aplicado via flag — processado no Nation
                player._alianca_defesa_bonus = bonus.reducao_custo_defesa;
            }
            if (bonus.intel_score) {
                player.intel_score = Math.min(100, (player.intel_score || 0) + 1);
            }
        });

        // Verifica se algum parceiro de aliança foi atacado por IA
        myAlliances.forEach(alliance => {
            if (!alliance.artigo_defesa) return;
            alliance.membros.forEach(memberCode => {
                if (memberCode === playerCode) return;
                const member = this.engine.data.nations[memberCode];
                if (!member) return;
                (member.em_guerra || []).forEach(enemyCode => {
                    if (enemyCode === playerCode) return;
                    // Notifica o jogador que um aliado está em guerra
                    if (!this._notifiedWars) this._notifiedWars = new Set();
                    const key = `${memberCode}_${enemyCode}`;
                    if (!this._notifiedWars.has(key)) {
                        this._notifiedWars.add(key);
                        this.engine.ui?.showNotification(
                            `🔴 ALERTA [${alliance.nome}]: ${member.nome} está em guerra com ${this.engine.data.nations[enemyCode]?.nome || enemyCode}. Artigo 5 pode ser invocado!`,
                            'threat');
                    }
                });
            });
        });
    }

    // ── Ingressar / Sair de Aliança ──────────────────────────────────────────

    requestJoin(allianceId) {
        const alliance   = this.alliances.find(a => a.id === allianceId);
        const playerCode = this.engine.state.playerNation?.codigo_iso;
        const player     = this.engine.data.nations[playerCode];
        if (!alliance || !player) return false;

        if (alliance.membros.includes(playerCode)) {
            this.engine.ui?.showNotification(`${player.nome} já é membro de ${alliance.nome}.`, 'info');
            return false;
        }

        // Verifica aprovação — baseado em relações com membros existentes
        const avgRelation = alliance.membros.reduce((sum, c) => {
            return sum + (player.relacoes?.[c] || 0);
        }, 0) / Math.max(1, alliance.membros.length);

        if (avgRelation < 10) {
            this.engine.ui?.showNotification(
                `❌ Candidatura rejeitada: relações insuficientes com membros de ${alliance.nome} (média: ${avgRelation.toFixed(0)})`,
                'threat');
            return false;
        }

        alliance.membros.push(playerCode);
        this.engine.ui?.showNotification(
            `✅ ${player.nome} ingressou em ${alliance.nome}!`, 'success');
        return true;
    }

    leaveAlliance(allianceId) {
        const alliance   = this.alliances.find(a => a.id === allianceId);
        const playerCode = this.engine.state.playerNation?.codigo_iso;
        const player     = this.engine.data.nations[playerCode];
        if (!alliance || !player) return;

        const idx = alliance.membros.indexOf(playerCode);
        if (idx < 0) return;

        alliance.membros.splice(idx, 1);

        // Penalidades
        const penalty = alliance.penalidade_saida || {};
        if (penalty.relacoes_membros) {
            alliance.membros.forEach(c => {
                if (player.relacoes) {
                    player.relacoes[c] = Math.max(-100,
                        (player.relacoes[c] || 0) + penalty.relacoes_membros);
                }
            });
        }
        if (penalty.defcon_impact) {
            this.engine.state.defcon = Math.max(1,
                this.engine.state.defcon - penalty.defcon_impact);
        }

        this.engine.ui?.showNotification(
            `⚠️ ${player.nome} saiu de ${alliance.nome}. Relações deterioradas.`, 'threat');
    }

    // ── Renderização para painel UI ─────────────────────────────────────────

    getAlliancesInfoHTML(playerCode) {
        const myAlliances = this.getAlliancesForNation(playerCode);
        if (!myAlliances.length) {
            return '<p style="color:var(--text-secondary);padding:10px">Sem alianças ativas. Junte-se a uma aliança no painel de Diplomacia.</p>';
        }

        return myAlliances.map(a => {
            const typeColors = {
                defesa_coletiva:   '#ff3333',
                economico_politico:'#ffaa00',
                seguranca_regional:'#ff8844',
                seguranca_informal:'#ff6600',
                defesa_tecnologica:'#00d2ff',
                inteligencia:      '#a78bfa',
                economico:         '#00ff88',
                politico_cultural: '#fbbf24',
                normalizacao_diplomatica: '#00d2ff'
            };
            const color = typeColors[a.tipo] || '#8b949e';
            const memberNames = a.membros.slice(0,6).map(c =>
                this.engine.data.nations[c]?.nome || c).join(', ');
            const more = a.membros.length > 6 ? ` +${a.membros.length - 6}` : '';

            return `
            <div style="background:rgba(255,255,255,0.03);border:1px solid rgba(255,255,255,0.07);border-left:3px solid ${color};border-radius:4px;padding:10px 12px;margin-bottom:8px">
                <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:4px">
                    <span style="color:${color};font-family:var(--font-data);font-size:0.75rem;letter-spacing:1px">${a.nome}</span>
                    ${a.artigo_defesa ? '<span style="background:rgba(255,51,51,0.15);color:#ff3333;font-size:0.6rem;padding:2px 6px;border-radius:3px;font-family:var(--font-data)">DEFESA COLETIVA</span>' : ''}
                </div>
                <div style="color:var(--text-secondary);font-size:0.67rem;margin-bottom:6px">${a.descricao}</div>
                <div style="color:var(--text-dim);font-size:0.63rem">
                    <span style="color:${color}">Membros (${a.membros.length}):</span> ${memberNames}${more}
                </div>
                ${a.artigo_defesa ? `<div style="color:#ff8844;font-size:0.62rem;margin-top:4px">⚔️ Chance de intervenção em ataque a membro: ${Math.round(a.reacao_agressao.chance_intervencao * 100)}%</div>` : ''}
            </div>`;
        }).join('');
    }
}
