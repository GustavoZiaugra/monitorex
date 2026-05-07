// Monitorex Dashboard — Client JS
document.addEventListener('DOMContentLoaded', () => {
  // Highlight active nav link
  const navLinks = document.querySelectorAll('nav a');
  const path = window.location.pathname;
  navLinks.forEach(link => {
    if (link.getAttribute('href') === path) link.classList.add('active');
  });

  // Hamburger toggle for mobile nav
  const hamburger = document.getElementById('nav-toggle');
  const nav = document.querySelector('nav');
  if (hamburger && nav) {
    hamburger.addEventListener('click', () => {
      nav.classList.toggle('nav-open');
    });
  }
});
