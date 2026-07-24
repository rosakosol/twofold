// Twofold site — shared behaviour: nav scroll state, scroll reveals, FAQ accordion.
(function () {
  const nav = document.querySelector('.nav');
  if (nav) {
    const onScroll = () => nav.classList.toggle('scrolled', window.scrollY > 8);
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
  }

  const reveals = document.querySelectorAll('.reveal');
  if (reveals.length && 'IntersectionObserver' in window) {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -8% 0px' });
    reveals.forEach((el, i) => {
      if (el.dataset.delay) el.style.transitionDelay = el.dataset.delay + 'ms';
      io.observe(el);
    });
    // Reveal anything already in the viewport right away (don't wait for a scroll).
    const revealVisible = () => {
      const h = window.innerHeight || document.documentElement.clientHeight;
      reveals.forEach((el) => { if (el.getBoundingClientRect().top < h * 0.95) el.classList.add('in'); });
    };
    requestAnimationFrame(revealVisible);
    window.addEventListener('load', revealVisible);
    // Failsafe: if the observer never delivers, reveal everything anyway.
    setTimeout(() => document.querySelectorAll('.reveal:not(.in)').forEach((el) => el.classList.add('in')), 1400);
  } else {
    reveals.forEach((el) => el.classList.add('in'));
  }

  // FAQ accordion
  document.querySelectorAll('[data-accordion] .acc-item').forEach((item) => {
    const btn = item.querySelector('.acc-q');
    if (!btn) return;
    btn.addEventListener('click', () => {
      const open = item.classList.contains('open');
      item.classList.toggle('open', !open);
    });
  });

  // Pricing billing toggle
  document.querySelectorAll('[data-toggle-group]').forEach((group) => {
    const buttons = group.querySelectorAll('button');
    buttons.forEach((b) => b.addEventListener('click', () => {
      buttons.forEach((x) => x.classList.remove('active'));
      b.classList.add('active');
      const val = b.dataset.val;
      document.querySelectorAll('[data-plan]').forEach((el) => {
        el.classList.toggle('hidden', el.dataset.plan !== val);
      });
    }));
  });
})();
