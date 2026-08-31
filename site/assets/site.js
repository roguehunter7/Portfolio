// Shared site behavior: theme toggle + email obfuscation + mermaid init.
// CSP allows 'self' scripts; mermaid loaded from the pinned CDN in each page's head.
(function () {
  'use strict';

  function applyTheme(theme) {
    document.documentElement.dataset.theme = theme;
    if (window.mermaid) {
      window.mermaid.initialize({ startOnLoad: false, theme: theme === 'light' ? 'default' : 'dark' });
      document.querySelectorAll('.mermaid').forEach(function (el) {
        el.removeAttribute('data-processed');
      });
    }
  }

  function runMermaid() {
    if (window.mermaid) {
      window.mermaid.run({ nodes: document.querySelectorAll('.mermaid') });
    }
  }

  function toggleTheme() {
    var html = document.documentElement;
    var next = html.dataset.theme === 'light' ? 'dark' : 'light';
    localStorage.setItem('theme', next);
    applyTheme(next);
    runMermaid();
  }

  function revealEmail() {
    var user = 'contact.sreeramkr';
    var domain = 'gmail.com';
    document.querySelectorAll('.email-link').forEach(function (el) {
      el.href = 'mailto:' + user + '@' + domain;
      el.textContent = user + '@' + domain;
    });
  }

  window.__portfolioToggle = toggleTheme;
  window.__portfolioRunMermaid = runMermaid;

  document.addEventListener('DOMContentLoaded', function () {
    var saved = localStorage.getItem('theme') || 'dark';
    applyTheme(saved);
    revealEmail();
    runMermaid();

    var btn = document.querySelector('.theme-toggle');
    if (btn) btn.addEventListener('click', toggleTheme);
  });
})();
