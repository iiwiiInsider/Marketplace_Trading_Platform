import { initEvmWalletUi, connectEvmWallet } from './web3/evmWallet.js';

// Expose a single entrypoint for the existing inline-HTML buttons.
window.connectEvmWallet = connectEvmWallet;

// Initialize status placeholders.
initEvmWalletUi();
