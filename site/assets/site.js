// Shared site behavior: theme toggle + email obfuscation + hero terminal + phase rail.
// CSP allows 'self' scripts only; diagrams are inline SVG themed by CSS variables.
(function () {
  'use strict';

  function reducedMotion() {
    return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  }
  function hasObserver() {
    return 'IntersectionObserver' in window;
  }

  function applyTheme(theme) {
    document.documentElement.dataset.theme = theme;
  }

  function toggleTheme() {
    var html = document.documentElement;
    var next = html.dataset.theme === 'light' ? 'dark' : 'light';
    localStorage.setItem('theme', next);
    applyTheme(next);
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
    if (reducedMotion()) {
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
    if (!hasObserver() || sections.some(function (s) { return !s; })) return;
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

    // Respect reduced motion (and older browsers): show everything immediately.
    if (reducedMotion() || !hasObserver()) {
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

  document.addEventListener('DOMContentLoaded', function () {
    var saved = localStorage.getItem('theme');
    var systemDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    applyTheme(saved || (systemDark ? 'dark' : 'light'));
    revealEmail();
    setupCopyEmail();
    setupTerminal();
    setupPhaseRail();
    setupReveal();

    var btn = document.querySelector('.theme-toggle');
    if (btn) btn.addEventListener('click', toggleTheme);
  });
})();
