// Leaf OS Web Helper: background worker.
// In a tab that runs Leaf OS, websites opened in Leaf OS's Chromium app are shown in a frame.
// Most sites send headers that forbid being shown inside another page (X-Frame-Options,
// Content-Security-Policy frame-ancestors). This worker removes those headers, but only for
// frames, and only inside tabs where Leaf OS is running. Normal browsing is not touched.

function ruleIds(tabId) {
  const base = (tabId % 500000000) * 4;
  return [base + 1, base + 2];
}

function originOf(url) {
  try { const u = new URL(url); return u.protocol === 'file:' ? 'file://' : u.origin; } catch (e) { return ''; }
}

// Leaf OS opened as a file, or from this computer, is always allowed.
// Websites (GitHub Pages, Google Sites...) are allowed once the user clicks the helper's icon there.
function alwaysAllowed(origin) {
  return origin === 'file://' || origin === 'null' || /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/.test(origin);
}

async function getTrusted() { return (await chrome.storage.local.get('trusted')).trusted || []; }
async function getActive() { return (await chrome.storage.session.get('tabs')).tabs || {}; }
async function setActive(tabId, on) {
  const tabs = await getActive();
  if (on) tabs[tabId] = Date.now(); else delete tabs[tabId];
  await chrome.storage.session.set({ tabs });
}

async function enableTab(tabId) {
  const [frameRule, ytRule] = ruleIds(tabId);
  await chrome.declarativeNetRequest.updateSessionRules({
    removeRuleIds: [frameRule, ytRule],
    addRules: [
      {
        id: frameRule,
        priority: 1,
        // (pages from this computer itself keep their protections: Leaf OS ISO uses them for downloaded files)
        condition: { tabIds: [tabId], resourceTypes: ['sub_frame'], excludedRequestDomains: ['127.0.0.1', 'localhost'] },
        action: {
          type: 'modifyHeaders',
          responseHeaders: [
            { header: 'x-frame-options', operation: 'remove' },
            { header: 'content-security-policy', operation: 'remove' },
            { header: 'content-security-policy-report-only', operation: 'remove' }
          ]
        }
      },
      {
        // YouTube's player refuses to start without a Referer ("Error 153"), and pages opened as files send none.
        id: ytRule,
        priority: 1,
        condition: { tabIds: [tabId], resourceTypes: ['sub_frame'], requestDomains: ['youtube.com', 'youtube-nocookie.com'], urlFilter: '/embed/' },
        action: { type: 'modifyHeaders', requestHeaders: [{ header: 'referer', operation: 'set', value: 'https://leafos.app/' }] }
      }
    ]
  });
  await setActive(tabId, true);
}

async function disableTab(tabId) {
  try { await chrome.declarativeNetRequest.updateSessionRules({ removeRuleIds: ruleIds(tabId) }); } catch (e) {}
  await setActive(tabId, false);
}

function badge(tabId, text, color, title) {
  chrome.action.setBadgeText({ tabId, text }).catch(() => {});
  if (color) chrome.action.setBadgeBackgroundColor({ tabId, color }).catch(() => {});
  if (title) chrome.action.setTitle({ tabId, title }).catch(() => {});
}

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  const tabId = sender.tab && sender.tab.id;
  if (!msg || tabId == null || tabId < 0) return;

  if (msg.type === 'leafos-hello') {
    (async () => {
      const origin = sender.origin || originOf(sender.url);
      const ok = alwaysAllowed(origin) || (await getTrusted()).includes(origin);
      if (ok) {
        await enableTab(tabId);
        badge(tabId, 'ON', '#059669', 'Leaf OS Web Helper is on in this tab');
      } else {
        badge(tabId, '!', '#d97706', 'Click to let Leaf OS on this site show websites');
      }
      sendResponse({ active: ok });
    })();
    return true;
  }

  if (msg.type === 'leafos-frame') {
    getActive().then(tabs => sendResponse({ active: !!tabs[tabId] }));
    return true;
  }
});

// Clicking the icon on a page that runs Leaf OS (for example on GitHub Pages or Google Sites) allows that site.
chrome.action.onClicked.addListener(async tab => {
  if (!tab || tab.id == null) return;
  let res = null;
  try { res = await chrome.tabs.sendMessage(tab.id, { type: 'leafos-query' }); } catch (e) {}
  if (!res || !res.origin) {
    badge(tab.id, '?', '#64748b', 'No Leaf OS page found in this tab. Open Leaf OS first. If Leaf OS is a file, turn on "Allow access to file URLs" for this helper.');
    return;
  }
  const trusted = await getTrusted();
  if (!trusted.includes(res.origin)) { trusted.push(res.origin); await chrome.storage.local.set({ trusted }); }
  await enableTab(tab.id);
  badge(tab.id, 'ON', '#059669', 'Leaf OS Web Helper is on in this tab');
  try { await chrome.tabs.sendMessage(tab.id, { type: 'leafos-enabled' }); } catch (e) {}
});

// When a tab leaves Leaf OS, stop changing its pages.
chrome.tabs.onUpdated.addListener((tabId, info) => {
  if (info.status === 'loading' && info.url !== undefined) disableTab(tabId);
});
chrome.tabs.onRemoved.addListener(tabId => { disableTab(tabId); });
