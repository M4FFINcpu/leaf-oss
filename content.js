// Leaf OS Web Helper: page script.
// 1) On a Leaf OS page: tells Leaf OS the helper is installed, and asks the worker to switch on for this tab.
// 2) On a website shown inside Leaf OS's Chromium (only after Leaf OS greets it): reports the page's
//    address and title so Leaf OS can show them, and opens "new window" links as Leaf OS tabs.
(() => {
  if (window.__leafosWebHelper) return;
  window.__leafosWebHelper = true;

  if (document.querySelector('meta[name="leafos-app"]')) {
    const mark = state => {
      document.documentElement.setAttribute('data-leafos-helper', state);
      window.dispatchEvent(new CustomEvent('leafos-helper', { detail: state }));
    };
    const hello = () => {
      try {
        chrome.runtime.sendMessage({ type: 'leafos-hello' }, res => {
          if (chrome.runtime.lastError) return;
          mark(res && res.active ? 'on' : 'needs-approval');
        });
      } catch (e) {}
    };
    chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
      if (!msg) return;
      if (msg.type === 'leafos-query') { sendResponse({ origin: location.protocol === 'file:' ? 'file://' : location.origin }); return; }
      if (msg.type === 'leafos-enabled') mark('on');
    });
    document.documentElement.setAttribute('data-leafos-helper', 'installed');
    window.addEventListener('leafos-helper-check', hello);
    window.addEventListener('hashchange', hello);
    hello();
    return;
  }

  if (window.top === window) return;
  let target = null;
  window.addEventListener('message', e => {
    if (target || e.source !== window.parent || !e.data || e.data.leafosPing !== 1) return;
    const origin = e.origin;
    try {
      chrome.runtime.sendMessage({ type: 'leafos-frame' }, res => {
        if (chrome.runtime.lastError || !res || !res.active || target) return;
        target = origin && origin !== 'null' ? origin : '*';
        start();
      });
    } catch (err) {}
  });
  const post = m => { try { window.parent.postMessage(m, target); } catch (e) {} };
  function start() {
    let last = '';
    const report = () => {
      const key = location.href + '\n' + document.title;
      if (key === last) return;
      last = key;
      post({ leafosFrame: { url: location.href, title: String(document.title || '').slice(0, 200) } });
    };
    report();
    setInterval(report, 600);
    document.addEventListener('click', e => {
      if (e.button !== 0) return;
      const a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
      if (!a || !/^https?:/i.test(a.href)) return;
      const t = (a.getAttribute('target') || '').toLowerCase();
      if (t === '_blank' || e.ctrlKey || e.metaKey || e.shiftKey) {
        e.preventDefault(); e.stopImmediatePropagation();
        post({ leafosOpenTab: a.href });
      } else if (t === '_top' || t === '_parent') {
        e.preventDefault();
        location.href = a.href;
      }
    }, true);
  }
})();
