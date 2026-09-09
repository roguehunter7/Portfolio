// Theme bootstrap — loaded render-blocking in <head> so the correct theme is
// applied before first paint (no flash of the wrong theme).
// External file rather than inline, so the CSP needs no nonce or 'unsafe-inline'.
document.documentElement.dataset.theme =
  localStorage.getItem('theme') ||
  (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
