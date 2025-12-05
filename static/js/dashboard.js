/************************************************************
 *  DASHBOARD – VERSIONE B (STABILE)
 *  - Auto-refresh via /api/dashboard-data
 *  - Storico da Redis (worker)
 *  - Tema manuale (localStorage)
 *  - Pulsanti mobile OK
 *  - Push DESKTOP integrate (SOLO DESKTOP)
 ************************************************************/

/************************************************************
 * TEMA, LOGO, ICONE
 ************************************************************/
function updateLogo() {
    const img = document.getElementById("navbar-logo");
    if (!img) return;

    const isDark = document.body.classList.contains("dark");
    img.src = isDark ? "/static/img/logoDark.png" : "/static/img/logoLight.png";
}

function updateThemeIcons() {
    const isDark = document.body.classList.contains("dark");
    const CLS_LIGHT = "bi-moon-stars";
    const CLS_DARK  = "bi-sun-fill";

    const iconDesktop = document.getElementById("theme-icon");
    const iconMobile  = document.getElementById("theme-icon-mobile");
    const label       = document.getElementById("theme-label");

    if (iconDesktop) {
        iconDesktop.classList.remove(CLS_LIGHT, CLS_DARK);
        iconDesktop.classList.add(isDark ? CLS_DARK : CLS_LIGHT);
    }

    if (iconMobile) {
        iconMobile.classList.remove(CLS_LIGHT, CLS_DARK);
        iconMobile.classList.add(isDark ? CLS_DARK : CLS_LIGHT);
    }

    if (label) {
        label.textContent = isDark ? "Scuro" : "Chiaro";
    }
}

function applyTheme(theme) {
    if (theme === "dark") document.body.classList.add("dark");
    else document.body.classList.remove("dark");

    updateLogo();
    updateThemeIcons();
}

function loadTheme() {
    const saved = localStorage.getItem("theme");
    if (saved === "dark" || saved === "light") applyTheme(saved);
    else applyTheme("light");
}

function toggleTheme() {
    const isDark = document.body.classList.contains("dark");
    const newTheme = isDark ? "light" : "dark";
    localStorage.setItem("theme", newTheme);
    applyTheme(newTheme);
}

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
    const tbody = document.getElementById("main-tbody");
    if (!tbody) return;

    tbody.querySelectorAll("tr").forEach(row => {
        if (!onlyDownActive) row.style.display = "";
        else row.style.display = row.classList.contains("row-down") ? "" : "none";
    });

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
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("width", "100%");
    svg.setAttribute("height", "20");

    history.forEach((sev, idx) => {
        const r = document.createElementNS("http://www.w3.org/2000/svg", "rect");
        r.setAttribute("x", idx * 8);
        r.setAttribute("width", 6);
        r.setAttribute("height", 20);

        r.setAttribute("fill", sev === 2 ? "red" : sev === 1 ? "yellow" : "limegreen");
        svg.appendChild(r);
    });

    return svg;
}

function renderTable(items) {
    const tbody = document.getElementById("main-tbody");
    if (!tbody) return;

    tbody.innerHTML = "";

    items.forEach(item => {
        const tr = document.createElement("tr");

        if (item.final === "DOWN") tr.classList.add("row-down");
        else if (item.k1 !== item.k2 || item.k1 !== item.k3 || item.k2 !== item.k3) tr.classList.add("row-mismatch");
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
        tr.appendChild(createStatusCell(item.final));

        const hist = document.createElement("td");
        hist.appendChild(buildHistorySvg(item.history || []));
        tr.appendChild(hist);

        tbody.appendChild(tr);
    });

    sortRowsBySeverity();
    applyOnlyDownFilter();
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
 * RENDER MOBILE
 ************************************************************/
function renderMobileCards(items) {
    const container = document.getElementById("mobile-list");
    if (!container) return;

    container.innerHTML = "";

    items.forEach(item => {
        const card = document.createElement("div");
        card.classList.add("mobile-card");

        if (item.final === "DOWN") card.classList.add("down");
        else if (item.k1 !== item.k2 || item.k1 !== item.k3 || item.k2 !== item.k3) card.classList.add("mismatch");
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
        add("Finale:", item.final);

        const l = document.createElement("div");
        l.classList.add("mobile-field", "mt-2");
        l.textContent = "Storico:";
        card.appendChild(l);

        const limitedHistory = (item.history || []).slice(-15);
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
        renderMobileCards(data.items || []);
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


window.togglePush = togglePush;

/************************************************************
 * INIT
 ************************************************************/
document.addEventListener("DOMContentLoaded", () => {
    loadTheme();
    initPushButton();

    const initial = document.body.getAttribute("data-global-state") || "GREEN";
    updateGlobalStatus(initial);
    updateMobileMenuStatus(initial);

    refreshDashboard();
    setInterval(refreshDashboard, 10000);
});