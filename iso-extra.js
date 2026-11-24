// Leaf OS ISO edition extras (loaded only by the ISO, after the desktop's own script).
// Adds: real Shut down / Restart, Terminal commands (netstatus, netfix, crashlog, free...),
// a Downloads app for files Chromium saves, real Chromium windows for logins, and notices.
(function () {
    if (!/^(127\.0\.0\.1|localhost)$/.test(location.hostname)) return;

    const post = (path, body) => fetch(path, { method: 'POST', headers: { 'X-Leaf': '1' }, body: body || '' });
    const getJSON = async path => { const r = await fetch(path, { cache: 'no-store' }); if (!r.ok) throw new Error('HTTP ' + r.status); return r.json(); };
    const getText = async path => { const r = await fetch(path, { cache: 'no-store' }); return r.text(); };
    const esc = s => escapeHtml(String(s == null ? '' : s));
    const arg = s => esc(JSON.stringify(String(s == null ? '' : s)));
    const fmtSize = n => n >= 1073741824 ? (n / 1073741824).toFixed(1) + ' GB' : n >= 1048576 ? (n / 1048576).toFixed(1) + ' MB' : n >= 1024 ? Math.round(n / 1024) + ' KB' : n + ' B';

    /* ---------- real Shut down / Restart ---------- */
    const basePower = window.powerAction;
    window.powerAction = function (kind) {
        if (kind !== 'shutdown' && kind !== 'restart') return basePower(kind);
        const sd = document.getElementById('v43-shutdown'), msg = document.getElementById('v43-shutdown-msg');
        if (msg) msg.textContent = kind === 'restart' ? 'Restarting' : 'Shutting down';
        if (sd) sd.style.display = 'flex';
        setTimeout(() => post(kind === 'restart' ? '/power/reboot' : '/power/off').catch(() => {}), 900);
    };

    /* ---------- real Chromium windows (for logins and anything that won't work inside Leaf OS) ---------- */
    window.leafOpenReal = function (url) {
        url = String(url || '').trim();
        if (!/^https?:\/\//i.test(url)) url = 'https://www.google.com/search?q=' + encodeURIComponent(url);
        showToast('Opening in a Chromium window: ' + url.replace(/^https?:\/\//, '').slice(0, 60));
        post('/open', url).catch(() => {});
    };
    window.brOpenReal = url => leafOpenReal(url);
    window.chrOpenReal = url => leafOpenReal(url);
    window.open = function (url) { if (url && /^https?:/i.test(String(url))) leafOpenReal(String(url)); return null; };
    window.addEventListener('click', e => {
        const a = e.target.closest ? e.target.closest('a[target="_blank"]') : null;
        if (a && /^https?:/i.test(a.href) && !a.href.startsWith(location.origin + '/')) {
            e.preventDefault(); e.stopPropagation();
            leafOpenReal(a.href);
        }
    }, true);

    // Files served by this computer (Downloads) always open directly in Chromium
    const baseLoad = window.brLoad;
    window.brLoad = function (t) {
        if (t && typeof t.url === 'string' && t.url.startsWith(location.origin + '/')) {
            t.token++; t.frame = null; t.via = ''; t.loading = false; t.awaitFirst = false;
            t.pane.innerHTML = '';
            let name = t.url.split('/').pop(); try { name = decodeURIComponent(name); } catch (e) {}
            brFrame(t, t.url, null, name);
            return;
        }
        return baseLoad(t);
    };

    /* ---------- Downloads app ---------- */
    document.head.insertAdjacentHTML('beforeend', `<style>
        .g-dl { background: linear-gradient(135deg, #22c55e, #15803d); }
        .dl-row { display: flex; align-items: center; gap: 12px; padding: 10px 12px; border: 1px solid var(--win-border); background: var(--win-surface); border-radius: 10px; margin-bottom: 8px; }
        .dl-ic { width: 38px; height: 38px; border-radius: 9px; display: flex; align-items: center; justify-content: center; color: #fff; font-weight: 800; font-size: 10.5px; flex-shrink: 0; }
        .dl-bar { height: 4px; border-radius: 2px; background: var(--win-border); overflow: hidden; margin-top: 5px; }
        .dl-bar > div { height: 100%; width: 40%; background: var(--accent-bright); animation: dlMove 1.1s ease-in-out infinite; }
        @keyframes dlMove { from { margin-left: -40%; } to { margin-left: 100%; } }
    </style>`);
    APPS.downloads = { title: 'Downloads', icon: '&#11015;', cls: 'g-dl', w: 680, h: 480 };
    const VIEW = /\.(png|jpe?g|gif|webp|bmp|ico|svg|mp4|webm|ogv|mp3|wav|ogg|oga|m4a|flac|pdf|txt|md|csv|json|html?|xml|log)$/i;
    const RUN = /\.(exe|com|bat|zip|jsdos)$/i;
    function dlKind(name) {
        const ext = name.includes('.') ? name.split('.').pop().toLowerCase() : '';
        if (/^(png|jpe?g|gif|webp|bmp|ico|svg)$/.test(ext)) return ['IMG', '#ec4899'];
        if (/^(mp4|webm|ogv|mkv|avi|mov)$/.test(ext)) return ['VID', '#8b5cf6'];
        if (/^(mp3|wav|ogg|oga|m4a|flac)$/.test(ext)) return ['MP3', '#f97316'];
        if (ext === 'pdf') return ['PDF', '#dc2626'];
        if (/^(zip|rar|7z|gz|tar|xz|jsdos)$/.test(ext)) return ['ZIP', '#ca8a04'];
        if (/^(exe|msi|com|bat)$/.test(ext)) return ['EXE', '#334155'];
        if (/^(html?|xml)$/.test(ext)) return ['WEB', '#2563eb'];
        return [(ext || 'FILE').slice(0, 4).toUpperCase(), '#64748b'];
    }
    let dlLast = null, dlKnown = null;
    function dlRender() {
        const body = document.getElementById('win-body-downloads');
        if (!body) return;
        const d = dlLast;
        if (!d) { body.innerHTML = '<div style="padding:20px;">Loading&hellip;</div>'; return; }
        const rows = d.files.map(f => {
            const [label, col] = dlKind(f.name.replace(/\.(crdownload|part|download|tmp)$/i, ''));
            const shown = f.partial ? f.name.replace(/\.(crdownload|part|download|tmp)$/i, '').replace(/^Unconfirmed \d+$/, 'New download') : f.name;
            const when = new Date(f.mtime * 1000).toLocaleString([], { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
            const btns = f.partial ? '' : [
                VIEW.test(f.name) ? `<button class="btn-accent" onclick="dlOpen(${arg(f.name)})">Open</button>` : '',
                RUN.test(f.name) ? `<button class="btn-accent" onclick="dlRun(${arg(f.name)})">Run</button>` : '',
                `<button class="btn-sm" onclick="dlDelete(${arg(f.name)})" title="Delete">&#128465;</button>`
            ].join(' ');
            return `<div class="dl-row"><div class="dl-ic" style="background:${col};">${esc(label)}</div>
                <div style="flex:1;min-width:0;"><div style="font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;" title="${esc(f.name)}">${esc(shown)}</div>
                <div style="font-size:11px;opacity:.65;">${f.partial ? 'Downloading&hellip; ' + fmtSize(f.size) : fmtSize(f.size) + ' &bull; ' + when}</div>
                ${f.partial ? '<div class="dl-bar"><div></div></div>' : ''}</div>${btns}</div>`;
        }).join('');
        const low = d.free < 300 * 1048576;
        body.innerHTML = `<div class="app-toolbar"><b style="font-size:13px;">Downloads</b>
                <span style="flex:1;font-size:11.5px;color:${low ? '#e11d48' : 'var(--win-muted)'};">${fmtSize(d.free)} free${low ? ': delete some files before downloading more' : ''}</span>
                <button class="btn-sm" onclick="dlRefresh()">&#8635; Refresh</button></div>
            <div style="flex:1;overflow-y:auto;padding:14px;background:var(--win-bg);color:var(--win-text);font-size:12.5px;">
                ${rows || `<div style="text-align:center;opacity:.7;padding:40px 10px;">No downloads yet. Files you download in Chromium appear here.</div>`}
                <div style="font-size:11px;opacity:.6;margin-top:10px;">Leaf OS runs from memory, so downloads disappear when the computer restarts. "Run" starts DOS programs and games in EXE Runner.</div>
            </div>`;
    }
    window.dlRefresh = async function () {
        try { dlLast = await getJSON('/api/downloads'); } catch (e) { return; }
        const done = dlLast.files.filter(f => !f.partial);
        if (dlKnown) {
            done.filter(f => !dlKnown.has(f.name + '|' + f.mtime + '|' + f.size)).forEach(f => {
                showToast('Downloaded: ' + f.name);
                try { pushNotification('Download complete', f.name + ' is in Downloads'); } catch (e) {}
            });
        }
        dlKnown = new Set(done.map(f => f.name + '|' + f.mtime + '|' + f.size));
        dlRender();
    };
    window.dlOpen = name => openApp('browser', { url: location.origin + '/dl/' + encodeURIComponent(name) });
    window.dlRun = async function (name) {
        try {
            const bytes = new Uint8Array(await (await fetch('/dl/' + encodeURIComponent(name), { cache: 'no-store' })).arrayBuffer());
            openApp('exe');
            setTimeout(() => exeRunBytes(bytes, name), 80);
        } catch (e) { showToast("Couldn't open " + name); }
    };
    window.dlDelete = async function (name) {
        try { await post('/api/downloads/delete', name); showToast('Deleted ' + name); } catch (e) {}
        dlRefresh();
    };
    const baseRender = window.renderAppBody;
    window.renderAppBody = function (id, opts = {}) {
        if (id === 'downloads' && document.getElementById('win-body-downloads')) { dlRender(); dlRefresh(); return; }
        if (id === 'sysinfo') {
            const r = baseRender(id, opts);
            getJSON('/api/sysinfo').then(s => {
                const b = document.querySelector('#win-body-sysinfo > div');
                if (!b) return;
                b.insertAdjacentHTML('beforeend', `<div style="margin-top:10px;"><strong>Computer:</strong> Debian 12 Linux (kernel ${esc(s.kernel)}), running from memory</div>
                    <div><strong>Memory:</strong> ${fmtSize(s.mem_available)} free of ${fmtSize(s.mem_total)}${s.swap_total ? ' (+ ' + fmtSize(s.swap_total) + ' compressed swap)' : ''}</div>
                    <div><strong>Storage:</strong> ${fmtSize(s.disk_free)} free of ${fmtSize(s.disk_total)}</div>
                    <div><strong>Up for:</strong> ${Math.round(s.uptime / 60)} minutes</div>`);
            }).catch(() => {});
            return r;
        }
        return baseRender(id, opts);
    };
    setInterval(() => { if (document.visibilityState === 'visible') dlRefresh(); }, 2000);
    dlRefresh();
    if (typeof initIcons === 'function') initIcons();

    /* ---------- Terminal commands ---------- */
    const baseRun = window.runCmd;
    window.runCmd = function (raw) {
        const out = document.getElementById('cmd-out');
        const words = String(raw || '').trim().split(/\s+/);
        const cmd = (words[0] || '').toLowerCase(), rest = words.slice(1).join(' ');
        const echo = () => { out.innerHTML += `<div>${esc(fmCurrentPath)}&gt; ${esc(raw)}</div>`; };
        const line = (text, color) => { const d = document.createElement('div'); d.style.whiteSpace = 'pre-wrap'; if (color) d.style.color = color; d.textContent = text; out.appendChild(d); out.scrollTop = out.scrollHeight; return d; };
        const slow = async (label, job) => { echo(); const d = line(label, '#94a3b8'); try { d.textContent = await job(); d.style.color = ''; } catch (e) { d.textContent = 'Error: ' + e.message; } out.scrollTop = out.scrollHeight; };
        switch (cmd) {
            case 'help':
                baseRun(raw);
                line('Computer: netstatus, netfix, free, crashlog, downloads, chromium <site>, shutdown, reboot, uname');
                return;
            case 'netstatus': case 'ifconfig': case 'ipconfig':
                return slow('Checking the network...', () => getText('/netstatus'));
            case 'netfix':
                return slow('Reconnecting the network (up to 1 minute)...', async () => (await post('/netfix')).text());
            case 'crashlog':
                return slow('Reading the crash log...', () => getText('/api/crashlog'));
            case 'free': case 'mem': case 'df':
                return slow('...', async () => { const s = await getJSON('/api/sysinfo'); return `Memory: ${fmtSize(s.mem_available)} free of ${fmtSize(s.mem_total)}\nSwap:   ${fmtSize(s.swap_free)} free of ${fmtSize(s.swap_total)}\nDisk:   ${fmtSize(s.disk_free)} free of ${fmtSize(s.disk_total)} (in memory)`; });
            case 'uname':
                echo(); line('Leaf OS 4.5 on Debian 12 Linux (live system)'); return;
            case 'downloads':
                echo(); openApp('downloads'); line('Opening Downloads...'); return;
            case 'chromium': case 'chrome': case 'browser':
                echo(); leafOpenReal(rest || 'https://www.google.com'); line('Opening Chromium...'); return;
            case 'shutdown': case 'poweroff':
                echo(); line('Shutting down...'); powerAction('shutdown'); return;
            case 'reboot': case 'restart':
                echo(); line('Restarting...'); powerAction('restart'); return;
        }
        return baseRun(raw);
    };

    /* ---------- notices after start-up ---------- */
    window.addEventListener('load', () => {
        getJSON('/api/crashinfo').then(c => {
            if (!c.last || Date.now() / 1000 - c.last > 180) return;
            const msg = 'Leaf OS restarted after a problem. Type crashlog in Command Prompt to see what happened.';
            setTimeout(() => { showToast(msg); try { pushNotification('Leaf OS restarted', msg); } catch (e) {} }, 5000);
        }).catch(() => {});
        setTimeout(() => {
            fetch('https://www.gstatic.com/generate_204', { mode: 'no-cors', cache: 'no-store' })
                .catch(() => showToast('No internet yet. Open Command Prompt and type netfix (or netstatus for details).'));
        }, 9000);
    });
})();
