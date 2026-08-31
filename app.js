const STORAGE_KEY = "meukm-data-v1";
const LEGACY_STORAGE_KEY = "autocusto-data-v2";

const todayISO = () => new Date().toISOString().slice(0, 10);
const uid = () => `${Date.now()}-${Math.random().toString(16).slice(2)}`;

const defaultState = {
  currentVehicleId: "vehicle-1",
  vehicles: [
    { id: "vehicle-1", name: "Shineray JEF 150", plate: "SEM PLACA", odometer: 7044 }
  ],
  records: [
    { id: "r1", vehicleId: "vehicle-1", type: "fuel", date: "2026-08-14", odometer: 6307, total: 50, liters: 8.2, pricePerLiter: 6.098, category: "Gasolina comum", place: "Posto Central", fullTank: true, notes: "" },
    { id: "r2", vehicleId: "vehicle-1", type: "fuel", date: "2026-08-21", odometer: 6454, total: 50, liters: 8.08, pricePerLiter: 6.188, category: "Gasolina comum", place: "Posto Central", fullTank: true, notes: "" },
    { id: "r3", vehicleId: "vehicle-1", type: "maintenance", date: "2026-08-21", odometer: 6454, total: 0, category: "Pneus - calibragem", place: "Posto Central", nextOdometer: 6954, nextDate: "2026-09-21", notes: "" },
    { id: "r4", vehicleId: "vehicle-1", type: "fuel", date: "2026-08-26", odometer: 6626, total: 50, liters: 8.01, pricePerLiter: 6.242, category: "Gasolina comum", place: "Posto Central", fullTank: true, notes: "" },
    { id: "r5", vehicleId: "vehicle-1", type: "fuel", date: "2026-08-31", odometer: 6845, total: 50, liters: 8.03, pricePerLiter: 6.227, category: "Gasolina comum", place: "Posto Central", fullTank: true, notes: "" },
    { id: "r6", vehicleId: "vehicle-1", type: "expense", date: "2026-08-08", odometer: 6210, total: 145.8, category: "Licenciamento", place: "Detran", paymentMethod: "Pix", notes: "" },
    { id: "r7", vehicleId: "vehicle-1", type: "maintenance", date: "2026-07-16", odometer: 5658, total: 239, category: "Troca de óleo", place: "Oficina do Bairro", nextOdometer: 7658, nextDate: "2026-11-16", notes: "Óleo e filtro" }
  ],
  settings: { darkMode: false, maintenanceNotifications: true, fuelNotifications: true }
};

let state = loadState();
let activeFilter = "all";
let deferredInstallPrompt = null;

const $ = (selector, scope = document) => scope.querySelector(selector);
const $$ = (selector, scope = document) => [...scope.querySelectorAll(selector)];

function loadState() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY) || localStorage.getItem(LEGACY_STORAGE_KEY);
    return saved ? JSON.parse(saved) : structuredClone(defaultState);
  } catch {
    return structuredClone(defaultState);
  }
}

function saveState(message) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  if (message) showToast(message);
}

function currency(value = 0) {
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(Number(value) || 0);
}

function number(value, digits = 1) {
  return new Intl.NumberFormat("pt-BR", { maximumFractionDigits: digits, minimumFractionDigits: digits }).format(Number(value) || 0);
}

function formatDate(date) {
  if (!date) return "Sem data";
  return new Intl.DateTimeFormat("pt-BR", { day: "2-digit", month: "short", year: "numeric", timeZone: "UTC" }).format(new Date(`${date}T12:00:00Z`));
}

function monthName(date = new Date()) {
  return new Intl.DateTimeFormat("pt-BR", { month: "long", year: "numeric" }).format(date).toUpperCase();
}

function currentVehicle() {
  return state.vehicles.find(v => v.id === state.currentVehicleId) || state.vehicles[0];
}

function vehicleRecords() {
  return state.records.filter(record => record.vehicleId === state.currentVehicleId);
}

function totalOf(records) {
  return records.reduce((sum, record) => sum + (Number(record.total) || 0), 0);
}

function getStats(records) {
  const sorted = [...records].sort((a, b) => a.odometer - b.odometer);
  const odometers = sorted.map(item => Number(item.odometer)).filter(Number.isFinite);
  const distance = odometers.length > 1 ? Math.max(...odometers) - Math.min(...odometers) : 0;
  const total = totalOf(records);
  const fuel = sorted.filter(item => item.type === "fuel" && item.fullTank && Number(item.liters) > 0);
  let consumptionDistance = 0;
  let consumptionLiters = 0;
  for (let index = 1; index < fuel.length; index += 1) {
    const traveled = Number(fuel[index].odometer) - Number(fuel[index - 1].odometer);
    if (traveled > 0) {
      consumptionDistance += traveled;
      consumptionLiters += Number(fuel[index].liters) || 0;
    }
  }
  const allFuel = records.filter(item => item.type === "fuel");
  const liters = allFuel.reduce((sum, item) => sum + (Number(item.liters) || 0), 0);
  const fuelTotal = totalOf(allFuel);
  return {
    total,
    distance,
    costPerKm: distance > 0 ? total / distance : 0,
    averageConsumption: consumptionLiters > 0 ? consumptionDistance / consumptionLiters : 0,
    averageFuelPrice: liters > 0 ? fuelTotal / liters : 0
  };
}

function recordLabel(record) {
  if (record.type === "fuel") return "Abastecimento";
  if (record.type === "maintenance") return record.category || "Manutenção";
  return record.category || "Despesa";
}

function recordSecondary(record) {
  const parts = [record.place, `${Math.round(record.odometer || 0)} km`].filter(Boolean);
  return parts.join(" • ");
}

function recordCard(record, editable = true) {
  return `
    <article class="record-card" data-type="${record.type}">
      <span class="record-accent" aria-hidden="true"></span>
      <div class="record-main">
        <strong>${escapeHtml(recordLabel(record))}</strong>
        <span>${escapeHtml(recordSecondary(record))}</span>
        <small>${formatDate(record.date)}</small>
      </div>
      <div class="record-side">
        <strong>${currency(record.total)}</strong>
        ${editable ? `<button data-edit-record="${record.id}">Editar</button>` : ""}
      </div>
    </article>`;
}

function render() {
  renderVehicles();
  renderHome();
  renderHistory();
  renderReports();
  renderSettings();
  applyTheme();
}

function renderVehicles() {
  const vehicleSelect = $("#vehicleSelect");
  vehicleSelect.innerHTML = state.vehicles.map(vehicle => `<option value="${vehicle.id}">${escapeHtml(vehicle.name)}</option>`).join("");
  vehicleSelect.value = state.currentVehicleId;
  $("#vehicleList").innerHTML = state.vehicles.map(vehicle => `
    <div class="vehicle-item">
      <strong>${escapeHtml(vehicle.name)}${vehicle.id === state.currentVehicleId ? " — atual" : ""}</strong>
      <span>${escapeHtml(vehicle.plate || "Sem placa")} • ${Math.round(vehicle.odometer || 0)} km</span>
    </div>`).join("");
}

function renderHome() {
  const records = vehicleRecords();
  const current = new Date();
  const monthRecords = records.filter(record => {
    const date = new Date(`${record.date}T12:00:00`);
    return date.getMonth() === current.getMonth() && date.getFullYear() === current.getFullYear();
  });
  const displayRecords = monthRecords.length ? monthRecords : records.filter(record => record.date.startsWith("2026-08"));
  const stats = getStats(records);
  const monthStats = getStats(displayRecords);
  const vehicle = currentVehicle();
  $("#monthLabel").textContent = displayRecords === monthRecords ? monthName(current) : "AGOSTO 2026";
  $("#monthTotal").textContent = currency(monthStats.total);
  $("#monthComparison").textContent = `${displayRecords.length} registros no período`;
  $("#avgConsumption").textContent = stats.averageConsumption ? number(stats.averageConsumption, 1) : "—";
  $("#costPerKm").textContent = stats.costPerKm ? currency(stats.costPerKm) : "—";
  $("#avgFuelPrice").textContent = stats.averageFuelPrice ? currency(stats.averageFuelPrice) : "—";
  $("#currentOdometer").textContent = `${Math.round(vehicle.odometer || 0)} km`;

  const maintenance = records
    .filter(record => record.type === "maintenance" && (record.nextDate || record.nextOdometer))
    .sort((a, b) => (a.nextDate || "9999").localeCompare(b.nextDate || "9999"))[0];
  $("#nextMaintenance").innerHTML = maintenance
    ? `<strong>${escapeHtml(maintenance.category)}</strong><p>${maintenance.nextDate ? `Até ${formatDate(maintenance.nextDate)}` : "Sem data definida"}</p><p>${maintenance.nextOdometer ? `Ao atingir ${Math.round(maintenance.nextOdometer)} km` : "Sem limite de quilometragem"}</p>`
    : `<strong>Nenhum lembrete programado</strong><p>Cadastre uma manutenção e informe o próximo prazo.</p>`;

  const recent = [...records].sort((a, b) => b.date.localeCompare(a.date) || b.odometer - a.odometer).slice(0, 5);
  $("#recentList").innerHTML = recent.length ? recent.map(record => recordCard(record, false)).join("") : emptyState("Nenhum registro encontrado.");
}

function renderHistory() {
  const records = vehicleRecords()
    .filter(record => activeFilter === "all" || record.type === activeFilter)
    .sort((a, b) => b.date.localeCompare(a.date) || b.odometer - a.odometer);
  $("#historyList").innerHTML = records.length ? records.map(record => recordCard(record)).join("") : emptyState("Nenhum registro neste filtro.");
}

function reportRecords() {
  const value = $("#reportPeriod")?.value || "6";
  const records = vehicleRecords();
  if (value === "all") return records;
  const months = Number(value);
  const newest = records.reduce((latest, item) => item.date > latest ? item.date : latest, todayISO());
  const cutoff = new Date(`${newest}T12:00:00`);
  cutoff.setMonth(cutoff.getMonth() - months + 1);
  return records.filter(item => new Date(`${item.date}T12:00:00`) >= cutoff);
}

function renderReports() {
  const records = reportRecords();
  const stats = getStats(records);
  $("#reportTotal").textContent = currency(stats.total);
  $("#reportDistance").textContent = `${Math.round(stats.distance)} km`;
  $("#reportCostKm").textContent = currency(stats.costPerKm);

  const months = buildMonthBuckets(records, $("#reportPeriod")?.value === "12" ? 12 : 6);
  const max = Math.max(...months.map(item => item.total), 1);
  $("#monthlyChart").innerHTML = months.map(item => `
    <div class="bar-column">
      <span class="bar-value">${compactCurrency(item.total)}</span>
      <span class="bar" style="height:${Math.max(4, (item.total / max) * 140)}px"></span>
      <span class="bar-label">${item.label}</span>
    </div>`).join("");

  const totals = ["fuel", "maintenance", "expense"].map(type => ({ type, total: totalOf(records.filter(item => item.type === type)) }));
  const maxCategory = Math.max(...totals.map(item => item.total), 1);
  const labels = { fuel: "Combustível", maintenance: "Manutenção", expense: "Outras despesas" };
  $("#categoryChart").innerHTML = totals.map(item => `
    <div class="category-row" data-type="${item.type}">
      <span>${labels[item.type]}</span>
      <div class="category-track"><div class="category-fill" style="width:${(item.total / maxCategory) * 100}%"></div></div>
      <strong>${currency(item.total)}</strong>
    </div>`).join("");
}

function buildMonthBuckets(records, count) {
  const newestText = records.reduce((latest, item) => item.date > latest ? item.date : latest, todayISO());
  const newest = new Date(`${newestText}T12:00:00`);
  return Array.from({ length: count }, (_, index) => {
    const date = new Date(newest.getFullYear(), newest.getMonth() - (count - 1 - index), 1);
    const key = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
    return {
      key,
      label: new Intl.DateTimeFormat("pt-BR", { month: "short" }).format(date).replace(".", ""),
      total: totalOf(records.filter(item => item.date.startsWith(key)))
    };
  });
}

function renderSettings() {
  $("#darkModeToggle").checked = Boolean(state.settings.darkMode);
  $("#maintenanceNotifications").checked = state.settings.maintenanceNotifications !== false;
  $("#fuelNotifications").checked = state.settings.fuelNotifications !== false;
}

function switchView(viewName) {
  $$(".view").forEach(view => {
    const active = view.id === `view-${viewName}`;
    view.classList.toggle("is-active", active);
    view.hidden = !active;
  });
  $$(".nav-item").forEach(button => button.classList.toggle("is-active", button.dataset.view === viewName));
  window.scrollTo({ top: 0, behavior: "smooth" });
  $(`#view-${viewName} h2`)?.focus?.();
}

function openRecordDialog(type, existingId = null) {
  $("#addMenuDialog").open && $("#addMenuDialog").close();
  const existing = existingId ? state.records.find(item => item.id === existingId) : null;
  const labels = { fuel: "Abastecimento", maintenance: "Manutenção", expense: "Despesa" };
  $("#recordForm").reset();
  $("#recordId").value = existing?.id || "";
  $("#recordType").value = type;
  $("#recordDialogTitle").textContent = existing ? `Editar ${labels[type].toLowerCase()}` : labels[type];
  $("#recordEyebrow").textContent = existing ? "EDITAR REGISTRO" : "NOVO REGISTRO";
  $("#recordDate").value = existing?.date || todayISO();
  $("#recordOdometer").value = existing?.odometer ?? currentVehicle().odometer;
  $("#recordPlace").value = existing?.place || "";
  $("#recordNotes").value = existing?.notes || "";
  $$(".conditional-fields").forEach(field => field.classList.remove("is-active"));
  $(`#${type}Fields`).classList.add("is-active");

  if (type === "fuel") {
    $("#fuelType").value = existing?.category || "Gasolina comum";
    $("#fuelPrice").value = existing?.pricePerLiter || "";
    $("#fuelLiters").value = existing?.liters || "";
    $("#fuelTotal").value = existing?.total || "";
    $("#fullTank").checked = existing ? Boolean(existing.fullTank) : true;
  }
  if (type === "maintenance") {
    $("#maintenanceCategory").value = existing?.category || "Troca de óleo";
    $("#maintenanceTotal").value = existing?.total || "";
    $("#nextOdometer").value = existing?.nextOdometer || "";
    $("#nextDate").value = existing?.nextDate || "";
  }
  if (type === "expense") {
    $("#expenseCategory").value = existing?.category || "Seguro";
    $("#expenseTotal").value = existing?.total || "";
    $("#paymentMethod").value = existing?.paymentMethod || "Pix";
  }
  $("#deleteRecordButton").hidden = !existing;
  $("#recordDialog").showModal();
}

function saveRecord(event) {
  event.preventDefault();
  const type = $("#recordType").value;
  const existingId = $("#recordId").value;
  const record = {
    id: existingId || uid(),
    vehicleId: state.currentVehicleId,
    type,
    date: $("#recordDate").value,
    odometer: Number($("#recordOdometer").value),
    place: $("#recordPlace").value.trim(),
    notes: $("#recordNotes").value.trim()
  };
  if (type === "fuel") Object.assign(record, {
    category: $("#fuelType").value,
    pricePerLiter: Number($("#fuelPrice").value),
    liters: Number($("#fuelLiters").value),
    total: Number($("#fuelTotal").value),
    fullTank: $("#fullTank").checked
  });
  if (type === "maintenance") Object.assign(record, {
    category: $("#maintenanceCategory").value,
    total: Number($("#maintenanceTotal").value),
    nextOdometer: Number($("#nextOdometer").value) || null,
    nextDate: $("#nextDate").value || null
  });
  if (type === "expense") Object.assign(record, {
    category: $("#expenseCategory").value,
    total: Number($("#expenseTotal").value),
    paymentMethod: $("#paymentMethod").value
  });

  if (!record.date || !Number.isFinite(record.odometer)) return showToast("Preencha a data e o odômetro.");
  if (type === "fuel" && (!record.total || !record.liters)) return showToast("Informe o valor e os litros do abastecimento.");

  if (existingId) {
    const index = state.records.findIndex(item => item.id === existingId);
    state.records[index] = record;
  } else {
    state.records.push(record);
  }
  const vehicle = currentVehicle();
  vehicle.odometer = Math.max(Number(vehicle.odometer) || 0, record.odometer);
  saveState(existingId ? "Registro atualizado." : "Registro salvo.");
  $("#recordDialog").close();
  render();
  switchView("history");
}

function deleteCurrentRecord() {
  const id = $("#recordId").value;
  if (!id || !confirm("Excluir este registro? Esta ação não pode ser desfeita.")) return;
  state.records = state.records.filter(item => item.id !== id);
  saveState("Registro excluído.");
  $("#recordDialog").close();
  render();
}

function autoCalculateFuel(changed) {
  const price = Number($("#fuelPrice").value);
  const liters = Number($("#fuelLiters").value);
  const total = Number($("#fuelTotal").value);
  if (changed === "fuelTotal" && price > 0 && total > 0) $("#fuelLiters").value = (total / price).toFixed(3);
  if (changed === "fuelLiters" && price > 0 && liters > 0) $("#fuelTotal").value = (price * liters).toFixed(2);
  if (changed === "fuelPrice" && price > 0) {
    if (total > 0) $("#fuelLiters").value = (total / price).toFixed(3);
    else if (liters > 0) $("#fuelTotal").value = (price * liters).toFixed(2);
  }
}

function addVehicle(event) {
  event.preventDefault();
  const vehicle = {
    id: uid(),
    name: $("#vehicleName").value.trim(),
    plate: $("#vehiclePlate").value.trim().toUpperCase(),
    odometer: Number($("#vehicleOdometer").value) || 0
  };
  state.vehicles.push(vehicle);
  state.currentVehicleId = vehicle.id;
  saveState("Veículo cadastrado.");
  $("#vehicleDialog").close();
  $("#vehicleForm").reset();
  render();
}

function exportBackup() {
  const blob = new Blob([JSON.stringify(state, null, 2)], { type: "application/json" });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = `meukm-backup-${todayISO()}.json`;
  link.click();
  URL.revokeObjectURL(link.href);
  showToast("Backup exportado.");
}

async function importBackup(file) {
  if (!file) return;
  try {
    const data = JSON.parse(await file.text());
    if (!Array.isArray(data.vehicles) || !Array.isArray(data.records)) throw new Error("invalid");
    state = data;
    state.settings ||= structuredClone(defaultState.settings);
    saveState("Backup importado.");
    render();
  } catch {
    showToast("Este arquivo de backup não é válido.");
  }
}

function applyTheme() {
  document.body.classList.toggle("dark", Boolean(state.settings.darkMode));
  $("meta[name='theme-color']").setAttribute("content", state.settings.darkMode ? "#102126" : "#087f8c");
}

function showToast(message) {
  const toast = $("#toast");
  toast.textContent = message;
  toast.classList.add("is-visible");
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => toast.classList.remove("is-visible"), 2600);
}

function emptyState(message) {
  return `<div class="empty-state">${escapeHtml(message)}</div>`;
}

function compactCurrency(value) {
  if (value >= 1000) return `R$${number(value / 1000, 1)}k`;
  return `R$${Math.round(value)}`;
}

function escapeHtml(value = "") {
  return String(value).replace(/[&<>'"]/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[character]);
}

function bindEvents() {
  document.addEventListener("click", event => {
    const viewButton = event.target.closest("[data-view], [data-view-target]");
    if (viewButton) switchView(viewButton.dataset.view || viewButton.dataset.viewTarget);
    if (event.target.closest("[data-open-add]")) $("#addMenuDialog").showModal();
    const addButton = event.target.closest("[data-add-type]");
    if (addButton) openRecordDialog(addButton.dataset.addType);
    const editButton = event.target.closest("[data-edit-record]");
    if (editButton) {
      const record = state.records.find(item => item.id === editButton.dataset.editRecord);
      if (record) openRecordDialog(record.type, record.id);
    }
    const closeButton = event.target.closest("[data-close-dialog]");
    if (closeButton) $(`#${closeButton.dataset.closeDialog}`).close();
    const filterButton = event.target.closest("[data-filter]");
    if (filterButton) {
      activeFilter = filterButton.dataset.filter;
      $$(".filter-chip").forEach(button => button.classList.toggle("is-active", button === filterButton));
      renderHistory();
    }
  });
  $("#vehicleSelect").addEventListener("change", event => { state.currentVehicleId = event.target.value; saveState(); render(); });
  $("#recordForm").addEventListener("submit", saveRecord);
  $("#deleteRecordButton").addEventListener("click", deleteCurrentRecord);
  ["fuelPrice", "fuelLiters", "fuelTotal"].forEach(id => $(`#${id}`).addEventListener("input", () => autoCalculateFuel(id)));
  $("#addVehicleButton").addEventListener("click", () => $("#vehicleDialog").showModal());
  $("#vehicleForm").addEventListener("submit", addVehicle);
  $("#reportPeriod").addEventListener("change", renderReports);
  $("#darkModeToggle").addEventListener("change", event => { state.settings.darkMode = event.target.checked; saveState(); applyTheme(); });
  $("#maintenanceNotifications").addEventListener("change", event => { state.settings.maintenanceNotifications = event.target.checked; saveState("Preferência salva."); });
  $("#fuelNotifications").addEventListener("change", event => { state.settings.fuelNotifications = event.target.checked; saveState("Preferência salva."); });
  $("#exportButton").addEventListener("click", exportBackup);
  $("#importInput").addEventListener("change", event => importBackup(event.target.files[0]));

  window.addEventListener("beforeinstallprompt", event => {
    event.preventDefault();
    deferredInstallPrompt = event;
    $("#installButton").hidden = false;
  });
  $("#installButton").addEventListener("click", async () => {
    if (!deferredInstallPrompt) return;
    deferredInstallPrompt.prompt();
    await deferredInstallPrompt.userChoice;
    deferredInstallPrompt = null;
    $("#installButton").hidden = true;
  });
}

bindEvents();
render();

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => navigator.serviceWorker.register("sw.js").catch(() => {}));
}
