/************************************************************
 *  DASHBOARD – VERSIONE B (STABILE)
 *  - Auto-refresh via /api/dashboard-data
 *  - Storico da Redis (worker)
 *  - Tema manuale (localStorage)
 *  - Pulsanti mobile OK
 *  - Push DESKTOP integrate (SOLO DESKTOP)
 ************************************************************/

/************************************************************
 * TEMA, LOGO, ICONE — auto / light / dark
 ************************************************************/
const _darkMQ = window.matchMedia("(prefers-color-scheme: dark)");

function _systemPrefersDark() {
    return _darkMQ.matches;
}

function _resolveTheme(mode) {
    if (mode === "dark") return "dark";
    if (mode === "light") return "light";
    return _systemPrefersDark() ? "dark" : "light";
}

function updateLogo() {
    const img = document.getElementById("navbar-logo");
    if (!img) return;
    const isDark = document.body.classList.contains("dark");
    img.src = isDark ? "/static/img/logoDark.png" : "/static/img/logoLight.png";
}

function updateThemeIcons() {
    const mode = localStorage.getItem("theme") || "auto";
    const icons = { auto: "bi-circle-half", light: "bi-sun-fill", dark: "bi-moon-stars-fill" };
    const labels = { auto: "Auto", light: "Chiaro", dark: "Scuro" };
    const cls = icons[mode] || "bi-circle-half";

    ["theme-icon", "theme-icon-mobile"].forEach(id => {
        const el = document.getElementById(id);
        if (!el) return;
        el.classList.remove("bi-circle-half", "bi-sun-fill", "bi-moon-stars-fill", "bi-moon-stars");
        el.classList.add(cls);
    });

    const label = document.getElementById("theme-label");
    if (label) label.textContent = labels[mode] || "Auto";
}

function applyTheme(mode) {
    const resolved = _resolveTheme(mode);
    if (resolved === "dark") document.body.classList.add("dark");
    else document.body.classList.remove("dark");
    updateLogo();
    updateThemeIcons();
}

function loadTheme() {
    const saved = localStorage.getItem("theme") || "auto";
    applyTheme(saved);
}

function toggleTheme() {
    const cycle = { auto: "light", light: "dark", dark: "auto" };
    const current = localStorage.getItem("theme") || "auto";
    const next = cycle[current] || "auto";
    localStorage.setItem("theme", next);
    applyTheme(next);
}

// Aggiorna in tempo reale quando il SO cambia tema (solo in modalità auto)
_darkMQ.addEventListener("change", () => {
    const mode = localStorage.getItem("theme") || "auto";
    if (mode === "auto") applyTheme("auto");
});

/************************************************************
 * STATO GLOBALE
 ************************************************************/
function updateGlobalStatus(state) {
    const led = document.getElementById("global-status-led");
    if (!led) return;

    led.className = "status-led";
    if (state === "RED") led.classList.add("status-led-red");
    else if (state === "YELLOW") led.classList.add("status-led-yellow");
    else led.classList.add("status-led-green");
}

function updateMobileMenuStatus(state) {
    const led  = document.getElementById("mobile-status-led");
    const text = document.getElementById("mobile-status-text");
    if (!led || !text) return;

    led.className = "status-led";

    if (state === "RED") {
        led.classList.add("status-led-red");
        text.textContent = "DOWN";
    } else if (state === "YELLOW") {
        led.classList.add("status-led-yellow");
        text.textContent = "PARZIALE";
    } else {
        led.classList.add("status-led-green");
        text.textContent = "OK";
    }
}

/************************************************************
 * FILTRO DOWN
 ************************************************************/
let onlyDownActive = false;

function applyOnlyDownFilter() {
    // Tabella nascosta (fallback)
    const tbody = document.getElementById("main-tbody");
    if (tbody) {
        tbody.querySelectorAll("tr").forEach(row => {
            if (!onlyDownActive) row.style.display = "";
            else row.style.display = (row.classList.contains("row-down") || row.classList.contains("row-mismatch")) ? "" : "none";
        });
    }

    // Desktop cards
    const desktopCards = document.getElementById("desktop-cards");
    if (desktopCards) {
        desktopCards.querySelectorAll(".dcard").forEach(card => {
            if (!onlyDownActive) card.style.display = "";
            else card.style.display = (card.classList.contains("dcard-down") || card.classList.contains("dcard-mismatch")) ? "" : "none";
        });
    }

    // Mobile cards
    const mobileList = document.getElementById("mobile-list");
    if (mobileList) {
        mobileList.querySelectorAll(".mobile-card").forEach(card => {
            if (!onlyDownActive) card.style.display = "";
            else card.style.display = (card.classList.contains("down") || card.classList.contains("mismatch")) ? "" : "none";
        });
    }

    const btn = document.getElementById("filter-btn");
    if (btn) {
        btn.setAttribute("data-active", onlyDownActive ? "1" : "0");
        btn.textContent = onlyDownActive ? "Mostra tutti" : "Mostra solo DOWN";
    }
}

function toggleOnlyDown() {
    onlyDownActive = !onlyDownActive;
    applyOnlyDownFilter();
}

/************************************************************
 * CONTEGGIO DOWN
 ************************************************************/
function updateDownCountFromItems(items) {
    const badge = document.getElementById("down-count-badge");
    if (!badge) return;
    badge.textContent = items.filter(i => i.final === "DOWN").length;
}

/************************************************************
 * RENDER TABELLA
 ************************************************************/
function createStatusCell(status) {
    const td = document.createElement("td");
    td.classList.add(status === "DOWN" ? "status-down" : "status-up");

    const icon = document.createElement("i");
    icon.classList.add("bi", "me-1");
    icon.classList.add(status === "DOWN" ? "bi-x-circle-fill" : "bi-check-circle-fill");
    icon.classList.add(status === "DOWN" ? "text-danger" : "text-success");

    td.appendChild(icon);
    td.appendChild(document.createTextNode(" " + status));

    return td;
}

function buildHistorySvg(history) {
    const BAR_H = 18;
    const RADIUS = 1.5;

    const wrapper = document.createElement("div");
    wrapper.classList.add("history-container");

    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("width", "100%");
    svg.setAttribute("height", BAR_H);
    svg.setAttribute("preserveAspectRatio", "none");
    svg.style.display = "block";

    const colors = { 0: "#34d399", 1: "#FFEE00", 2: "#f87171" };
    const labels = { 0: "UP", 1: "Mismatch", 2: "DOWN" };
    const interval = 60;
    const n = history.length || 1;

    // Calcola dimensioni proporzionali: 75% barra, 25% gap
    const cellFraction = 100 / n;
    const barPct = cellFraction * 0.75;
    const gapPct = cellFraction * 0.25;

    history.forEach((point, idx) => {
        // Retrocompatibile: supporta sia intero (vecchio) che oggetto (nuovo)
        const sev = typeof point === "object" ? point.s : point;
        const xPct = idx * cellFraction + gapPct / 2;

        const r = document.createElementNS("http://www.w3.org/2000/svg", "rect");
        r.setAttribute("x", xPct + "%");
        r.setAttribute("y", 0);
        r.setAttribute("width", barPct + "%");
        r.setAttribute("height", BAR_H);
        r.setAttribute("rx", RADIUS);
        r.setAttribute("ry", RADIUS);
        r.setAttribute("fill", colors[sev] || "#94a3b8");
        r.style.transition = "opacity 0.15s";
        r.style.cursor = "default";

        // Tooltip con data e ora
        const secsAgo = (history.length - 1 - idx) * interval;
        const pointDate = new Date(Date.now() - secsAgo * 1000);
        const dateStr = pointDate.toLocaleDateString("it-IT", { day: "2-digit", month: "2-digit", year: "numeric" });
        const timeStr = pointDate.toLocaleTimeString("it-IT", { hour: "2-digit", minute: "2-digit", second: "2-digit" });

        const title = document.createElementNS("http://www.w3.org/2000/svg", "title");
        let tooltipText = labels[sev] + " — " + dateStr + " " + timeStr;
        // Se mismatch e abbiamo dati per-sonda, mostra quali sono DOWN
        if (sev === 1 && typeof point === "object" && point.k1 != null) {
            const probeNames = { k1: "Aruba", k2: "TIM", k3: "ILIAD", n1: "NodePing" };
            const down = ["k1","k2","k3","n1"].filter(k => point[k] === 0).map(k => probeNames[k]);
            if (down.length > 0) tooltipText += " (DOWN: " + down.join(", ") + ")";
        }
        title.textContent = tooltipText;
        r.appendChild(title);

        r.addEventListener("mouseenter", () => { r.style.opacity = "0.7"; });
        r.addEventListener("mouseleave", () => { r.style.opacity = "1"; });

        svg.appendChild(r);
    });

    wrapper.appendChild(svg);
    return wrapper;
}

function renderTable(items) {
    const tbody = document.getElementById("main-tbody");
    if (!tbody) return;

    tbody.innerHTML = "";

    items.forEach(item => {
        const tr = document.createElement("tr");
        const CHECK_KEYS = ["k1", "k2", "k3", "n1"];
        const states = new Set(CHECK_KEYS.map(k => item[k]));

        if (item.final === "DOWN") tr.classList.add("row-down");
        else if (states.size > 1) tr.classList.add("row-mismatch");
        else tr.classList.add("row-up");

        const tdName = document.createElement("td");
        if (item.link) {
            const a = document.createElement("a");
            a.href = item.link;
            a.textContent = item.name;
            a.target = "_blank";
            a.classList.add("text-decoration-none");
            tdName.appendChild(a);
        } else {
            tdName.textContent = item.name;
        }

        tr.appendChild(tdName);
        tr.appendChild(createStatusCell(item.k1));
        tr.appendChild(createStatusCell(item.k2));
        tr.appendChild(createStatusCell(item.k3));
        tr.appendChild(createStatusCell(item.n1));
        tr.appendChild(createStatusCell(item.final));

        const hist = document.createElement("td");
        hist.appendChild(buildHistorySvg((item.history || []).slice(-60)));
        tr.appendChild(hist);

        tbody.appendChild(tr);
    });

    sortRowsBySeverity();
}

function sortRowsBySeverity() {
    const tbody = document.getElementById("main-tbody");
    if (!tbody) return;

    const order = { "row-down": 0, "row-mismatch": 1, "row-up": 2 };

    Array.from(tbody.querySelectorAll("tr"))
        .sort((a, b) => {
            const ac = a.classList.contains("row-down") ? "row-down" :
                       a.classList.contains("row-mismatch") ? "row-mismatch" : "row-up";
            const bc = b.classList.contains("row-down") ? "row-down" :
                       b.classList.contains("row-mismatch") ? "row-mismatch" : "row-up";
            return order[ac] - order[bc];
        })
        .forEach(r => tbody.appendChild(r));
}

/************************************************************
 * RENDER DESKTOP CARDS
 ************************************************************/
function renderDesktopCards(items) {
    const container = document.getElementById("desktop-cards");
    if (!container) return;

    container.innerHTML = "";

    const grid = document.createElement("div");
    grid.classList.add("desktop-card-grid");

    // Ordina: DOWN prima, poi mismatch, poi UP
    const sorted = [...items].sort((a, b) => {
        const sev = s => s.final === "DOWN" ? 0 : new Set(["k1","k2","k3","n1"].map(k => s[k])).size > 1 ? 1 : 2;
        return sev(a) - sev(b);
    });

    sorted.forEach(item => {
        const CHECK_KEYS = ["k1", "k2", "k3", "n1"];
        const states = new Set(CHECK_KEYS.map(k => item[k]));
        let severity = "up";
        if (item.final === "DOWN") severity = "down";
        else if (states.size > 1) severity = "mismatch";

        const card = document.createElement("div");
        card.classList.add("dcard", "dcard-" + severity);

        // Header: nome + stato finale
        const header = document.createElement("div");
        header.classList.add("dcard-header");

        const name = document.createElement("div");
        name.classList.add("dcard-name");
        if (item.link) {
            const a = document.createElement("a");
            a.href = item.link;
            a.target = "_blank";
            a.textContent = item.name;
            name.appendChild(a);
        } else {
            name.textContent = item.name;
        }

        const badge = document.createElement("span");
        badge.classList.add("dcard-badge", "dcard-badge-" + severity);
        badge.textContent = item.final;

        header.appendChild(name);
        header.appendChild(badge);
        card.appendChild(header);

        // Sonde
        const probes = document.createElement("div");
        probes.classList.add("dcard-probes");

        const probeLabels = { k1: "Aruba Bergamo", k2: "TIM Sestu", k3: "ILIAD Sinnai", n1: "NodePing Europe" };
        CHECK_KEYS.forEach(k => {
            const p = document.createElement("span");
            p.classList.add("dcard-probe", item[k] === "DOWN" ? "dcard-probe-down" : "dcard-probe-up");
            p.textContent = probeLabels[k];
            p.title = (k === "k1" ? "Aruba Bergamo" : k === "k2" ? "TIM Sestu" : k === "k3" ? "ILIAD Sinnai" : "NodePing Europe") + ": " + item[k];
            probes.appendChild(p);
        });

        card.appendChild(probes);

        // Storico
        const hist = document.createElement("div");
        hist.classList.add("dcard-history");
        hist.appendChild(buildHistorySvg((item.history || []).slice(-60)));
        card.appendChild(hist);

        grid.appendChild(card);
    });

    container.appendChild(grid);
}

/************************************************************
 * RENDER MOBILE
 ************************************************************/
function renderMobileCards(items) {
    const container = document.getElementById("mobile-list");
    if (!container) return;

    container.innerHTML = "";

    items.forEach(item => {
        const card = document.createElement("div");
        card.classList.add("mobile-card");

        const CHECK_KEYS = ["k1", "k2", "k3", "n1"];
        const states = new Set(CHECK_KEYS.map(k => item[k]));

        if (item.final === "DOWN") card.classList.add("down");
        else if (states.size > 1) card.classList.add("mismatch");
        else card.classList.add("up");

        const title = document.createElement("div");
        title.classList.add("mobile-title");
        title.textContent = item.name;
        card.appendChild(title);

        function add(label, status) {
            const field = document.createElement("div");
            field.classList.add("mobile-field");
            field.textContent = label;
            card.appendChild(field);

            const val = document.createElement("div");
            val.classList.add("mobile-value");

            const icon = document.createElement("i");
            icon.classList.add("bi", "me-1");
            icon.classList.add(status === "DOWN" ? "bi-x-circle-fill" : "bi-check-circle-fill");
            icon.classList.add(status === "DOWN" ? "text-danger" : "text-success");

            val.appendChild(icon);
            val.appendChild(document.createTextNode(" " + status));
            card.appendChild(val);
        }

        add("Aruba Bergamo:", item.k1);
        add("TIM Sestu:", item.k2);
        add("ILIAD Sinnai:", item.k3);
        add("NodePing Europe:", item.n1);
        add("Finale:", item.final);

        const l = document.createElement("div");
        l.classList.add("mobile-field", "mt-2");
        l.textContent = "Storico:";
        card.appendChild(l);

        const limitedHistory = (item.history || []).slice(-60);
        card.appendChild(buildHistorySvg(limitedHistory));
        container.appendChild(card);
    });
}

/************************************************************
 * AUTO REFRESH
 ************************************************************/
async function refreshDashboard() {
    try {
        const res = await fetch("/api/dashboard-data", { cache: "no-store" });
        if (!res.ok) return;

        const data = await res.json();
        renderTable(data.items || []);
        renderDesktopCards(data.items || []);
        renderMobileCards(data.items || []);
        applyOnlyDownFilter();
        updateDownCountFromItems(data.items || []);
        updateGlobalStatus(data.global_state || "GREEN");
        updateMobileMenuStatus(data.global_state || "GREEN");

    } catch (e) {
        console.error("Errore auto-refresh:", e);
    }
}

/************************************************************
 * PUSH DESKTOP (UNICA VERSIONE)
 ************************************************************/
function updatePushButton(enabled) {
    const icon = document.getElementById("push-icon");
    if (!icon) return;

    icon.classList.remove("bi-bell", "bi-bell-fill", "text-success");

    if (enabled) icon.classList.add("bi-bell-fill", "text-success");
    else icon.classList.add("bi-bell");
}

async function getSubscription() {
    const reg = await navigator.serviceWorker.getRegistration("/sw.js");
    if (!reg) return null;
    return await reg.pushManager.getSubscription();
}

async function subscribeDesktop() {
    const perm = await Notification.requestPermission();
    if (perm !== "granted") {
        alert("Notifiche disattivate dal browser.");
        return;
    }

    const reg = await navigator.serviceWorker.getRegistration("/sw.js");
    if (!reg) {
        alert("Service Worker non disponibile.");
        return;
    }

    const toUint8 = (b64) => {
        const pad = "=".repeat((4 - b64.length % 4) % 4);
        const safe = (b64 + pad).replace(/-/g, "+").replace(/_/g, "/");
        return Uint8Array.from(atob(safe), c => c.charCodeAt(0));
    };

    const sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: toUint8(VAPID_PUBLIC_KEY),
    });

    await fetch("/push/subscribe", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(sub),
    });

    updatePushButton(true);
}

async function unsubscribeDesktop() {
    const sub = await getSubscription();
    if (!sub) return;

    await sub.unsubscribe();

    await fetch("/push/unsubscribe", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ endpoint: sub.endpoint }),
    });

    updatePushButton(false);
}

async function togglePush() {
    const sub = await getSubscription();
    if (sub) await unsubscribeDesktop();
    else await subscribeDesktop();
}

async function initPushButton() {
    const sub = await getSubscription();
    updatePushButton(!!sub);
}

async function enablePush() {
    await subscribeDesktop();
}

window.togglePush = togglePush;
window.enablePush = enablePush;

/************************************************************
 * INIT
 ************************************************************/
document.addEventListener("DOMContentLoaded", () => {
    loadTheme();

    // Registrazione Service Worker
    if ("serviceWorker" in navigator) {
        navigator.serviceWorker.register("/sw.js")
            .then(reg => console.log("SW registrato:", reg))
            .catch(err => console.error("SW error:", err));
    }

    initPushButton();

    const initial = document.body.getAttribute("data-global-state") || "GREEN";
    updateGlobalStatus(initial);
    updateMobileMenuStatus(initial);

    refreshDashboard();
    setInterval(refreshDashboard, 10000);
});