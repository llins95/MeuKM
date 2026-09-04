const STORAGE_KEY = "meukm-data-v1";
const LEGACY_STORAGE_KEY = "autocusto-data-v2";
const LEGACY_AUTH_KEY = "meukm-account-v1";
const CLOUD_SESSION_KEY = "meukm-cloud-session-v1";
const SUPABASE_URL = "https://nnntmfdfkafigabwsjzz.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_g8lo_wxILrAawLX_Bxaauw_82Db9zKe";
const SYNC_TABLE = "meukm_user_data";
const EPOCH = "1970-01-01T00:00:00.000Z";

const todayISO = () => new Date().toISOString().slice(0, 10);
const uid = () => `${Date.now()}-${Math.random().toString(16).slice(2)}`;
const nowISO = () => new Date().toISOString();

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

function createEmptyState() {
  const createdAt = nowISO();
  return {
    currentVehicleId: "vehicle-empty",
    vehicles: [{ id: "vehicle-empty", name: "Meu veículo", plate: "SEM PLACA", odometer: 0, _updatedAt: createdAt }],
    records: [],
    deletedRecords: [],
    settings: { ...structuredClone(defaultState.settings), _updatedAt: createdAt },
    sync: { modifiedAt: createdAt, resetAt: createdAt, dirty: true }
  };
}

const hadPersistedStateAtBoot = Boolean(localStorage.getItem(STORAGE_KEY) || localStorage.getItem(LEGACY_STORAGE_KEY));
let state = loadState();
let legacyAccount = loadLegacyAccount();
let cloudSession = loadCloudSession();
let activeFilter = "all";
let deferredInstallPrompt = null;
let syncPromise = null;
let syncTimer = null;
let syncStatusText = cloudSession ? "Conectando à nuvem…" : "Entre para sincronizar entre aparelhos.";
let localDataChangedThisRun = false;

const $ = (selector, scope = document) => scope.querySelector(selector);
const $$ = (selector, scope = document) => [...scope.querySelectorAll(selector)];

function loadState() {
  try {
    const saved = localStorage.getItem(STORAGE_KEY) || localStorage.getItem(LEGACY_STORAGE_KEY);
    return normalizeState(saved ? JSON.parse(saved) : structuredClone(defaultState), saved ? nowISO() : EPOCH);
  } catch {
    return normalizeState(structuredClone(defaultState), EPOCH);
  }
}

function normalizeState(candidate, fallbackTimestamp = EPOCH) {
  const source = candidate && typeof candidate === "object" ? candidate : structuredClone(defaultState);
  const settings = source.settings && typeof source.settings === "object" ? source.settings : {};
  return {
    currentVehicleId: source.currentVehicleId || source.vehicles?.[0]?.id || "vehicle-empty",
    vehicles: Array.isArray(source.vehicles)
      ? source.vehicles.map(vehicle => ({ ...vehicle, _updatedAt: vehicle._updatedAt || fallbackTimestamp }))
      : [],
    records: Array.isArray(source.records)
      ? source.records.map(record => ({ ...record, _updatedAt: record._updatedAt || fallbackTimestamp }))
      : [],
    deletedRecords: Array.isArray(source.deletedRecords)
      ? source.deletedRecords.filter(item => item?.id).map(item => ({ id: item.id, _updatedAt: item._updatedAt || fallbackTimestamp }))
      : [],
    settings: { ...structuredClone(defaultState.settings), ...settings, _updatedAt: settings._updatedAt || fallbackTimestamp },
    sync: {
      ownerId: source.sync?.ownerId || null,
      modifiedAt: source.sync?.modifiedAt || fallbackTimestamp,
      resetAt: source.sync?.resetAt || null,
      lastSyncedAt: source.sync?.lastSyncedAt || null,
      dirty: source.sync?.dirty ?? hadPersistedStateAtBoot
    }
  };
}

function loadLegacyAccount() {
  try {
    const saved = localStorage.getItem(LEGACY_AUTH_KEY);
    return saved ? JSON.parse(saved) : null;
  } catch {
    return null;
  }
}

function loadCloudSession() {
  try {
    const saved = localStorage.getItem(CLOUD_SESSION_KEY);
    return saved ? JSON.parse(saved) : null;
  } catch {
    return null;
  }
}

function isSignedIn() {
  return Boolean(cloudSession?.access_token && cloudSession?.user?.id);
}

function storeCloudSession(session) {
  if (!session?.access_token || !session?.user?.id) return;
  cloudSession = {
    ...session,
    expires_at: session.expires_at || Math.floor(Date.now() / 1000) + Number(session.expires_in || 3600)
  };
  localStorage.setItem(CLOUD_SESSION_KEY, JSON.stringify(cloudSession));
}

function clearCloudSession() {
  cloudSession = null;
  localStorage.removeItem(CLOUD_SESSION_KEY);
}

function markStateModified() {
  state.sync ||= {};
  state.sync.modifiedAt = nowISO();
  state.sync.dirty = true;
  localDataChangedThisRun = true;
}

function saveState(message, { sync = true } = {}) {
  if (sync) markStateModified();
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  if (message) showToast(message);
  if (sync) scheduleCloudSync();
}

function stateForCloud(candidate = state) {
  const payload = structuredClone(candidate);
  payload.sync = {
    ownerId: payload.sync?.ownerId || null,
    modifiedAt: payload.sync?.modifiedAt || EPOCH,
    resetAt: payload.sync?.resetAt || null
  };
  return payload;
}

function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function newestItemById(...collections) {
  const result = new Map();
  collections.flat().forEach(item => {
    if (!item?.id) return;
    const current = result.get(item.id);
    if (!current || (item._updatedAt || EPOCH) >= (current._updatedAt || EPOCH)) result.set(item.id, item);
  });
  return result;
}

function mergeCloudStates(localCandidate, remoteCandidate, ownerId) {
  const local = normalizeState(localCandidate, EPOCH);
  const remote = normalizeState(remoteCandidate, EPOCH);
  const resetAt = [local.sync.resetAt, remote.sync.resetAt].filter(Boolean).sort().at(-1) || null;
  const deletedRecords = [...newestItemById(local.deletedRecords, remote.deletedRecords).values()]
    .filter(item => !resetAt || item._updatedAt >= resetAt);
  const deletedById = new Map(deletedRecords.map(item => [item.id, item._updatedAt]));
  const records = [...newestItemById(local.records, remote.records).values()]
    .filter(item => (!resetAt || item._updatedAt >= resetAt) && (!deletedById.has(item.id) || item._updatedAt > deletedById.get(item.id)));
  const vehicles = [...newestItemById(local.vehicles, remote.vehicles).values()]
    .filter(item => !resetAt || item._updatedAt >= resetAt);
  const localSettingsWin = (local.settings._updatedAt || EPOCH) >= (remote.settings._updatedAt || EPOCH);
  const localRootWins = (local.sync.modifiedAt || EPOCH) >= (remote.sync.modifiedAt || EPOCH);
  const currentVehicleId = localRootWins ? local.currentVehicleId : remote.currentVehicleId;
  const fallbackVehicleId = vehicles[0]?.id || "vehicle-empty";

  return normalizeState({
    currentVehicleId: vehicles.some(item => item.id === currentVehicleId) ? currentVehicleId : fallbackVehicleId,
    vehicles,
    records,
    deletedRecords,
    settings: localSettingsWin ? local.settings : remote.settings,
    sync: {
      ownerId,
      modifiedAt: [local.sync.modifiedAt, remote.sync.modifiedAt].sort().at(-1) || EPOCH,
      resetAt,
      dirty: false
    }
  }, EPOCH);
}

function authErrorMessage(error) {
  const message = String(error?.message || "").toLowerCase();
  if (message.includes("invalid login credentials")) return "E-mail ou senha incorretos.";
  if (message.includes("email not confirmed")) return "Confirme o e-mail recebido antes de entrar.";
  if (message.includes("user already registered") || message.includes("already been registered")) return "Este e-mail já possui cadastro. Use a opção Entrar.";
  if (message.includes("password") && message.includes("characters")) return "A senha precisa ter pelo menos 6 caracteres.";
  if (!navigator.onLine || error?.name === "TypeError") return "Sem conexão. Conecte-se à internet e tente novamente.";
  return "Não foi possível concluir. Tente novamente em instantes.";
}

async function supabaseRequest(path, { method = "GET", body, token, headers = {} } = {}) {
  const response = await fetch(`${SUPABASE_URL}${path}`, {
    method,
    cache: "no-store",
    headers: {
      apikey: SUPABASE_PUBLISHABLE_KEY,
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body !== undefined ? { "Content-Type": "application/json" } : {}),
      ...headers
    },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const text = await response.text();
  let data = null;
  if (text) {
    try { data = JSON.parse(text); } catch { data = text; }
  }
  if (!response.ok) {
    const error = new Error(data?.error_description || data?.msg || data?.message || `Erro ${response.status}`);
    error.status = response.status;
    throw error;
  }
  return data;
}

async function ensureFreshSession() {
  if (!isSignedIn()) return null;
  const expiresSoon = Number(cloudSession.expires_at || 0) * 1000 <= Date.now() + 60_000;
  if (!expiresSoon) return cloudSession;
  try {
    const refreshed = await supabaseRequest("/auth/v1/token?grant_type=refresh_token", {
      method: "POST",
      body: { refresh_token: cloudSession.refresh_token }
    });
    storeCloudSession(refreshed);
    return cloudSession;
  } catch (error) {
    if (error.status === 400 || error.status === 401) clearCloudSession();
    throw error;
  }
}

function setSyncStatus(message) {
  syncStatusText = message;
  if ($("#accountSummary")) renderAccount();
}

async function fetchCloudState(session) {
  const userId = encodeURIComponent(session.user.id);
  const rows = await supabaseRequest(`/rest/v1/${SYNC_TABLE}?user_id=eq.${userId}&select=data,updated_at&limit=1`, {
    token: session.access_token
  });
  return Array.isArray(rows) ? rows[0] || null : null;
}

async function pushCloudState(session) {
  const rows = await supabaseRequest(`/rest/v1/${SYNC_TABLE}?on_conflict=user_id`, {
    method: "POST",
    token: session.access_token,
    headers: { Prefer: "resolution=merge-duplicates,return=representation" },
    body: [{ user_id: session.user.id, data: stateForCloud() }]
  });
  return Array.isArray(rows) ? rows[0] || null : null;
}

async function performCloudSync() {
  if (!isSignedIn()) return;
  if (!navigator.onLine) {
    setSyncStatus("Sem internet. As alterações serão enviadas quando a conexão voltar.");
    return;
  }

  setSyncStatus("Sincronizando…");
  const session = await ensureFreshSession();
  if (!session) return;
  const ownerId = session.user.id;

  if (state.sync.ownerId && state.sync.ownerId !== ownerId) {
    localStorage.setItem(`meukm-data-backup-${state.sync.ownerId}`, JSON.stringify(state));
    state = createEmptyState();
    state.sync.ownerId = ownerId;
    localDataChangedThisRun = false;
  }

  const remoteRow = await fetchCloudState(session);
  const localCanMerge = !state.sync.ownerId || state.sync.ownerId === ownerId
    ? hadPersistedStateAtBoot || localDataChangedThisRun || state.sync.ownerId === ownerId
    : false;

  if (remoteRow) {
    state = localCanMerge
      ? mergeCloudStates(state, remoteRow.data, ownerId)
      : normalizeState(remoteRow.data, EPOCH);
    state.sync.ownerId = ownerId;
  } else {
    state.sync.ownerId = ownerId;
  }

  const remotePayload = remoteRow?.data ? stateForCloud(normalizeState(remoteRow.data, EPOCH)) : null;
  const shouldPush = !remoteRow || state.sync.dirty || canonicalJson(stateForCloud()) !== canonicalJson(remotePayload);
  const savedRow = shouldPush ? await pushCloudState(session) : remoteRow;
  state.sync.dirty = false;
  state.sync.lastSyncedAt = savedRow?.updated_at || remoteRow?.updated_at || nowISO();
  localDataChangedThisRun = false;
  saveState(null, { sync: false });
  setSyncStatus(`Sincronizado em ${new Intl.DateTimeFormat("pt-BR", { hour: "2-digit", minute: "2-digit" }).format(new Date(state.sync.lastSyncedAt))}.`);
  render();
}

function syncWithCloud({ showResult = false } = {}) {
  if (syncPromise) return syncPromise;
  syncPromise = performCloudSync()
    .then(() => { if (showResult && isSignedIn()) showToast("Dados sincronizados."); })
    .catch(error => {
      setSyncStatus(error.status === 401 ? "A sessão expirou. Entre novamente." : authErrorMessage(error));
      if (showResult) showToast(authErrorMessage(error));
    })
    .finally(() => { syncPromise = null; });
  return syncPromise;
}

function scheduleCloudSync() {
  if (!isSignedIn()) return;
  clearTimeout(syncTimer);
  syncTimer = setTimeout(() => syncWithCloud(), 700);
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

function getFuelPrediction(records, vehicle) {
  const fuel = records
    .filter(item => item.type === "fuel" && item.fullTank && Number(item.odometer) > 0)
    .sort((a, b) => Number(a.odometer) - Number(b.odometer) || a.date.localeCompare(b.date));
  if (fuel.length < 2) return null;

  const recent = fuel.slice(-6);
  const distanceIntervals = [];
  const dayIntervals = [];
  for (let index = 1; index < recent.length; index += 1) {
    const traveled = Number(recent[index].odometer) - Number(recent[index - 1].odometer);
    if (traveled > 0) distanceIntervals.push(traveled);
    const previousDate = new Date(`${recent[index - 1].date}T12:00:00Z`);
    const currentDate = new Date(`${recent[index].date}T12:00:00Z`);
    const days = Math.round((currentDate - previousDate) / 86400000);
    if (days > 0) dayIntervals.push(days);
  }
  if (!distanceIntervals.length) return null;

  const averageDistance = distanceIntervals.reduce((sum, value) => sum + value, 0) / distanceIntervals.length;
  const averageDays = dayIntervals.length ? dayIntervals.reduce((sum, value) => sum + value, 0) / dayIntervals.length : 0;
  const last = recent.at(-1);
  const currentOdometer = Math.max(Number(vehicle?.odometer) || 0, ...records.map(item => Number(item.odometer) || 0));
  const predictedOdometer = Number(last.odometer) + averageDistance;
  const remainingDistance = predictedOdometer - currentOdometer;
  const predictedDate = averageDays
    ? new Date(new Date(`${last.date}T12:00:00Z`).getTime() + averageDays * 86400000).toISOString().slice(0, 10)
    : null;

  return { averageDistance, predictedOdometer, remainingDistance, predictedDate, sampleSize: distanceIntervals.length };
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

  const prediction = getFuelPrediction(records, vehicle);
  if (!prediction) {
    $("#fuelPrediction").innerHTML = `<strong>Ainda sem previsão</strong><p>Registre pelo menos dois abastecimentos com tanque completo para iniciar o cálculo.</p>`;
  } else {
    const dueNow = prediction.remainingDistance <= 0;
    $("#fuelPrediction").innerHTML = `
      <strong>${dueNow ? "Abastecimento provável em breve" : `Daqui a aproximadamente ${Math.round(prediction.remainingDistance)} km`}</strong>
      <p>Estimativa para ${Math.round(prediction.predictedOdometer)} km${prediction.predictedDate ? `, por volta de ${formatDate(prediction.predictedDate)}` : ""}.</p>
      <small>Média dos últimos ${prediction.sampleSize} intervalos: ${Math.round(prediction.averageDistance)} km por tanque.</small>`;
  }

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
  $("#reportConsumption").textContent = stats.averageConsumption ? `${number(stats.averageConsumption, 1)} km/L` : "—";

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

function reportExportData() {
  const records = reportRecords();
  const periodSelect = $("#reportPeriod");
  const monthCount = periodSelect.value === "12" ? 12 : 6;
  return {
    vehicle: currentVehicle(),
    period: periodSelect.options[periodSelect.selectedIndex].textContent,
    stats: getStats(records),
    months: buildMonthBuckets(records, monthCount),
    categories: [
      { label: "Combustível", color: "#d96b00", total: totalOf(records.filter(item => item.type === "fuel")) },
      { label: "Manutenção", color: "#476a57", total: totalOf(records.filter(item => item.type === "maintenance")) },
      { label: "Outras despesas", color: "#b93a2f", total: totalOf(records.filter(item => item.type === "expense")) }
    ]
  };
}

function roundedRect(context, x, y, width, height, radius, color) {
  context.beginPath();
  context.roundRect(x, y, width, height, radius);
  context.fillStyle = color;
  context.fill();
}

function drawReportCanvas() {
  const data = reportExportData();
  const canvas = document.createElement("canvas");
  canvas.width = 1400;
  canvas.height = 1900;
  const context = canvas.getContext("2d");
  const navy = "#081f3a";
  const blue = "#0759d6";
  const teal = "#23c6bd";
  const muted = "#5d6a6e";
  context.fillStyle = "#f3f6f7";
  context.fillRect(0, 0, canvas.width, canvas.height);

  context.fillStyle = navy;
  context.fillRect(0, 0, canvas.width, 300);
  context.fillStyle = teal;
  context.beginPath();
  context.arc(120, 105, 44, 0, Math.PI * 2);
  context.fill();
  context.fillStyle = "#ffffff";
  context.font = "800 58px Arial";
  context.fillText("MeuKM", 195, 125);
  context.font = "700 28px Arial";
  context.fillStyle = "#cce7ff";
  context.fillText("RELATÓRIO DO VEÍCULO", 80, 220);
  context.textAlign = "right";
  context.fillText(data.period, 1320, 100);
  context.font = "24px Arial";
  context.fillText(`${data.vehicle.name} • ${data.vehicle.plate || "Sem placa"}`, 1320, 150);
  context.textAlign = "left";

  const cards = [
    ["Total gasto", currency(data.stats.total)],
    ["Distância", `${Math.round(data.stats.distance)} km`],
    ["Custo por km", currency(data.stats.costPerKm)],
    ["Consumo médio", data.stats.averageConsumption ? `${number(data.stats.averageConsumption, 1)} km/L` : "Sem dados"]
  ];
  cards.forEach(([label, value], index) => {
    const x = 80 + (index % 2) * 630;
    const y = 360 + Math.floor(index / 2) * 170;
    roundedRect(context, x, y, 590, 135, 24, "#ffffff");
    context.fillStyle = muted;
    context.font = "25px Arial";
    context.fillText(label, x + 28, y + 45);
    context.fillStyle = navy;
    context.font = "800 39px Arial";
    context.fillText(value, x + 28, y + 100);
  });

  roundedRect(context, 80, 730, 1240, 500, 28, "#ffffff");
  context.fillStyle = navy;
  context.font = "800 34px Arial";
  context.fillText("Gastos mensais", 120, 795);
  const monthlyMax = Math.max(...data.months.map(item => item.total), 1);
  const chartLeft = 125;
  const chartBottom = 1135;
  const chartWidth = 1150;
  const barGap = 15;
  const barWidth = Math.max(34, (chartWidth - barGap * (data.months.length - 1)) / data.months.length);
  data.months.forEach((item, index) => {
    const barHeight = Math.max(5, item.total / monthlyMax * 250);
    const x = chartLeft + index * (barWidth + barGap);
    roundedRect(context, x, chartBottom - barHeight, barWidth, barHeight, 10, blue);
    context.fillStyle = muted;
    context.font = `${data.months.length > 6 ? 18 : 22}px Arial`;
    context.textAlign = "center";
    context.fillText(item.label.toUpperCase(), x + barWidth / 2, chartBottom + 38);
    context.save();
    context.translate(x + barWidth / 2, chartBottom - barHeight - 12);
    if (data.months.length > 8) context.rotate(-Math.PI / 4);
    context.fillText(compactCurrency(item.total), 0, 0);
    context.restore();
  });
  context.textAlign = "left";

  roundedRect(context, 80, 1270, 1240, 410, 28, "#ffffff");
  context.fillStyle = navy;
  context.font = "800 34px Arial";
  context.fillText("Gastos por categoria", 120, 1335);
  const categoryMax = Math.max(...data.categories.map(item => item.total), 1);
  data.categories.forEach((item, index) => {
    const y = 1405 + index * 85;
    context.fillStyle = navy;
    context.font = "25px Arial";
    context.fillText(item.label, 120, y);
    roundedRect(context, 410, y - 27, 650, 28, 14, "#e3e9eb");
    roundedRect(context, 410, y - 27, Math.max(8, item.total / categoryMax * 650), 28, 14, item.color);
    context.textAlign = "right";
    context.font = "800 25px Arial";
    context.fillText(currency(item.total), 1270, y);
    context.textAlign = "left";
  });

  context.fillStyle = muted;
  context.font = "22px Arial";
  context.fillText(`Gerado pelo MeuKM em ${new Intl.DateTimeFormat("pt-BR").format(new Date())}`, 80, 1805);
  context.textAlign = "right";
  context.fillText("Valores calculados a partir dos registros informados", 1320, 1805);
  return canvas;
}

function downloadBlob(blob, filename) {
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = filename;
  link.click();
  setTimeout(() => URL.revokeObjectURL(link.href), 1000);
}

function exportReportPng() {
  const canvas = drawReportCanvas();
  canvas.toBlob(blob => {
    if (!blob) return showToast("Não foi possível gerar o PNG.");
    downloadBlob(blob, `meukm-relatorio-${todayISO()}.png`);
    showToast("Relatório PNG exportado.");
  }, "image/png");
}

function exportReportPdf() {
  const jsPDF = window.jspdf?.jsPDF;
  if (!jsPDF) return showToast("O gerador de PDF ainda não carregou.");
  const canvas = drawReportCanvas();
  const pdf = new jsPDF({ orientation: "portrait", unit: "mm", format: "a4", compress: true });
  const imageHeight = 210 * canvas.height / canvas.width;
  pdf.addImage(canvas.toDataURL("image/jpeg", 0.92), "JPEG", 0, (297 - imageHeight) / 2, 210, imageHeight, undefined, "FAST");
  pdf.save(`meukm-relatorio-${todayISO()}.pdf`);
  showToast("Relatório PDF exportado.");
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
  renderAccount();
}

function renderAccount() {
  const summary = $("#accountSummary");
  const accountButton = $("#accountButton");
  const logoutButton = $("#logoutButton");
  const syncNowButton = $("#syncNowButton");

  if (isSignedIn()) {
    const user = cloudSession.user;
    const name = user.user_metadata?.name || user.email?.split("@")[0] || "Minha conta";
    summary.innerHTML = `<strong>${escapeHtml(name)}</strong><span>${escapeHtml(user.email || "")} • ${escapeHtml(syncStatusText)}</span>`;
    accountButton.hidden = true;
    logoutButton.hidden = false;
    syncNowButton.hidden = false;
    return;
  }

  logoutButton.hidden = true;
  syncNowButton.hidden = true;
  if (legacyAccount) {
    summary.innerHTML = `<strong>Ative a sincronização</strong><span>${escapeHtml(legacyAccount.email)} • cadastre esta conta na nuvem para usar os mesmos dados em outros aparelhos.</span>`;
    accountButton.textContent = "Ativar sincronização";
    accountButton.hidden = false;
    return;
  }

  summary.innerHTML = "<strong>Nenhuma conta conectada</strong><span>Cadastre-se ou entre para usar os mesmos dados no celular e no computador.</span>";
  accountButton.textContent = "Cadastrar ou entrar";
  accountButton.hidden = false;
}

function setAuthMode(mode) {
  const isLogin = mode === "login";
  $("#loginForm").hidden = !isLogin;
  $("#registerForm").hidden = isLogin;
  $$('[data-auth-mode]').forEach(button => {
    const selected = button.dataset.authMode === mode;
    button.classList.toggle("is-active", selected);
    button.setAttribute("aria-selected", String(selected));
  });
  $("#authMessage").textContent = "";
}

function openAccountDialog() {
  $("#loginForm").reset();
  $("#registerForm").reset();
  const suggestedEmail = cloudSession?.user?.email || legacyAccount?.email || "";
  if (suggestedEmail) {
    $("#loginEmail").value = suggestedEmail;
    $("#registerEmail").value = suggestedEmail;
  }
  if (legacyAccount?.name) $("#registerName").value = legacyAccount.name;
  setAuthMode(legacyAccount ? "register" : "login");
  $("#accountDialog").showModal();
}

async function registerAccount(event) {
  event.preventDefault();
  const message = $("#authMessage");
  const name = $("#registerName").value.trim();
  const email = $("#registerEmail").value.trim().toLowerCase();
  const password = $("#registerPassword").value;
  const confirmation = $("#registerPasswordConfirm").value;

  if (name.length < 2) {
    message.textContent = "Informe seu nome.";
    return;
  }
  if (password.length < 6) {
    message.textContent = "A senha precisa ter pelo menos 6 caracteres.";
    return;
  }
  if (password !== confirmation) {
    message.textContent = "As senhas não são iguais.";
    return;
  }
  try {
    message.textContent = "Criando sua conta…";
    const result = await supabaseRequest("/auth/v1/signup", {
      method: "POST",
      body: { email, password, data: { name } }
    });
    const session = result?.session || (result?.access_token ? result : null);
    if (!session) {
      setAuthMode("login");
      $("#loginEmail").value = email;
      message.textContent = "Cadastro criado. Confirme o e-mail recebido e depois use a opção Entrar.";
      return;
    }
    storeCloudSession(session);
    legacyAccount = null;
    localStorage.removeItem(LEGACY_AUTH_KEY);
    $("#accountDialog").close();
    renderAccount();
    showToast("Conta criada. Sincronizando seus dados…");
    await syncWithCloud();
  } catch (error) {
    message.textContent = authErrorMessage(error);
  }
}

async function loginAccount(event) {
  event.preventDefault();
  const message = $("#authMessage");
  const email = $("#loginEmail").value.trim().toLowerCase();
  const password = $("#loginPassword").value;

  try {
    message.textContent = "Entrando…";
    const result = await supabaseRequest("/auth/v1/token?grant_type=password", {
      method: "POST",
      body: { email, password }
    });
    storeCloudSession(result);
    legacyAccount = null;
    localStorage.removeItem(LEGACY_AUTH_KEY);
    $("#accountDialog").close();
    renderAccount();
    showToast("Login realizado. Sincronizando…");
    await syncWithCloud();
  } catch (error) {
    message.textContent = authErrorMessage(error);
  }
}

async function logoutAccount() {
  await syncWithCloud();
  try {
    if (cloudSession?.access_token && navigator.onLine) {
      await supabaseRequest("/auth/v1/logout", { method: "POST", token: cloudSession.access_token });
    }
  } catch {
    // A sessão local ainda deve ser encerrada mesmo se a rede falhar.
  }
  clearCloudSession();
  syncStatusText = "Entre para sincronizar entre aparelhos.";
  renderAccount();
  showToast("Você saiu da conta.");
}

function openDeleteDataDialog() {
  $("#deleteDataForm").reset();
  $("#confirmDeleteDataButton").disabled = true;
  $("#deleteDataDialog").showModal();
}

async function deleteAllData(event) {
  event.preventDefault();
  if ($("#deleteDataConfirmation").value.trim().toUpperCase() !== "APAGAR") return;

  if (isSignedIn() && !navigator.onLine) {
    showToast("Conecte-se à internet para apagar também os dados sincronizados.");
    return;
  }

  const ownerId = cloudSession?.user?.id || null;
  state = createEmptyState();
  state.sync.ownerId = ownerId;
  legacyAccount = null;
  localStorage.removeItem(LEGACY_STORAGE_KEY);
  localStorage.removeItem(LEGACY_AUTH_KEY);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));

  if (isSignedIn()) {
    await syncWithCloud();
    if (state.sync.dirty) {
      showToast("Não foi possível apagar os dados da nuvem. Tente novamente.");
      return;
    }
  }

  $("#deleteDataDialog").close();
  render();
  switchView("home");
  showToast(isSignedIn() ? "Dados apagados em todos os aparelhos." : "Todos os dados deste aparelho foram apagados.");
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
    notes: $("#recordNotes").value.trim(),
    _updatedAt: nowISO()
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
  vehicle._updatedAt = record._updatedAt;
  saveState(existingId ? "Registro atualizado." : "Registro salvo.");
  $("#recordDialog").close();
  render();
  switchView("history");
}

function deleteCurrentRecord() {
  const id = $("#recordId").value;
  if (!id || !confirm("Excluir este registro? Esta ação não pode ser desfeita.")) return;
  state.records = state.records.filter(item => item.id !== id);
  state.deletedRecords ||= [];
  state.deletedRecords.push({ id, _updatedAt: nowISO() });
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
  const createdAt = nowISO();
  event.preventDefault();
  const vehicle = {
    id: uid(),
    name: $("#vehicleName").value.trim(),
    plate: $("#vehiclePlate").value.trim().toUpperCase(),
    odometer: Number($("#vehicleOdometer").value) || 0,
    _updatedAt: createdAt
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
    const importedAt = nowISO();
    state = normalizeState(data, importedAt);
    state.vehicles = state.vehicles.map(item => ({ ...item, _updatedAt: importedAt }));
    state.records = state.records.map(item => ({ ...item, _updatedAt: importedAt }));
    state.settings._updatedAt = importedAt;
    state.sync.modifiedAt = importedAt;
    state.sync.dirty = true;
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
    const authModeButton = event.target.closest("[data-auth-mode]");
    if (authModeButton) setAuthMode(authModeButton.dataset.authMode);
  });
  $("#vehicleSelect").addEventListener("change", event => { state.currentVehicleId = event.target.value; saveState(); render(); });
  $("#recordForm").addEventListener("submit", saveRecord);
  $("#deleteRecordButton").addEventListener("click", deleteCurrentRecord);
  ["fuelPrice", "fuelLiters", "fuelTotal"].forEach(id => $(`#${id}`).addEventListener("input", () => autoCalculateFuel(id)));
  $("#addVehicleButton").addEventListener("click", () => $("#vehicleDialog").showModal());
  $("#vehicleForm").addEventListener("submit", addVehicle);
  $("#reportPeriod").addEventListener("change", renderReports);
  $("#exportReportPng").addEventListener("click", exportReportPng);
  $("#exportReportPdf").addEventListener("click", exportReportPdf);
  $("#darkModeToggle").addEventListener("change", event => { state.settings.darkMode = event.target.checked; state.settings._updatedAt = nowISO(); saveState(); applyTheme(); });
  $("#maintenanceNotifications").addEventListener("change", event => { state.settings.maintenanceNotifications = event.target.checked; state.settings._updatedAt = nowISO(); saveState("Preferência salva."); });
  $("#fuelNotifications").addEventListener("change", event => { state.settings.fuelNotifications = event.target.checked; state.settings._updatedAt = nowISO(); saveState("Preferência salva."); });
  $("#exportButton").addEventListener("click", exportBackup);
  $("#importInput").addEventListener("change", event => importBackup(event.target.files[0]));
  $("#accountButton").addEventListener("click", openAccountDialog);
  $("#syncNowButton").addEventListener("click", () => syncWithCloud({ showResult: true }));
  $("#logoutButton").addEventListener("click", logoutAccount);
  $("#loginForm").addEventListener("submit", loginAccount);
  $("#registerForm").addEventListener("submit", registerAccount);
  $("#openDeleteDataButton").addEventListener("click", openDeleteDataDialog);
  $("#deleteDataConfirmation").addEventListener("input", event => {
    $("#confirmDeleteDataButton").disabled = event.target.value.trim().toUpperCase() !== "APAGAR";
  });
  $("#deleteDataForm").addEventListener("submit", deleteAllData);

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

  window.addEventListener("online", () => syncWithCloud());
  window.addEventListener("offline", () => setSyncStatus("Sem internet. As alterações ficarão salvas neste aparelho."));
}

bindEvents();
render();
if (isSignedIn()) syncWithCloud();

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => navigator.serviceWorker.register("sw.js").catch(() => {}));
}
