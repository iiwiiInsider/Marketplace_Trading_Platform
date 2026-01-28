export const CHAINS = {
  1: { name: 'Ethereum Mainnet', nativeSymbol: 'ETH' },
  10: { name: 'Optimism', nativeSymbol: 'ETH' },
  56: { name: 'BNB Chain', nativeSymbol: 'BNB' },
  137: { name: 'Polygon', nativeSymbol: 'POL' },
  42161: { name: 'Arbitrum One', nativeSymbol: 'ETH' },
  43114: { name: 'Avalanche C-Chain', nativeSymbol: 'AVAX' },
  11155111: { name: 'Sepolia (testnet)', nativeSymbol: 'ETH' },
};

export function chainLabel(chainId) {
  const info = CHAINS[chainId];
  if (info) return `${info.name} (chainId ${chainId})`;
  return `Unknown (chainId ${chainId ?? '—'})`;
}

export function nativeSymbol(chainId) {
  return CHAINS[chainId]?.nativeSymbol ?? 'NATIVE';
}
