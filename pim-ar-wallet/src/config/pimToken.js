// Configure the PIM ERC-20 contract address per chain.
// If you don't have a deployed contract yet, leave it null.
//
// Example:
// export const PIM_TOKEN_BY_CHAIN = {
//   42161: '0xYourArbitrumPimToken',
//   11155111: '0xYourSepoliaPimToken'
// };

export const PIM_TOKEN_BY_CHAIN = {
  // 42161: null,
  // 11155111: null,
};

export function pimTokenAddressForChain(chainId) {
  const addr = PIM_TOKEN_BY_CHAIN[chainId];
  if (!addr) return null;
  return addr;
}
