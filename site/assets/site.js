// Shared site behavior: theme toggle + email obfuscation + hero terminal + phase rail.
// Each phase embeds a self-contained Archify diagram in an iframe; no client-side renderer.
(function () {
  'use strict';

  function reducedMotion() {
    return window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  }
  function hasObserver() {
    return 'IntersectionObserver' in window;
  }

  // Each diagram is a separate document that themes itself from its own
  // localStorage or the OS preference, so the site's choice is pushed into
  // every frame. Same-origin, so this is a direct DOM write rather than a
  // reload — no flicker, no refetch of a 600 KB viewer.
  function syncDiagramTheme(theme) {
    document.querySelectorAll('iframe.diagram-frame').forEach(function (frame) {
      try {
        var doc = frame.contentDocument;
        if (!doc || !doc.documentElement) return;
        doc.documentElement.setAttribute('data-theme', theme);
        frame.contentWindow.localStorage.setItem('archify-theme', theme);
      } catch (err) {
        /* not loaded yet, or cross-origin: the load handler retries */
      }
    });
  }

  function setupDiagramTheme() {
    document.querySelectorAll('iframe.diagram-frame').forEach(function (frame) {
      frame.addEventListener('load', function () {
        syncDiagramTheme(document.documentElement.dataset.theme);
      });
    });
    // Frames that finished loading before this ran have no event left to fire.
    syncDiagramTheme(document.documentElement.dataset.theme);
  }

  function applyTheme(theme) {
    document.documentElement.dataset.theme = theme;
    syncDiagramTheme(theme);
  }

  function toggleTheme() {
    var html = document.documentElement;
    var next = html.dataset.theme === 'light' ? 'dark' : 'light';
    localStorage.setItem('theme', next);
    if (!reducedMotion() && document.startViewTransition) {
      document.startViewTransition(function () { applyTheme(next); });
    } else {
      applyTheme(next);
    }
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

  // Wide diagrams scroll sideways inside their frame; flag that so the fade
  // affordance only appears when there really is hidden content.
  function setupDiagramScroll() {
    var frames = document.querySelectorAll('.diagram-container');
    if (!frames.length) return;
    var update = function (el) {
      el.classList.toggle('is-scrollable', el.scrollWidth > el.clientWidth + 1);
    };
    frames.forEach(function (el) {
      update(el);
      el.addEventListener('scroll', function () { update(el); }, { passive: true });
    });
    window.addEventListener('resize', function () {
      frames.forEach(update);
    });
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

  document.addEventListener('DOMContentLoaded', function () {
    var saved = localStorage.getItem('theme');
    var systemDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    applyTheme(saved || (systemDark ? 'dark' : 'light'));
    setupDiagramTheme();
    revealEmail();
    setupCopyEmail();
    setupTerminal();
    setupDiagramScroll();
    setupPhaseRail();
    setupReveal();

    var btn = document.querySelector('.theme-toggle');
    if (btn) btn.addEventListener('click', toggleTheme);
  });
})();
