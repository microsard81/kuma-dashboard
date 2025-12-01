/************************************************************
 *  DASHBOARD – VERSIONE B (STABILE)
 *  - Auto-refresh via /api/dashboard-data
 *  - Storico da Redis (worker)
 *  - Tema manuale (localStorage)
 *  - Pulsanti mobile OK
 *  - Push desktop integrate
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
    if (theme === "dark") {
        document.body.classList.add("dark");
    } else {
        document.body.classList.remove("dark");
    }

    updateLogo();
    updateThemeIcons();
}

function loadTheme() {
    const saved = localStorage.getItem("theme");
    if (saved === "dark" || saved === "light") {
        applyTheme(saved);
    } else {
        applyTheme("light"); // default
    }
}

function toggleTheme() {
    const isDark = document.body.classList.contains("dark");
    const newTheme = isDark ? "light" : "dark";
    localStorage.setItem("theme", newTheme);
    applyTheme(newTheme);
}

/************************************************************
 * STATO GLOBALE (SEMAFORO)
 ************************************************************/

function updateGlobalStatus(state) {
    const led = document.getElementById("global-status-led");
    if (!led) return;

    led.className = "status-led";
    if (state === "RED") {
        led.classList.add("status-led-red");
    } else if (state === "YELLOW") {
        led.classList.add("status-led-yellow");
    } else {
        led.classList.add("status-led-green");
    }
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
 * FILTRO "MOSTRA SOLO DOWN"
 ************************************************************/

let onlyDownActive = false;

function applyOnlyDownFilter() {
    const tbody = document.getElementById("main-tbody");
    if (!tbody) return;

    const rows = tbody.querySelectorAll("tr");
    rows.forEach(row => {
        if (!onlyDownActive) {
            row.style.display = "";
        } else {
            row.style.display = row.classList.contains("row-down") ? "" : "none";
        }
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
 * RENDERING – TABELLA
 ************************************************************/

function createStatusCell(textStatus) {
    const td = document.createElement("td");
    const isDown = textStatus === "DOWN";

    td.classList.add(isDown ? "status-down" : "status-up");

    const icon = document.createElement("i");
    icon.classList.add("bi", "me-1");
    if (isDown) icon.classList.add("bi-x-circle-fill", "text-danger");
    else icon.classList.add("bi-check-circle-fill", "text-success");

    td.appendChild(icon);
    td.appendChild(document.createTextNode(" " + textStatus));
    return td;
}

function buildHistorySvg(history) {
    const svgNS = "http://www.w3.org/2000/svg";
    const svg = document.createElementNS(svgNS, "svg");
    svg.setAttribute("width", "100%");
    svg.setAttribute("height", "20");

    history.forEach((sev, idx) => {
        const rect = document.createElementNS(svgNS, "rect");
        rect.setAttribute("x", String(idx * 8));
        rect.setAttribute("y", "0");
        rect.setAttribute("width", "6");
        rect.setAttribute("height", "20");

        let color = "limegreen";
        if (sev === 1) color = "yellow";
        if (sev === 2) color = "red";

        rect.setAttribute("fill", color);
        svg.appendChild(rect);
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
        else if (item.k1 !== item.k2) tr.classList.add("row-mismatch");
        else tr.classList.add("row-up");

        const tdName = document.createElement("td");
        if (item.link) {
            const a = document.createElement("a");
            a.href = item.link;
            a.target = "_blank";
            a.textContent = item.name;
            a.classList.add("text-decoration-none");
            tdName.appendChild(a);
        } else tdName.textContent = item.name;

        tr.appendChild(tdName);
        tr.appendChild(createStatusCell(item.k1));
        tr.appendChild(createStatusCell(item.k2));
        tr.appendChild(createStatusCell(item.final));

        const tdHist = document.createElement("td");
        tdHist.appendChild(buildHistorySvg(item.history || []));
        tr.appendChild(tdHist);

        tbody.appendChild(tr);
    });

    sortRowsBySeverity();
    applyOnlyDownFilter();
}

function sortRowsBySeverity() {
    const tbody = document.getElementById("main-tbody");
    if (!tbody) return;

    const rows = Array.from(tbody.querySelectorAll("tr"));
    const order = { "row-down": 0, "row-mismatch": 1, "row-up": 2 };

    rows.sort((a, b) => {
        const aClass =
            a.classList.contains("row-down") ? "row-down" :
            a.classList.contains("row-mismatch") ? "row-mismatch" :
            "row-up";

        const bClass =
            b.classList.contains("row-down") ? "row-down" :
            b.classList.contains("row-mismatch") ? "row-mismatch" :
            "row-up";

        return order[aClass] - order[bClass];
    });

    rows.forEach(r => tbody.appendChild(r));
}

/************************************************************
 * RENDERING – MOBILE CARDS
 ************************************************************/

function renderMobileCards(items) {
    const container = document.getElementById("mobile-list");
    if (!container) return;

    container.innerHTML = "";

    items.forEach(item => {
        const card = document.createElement("div");
        card.classList.add("mobile-card");

        if (item.final === "DOWN") card.classList.add("down");
        else if (item.k1 !== item.k2) card.classList.add("mismatch");
        else card.classList.add("up");

        const title = document.createElement("div");
        title.classList.add("mobile-title");
        title.textContent = item.name;
        card.appendChild(title);

        function addRow(label, status) {
            const field = document.createElement("div");
            field.classList.add("mobile-field");
            field.textContent = label;
            card.appendChild(field);

            const val = document.createElement("div");
            val.classList.add("mobile-value");

            const icon = document.createElement("i");
            icon.classList.add("bi", "me-1");
            if (status === "DOWN") icon.classList.add("bi-x-circle-fill", "text-danger");
            else icon.classList.add("bi-check-circle-fill", "text-success");

            val.appendChild(icon);
            val.appendChild(document.createTextNode(" " + status));
            card.appendChild(val);
        }

        addRow("Aruba Bergamo:", item.k1);
        addRow("TIM Sestu:", item.k2);
        addRow("Finale:", item.final);

        const label = document.createElement("div");
        label.classList.add("mobile-field", "mt-2");
        label.textContent = "Storico:";
        card.appendChild(label);

        card.appendChild(buildHistorySvg(item.history || []));

        container.appendChild(card);
    });
}

/************************************************************
 * AUTO REFRESH
 ************************************************************/

async function refreshDashboard() {
    try {
        const resp = await fetch("/api/dashboard-data", { cache: "no-store" });
        if (!resp.ok) return;

        const data = await resp.json();
        const items = data.items || [];
        const globalState = data.global_state || "GREEN";

        renderTable(items);
        renderMobileCards(items);
        updateDownCountFromItems(items);
        updateGlobalStatus(globalState);
        updateMobileMenuStatus(globalState);
    } catch (e) {
        console.error("Errore auto-refresh:", e);
    }
}

/************************************************************
 * PUSH DESKTOP
 ************************************************************/

function updatePushButton(isEnabled) {
    const icon = document.getElementById("push-icon");
    if (!icon) return;

    icon.classList.remove("bi-bell", "bi-bell-fill", "text-success");

    if (isEnabled) {
        icon.classList.add("bi-bell-fill", "text-success");
    } else {
        icon.classList.add("bi-bell");
    }
}

async function getSubscription() {
    const reg = await navigator.serviceWorker.getRegistration("/sw.js");
    if (!reg) return null;

    return await reg.pushManager.getSubscription();
}

async function subscribeDesktop() {
    const permission = await Notification.requestPermission();
    if (permission !== "granted") {
        alert("Le notifiche sono disattivate dal browser.");
        return;
    }

    const reg = await navigator.serviceWorker.getRegistration("/sw.js");
    if (!reg) {
        alert("Service Worker non disponibile.");
        return;
    }

    // Crea SUB
    const key = VAPID_PUBLIC_KEY;
    const toUint8 = (base64) => {
        const padding = "=".repeat((4 - base64.length % 4) % 4);
        const safe = (base64 + padding).replace(/-/g, "+").replace(/_/g, "/");
        const raw = atob(safe);
        return Uint8Array.from([...raw].map(c => c.charCodeAt(0)));
    };

    const sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: toUint8(key),
    });

    // Invia al backend
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

    // Cancella lato browser
    await sub.unsubscribe();

    // Cancella lato server
    await fetch("/push/unsubscribe", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ endpoint: sub.endpoint }),
    });

    updatePushButton(false);
}

async function togglePush() {
    const sub = await getSubscription();
    if (sub) {
        await unsubscribeDesktop();
    } else {
        await subscribeDesktop();
    }
}

async function initPushButton() {
    const sub = await getSubscription();
    updatePushButton(!!sub);
}

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