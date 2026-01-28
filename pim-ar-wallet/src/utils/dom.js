export function setText(id, text) {
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent = text;
}

export function setDisabled(id, disabled) {
  const el = document.getElementById(id);
  if (!el) return;
  el.disabled = Boolean(disabled);
}
