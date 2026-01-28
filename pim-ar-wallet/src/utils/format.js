export function shortenAddress(address, chars = 6) {
  if (!address || typeof address !== 'string') return '—';
  if (!address.startsWith('0x') || address.length < 10) return address;
  return `${address.slice(0, 2 + chars)}…${address.slice(-chars)}`;
}

export function formatDecimalString(value, { maxFrac = 6 } = {}) {
  if (value === null || value === undefined) return '—';
  const str = String(value).trim();
  if (!str) return '—';

  const m = str.match(/^(-?)(\d+)(?:\.(\d+))?$/);
  if (!m) return str;

  const sign = m[1] || '';
  const intPart = m[2] || '0';
  const fracPart = m[3] || '';

  const intWithSep = intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  if (!fracPart) return sign + intWithSep;

  const trimmedFrac = fracPart.slice(0, Math.max(0, maxFrac)).replace(/0+$/, '');
  if (!trimmedFrac) return sign + intWithSep;
  return `${sign}${intWithSep}.${trimmedFrac}`;
}

export function formatNumber(value, { maxFrac = 6 } = {}) {
  // Back-compat wrapper: prefer decimal-string formatting when possible.
  if (typeof value === 'string') return formatDecimalString(value, { maxFrac });
  const num = value;
  if (!Number.isFinite(num)) return '—';
  return num.toLocaleString(undefined, { maximumFractionDigits: maxFrac });
}

export function formatTokenAmount(raw, decimals) {
  const rawBig = BigInt(raw ?? 0);
  const d = Number(decimals ?? 18);
  if (!Number.isFinite(d) || d < 0 || d > 255) return rawBig.toString();

  const base = 10n ** BigInt(d);
  const whole = rawBig / base;
  const frac = rawBig % base;

  if (frac === 0n) return whole.toString();

  // Trim trailing zeros in fractional.
  let fracStr = frac.toString().padStart(d, '0');
  fracStr = fracStr.replace(/0+$/, '');
  return `${whole.toString()}.${fracStr}`;
}
