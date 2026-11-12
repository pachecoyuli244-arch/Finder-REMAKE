/* PVFinder: configurable public presentation, never inject HTML or executable code. */
(() => {
  'use strict';
  const apply = (data) => {
    const values = data && data.values;
    if (!values || typeof values !== 'object') return;
    window.PVF_SITE_CONTENT = values;
    for (const el of document.querySelectorAll('[data-site-field]')) {
      const key = el.dataset.siteField;
      if (typeof values[key] === 'string') el.textContent = values[key];
    }
    for (const el of document.querySelectorAll('[data-site-price]')) {
      const val = Number(values[el.dataset.sitePrice]);
      if (Number.isFinite(val) && val >= 1 && val <= 999.99) {
        el.textContent = '$' + val.toLocaleString('en-US', {maximumFractionDigits:2});
      }
    }
    const url = values.sales_discord_link;
    if (typeof url === 'string') {
      try {
        const u = new URL(url);
        if (u.protocol === 'https:' && ['discord.com','www.discord.com','discord.gg','www.discord.gg'].includes(u.hostname)) {
          document.querySelectorAll('[data-site-link="discord"]').forEach(a => {a.href = u.href;});
        }
      } catch (_) {}
    }
    const color = k => typeof values[k] === 'string' && /^#[0-9a-fA-F]{6}$/.test(values[k]) ? values[k] : '';
    const primary = color('theme_primary');
    const secondary = color('theme_secondary');
    const homeBg = color('theme_background');
    const salesBg = color('theme_sales_background');
    const vars = document.documentElement.style;
    if (primary) vars.setProperty('--purple', primary);
    if (secondary) {
      vars.setProperty('--blue',secondary);
      vars.setProperty('--cyan',secondary);
    }
    if (homeBg && !document.body.classList.contains('sales-page')) vars.setProperty('--bg',homeBg);
    if (salesBg && document.body.classList.contains('sales-page')) vars.setProperty('--bg',salesBg);
    if (primary && secondary) {
      const style = document.createElement('style');
      style.textContent = '.grad{background:linear-gradient(92deg,' + secondary + ',' + primary + ');-webkit-background-clip:text;background-clip:text;color:transparent}' +
          '.primary,button[data-plan],.paypal-checkout{--site-primary:' + primary + ';--site-secondary:' + secondary + '}' +
          '.primary,button[data-plan]{background:linear-gradient(100deg,' + secondary + ',' + primary + ')}';
      document.head.appendChild(style);
    }
    const announcement = document.getElementById('site-announcement');
    if (announcement) {
      const text = (values.site_announcement || '').trim();
      announcement.textContent = text;
      announcement.hidden = !text;
    }
    const extra = document.getElementById('site-extra-content');
    if (extra) {
      const title = (values.sales_extra_title || '').trim();
      const body = (values.sales_extra_text || '').trim();
      extra.hidden = !title && !body;
    }
    const brand = typeof values.brand_name === 'string' && values.brand_name ? values.brand_name : 'PVFINDER';
    document.title = document.body.classList.contains('sales-page') ? brand + ' | Planes de acceso' : brand + ' | Live Feed';
  };
  window.PVF_SITE_CONFIG_READY = fetch('/api/site/content',{cache:'no-store',credentials:'same-origin'})
    .then(r => r.ok ? r.json() : null)
    .then(apply)
    .catch(() => {});
})();
