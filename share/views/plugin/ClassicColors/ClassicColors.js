(() => {
  'use strict';
  const root = document.documentElement;
  const base = document.body.dataset.ndUriBase || '';
  let saving = false;
  let refreshing = false;
  let generation = 0;
  const apply = classic => {
    if (classic) root.setAttribute('data-nd-palette', 'classic');
    else root.removeAttribute('data-nd-palette');
  };
  const refresh = async () => {
    if (saving || refreshing || document.hidden) return;
    refreshing = true;
    const started = generation;
    try {
      const response = await fetch(base + '/ajax/appearance', {
        credentials: 'same-origin', cache: 'no-store',
        headers: {'X-Requested-With': 'XMLHttpRequest'}
      });
      if (response.ok) {
        const state = await response.json();
        if (!saving && started === generation) apply(state.classic_colors === 1);
      }
    } catch (_) { /* Keep the existing palette on a temporary connection failure. */ }
    finally { refreshing = false; }
  };
  const save = async (event, form) => {
    if (!(form instanceof HTMLElement) || form.id !== 'nd-appearance-form') return;
    event.preventDefault();
    event.stopPropagation();
    if (saving) return;
    saving = true;
    generation += 1;
    const button = form.querySelector('button[type="button"]');
    const status = form.querySelector('[role="status"]');
    button.disabled = true;
    status.textContent = 'Saving…';
    try {
      const body = new URLSearchParams();
      body.set('csrf', form.querySelector('[name="csrf"]').value);
      body.set('classic_colors', form.querySelector('[name="classic_colors"]').checked ? '1' : '0');
      const response = await fetch(form.dataset.action, {
        method: 'POST', credentials: 'same-origin', cache: 'no-store', body,
        headers: {'X-Requested-With': 'XMLHttpRequest'}
      });
      if (!response.ok) throw new Error('save failed');
      const state = await response.json();
      apply(state.classic_colors === 1);
      status.textContent = 'Saved for everyone.';
    } catch (_) {
      status.textContent = 'Could not save. Reload this page and try again.';
    } finally { saving = false; button.disabled = false; }
  };
  document.addEventListener('click', event => {
    const button = event.target instanceof Element ? event.target.closest('#nd-appearance-form button[type="button"]') : null;
    if (button) save(event, button.closest('#nd-appearance-form'));
  }, true);
  refresh();
  setInterval(refresh, 30000);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });
})();
