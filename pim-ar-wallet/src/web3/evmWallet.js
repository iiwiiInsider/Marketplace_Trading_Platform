import Web3 from 'web3';

import { chainLabel, nativeSymbol } from '../config/chains.js';
import { pimTokenAddressForChain } from '../config/pimToken.js';
import { setDisabled, setText } from '../utils/dom.js';
import { formatDecimalString, formatTokenAmount, shortenAddress } from '../utils/format.js';
import { toast } from '../ui/toast.js';
import { ERC20_ABI } from './erc20Abi.js';

function getEthereum() {
  return window.ethereum;
}

function isHexString(value) {
  return typeof value === 'string' && /^0x[0-9a-fA-F]+$/.test(value);
}

function chainIdFromProvider(chainIdValue) {
  if (typeof chainIdValue === 'number') return chainIdValue;
  if (isHexString(chainIdValue)) return Number.parseInt(chainIdValue, 16);
  const num = Number(chainIdValue);
  return Number.isFinite(num) ? num : null;
}

function ensureUiDefaults() {
  setText('evmStatus', 'Not connected');
  setText('evmAddr', '—');
  setText('evmChain', '—');
  setText('evmNative', '—');
  setText('evmPim', '—');
}

async function readNativeBalance(web3, address, chainId) {
  const wei = await web3.eth.getBalance(address);
  const native = web3.utils.fromWei(wei, 'ether');
  return `${formatDecimalString(native, { maxFrac: 6 })} ${nativeSymbol(chainId)}`;
}

async function readPimBalance(web3, address, chainId) {
  const tokenAddr = pimTokenAddressForChain(chainId);
  if (!tokenAddr) return 'Not configured';

  const contract = new web3.eth.Contract(ERC20_ABI, tokenAddr);

  // Some tokens return decimals/symbol as strings; normalize.
  const [raw, decimals, symbol] = await Promise.all([
    contract.methods.balanceOf(address).call(),
    contract.methods.decimals().call().catch(() => 18),
    contract.methods.symbol().call().catch(() => 'PIM'),
  ]);

  const amount = formatTokenAmount(raw, decimals);
  return `${formatDecimalString(amount, { maxFrac: 6 })} ${symbol || 'PIM'}`;
}

function renderConnected({ address, chainId }) {
  setText('evmStatus', 'Connected');
  setText('evmAddr', `${shortenAddress(address)} (${address})`);
  setText('evmChain', chainLabel(chainId));
}

function renderDisconnected(reason) {
  ensureUiDefaults();
  if (reason) setText('evmStatus', reason);
}

export async function connectEvmWallet() {
  const ethereum = getEthereum();
  if (!ethereum) {
    toast('No injected wallet found. Install MetaMask (or another EVM wallet).');
    renderDisconnected('No wallet provider');
    return;
  }

  setDisabled('evmConnectBtn', true);
  setText('evmStatus', 'Connecting…');

  try {
    const accounts = await ethereum.request({ method: 'eth_requestAccounts' });
    const address = accounts?.[0];
    if (!address) throw new Error('No account selected');

    const chainIdRaw = await ethereum.request({ method: 'eth_chainId' });
    const chainId = chainIdFromProvider(chainIdRaw);

    const web3 = new Web3(ethereum);

    renderConnected({ address, chainId });

    setText('evmNative', 'Loading…');
    setText('evmPim', 'Loading…');

    const [nativeLine, pimLine] = await Promise.all([
      readNativeBalance(web3, address, chainId),
      readPimBalance(web3, address, chainId),
    ]);

    setText('evmNative', nativeLine);
    setText('evmPim', pimLine);

    toast('EVM wallet connected');

    // Subscribe after first successful connect.
    if (!connectEvmWallet.__subscribed) {
      connectEvmWallet.__subscribed = true;

      ethereum.on?.('accountsChanged', () => {
        // Best-effort refresh.
        connectEvmWallet().catch(() => undefined);
      });
      ethereum.on?.('chainChanged', () => {
        connectEvmWallet().catch(() => undefined);
      });
      ethereum.on?.('disconnect', () => {
        renderDisconnected('Disconnected');
      });
    }
  } catch (err) {
    const message = err?.message ? String(err.message) : 'Wallet connect failed';
    toast(message);
    renderDisconnected('Not connected');
  } finally {
    setDisabled('evmConnectBtn', false);
  }
}

export function initEvmWalletUi() {
  ensureUiDefaults();

  // If already connected (some wallets expose selectedAddress), we can show it.
  const ethereum = getEthereum();
  const preAddr = ethereum?.selectedAddress;
  if (preAddr) {
    // Fire and forget; will also populate balances.
    connectEvmWallet().catch(() => undefined);
  }
}
