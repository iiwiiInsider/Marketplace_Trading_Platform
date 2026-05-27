import { initEvmWalletUi, connectEvmWallet, mintPimFromUi, addHardhatNetworkFromUi } from './web3/evmWallet.js';

// Expose a single entrypoint for the existing inline-HTML buttons.
window.connectEvmWallet = connectEvmWallet;
window.mintPimFromUi = mintPimFromUi;
window.addHardhatNetworkFromUi = addHardhatNetworkFromUi;

// Initialize status placeholders.
initEvmWalletUi();
