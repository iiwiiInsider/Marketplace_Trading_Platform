import Web3 from 'web3';

import { chainLabel, nativeSymbol } from '../config/chains.js';
import { pimTokenAddressForChain } from '../config/pimToken.js';
import { setDisabled, setText } from '../utils/dom.js';
import { formatDecimalString, formatTokenAmount, shortenAddress } from '../utils/format.js';
import { toast } from '../ui/toast.js';
import { ERC20_ABI } from './erc20Abi.js';

let lastSession = null;

function getEthereum() {
  return window.ethereum;
}

function toHexChainId(chainId) {
  if (!Number.isFinite(chainId)) return null;
  return `0x${Number(chainId).toString(16)}`;
}

const HARDHAT_CHAIN = {
  chainId: toHexChainId(31337),
  chainName: 'Hardhat Local',
  nativeCurrency: { name: 'Ethereum', symbol: 'ETH', decimals: 18 },
  rpcUrls: ['http://127.0.0.1:8545'],
};

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
  setText('evmPimSupply', '—');
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

async function readPimSupply(web3, chainId) {
  const tokenAddr = pimTokenAddressForChain(chainId);
  if (!tokenAddr) return 'Not configured';

  const contract = new web3.eth.Contract(ERC20_ABI, tokenAddr);

  const [rawSupply, rawMax, decimals, symbol] = await Promise.all([
    contract.methods.totalSupply().call().catch(() => null),
    contract.methods.maxSupply().call().catch(() => null),
    contract.methods.decimals().call().catch(() => 18),
    contract.methods.symbol().call().catch(() => 'PIM'),
  ]);

  if (!rawSupply) return 'Unavailable';

  const supply = formatTokenAmount(rawSupply, decimals);
  const supplyTxt = formatDecimalString(supply, { maxFrac: 0 });

  if (!rawMax) return `${supplyTxt} ${(symbol || 'PIM')} minted`;
  const max = formatTokenAmount(rawMax, decimals);
  const maxTxt = formatDecimalString(max, { maxFrac: 0 });
  return `${supplyTxt} / ${maxTxt} ${(symbol || 'PIM')}`;
}

async function refreshEvmReadouts() {
  const s = lastSession;
  if (!s?.web3 || !s?.address) return;

  setText('evmNative', 'Loading…');
  setText('evmPim', 'Loading…');
  setText('evmPimSupply', 'Loading…');

  const [nativeLine, pimLine, supplyLine] = await Promise.all([
    readNativeBalance(s.web3, s.address, s.chainId),
    readPimBalance(s.web3, s.address, s.chainId),
    readPimSupply(s.web3, s.chainId),
  ]);

  setText('evmNative', nativeLine);
  setText('evmPim', pimLine);
  setText('evmPimSupply', supplyLine);
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

    lastSession = { web3, address, chainId };

    renderConnected({ address, chainId });

    await refreshEvmReadouts();

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

export async function addHardhatNetworkFromUi() {
  const ethereum = getEthereum();
  if (!ethereum?.request) {
    toast('No injected wallet found. Install MetaMask.');
    return;
  }

  setDisabled('evmAddHardhatBtn', true);

  try {
    // Try switching first (if it already exists).
    await ethereum.request({
      method: 'wallet_switchEthereumChain',
      params: [{ chainId: HARDHAT_CHAIN.chainId }],
    });
  } catch (err) {
    const code = err?.code;

    // 4902 = chain not added
    if (code === 4902 || String(err?.message || '').toLowerCase().includes('unrecognized')) {
      try {
        await ethereum.request({
          method: 'wallet_addEthereumChain',
          params: [HARDHAT_CHAIN],
        });
        await ethereum.request({
          method: 'wallet_switchEthereumChain',
          params: [{ chainId: HARDHAT_CHAIN.chainId }],
        });
      } catch (err2) {
        const msg2 = err2?.message ? String(err2.message) : 'Failed to add network';
        toast(msg2);
        return;
      }
    } else {
      const msg = err?.message ? String(err.message) : 'Failed to switch network';
      toast(msg);
      return;
    }
  } finally {
    setDisabled('evmAddHardhatBtn', false);
  }

  toast('Hardhat network selected');
  // Refresh UI if already connected.
  await connectEvmWallet().catch(() => undefined);
}

export async function mintPimFromUi() {
  const s = lastSession;
  if (!s?.web3 || !s?.address) {
    toast('Connect your EVM wallet first.');
    return;
  }

  const tokenAddr = pimTokenAddressForChain(s.chainId);
  if (!tokenAddr) {
    toast('PIM contract not configured for this chain.');
    return;
  }

  const input = document.getElementById('evmPimMintAmount');
  const raw = (input?.value || '').toString().trim();
  if (!raw) {
    toast('Enter a mint amount.');
    return;
  }

  let amountWei;
  try {
    // PIMToken uses 18 decimals.
    amountWei = s.web3.utils.toWei(raw, 'ether');
  } catch (_) {
    toast('Invalid amount');
    return;
  }

  const contract = new s.web3.eth.Contract(ERC20_ABI, tokenAddr);

  setDisabled('evmPimMintBtn', true);
  toast('Minting… confirm in your wallet');

  try {
    await contract.methods.mint(amountWei).send({ from: s.address });
    if (input) input.value = '';
    toast('Mint complete');
    await refreshEvmReadouts();
  } catch (err) {
    const message = err?.message ? String(err.message) : 'Mint failed';
    toast(message);
  } finally {
    setDisabled('evmPimMintBtn', false);
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
