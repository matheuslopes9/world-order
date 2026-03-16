/**
 * Utility functions for World Order
 */
const Utils = {
    formatCurrency: (value) => {
        if (value >= 1000) return `$${(value / 1000).toFixed(1)}T`;
        return `$${value}B`;
    },
    formatNumber: (num) => {
        return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
    },
    getRandomInt: (min, max) => {
        return Math.floor(Math.random() * (max - min + 1)) + min;
    }
};
