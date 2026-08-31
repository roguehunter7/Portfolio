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

  function setupReveal() {
    var targets = document.querySelectorAll('.js-reveal');
    if (!targets.length) return;

    // Respect reduced motion: show everything immediately, no animation.
    if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      targets.forEach(function (el) { el.classList.add('is-visible'); });
      return;
    }

    if (!('IntersectionObserver' in window)) {
      targets.forEach(function (el) { el.classList.add('is-visible'); });
      return;
    }

    var observer = new IntersectionObserver(function (entries, obs) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add('is-visible');
        obs.unobserve(entry.target);
      });
    }, { threshold: 0.1, rootMargin: '0px 0px -8% 0px' });

    targets.forEach(function (el) { observer.observe(el); });
  }

  window.__portfolioToggle = toggleTheme;
  window.__portfolioRunMermaid = runMermaid;

  document.addEventListener('DOMContentLoaded', function () {
    var saved = localStorage.getItem('theme') || 'dark';
    applyTheme(saved);
    revealEmail();
    runMermaid();
    setupReveal();

    var btn = document.querySelector('.theme-toggle');
    if (btn) btn.addEventListener('click', toggleTheme);
  });
})();
