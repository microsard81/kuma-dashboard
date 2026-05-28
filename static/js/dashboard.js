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
        const timeStr = pointDate.toLocaleTimeString("it-IT", { hour: "2-digit", minute: "2-digit" });

        const title = document.createElementNS("http://www.w3.org/2000/svg", "title");
        let tooltipText = labels[sev] + " — " + dateStr + " " + timeStr;
        // Se mismatch e abbiamo dati per-sonda, mostra quali sono DOWN
        if (sev === 1 && typeof point === "object" && point.k1 != null) {
            const probeNames = { k1: "Aruba", k2: "TIM", k3: "ILIAD", n1: "NodePing", u1: "Uptime" };
            const down = ["k1","k2","k3","n1","u1"].filter(k => point[k] === 0).map(k => probeNames[k]);
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
        const CHECK_KEYS = ["k1", "k2", "k3", "n1", "u1"];
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
        tr.appendChild(createStatusCell(item.u1));
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
        const sev = s => s.final === "DOWN" ? 0 : new Set(["k1","k2","k3","n1","u1"].map(k => s[k])).size > 1 ? 1 : 2;
        return sev(a) - sev(b);
    });

    sorted.forEach(item => {
        const CHECK_KEYS = ["k1", "k2", "k3", "n1", "u1"];
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

        const probeLabels = { k1: "Aruba Bergamo", k2: "TIM Sestu", k3: "ILIAD Sinnai", n1: "NodePing Europe", u1: "Uptime" };
        CHECK_KEYS.forEach(k => {
            const p = document.createElement("span");
            p.classList.add("dcard-probe", item[k] === "DOWN" ? "dcard-probe-down" : "dcard-probe-up");
            p.textContent = probeLabels[k];
            p.title = probeLabels[k] + ": " + item[k];
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

        const CHECK_KEYS = ["k1", "k2", "k3", "n1", "u1"];
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
        add("Uptime:", item.u1);
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
 * INVERTER SENSOR SECTION
 ************************************************************/
const INVERTER_MAX_HISTORY = 60;
const INVERTER_STALE_THRESHOLD_MS = 5 * 60 * 1000; // 5 minuti

// Cache istanze Chart.js (chiave = sensor id)
const sparklineCharts = {};

function categoriseSensors(sensors) {
    return {
        temperature: sensors.filter(s => s.category === "temperature"),
        power: sensors.filter(s => s.category === "power"),
    };
}

function _sortByUserOrder(sensors, storageKey) {
    const saved = localStorage.getItem(storageKey);
    if (!saved) return sensors;
    try {
        const order = JSON.parse(saved);
        return [...sensors].sort((a, b) => {
            const ia = order.indexOf(a.id);
            const ib = order.indexOf(b.id);
            // Non trovati vanno in fondo
            const pa = ia === -1 ? 9999 : ia;
            const pb = ib === -1 ? 9999 : ib;
            return pa - pb;
        });
    } catch (e) {
        return sensors;
    }
}

function _saveUserOrder(containerId, storageKey) {
    const container = document.getElementById(containerId);
    if (!container) return;
    const ids = Array.from(container.querySelectorAll(".inverter-card"))
        .map(card => card.dataset.sensorId);
    localStorage.setItem(storageKey, JSON.stringify(ids));
}

// Stato drag & drop (lockato di default)
let inverterReorderEnabled = false;

function toggleInverterReorder() {
    inverterReorderEnabled = !inverterReorderEnabled;
    const btn = document.getElementById("inverter-reorder-btn");
    if (btn) {
        if (inverterReorderEnabled) {
            btn.classList.add("active");
            btn.innerHTML = '<i class="bi bi-lock"></i>';
            btn.title = "Blocca posizione";
        } else {
            btn.classList.remove("active");
            btn.innerHTML = '<i class="bi bi-arrows-move"></i>';
            btn.title = "Riordina sensori";
        }
    }
    // Aggiorna draggable su tutte le card
    document.querySelectorAll(".inverter-card").forEach(card => {
        card.draggable = inverterReorderEnabled;
        card.style.cursor = inverterReorderEnabled ? "grab" : "default";
    });
}

window.toggleInverterReorder = toggleInverterReorder;

function isSensorStale(sensorTimestamp, responseTimestamp) {
    if (!sensorTimestamp || !responseTimestamp) return false;
    const sensorTime = new Date(sensorTimestamp).getTime();
    const responseTime = new Date(responseTimestamp).getTime();
    return (responseTime - sensorTime) > INVERTER_STALE_THRESHOLD_MS;
}

function getSparklineData(history, sensorId) {
    const entries = (history[sensorId] || []).slice(-INVERTER_MAX_HISTORY);
    return entries;
}

function renderInverterCards(data) {
    const { temperature, power } = categoriseSensors(data.sensors || []);
    const history = data.history || {};
    const responseTs = data.timestamp;
    const thresholds = data.thresholds || {};

    const sortedTemp = _sortByUserOrder(temperature, "inverter_temp_order");
    const sortedPower = _sortByUserOrder(power, "inverter_power_order");

    _renderCardGroup("inverter-temp-grid", sortedTemp, history, responseTs, "bi-thermometer-half", thresholds.temperature, "inverter_temp_order");
    _renderCardGroup("inverter-power-grid", sortedPower, history, responseTs, "bi-lightning-charge", thresholds.power, "inverter_power_order");
}

function _renderCardGroup(containerId, sensors, history, responseTs, iconClass, thresholds, orderKey) {
    const container = document.getElementById(containerId);
    if (!container) return;

    // Distruggi chart esistenti per questo container
    container.querySelectorAll("canvas").forEach(c => {
        if (sparklineCharts[c.id]) {
            sparklineCharts[c.id].destroy();
            delete sparklineCharts[c.id];
        }
    });

    container.innerHTML = "";

    const category = iconClass === "bi-thermometer-half" ? "temperature" : "power";

    sensors.forEach(sensor => {
        const card = document.createElement("div");
        card.classList.add("inverter-card");
        card.dataset.sensorId = sensor.id;
        card.draggable = inverterReorderEnabled;
        card.style.cursor = inverterReorderEnabled ? "grab" : "default";

        // Colore card in base a categoria e stato soglia
        const badgeState = _getBadgeState(sensor.value, category, thresholds);
        if (badgeState === "critical") {
            card.classList.add("inverter-card-critical");
        } else if (badgeState === "warning") {
            card.classList.add("inverter-card-warning");
        } else if (category === "power") {
            card.classList.add("inverter-card-power");
        } else {
            card.classList.add("inverter-card-temp");
        }

        // Drag & drop (attivo solo quando sbloccato)
        card.addEventListener("dragstart", (e) => {
            if (!inverterReorderEnabled) { e.preventDefault(); return; }
            e.dataTransfer.setData("text/plain", sensor.id);
            card.classList.add("dragging");
        });
        card.addEventListener("dragend", () => {
            card.classList.remove("dragging");
            _saveUserOrder(containerId, orderKey);
        });
        card.addEventListener("dragover", (e) => {
            if (!inverterReorderEnabled) return;
            e.preventDefault();
            const dragging = container.querySelector(".dragging");
            if (dragging && dragging !== card) {
                const rect = card.getBoundingClientRect();
                const midX = rect.left + rect.width / 2;
                if (e.clientX < midX) {
                    container.insertBefore(dragging, card);
                } else {
                    container.insertBefore(dragging, card.nextSibling);
                }
            }
        });

        // Header
        const header = document.createElement("div");
        header.classList.add("inverter-card-header");

        const nameEl = document.createElement("span");
        nameEl.classList.add("inverter-card-name");
        nameEl.innerHTML = `<i class="bi ${iconClass} me-1"></i>${sensor.name}`;

        const badge = document.createElement("span");
        badge.classList.add("inverter-card-badge");

        // Stato badge già calcolato sopra per il colore card
        if (badgeState === "critical") {
            badge.classList.add("critical");
        } else if (badgeState === "warning") {
            badge.classList.add("warning");
        }
        // Stale ha priorità visiva solo se non c'è critical/warning
        if (isSensorStale(sensor.timestamp, responseTs) && badgeState === "normal") {
            badge.classList.add("stale");
        }

        badge.textContent = sensor.value != null ? sensor.value + " " + (sensor.unit || "") : "—";

        header.appendChild(nameEl);
        header.appendChild(badge);
        card.appendChild(header);

        // Sparkline
        const sparkDiv = document.createElement("div");
        sparkDiv.classList.add("inverter-card-sparkline");
        const canvas = document.createElement("canvas");
        const canvasId = "spark-" + sensor.id.replace(/[^a-zA-Z0-9]/g, "_");
        canvas.id = canvasId;
        canvas.width = 200;
        canvas.height = 40;
        sparkDiv.appendChild(canvas);
        card.appendChild(sparkDiv);

        container.appendChild(card);

        // Render sparkline chart dopo che il canvas è nel DOM
        const entries = getSparklineData(history, sensor.id);
        if (entries.length > 0) {
            requestAnimationFrame(() => {
                createOrUpdateSparkline(canvasId, entries, category);
            });
        }
    });
}

function _getBadgeState(value, category, thresholds) {
    if (value == null || !thresholds) return "normal";
    if (category === "temperature") {
        // Temperatura: warning/critical se MAGGIORE DI
        if (value > thresholds.critical) return "critical";
        if (value > thresholds.warning) return "warning";
    } else {
        // Potenza: warning/critical se MINORE DI
        if (value < thresholds.critical) return "critical";
        if (value < thresholds.warning) return "warning";
    }
    return "normal";
}

function createOrUpdateSparkline(canvasId, entries, category) {
    const canvas = document.getElementById(canvasId);
    if (!canvas) return;

    const values = entries.map(e => e.v);
    const labels = entries.map(e => {
        if (!e.t) return "";
        const d = new Date(e.t);
        return d.getHours().toString().padStart(2, "0") + ":" + d.getMinutes().toString().padStart(2, "0");
    });

    // Scale Y fisse per categoria
    const yMin = category === "power" ? 1 : 10;
    const yMax = category === "power" ? 100 : 65;

    // Se esiste già un chart, aggiorna i dati
    if (sparklineCharts[canvasId]) {
        sparklineCharts[canvasId].data.labels = labels;
        sparklineCharts[canvasId].data.datasets[0].data = values;
        sparklineCharts[canvasId].options.scales.y.min = yMin;
        sparklineCharts[canvasId].options.scales.y.max = yMax;
        sparklineCharts[canvasId].update("none");
        return;
    }

    // Crea nuovo chart
    try {
        sparklineCharts[canvasId] = new Chart(canvas, {
            type: "line",
            data: {
                labels: labels,
                datasets: [{
                    data: values,
                    borderColor: "#5eead4",
                    borderWidth: 1.5,
                    fill: true,
                    backgroundColor: "rgba(94, 234, 212, 0.1)",
                    pointRadius: 0,
                    tension: 0.3,
                }],
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false },
                    tooltip: {
                        enabled: true,
                        mode: "index",
                        intersect: false,
                        callbacks: {
                            title: function(ctx) { return ctx[0].label || ""; },
                            label: function(ctx) { return ctx.parsed.y.toFixed(1); },
                        },
                    },
                },
                scales: {
                    x: { display: false },
                    y: { display: false, min: yMin, max: yMax },
                },
                animation: false,
            },
        });
    } catch (e) {
        console.error("Errore creazione sparkline:", e);
    }
}

function updateInverterTimestamp(ts) {
    const el = document.getElementById("inverter-timestamp");
    if (!el) return;
    el.textContent = ts ? "Ultimo aggiornamento: " + ts : "";
}

function showInverterError(msg) {
    const el = document.getElementById("inverter-error");
    if (!el) return;
    el.innerHTML = '<i class="bi bi-exclamation-triangle me-2"></i>' + msg;
    el.classList.remove("d-none");
}

function clearInverterError() {
    const el = document.getElementById("inverter-error");
    if (!el) return;
    el.classList.add("d-none");
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

    // Inverter data refresh (indipendente — errore non blocca dashboard)
    try {
        const res = await fetch("/api/inverter-data", { cache: "no-store" });
        if (!res.ok) {
            showInverterError("Errore nel caricamento dati sensori");
            return;
        }
        const data = await res.json();
        if (data.error) {
            showInverterError(data.error);
        } else {
            clearInverterError();
            renderInverterCards(data);
            updateInverterTimestamp(data.timestamp);
        }
    } catch (e) {
        console.error("Errore auto-refresh inverter:", e);
        showInverterError("Errore di rete");
    }
}

/************************************************************
 * PUSH DESKTOP (UNICA VERSIONE)
 ************************************************************/
function updatePushUI(enabled) {
    // Icona navbar
    const icon = document.getElementById("push-icon");
    if (icon) {
        icon.classList.remove("bi-bell", "bi-bell-fill", "text-success");
        if (enabled) icon.classList.add("bi-bell-fill", "text-success");
        else icon.classList.add("bi-bell");
    }

    // Desktop popover
    const badge = document.getElementById("push-status-badge");
    const btn = document.getElementById("push-toggle-btn");
    const thresholdSection = document.getElementById("threshold-section");
    if (badge) {
        badge.textContent = enabled ? "ON" : "OFF";
        badge.className = "badge " + (enabled ? "bg-success" : "bg-secondary");
    }
    if (btn) btn.textContent = enabled ? "Disabilita" : "Abilita";
    if (thresholdSection) thresholdSection.style.display = enabled ? "" : "none";

    // Mobile
    const badgeMobile = document.getElementById("push-status-badge-mobile");
    const btnMobile = document.getElementById("push-toggle-btn-mobile");
    const mobileWrapper = document.getElementById("threshold-mobile-wrapper");
    if (badgeMobile) {
        badgeMobile.textContent = enabled ? "ON" : "OFF";
        badgeMobile.className = "badge " + (enabled ? "bg-success" : "bg-secondary");
    }
    if (btnMobile) btnMobile.textContent = enabled ? "Disabilita" : "Abilita";
    if (mobileWrapper) mobileWrapper.style.display = enabled ? "" : "none";
}

// Alias per retrocompatibilità interna
function updatePushButton(enabled) {
    updatePushUI(enabled);
}

async function getSubscription() {
    const reg = await navigator.serviceWorker.getRegistration("/sw.js");
    if (!reg) return null;
    return await reg.pushManager.getSubscription();
}

async function subscribeDesktop() {
    // IMPORTANTE: requestPermission DEVE essere la prima chiamata async
    // dopo il gesto utente, altrimenti iOS Safari la blocca.
    const perm = await Notification.requestPermission();
    if (perm !== "granted") {
        alert("Notifiche disattivate dal browser.");
        return;
    }

    const reg = await navigator.serviceWorker.getRegistration("/sw.js");
    if (!reg) {
        // Prova a registrare il SW se non è ancora pronto
        try {
            await navigator.serviceWorker.register("/sw.js");
            await navigator.serviceWorker.ready;
        } catch (e) {
            alert("Service Worker non disponibile.");
            return;
        }
    }

    const swReg = await navigator.serviceWorker.ready;

    const toUint8 = (b64) => {
        const pad = "=".repeat((4 - b64.length % 4) % 4);
        const safe = (b64 + pad).replace(/-/g, "+").replace(/_/g, "/");
        return Uint8Array.from(atob(safe), c => c.charCodeAt(0));
    };

    try {
        const sub = await swReg.pushManager.subscribe({
            userVisibleOnly: true,
            applicationServerKey: toUint8(VAPID_PUBLIC_KEY),
        });

        await fetch("/push/subscribe", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(sub),
        });

        updatePushUI(true);
    } catch (e) {
        console.error("Errore subscribe push:", e);
        alert("Errore nell'attivazione delle notifiche.");
    }
}

async function unsubscribeDesktop() {
    const sub = await getSubscription();
    if (!sub) return;

    try {
        await sub.unsubscribe();
        await fetch("/push/unsubscribe", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ endpoint: sub.endpoint }),
        });
    } catch (e) {
        console.error("Errore unsubscribe push:", e);
    }

    updatePushUI(false);
}

async function togglePushFromPopover() {
    // Controlla prima se c'è già una subscription SENZA await lunghi
    // per mantenere il contesto del gesto utente su iOS Safari
    try {
        const reg = await navigator.serviceWorker.getRegistration("/sw.js");
        const sub = reg ? await reg.pushManager.getSubscription() : null;
        if (sub) {
            await unsubscribeDesktop();
        } else {
            await subscribeDesktop();
        }
    } catch (e) {
        // Fallback: prova a subscribere direttamente
        await subscribeDesktop();
    }
}

async function togglePush() {
    await togglePushFromPopover();
}

async function initPushButton() {
    const sub = await getSubscription();
    updatePushUI(!!sub);
}

async function enablePush() {
    await subscribeDesktop();
}

window.togglePush = togglePush;
window.togglePushFromPopover = togglePushFromPopover;
window.enablePush = enablePush;

/************************************************************
 * SOGLIA NOTIFICA
 ************************************************************/
function initThresholdSelector() {
    const saved = parseInt(localStorage.getItem("push_threshold"), 10) || 1;
    const desktop = document.getElementById("threshold-select");
    const mobile = document.getElementById("threshold-select-mobile");
    if (desktop) desktop.value = saved;
    if (mobile) mobile.value = saved;
}

async function updateThreshold(value) {
    const threshold = parseInt(value, 10);
    if (isNaN(threshold) || threshold < 1 || threshold > 5) return;

    // Sync both selectors
    const desktop = document.getElementById("threshold-select");
    const mobile = document.getElementById("threshold-select-mobile");
    if (desktop) desktop.value = threshold;
    if (mobile) mobile.value = threshold;

    // Save to localStorage
    localStorage.setItem("push_threshold", threshold);

    // Send to backend
    const sub = await getSubscription();
    if (!sub) return;

    try {
        const res = await fetch("/push/threshold", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ endpoint: sub.endpoint, threshold: threshold }),
        });
        if (res.ok) {
            const sel = desktop || mobile;
            if (sel) {
                sel.style.borderColor = "#34d399";
                setTimeout(() => { sel.style.borderColor = ""; }, 1500);
            }
        } else {
            alert("Errore nell'aggiornamento della soglia.");
        }
    } catch (e) {
        console.error("Errore aggiornamento soglia:", e);
        alert("Errore di rete nell'aggiornamento della soglia.");
    }
}

window.updateThreshold = updateThreshold;

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
    initThresholdSelector();

    const initial = document.body.getAttribute("data-global-state") || "GREEN";
    updateGlobalStatus(initial);
    updateMobileMenuStatus(initial);

    refreshDashboard();
    setInterval(refreshDashboard, 60000);

    // Inverter initial render
    if (typeof INVERTER_INITIAL_DATA !== "undefined" && INVERTER_INITIAL_DATA && !INVERTER_INITIAL_DATA.error) {
        renderInverterCards(INVERTER_INITIAL_DATA);
        updateInverterTimestamp(INVERTER_INITIAL_DATA.timestamp);
    }
});