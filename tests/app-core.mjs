import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const storage = new Map();
let uploadedRow = null;
const source = fs.readFileSync(new URL('../app.js', import.meta.url), 'utf8')
  .replace(/\nbindEvents\(\);\nrender\(\);[\s\S]*$/, '');
const context = vm.createContext({
  console,
  structuredClone,
  localStorage: {
    getItem: (key) => storage.get(key) ?? null,
    setItem: (key, value) => storage.set(key, value),
    removeItem: (key) => storage.delete(key),
  },
  navigator: { onLine: true },
  document: { querySelector: () => null, querySelectorAll: () => [] },
  window: {},
  fetch: async (url, options = {}) => {
    if (String(url).includes('/rest/v1/meukm_user_data') && (options.method ?? 'GET') === 'GET') {
      return new Response('[]', { status: 200, headers: { 'content-type': 'application/json' } });
    }
    if (String(url).includes('/rest/v1/meukm_user_data') && options.method === 'POST') {
      uploadedRow = JSON.parse(options.body)[0];
      return new Response(JSON.stringify([{ ...uploadedRow, updated_at: '2026-09-04T22:00:00.000Z' }]), {
        status: 201,
        headers: { 'content-type': 'application/json' },
      });
    }
    throw new Error(`Unexpected request: ${url}`);
  },
  Response,
  setTimeout,
  clearTimeout,
  URL,
  Intl,
  Date,
});
new vm.Script(source, { filename: 'app.js' }).runInContext(context);

const sampleRecords = [
  { id: 'a', vehicleId: 'v', type: 'fuel', date: '2026-01-01', odometer: 100, liters: 5, total: 30, fullTank: true },
  { id: 'b', vehicleId: 'v', type: 'fuel', date: '2026-01-05', odometer: 200, liters: 4, total: 25, fullTank: true },
];
const stats = context.getStats(sampleRecords);
assert.equal(stats.averageConsumption, 25);
assert.equal(stats.distance, 100);

const prediction = context.getFuelPrediction(sampleRecords, { odometer: 200 });
assert.equal(prediction.predictedOdometer, 300);
assert.equal(prediction.remainingDistance, 100);

const local = {
  currentVehicleId: 'v',
  vehicles: [{ id: 'v', name: 'Local', odometer: 200, _updatedAt: '2026-01-05T00:00:00.000Z' }],
  records: [{ ...sampleRecords[1], _updatedAt: '2026-01-05T00:00:00.000Z' }],
  deletedRecords: [],
  settings: { darkMode: false, _updatedAt: '2026-01-05T00:00:00.000Z' },
  sync: { modifiedAt: '2026-01-05T00:00:00.000Z' },
};
const remoteWithNewerDeletion = {
  ...local,
  records: [{ ...sampleRecords[1], total: 20, _updatedAt: '2026-01-04T00:00:00.000Z' }],
  deletedRecords: [{ id: 'b', _updatedAt: '2026-01-06T00:00:00.000Z' }],
  sync: { modifiedAt: '2026-01-06T00:00:00.000Z' },
};
const merged = context.mergeCloudStates(local, remoteWithNewerDeletion, 'user-1');
assert.equal(merged.records.length, 0, 'A exclusão mais recente deve prevalecer na sincronização.');
assert.equal(merged.sync.ownerId, 'user-1');

const cloudPayload = context.stateForCloud(merged);
assert.equal('dirty' in cloudPayload.sync, false);
assert.equal('lastSyncedAt' in cloudPayload.sync, false);

vm.runInContext(`
  render = () => {};
  cloudSession = {
    access_token: 'test-token',
    refresh_token: 'test-refresh',
    expires_at: Math.floor(Date.now() / 1000) + 3600,
    user: { id: '11111111-1111-4111-8111-111111111111', email: 'teste@meukm.app', user_metadata: { name: 'Teste' } }
  };
`, context);
await context.syncWithCloud();
assert.equal(uploadedRow.user_id, '11111111-1111-4111-8111-111111111111');
assert.equal(uploadedRow.data.sync.dirty, undefined);
assert.equal(vm.runInContext('state.sync.dirty', context), false);

console.log('App core tests: OK');
