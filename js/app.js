/**
 * Entry point for World Order
 */
const engine = new GameEngine();
window.engine = engine; // Garante acessibilidade global

window.addEventListener('DOMContentLoaded', () => {
    // A inicialização é delegada ao Motor
    engine.init();
});
