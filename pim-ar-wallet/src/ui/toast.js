function getToastEls() {
  const toast = document.getElementById('toast');
  const toastText = document.getElementById('toastText');
  return { toast, toastText };
}

export function toast(message) {
  const { toast, toastText } = getToastEls();
  if (!toast || !toastText) {
    // Fallback for environments where the UI isn't loaded yet.
    // eslint-disable-next-line no-alert
    alert(message);
    return;
  }

  toastText.textContent = String(message);
  toast.classList.remove('opacity-0');
  toast.classList.add('opacity-100');

  window.clearTimeout(toast.__hideTimer);
  toast.__hideTimer = window.setTimeout(() => {
    toast.classList.add('opacity-0');
    toast.classList.remove('opacity-100');
  }, 2600);
}
