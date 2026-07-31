// Monitorex Dashboard — Client JS v2
import {Socket} from "phoenix";
import {LiveSocket} from "phoenix_live_view";

(function() {
  'use strict';

  const NAV_KEY = 'monitorex_nav_open';

  function highlightActiveNav() {
    const path = window.location.pathname;
    document.querySelectorAll('nav a').forEach(link => {
      const href = link.getAttribute('href');
      link.classList.toggle('active', href === path);
    });
  }

  function setupNavToggle() {
    const hamburger = document.getElementById('nav-toggle');
    const nav = document.querySelector('nav');
    if (!hamburger || !nav) return;

    const saved = sessionStorage.getItem(NAV_KEY);
    if (saved === 'true' && window.innerWidth <= 768) {
      nav.classList.add('nav-open');
      hamburger.classList.add('nav-open');
      document.body.classList.add('nav-open');
    }

    hamburger.addEventListener('click', () => {
      const isOpen = nav.classList.toggle('nav-open');
      hamburger.classList.toggle('nav-open', isOpen);
      document.body.classList.toggle('nav-open', isOpen);
      try {
        if (isOpen) { sessionStorage.setItem(NAV_KEY, 'true'); }
        else { sessionStorage.removeItem(NAV_KEY); }
      } catch (_) {}
    });

    nav.querySelectorAll('a').forEach(link => {
      link.addEventListener('click', () => {
        if (window.innerWidth <= 768) {
          nav.classList.remove('nav-open');
          hamburger.classList.remove('nav-open');
          document.body.classList.remove('nav-open');
          try { sessionStorage.removeItem(NAV_KEY); } catch (_) {}
        }
      });
    });
  }

  function setupResizeHandler() {
    let prevWidth = window.innerWidth;
    window.addEventListener('resize', () => {
      const width = window.innerWidth;
      if (prevWidth <= 768 && width > 768) {
        const nav = document.querySelector('nav');
        const hamburger = document.getElementById('nav-toggle');
        if (nav && hamburger) {
          nav.classList.remove('nav-open');
          hamburger.classList.remove('nav-open');
          document.body.classList.remove('nav-open');
          try { sessionStorage.removeItem(NAV_KEY); } catch (_) {}
        }
      }
      prevWidth = width;
    });
  }

  document.addEventListener('DOMContentLoaded', () => {
    highlightActiveNav();
    setupNavToggle();
    setupResizeHandler();
  });
})();

const csrfMeta = document.querySelector("meta[name='csrf-token']");
const socketMeta = document.querySelector("meta[name='monitorex-socket-path']");
const csrfToken = csrfMeta ? csrfMeta.getAttribute("content") : "";
const socketPath = socketMeta ? socketMeta.getAttribute("content") : "/live";

const liveSocket = new LiveSocket(socketPath, Socket, {params: {_csrf_token: csrfToken}});
liveSocket.connect();
