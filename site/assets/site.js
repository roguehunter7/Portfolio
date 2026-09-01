// Shared site behavior: theme toggle + email obfuscation + mermaid init + hero terminal + phase rail.
// CSP allows 'self' scripts; mermaid loaded from the pinned CDN on pages that render diagrams.
(function () {
  'use strict';

  function applyTheme(theme) {
    document.documentElement.dataset.theme = theme;
    if (window.mermaid) {
      window.mermaid.initialize({
        startOnLoad: false,
        // 'base' + explicit variables so diagrams match the site palette in both themes
        theme: 'base',
        themeVariables: theme === 'light'
          ? {
              fontFamily: '"JetBrains Mono", Menlo, monospace',
              fontSize: '14px',
              primaryColor: '#f1f5f9',
              primaryTextColor: '#0f172a',
              primaryBorderColor: '#2563eb',
              secondaryColor: '#e2e8f0',
              tertiaryColor: '#f8fafc',
              lineColor: '#64748b'
            }
          : {
              fontFamily: '"JetBrains Mono", Menlo, monospace',
              fontSize: '14px',
              primaryColor: '#1a2332',
              primaryTextColor: '#e2e8f0',
              primaryBorderColor: '#60a5fa',
              secondaryColor: '#111827',
              tertiaryColor: '#1f2a3d',
              lineColor: '#94a3b8'
            }
      });
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

  // Copy-email micro-button: clipboard write + transient "copied" feedback.
  function setupCopyEmail() {
    document.querySelectorAll('.copy-email').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var addr = 'contact.sreeramkr@gmail.com';
        var done = function () {
          btn.classList.add('copied');
          var prev = btn.textContent;
          btn.textContent = 'copied \u2713';
          setTimeout(function () { btn.classList.remove('copied'); btn.textContent = prev; }, 1600);
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(addr).then(done, done);
        } else {
          done();
        }
      });
    });
  }

  // Hero terminal: one command types itself once; reduced motion shows it static.
  function setupTerminal() {
    var el = document.querySelector('[data-type]');
    if (!el) return;
    var text = el.getAttribute('data-type');
    if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      el.textContent = text;
      return;
    }
    var i = 0;
    var step = function () {
      if (i <= text.length) {
        el.textContent = text.slice(0, i);
        i += 1;
        setTimeout(step, 34);
      }
    };
    setTimeout(step, 400);
  }

  // Archive phase rail: highlight the phase currently in view.
  function setupPhaseRail() {
    var rail = document.querySelector('.phase-rail');
    if (!rail) return;
    var links = rail.querySelectorAll('a');
    var sections = links.length
      ? Array.prototype.map.call(links, function (a) { return document.querySelector(a.getAttribute('href')); })
      : [];
    if (!('IntersectionObserver' in window) || sections.some(function (s) { return !s; })) {
      return;
    }
    var activate = function (idx) {
      links.forEach(function (a, i) { a.classList.toggle('active', i === idx); });
    };
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        var idx = sections.indexOf(entry.target);
        if (idx > -1) activate(idx);
      });
    }, { rootMargin: '-20% 0px -70% 0px', threshold: 0 });
    sections.forEach(function (s) { observer.observe(s); });
    activate(0);
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
    var saved = localStorage.getItem('theme');
    var systemDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    applyTheme(saved || (systemDark ? 'dark' : 'light'));
    revealEmail();
    setupCopyEmail();
    setupTerminal();
    runMermaid();
    setupPhaseRail();
    setupReveal();

    var btn = document.querySelector('.theme-toggle');
    if (btn) btn.addEventListener('click', toggleTheme);
  });
})();
