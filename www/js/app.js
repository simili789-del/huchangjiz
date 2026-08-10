'use strict';

/* ============================================================
   货场作业记账 - 核心应用逻辑
   数据存储：localStorage（Capacitor WebView 持久化存储）
   ============================================================ */

const DEFAULT_TYPES = [
  { id: 't_load',  name: '货场装车', group: 'load',  color: '#007AFF', icon: 'truck' },
  { id: 't_stack', name: '货场归剁', group: 'stack', color: '#5856D6', icon: 'box' },
  { id: 't_out',   name: '外倒装车', group: 'xfer',  color: '#FF9500', icon: 'truck' },
  { id: 't_in',    name: '内倒装车', group: 'xfer',  color: '#FF3B30', icon: 'truck' },
  { id: 't_instk', name: '内倒归剁', group: 'stack', color: '#34C759', icon: 'box' },
];
const DEFAULT_PRICES = { t_load: 2.00, t_stack: 1.50, t_out: 2.00, t_in: 2.00, t_instk: 1.50 };
const TINT_COLORS = ['#007AFF', '#5856D6', '#AF52DE', '#FF3B30', '#FF9500', '#34C759', '#FF6482', '#64D2FF'];

const LS_KEY = 'hc_data_v1';
const LS_BACKUP_KEY = 'hc_backup_v1';

function uid() { return 'R' + Date.now().toString(36) + Math.random().toString(36).slice(2, 7); }
function todayStr(offsetDays = 0) {
  const d = new Date();
  d.setDate(d.getDate() + offsetDays);
  return d.toISOString().slice(0, 10);
}
function fmtMoney(n) { return (Math.round((n + Number.EPSILON) * 100) / 100).toFixed(2); }
function sum(arr) { return arr.reduce((a, b) => a + b, 0); }

class HCApp {
  constructor() {
    this.state = this.loadState();
    this.undoStack = [];
    this.editingId = null;
    this.selectedIds = new Set();
    this.currentTab = 'today';
    this.init();
  }

  /* ---------------- 数据持久化 ---------------- */
  loadState() {
    let raw = null;
    try { raw = JSON.parse(localStorage.getItem(LS_KEY)); } catch (e) { raw = null; }
    if (!raw) {
      raw = {
        types: JSON.parse(JSON.stringify(DEFAULT_TYPES)),
        prices: JSON.parse(JSON.stringify(DEFAULT_PRICES)),
        records: [],
        profile: { name: '', car: '', site: '' },
        salary: { base: 0, meal: 0, night: 0, bonus: 0, deduct: 0 },
        cfg: {
          theme: 'system', tint: '#007AFF', hideAmt: false,
          dayGoal: 0, moGoal: 0, defName: '', defCar: '', lastShift: 'day',
        },
      };
    }
    // 兼容旧字段/缺省字段修复
    raw.types = raw.types || JSON.parse(JSON.stringify(DEFAULT_TYPES));
    raw.prices = raw.prices || JSON.parse(JSON.stringify(DEFAULT_PRICES));
    raw.records = raw.records || [];
    raw.profile = raw.profile || { name: '', car: '', site: '' };
    raw.salary = raw.salary || { base: 0, meal: 0, night: 0, bonus: 0, deduct: 0 };
    raw.cfg = raw.cfg || {};
    raw.cfg.theme = raw.cfg.theme || 'system';
    raw.cfg.tint = raw.cfg.tint || '#007AFF';
    raw.cfg.hideAmt = !!raw.cfg.hideAmt;
    raw.cfg.dayGoal = raw.cfg.dayGoal || 0;
    raw.cfg.moGoal = raw.cfg.moGoal || 0;
    raw.cfg.lastShift = raw.cfg.lastShift || 'day';
    return raw;
  }

  save(pushUndo = true) {
    if (pushUndo) this.pushUndo();
    localStorage.setItem(LS_KEY, JSON.stringify(this.state));
    this.maybeDailyBackup();
  }

  pushUndo() {
    const snap = JSON.stringify({ types: this.state.types, prices: this.state.prices, records: this.state.records });
    this.undoStack.push(snap);
    if (this.undoStack.length > 30) this.undoStack.shift();
  }

  undo() {
    if (!this.undoStack.length) { this.toast('没有可撤销的操作'); return; }
    const snap = JSON.parse(this.undoStack.pop());
    this.state.types = snap.types;
    this.state.prices = snap.prices;
    this.state.records = snap.records;
    localStorage.setItem(LS_KEY, JSON.stringify(this.state));
    this.toast('已撤销');
    this.renderAll();
  }

  maybeDailyBackup() {
    let backups = {};
    try { backups = JSON.parse(localStorage.getItem(LS_BACKUP_KEY)) || {}; } catch (e) { backups = {}; }
    const today = todayStr();
    if (!backups[today]) {
      backups[today] = { records: this.state.records, profile: this.state.profile, at: Date.now() };
      const keys = Object.keys(backups).sort();
      while (keys.length > 7) { delete backups[keys.shift()]; }
      localStorage.setItem(LS_BACKUP_KEY, JSON.stringify(backups));
    }
  }

  /* ---------------- 初始化 ---------------- */
  init() {
    this.applyTheme();
    this.bindTabbar();
    this.bindTodayTab();
    this.bindDetailTab();
    this.bindReportTab();
    this.bindSettingsTab();
    this.bindSheetOverlay();
    document.addEventListener('keydown', (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z') { e.preventDefault(); this.undo(); }
    });
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => this.applyTheme());
    this.renderAll();
  }

  applyTheme() {
    const mode = this.state.cfg.theme;
    let dark = false;
    if (mode === 'dark') dark = true;
    else if (mode === 'system') dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
    document.documentElement.style.setProperty('--blue', this.state.cfg.tint || '#007AFF');
  }

  renderAll() {
    document.getElementById('siteSubtitle').textContent = this.state.profile.site || '未设置货场名称';
    this.renderToday();
    this.renderDetail();
    this.renderReport();
    this.renderSettings();
  }

  /* ---------------- Tab 切换 ---------------- */
  bindTabbar() {
    document.querySelectorAll('.tab-item').forEach((el) => {
      el.addEventListener('click', () => this.switchTab(el.dataset.tab));
    });
  }
  switchTab(tab) {
    this.currentTab = tab;
    document.querySelectorAll('.tab-item').forEach((el) => el.classList.toggle('active', el.dataset.tab === tab));
    document.querySelectorAll('.tab-panel').forEach((el) => el.classList.remove('active'));
    document.getElementById('tab-' + tab).classList.add('active');
    if (tab === 'detail') this.renderDetail();
    if (tab === 'report') this.renderReport();
  }

  /* ---------------- 通用：Toast / Sheet ---------------- */
  toast(msg, opts = {}) {
    const el = document.getElementById('toast');
    el.innerHTML = msg + (opts.undo ? ' <span class="undo-btn" id="toastUndo">撤销</span>' : '');
    el.classList.add('show');
    if (opts.undo) {
      document.getElementById('toastUndo').onclick = () => { opts.undo(); el.classList.remove('show'); };
    }
    clearTimeout(this._toastTimer);
    this._toastTimer = setTimeout(() => el.classList.remove('show'), opts.undo ? 4000 : 3500);
  }

  bindSheetOverlay() {
    document.getElementById('sheetOverlay').addEventListener('click', (e) => {
      if (e.target.id === 'sheetOverlay') this.closeSheet();
    });
  }
  openSheet(html) {
    document.getElementById('sheetContent').innerHTML = html;
    document.getElementById('sheetOverlay').classList.add('show');
  }
  closeSheet() { document.getElementById('sheetOverlay').classList.remove('show'); }

  confirmSheet(title, onConfirm, confirmLabel = '确认删除') {
    this.openSheet(`
      <div class="sheet-title">${title}</div>
      <div class="sheet-actions">
        <button class="btn secondary block" id="sheetCancel">取消</button>
        <button class="btn danger block" id="sheetConfirm">${confirmLabel}</button>
      </div>
    `);
    document.getElementById('sheetCancel').onclick = () => this.closeSheet();
    document.getElementById('sheetConfirm').onclick = () => { onConfirm(); this.closeSheet(); };
  }

  /* ============================================================
     今日 Tab
     ============================================================ */
  bindTodayTab() {
    document.getElementById('f_date').value = todayStr();
    document.querySelectorAll('#f_shift .seg-item').forEach((el) => {
      el.addEventListener('click', () => {
        document.querySelectorAll('#f_shift .seg-item').forEach((s) => s.classList.remove('active'));
        el.classList.add('active');
      });
    });
    document.getElementById('f_name').value = this.state.profile.name || '';
    document.getElementById('f_car').value = this.state.profile.car || '';
    this.setShiftUI(this.state.cfg.lastShift);

    document.getElementById('saveBtn').addEventListener('click', () => this.saveTodayRecord());
    document.getElementById('cancelEditBtn').addEventListener('click', () => this.cancelEdit());
    document.getElementById('copyYesterdayBtn').addEventListener('click', () => this.copyYesterday());
  }

  setShiftUI(val) {
    document.querySelectorAll('#f_shift .seg-item').forEach((s) => s.classList.toggle('active', s.dataset.val === val));
  }
  getShiftUI() {
    return document.querySelector('#f_shift .seg-item.active').dataset.val;
  }

  renderStepperList(counts = {}) {
    const wrap = document.getElementById('stepperList');
    wrap.innerHTML = this.state.types.map((t) => {
      const price = this.state.prices[t.id] || 0;
      const c = counts[t.id] || 0;
      return `
      <div class="stepper-row" data-type="${t.id}">
        <div class="type-dot" style="background:${t.color}"></div>
        <div class="type-info">
          <div class="type-name">${t.name}</div>
          <div class="type-price">¥${fmtMoney(price)}/车</div>
        </div>
        <div class="stepper-ctrl">
          <button class="step-btn quick" data-op="+5">+5</button>
          <button class="step-btn quick" data-op="+10">+10</button>
          <button class="step-btn minus" data-op="-1">−</button>
          <input class="step-input" type="number" value="${c}" data-type="${t.id}">
          <button class="step-btn plus" data-op="+1">+</button>
        </div>
      </div>`;
    }).join('') || '<div class="empty-hint">暂无作业类型，请前往设置添加</div>';

    wrap.querySelectorAll('.stepper-row').forEach((row) => {
      const typeId = row.dataset.type;
      const input = row.querySelector('.step-input');
      const apply = (delta) => {
        let v = parseInt(input.value || '0', 10) + delta;
        if (v < 0) v = 0;
        input.value = v;
        this.updateSaveBtnTotal();
      };
      row.querySelectorAll('.step-btn').forEach((btn) => {
        const op = btn.dataset.op;
        const delta = op === '-1' ? -1 : op === '+1' ? 1 : op === '+5' ? 5 : 10;
        let timer = null, interval = null;
        const start = (e) => {
          e.preventDefault();
          apply(delta);
          timer = setTimeout(() => {
            interval = setInterval(() => apply(delta), 100);
          }, 400);
        };
        const stop = () => { clearTimeout(timer); clearInterval(interval); };
        btn.addEventListener('mousedown', start);
        btn.addEventListener('touchstart', start, { passive: false });
        ['mouseup', 'mouseleave', 'touchend', 'touchcancel'].forEach((ev) => btn.addEventListener(ev, stop));
      });
      input.addEventListener('input', () => this.updateSaveBtnTotal());
      let lastTap = 0;
      input.addEventListener('touchend', () => {
        const now = Date.now();
        if (now - lastTap < 300) { input.value = 0; this.updateSaveBtnTotal(); }
        lastTap = now;
      });
      input.addEventListener('dblclick', () => { input.value = 0; this.updateSaveBtnTotal(); });
    });
    this.updateSaveBtnTotal();
  }

  getCurrentCounts() {
    const counts = {};
    document.querySelectorAll('#stepperList .step-input').forEach((inp) => {
      const v = parseInt(inp.value || '0', 10);
      if (v > 0) counts[inp.dataset.type] = v;
    });
    return counts;
  }

  calcAmount(counts) {
    return sum(Object.keys(counts).map((tid) => (counts[tid] || 0) * (this.state.prices[tid] || 0)));
  }

  updateSaveBtnTotal() {
    const counts = this.getCurrentCounts();
    const amt = this.calcAmount(counts);
    document.getElementById('saveBtn').textContent = `保存 · ¥${fmtMoney(amt)}`;
  }

  saveTodayRecord() {
    const date = document.getElementById('f_date').value || todayStr();
    const name = document.getElementById('f_name').value.trim();
    const car = document.getElementById('f_car').value.trim();
    const shift = this.getShiftUI();
    const counts = this.getCurrentCounts();

    if (!name) { this.toast('请输入姓名'); return; }
    if (Object.keys(counts).length === 0) { this.toast('请至少录入一项作业车数'); return; }

    this.state.cfg.lastShift = shift;

    if (this.editingId) {
      const rec = this.state.records.find((r) => r.id === this.editingId);
      if (rec) {
        rec.versions = rec.versions || [];
        rec.versions.push({ counts: rec.counts, note: rec.note, at: Date.now() });
        rec.date = date; rec.name = name; rec.car = car; rec.shift = shift;
        rec.counts = counts; rec.upd = Date.now();
      }
      this.editingId = null;
      document.getElementById('editBanner').style.display = 'none';
      this.toast('已更新记录');
    } else {
      const existing = this.state.records.find(
        (r) => r.date === date && r.name === name && r.car === car && r.shift === shift
      );
      if (existing) {
        Object.keys(counts).forEach((tid) => {
          existing.counts[tid] = (existing.counts[tid] || 0) + counts[tid];
        });
        existing.upd = Date.now();
        this.toast('已累加到现有记录');
      } else {
        this.state.records.unshift({
          id: uid(), date, name, car, shift, counts, note: '', versions: [], upd: Date.now(),
        });
        this.toast('已保存记录');
      }
    }
    this.save();
    this.renderStepperList({});
    this.renderToday();
    this.renderDetail();
    this.renderReport();
  }

  editRecord(id) {
    const rec = this.state.records.find((r) => r.id === id);
    if (!rec) return;
    this.editingId = id;
    document.getElementById('f_date').value = rec.date;
    document.getElementById('f_name').value = rec.name;
    document.getElementById('f_car').value = rec.car;
    this.setShiftUI(rec.shift);
    this.renderStepperList(rec.counts);
    document.getElementById('editBanner').style.display = 'flex';
    this.switchTab('today');
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  cancelEdit() {
    this.editingId = null;
    document.getElementById('editBanner').style.display = 'none';
    document.getElementById('f_date').value = todayStr();
    document.getElementById('f_name').value = this.state.profile.name || '';
    document.getElementById('f_car').value = this.state.profile.car || '';
    this.renderStepperList({});
  }

  deleteRecord(id, refreshFns) {
    const idx = this.state.records.findIndex((r) => r.id === id);
    if (idx === -1) return;
    const removed = this.state.records[idx];
    this.pushUndo();
    this.state.records.splice(idx, 1);
    localStorage.setItem(LS_KEY, JSON.stringify(this.state));
    this.toast('已删除记录', {
      undo: () => {
        this.state.records.splice(idx, 0, removed);
        localStorage.setItem(LS_KEY, JSON.stringify(this.state));
        refreshFns.forEach((f) => f());
      },
    });
    refreshFns.forEach((f) => f());
  }

  recordsForDate(date) { return this.state.records.filter((r) => r.date === date); }

  renderToday() {
    const date = todayStr();
    const recs = this.recordsForDate(date);
    const dayRecs = recs.filter((r) => r.shift === 'day');
    const nightRecs = recs.filter((r) => r.shift === 'night');
    const countOf = (r) => sum(Object.values(r.counts));
    const totalCount = sum(recs.map(countOf));
    const dayCount = sum(dayRecs.map(countOf));
    const nightCount = sum(nightRecs.map(countOf));
    const totalIncome = sum(recs.map((r) => this.calcAmount(r.counts)));

    document.getElementById('todayCount').textContent = totalCount;
    document.getElementById('todayShiftBreak').textContent = `白 ${dayCount} · 夜 ${nightCount}`;
    document.getElementById('todayIncome').textContent = '¥' + fmtMoney(totalIncome);

    const goal = this.state.cfg.dayGoal || 0;
    const pct = goal > 0 ? Math.min(100, Math.round((totalCount / goal) * 100)) : 0;
    document.getElementById('goalBar').style.width = pct + '%';
    document.getElementById('goalText').textContent = goal > 0 ? `目标 ${goal} 车 · 已完成 ${pct}%` : '未设置日目标';

    const yDate = todayStr(-1);
    const yRecs = this.recordsForDate(yDate);
    const yCount = sum(yRecs.map(countOf));
    const yIncome = sum(yRecs.map((r) => this.calcAmount(r.counts)));
    document.getElementById('yesterdaySum').textContent = `昨日：${yCount}车 / ¥${fmtMoney(yIncome)}`;

    // 昨天各类型明细
    const typeTotals = {};
    yRecs.forEach((r) => Object.keys(r.counts).forEach((tid) => {
      typeTotals[tid] = (typeTotals[tid] || 0) + r.counts[tid];
    }));
    const yDetailEl = document.getElementById('yesterdayDetail');
    const rows = this.state.types.filter((t) => typeTotals[t.id]).map((t) => {
      const c = typeTotals[t.id];
      const amt = c * (this.state.prices[t.id] || 0);
      return `<div class="row" style="padding:6px 0;">
        <span><span class="type-dot" style="display:inline-block;background:${t.color};margin-right:6px;"></span>${t.name}</span>
        <span>${c}车 · ¥${fmtMoney(amt)}</span>
      </div>`;
    }).join('');
    yDetailEl.innerHTML = rows || '<div class="empty-hint">昨天暂无记录</div>';

    // 今日记录列表
    document.getElementById('todayRecCount').textContent = recs.length;
    const listEl = document.getElementById('todayRecords');
    listEl.innerHTML = recs.map((r) => this.renderRecordItem(r, { editable: true })).join('') ||
      '<div class="empty-hint">今日暂无记录</div>';
    listEl.querySelectorAll('[data-edit]').forEach((el) => el.addEventListener('click', () => this.editRecord(el.dataset.edit)));
    listEl.querySelectorAll('[data-del]').forEach((el) => el.addEventListener('click', () => {
      this.confirmSheet('确认删除这条记录？', () => this.deleteRecord(el.dataset.del, [() => this.renderToday(), () => this.renderDetail(), () => this.renderReport()]));
    }));

    if (this.editingId) this.renderStepperList((this.state.records.find(r => r.id === this.editingId) || {}).counts || {});
  }

  renderRecordItem(r, opts = {}) {
    const amt = this.calcAmount(r.counts);
    const cnt = sum(Object.values(r.counts));
    const hide = this.state.cfg.hideAmt;
    const detail = this.state.types.filter((t) => r.counts[t.id]).map((t) => `${t.name} ${r.counts[t.id]}`).join(' · ');
    const checkbox = opts.selectable ? `<input type="checkbox" class="record-checkbox" data-sel="${r.id}" ${this.selectedIds.has(r.id) ? 'checked' : ''}>` : '';
    return `
    <div class="record-item">
      <div class="record-top">
        <div>${checkbox}<span class="record-name">${r.name || '未命名'}</span><span class="shift-tag ${r.shift}">${r.shift === 'day' ? '白班' : '夜班'}</span></div>
        <div class="record-amount ${hide ? 'hidden-amt' : ''}">${hide ? '¥•••' : '¥' + fmtMoney(amt)}</div>
      </div>
      <div class="record-meta">${r.date} · 车号 ${r.car || '-'} · 共 ${hide ? '••' : cnt} 车</div>
      <div class="record-meta">${detail || '-'}${r.note ? ' · 备注：' + r.note : ''}</div>
      ${opts.editable ? `<div class="record-actions"><span data-edit="${r.id}">编辑</span><span class="del" data-del="${r.id}">删除</span></div>` : ''}
    </div>`;
  }

  copyYesterday() {
    const yRecs = this.recordsForDate(todayStr(-1));
    if (!yRecs.length) { this.toast('昨天没有记录可复制'); return; }
    const names = [...new Set(yRecs.map((r) => r.name))];
    const options = ['全部人员', ...names];
    this.openSheet(`
      <div class="sheet-title">复制昨日数据</div>
      <div class="chip-row">${options.map((n, i) => `<div class="chip ${i === 0 ? 'active' : ''}" data-name="${i === 0 ? '' : n}">${n}</div>`).join('')}</div>
      <div class="sheet-actions">
        <button class="btn secondary block" id="sheetCancel">取消</button>
        <button class="btn block" id="doCopy">复制</button>
      </div>
    `);
    let selName = '';
    document.querySelectorAll('#sheetContent .chip').forEach((c) => c.addEventListener('click', () => {
      document.querySelectorAll('#sheetContent .chip').forEach((x) => x.classList.remove('active'));
      c.classList.add('active');
      selName = c.dataset.name;
    }));
    document.getElementById('sheetCancel').onclick = () => this.closeSheet();
    document.getElementById('doCopy').onclick = () => {
      const targets = selName ? yRecs.filter((r) => r.name === selName) : yRecs;
      const today = todayStr();
      this.pushUndo();
      targets.forEach((r) => {
        this.state.records.unshift({ ...r, id: uid(), date: today, upd: Date.now(), versions: [] });
      });
      this.save(false);
      this.toast(`已复制 ${targets.length} 条记录到今天`);
      this.closeSheet();
      this.renderAll();
    };
  }

  /* ============================================================
     明细 Tab
     ============================================================ */
  bindDetailTab() {
    document.getElementById('rangeStart').value = todayStr();
    document.getElementById('rangeEnd').value = todayStr();
    document.querySelectorAll('#quickFilters .chip').forEach((chip) => {
      chip.addEventListener('click', () => {
        document.querySelectorAll('#quickFilters .chip').forEach((c) => c.classList.remove('active'));
        chip.classList.add('active');
        this.applyQuickRange(chip.dataset.range);
        this.renderDetail();
      });
    });
    document.querySelectorAll('#filterShift .seg-item').forEach((el) => {
      el.addEventListener('click', () => {
        document.querySelectorAll('#filterShift .seg-item').forEach((s) => s.classList.remove('active'));
        el.classList.add('active');
        this.renderDetail();
      });
    });
    ['rangeStart', 'rangeEnd', 'searchKw', 'sortOrder'].forEach((id) => {
      document.getElementById(id).addEventListener('input', () => this.renderDetail());
      document.getElementById(id).addEventListener('change', () => this.renderDetail());
    });
    document.getElementById('exportCsvBtn').addEventListener('click', () => this.exportRecordsCsv(this.getFilteredRecords()));
    document.getElementById('batchExport').addEventListener('click', () => {
      const recs = this.state.records.filter((r) => this.selectedIds.has(r.id));
      this.exportRecordsCsv(recs);
    });
    document.getElementById('batchDelete').addEventListener('click', () => {
      this.confirmSheet(`确认删除已选中的 ${this.selectedIds.size} 条记录？`, () => {
        this.pushUndo();
        this.state.records = this.state.records.filter((r) => !this.selectedIds.has(r.id));
        this.selectedIds.clear();
        this.save(false);
        this.renderAll();
      });
    });
    document.getElementById('batchCancel').addEventListener('click', () => { this.selectedIds.clear(); this.renderDetail(); });
  }

  applyQuickRange(range) {
    const today = todayStr();
    if (range === 'today') {
      document.getElementById('rangeStart').value = today;
      document.getElementById('rangeEnd').value = today;
    } else if (range === '7d') {
      document.getElementById('rangeStart').value = todayStr(-6);
      document.getElementById('rangeEnd').value = today;
    } else if (range === 'month') {
      const d = new Date();
      document.getElementById('rangeStart').value = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-01`;
      document.getElementById('rangeEnd').value = today;
    } else if (range === 'lastmonth') {
      const d = new Date();
      d.setDate(1); d.setMonth(d.getMonth() - 1);
      const start = new Date(d);
      const end = new Date(d.getFullYear(), d.getMonth() + 1, 0);
      document.getElementById('rangeStart').value = start.toISOString().slice(0, 10);
      document.getElementById('rangeEnd').value = end.toISOString().slice(0, 10);
    }
  }

  getFilteredRecords() {
    const start = document.getElementById('rangeStart').value;
    const end = document.getElementById('rangeEnd').value;
    const shift = document.querySelector('#filterShift .seg-item.active').dataset.val;
    const kw = document.getElementById('searchKw').value.trim().toLowerCase();
    const order = document.getElementById('sortOrder').value;
    let recs = this.state.records.filter((r) => (!start || r.date >= start) && (!end || r.date <= end));
    if (shift !== 'all') recs = recs.filter((r) => r.shift === shift);
    if (kw) recs = recs.filter((r) => (r.name || '').toLowerCase().includes(kw) || (r.car || '').toLowerCase().includes(kw));
    recs = recs.slice().sort((a, b) => order === 'asc' ? a.date.localeCompare(b.date) : b.date.localeCompare(a.date));
    return recs;
  }

  renderDetail() {
    // 近7天矩阵
    const matrixEl = document.getElementById('matrix7');
    let rowsHtml = '';
    for (let i = 0; i >= -6; i--) {
      const date = todayStr(i);
      const recs = this.recordsForDate(date);
      const typeTotals = {};
      recs.forEach((r) => Object.keys(r.counts).forEach((tid) => { typeTotals[tid] = (typeTotals[tid] || 0) + r.counts[tid]; }));
      const total = sum(Object.values(typeTotals));
      const detail = this.state.types.filter((t) => typeTotals[t.id]).map((t) => `${t.name} ${typeTotals[t.id]}`).join(' · ') || '无记录';
      rowsHtml += `<div class="day-matrix-row"><div class="day-matrix-head"><span>${date}</span><span>${total}车</span></div><div class="day-matrix-types">${detail}</div></div>`;
    }
    matrixEl.innerHTML = rowsHtml;

    // 筛选记录
    const recs = this.getFilteredRecords();
    const totalCount = sum(recs.map((r) => sum(Object.values(r.counts))));
    const totalAmt = sum(recs.map((r) => this.calcAmount(r.counts)));
    document.getElementById('sumCount').textContent = totalCount;
    document.getElementById('sumAmount').textContent = fmtMoney(totalAmt);

    const listEl = document.getElementById('detailRecords');
    listEl.innerHTML = recs.map((r) => this.renderRecordItem(r, { editable: true, selectable: true })).join('') ||
      '<div class="empty-hint">暂无符合条件的记录</div>';
    listEl.querySelectorAll('[data-edit]').forEach((el) => el.addEventListener('click', () => this.editRecord(el.dataset.edit)));
    listEl.querySelectorAll('[data-del]').forEach((el) => el.addEventListener('click', () => {
      this.confirmSheet('确认删除这条记录？', () => this.deleteRecord(el.dataset.del, [() => this.renderDetail(), () => this.renderToday(), () => this.renderReport()]));
    }));
    listEl.querySelectorAll('[data-sel]').forEach((el) => el.addEventListener('change', () => {
      if (el.checked) this.selectedIds.add(el.dataset.sel); else this.selectedIds.delete(el.dataset.sel);
      this.updateBatchBar();
    }));
    this.updateBatchBar();
  }

  updateBatchBar() {
    const bar = document.getElementById('batchBar');
    if (this.selectedIds.size > 0) {
      bar.style.display = 'flex';
      document.getElementById('batchCount').textContent = this.selectedIds.size;
    } else {
      bar.style.display = 'none';
    }
  }

  csvEscape(v) { return `"${String(v ?? '').replace(/"/g, '""')}"`; }

  exportRecordsCsv(recs) {
    if (!recs.length) { this.toast('没有可导出的数据'); return; }
    const typeNames = this.state.types.map((t) => t.name);
    const header = ['日期', '班次', '姓名', '车号', ...typeNames, '总车数', '金额', '备注'];
    const lines = [header.map((h) => this.csvEscape(h)).join(',')];
    recs.forEach((r) => {
      const cnt = sum(Object.values(r.counts));
      const amt = this.calcAmount(r.counts);
      const row = [
        r.date, r.shift === 'day' ? '白班' : '夜班', r.name, r.car,
        ...this.state.types.map((t) => r.counts[t.id] || 0),
        cnt, fmtMoney(amt), r.note || '',
      ];
      lines.push(row.map((v) => this.csvEscape(v)).join(','));
    });
    this.downloadFile(`货场记账_${todayStr()}.csv`, '\uFEFF' + lines.join('\n'), 'text/csv');
  }

  // UTF-8 安全的 base64 编码（CSV/JSON 含中文，不能直接用 btoa）
  btoaUnicode(str) {
    return btoa(unescape(encodeURIComponent(str)));
  }

  async downloadFile(filename, content, mime) {
    // 在 Capacitor Android WebView 中，浏览器式的 a.download 下载不会触发保存，
    // 因此优先改用系统分享（@capacitor/share），由用户选择保存到 Download / 微信 等。
    try {
      if (window.Capacitor && Capacitor.Plugins && Capacitor.Plugins.Share) {
        const dataUrl = 'data:' + mime + ';base64,' + this.btoaUnicode(content);
        await Capacitor.Plugins.Share.share({ title: filename, files: [dataUrl] });
        this.toast('已导出：' + filename);
        return;
      }
    } catch (e) {
      // 用户取消分享或分享失败，降级到浏览器下载
    }
    // 浏览器 / 桌面降级方案
    try {
      const blob = new Blob([content], { type: mime });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url; a.download = filename;
      document.body.appendChild(a); a.click(); document.body.removeChild(a);
      setTimeout(() => URL.revokeObjectURL(url), 2000);
      this.toast('已导出：' + filename);
    } catch (e) {
      this.toast('导出失败：' + e.message);
    }
  }

  /* ============================================================
     月报 Tab
     ============================================================ */
  bindReportTab() {
    const d = new Date();
    document.getElementById('reportMonth').value = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    document.getElementById('reportMonth').addEventListener('change', () => this.renderReport());
    document.getElementById('reportPerson').addEventListener('change', () => this.renderReport());
    document.getElementById('exportMonthCsv').addEventListener('click', () => this.exportRecordsCsv(this.getMonthRecords()));
    document.getElementById('exportPayrollCsv').addEventListener('click', () => this.exportPayrollCsv());
  }

  getMonthRecords() {
    const ym = document.getElementById('reportMonth').value || `${todayStr().slice(0, 7)}`;
    const person = document.getElementById('reportPerson').value;
    let recs = this.state.records.filter((r) => r.date.startsWith(ym));
    if (person) recs = recs.filter((r) => r.name === person);
    return recs;
  }

  renderReport() {
    // 人员下拉
    const allNames = [...new Set(this.state.records.map((r) => r.name).filter(Boolean))].sort();
    const personSel = document.getElementById('reportPerson');
    const curVal = personSel.value;
    personSel.innerHTML = '<option value="">全部人员</option>' + allNames.map((n) => `<option value="${n}">${n}</option>`).join('');
    personSel.value = allNames.includes(curVal) ? curVal : '';

    const recs = this.getMonthRecords();
    const hide = this.state.cfg.hideAmt;

    // 按单价分组
    const priceGroups = {};
    recs.forEach((r) => {
      Object.keys(r.counts).forEach((tid) => {
        const price = this.state.prices[tid] || 0;
        priceGroups[price] = priceGroups[price] || { total: 0, day: 0, night: 0 };
        priceGroups[price].total += r.counts[tid];
        priceGroups[price][r.shift] += r.counts[tid];
      });
    });
    const priceKeys = Object.keys(priceGroups).map(Number).sort((a, b) => a - b);
    document.getElementById('priceSummary').innerHTML = priceKeys.map((p) => {
      const g = priceGroups[p];
      return `<div class="row" style="padding:6px 0;"><span>单价 ¥${fmtMoney(p)}</span><span>${g.total}车（白${g.day}/夜${g.night}）</span></div>`;
    }).join('') || '<div class="empty-hint">本月暂无数据</div>';

    const pieceIncome = sum(recs.map((r) => this.calcAmount(r.counts)));
    const sal = this.state.salary;
    const totalSalary = pieceIncome + (+sal.base || 0) + (+sal.meal || 0) + (+sal.night || 0) + (+sal.bonus || 0) - (+sal.deduct || 0);
    document.getElementById('pieceIncome').textContent = hide ? '¥•••' : '¥' + fmtMoney(pieceIncome);
    document.getElementById('totalSalary').textContent = hide ? '¥•••' : '¥' + fmtMoney(totalSalary);

    // 每日柱状图
    const ym = document.getElementById('reportMonth').value || todayStr().slice(0, 7);
    const [yy, mm] = ym.split('-').map(Number);
    const daysInMonth = new Date(yy, mm, 0).getDate();
    const dailyCounts = new Array(daysInMonth + 1).fill(0);
    recs.forEach((r) => {
      const day = parseInt(r.date.slice(8, 10), 10);
      dailyCounts[day] += sum(Object.values(r.counts));
    });
    const maxCount = Math.max(1, ...dailyCounts);
    let barsHtml = '';
    for (let day = 1; day <= daysInMonth; day++) {
      const h = Math.round((dailyCounts[day] / maxCount) * 100);
      barsHtml += `<div class="bar-col"><div class="bar" style="height:${h}%;" title="${day}日：${dailyCounts[day]}车"></div><div class="bar-label">${day}</div></div>`;
    }
    document.getElementById('barChart').innerHTML = barsHtml;

    // 作业类型分布
    const typeTotals = {};
    recs.forEach((r) => Object.keys(r.counts).forEach((tid) => { typeTotals[tid] = (typeTotals[tid] || 0) + r.counts[tid]; }));
    document.getElementById('typeDist').innerHTML = this.state.types.map((t) => {
      const c = typeTotals[t.id] || 0;
      const amt = c * (this.state.prices[t.id] || 0);
      return `<div class="row" style="padding:6px 0;"><span><span class="type-dot" style="display:inline-block;background:${t.color};margin-right:6px;"></span>${t.name}</span><span>${c}车 · ¥${fmtMoney(amt)}</span></div>`;
    }).join('') || '<div class="empty-hint">本月暂无数据</div>';

    // 按人员统计
    const personMap = {};
    recs.forEach((r) => {
      personMap[r.name] = personMap[r.name] || { total: 0, day: 0, night: 0, amt: 0 };
      const c = sum(Object.values(r.counts));
      personMap[r.name].total += c;
      personMap[r.name][r.shift] += c;
      personMap[r.name].amt += this.calcAmount(r.counts);
    });
    const personRows = Object.keys(personMap).sort((a, b) => personMap[b].total - personMap[a].total).map((name) => {
      const p = personMap[name];
      return `<div class="row" style="padding:6px 0;"><span>${name}</span><span>${p.total}车（白${p.day}/夜${p.night}） · ¥${fmtMoney(p.amt)}</span></div>`;
    }).join('');
    document.getElementById('personStats').innerHTML = personRows || '<div class="empty-hint">本月暂无数据</div>';
  }

  exportPayrollCsv() {
    const recs = this.getMonthRecords();
    if (!recs.length) { this.toast('本月暂无数据'); return; }
    const personMap = {};
    recs.forEach((r) => {
      personMap[r.name] = personMap[r.name] || 0;
      personMap[r.name] += this.calcAmount(r.counts);
    });
    const sal = this.state.salary;
    const header = ['姓名', '计件', '底薪', '餐补', '加班', '工龄奖', '扣款', '应发工资'];
    const lines = [header.map((h) => this.csvEscape(h)).join(',')];
    Object.keys(personMap).forEach((name) => {
      const piece = personMap[name];
      const total = piece + (+sal.base || 0) + (+sal.meal || 0) + (+sal.night || 0) + (+sal.bonus || 0) - (+sal.deduct || 0);
      const row = [name, fmtMoney(piece), sal.base || 0, sal.meal || 0, sal.night || 0, sal.bonus || 0, sal.deduct || 0, fmtMoney(total)];
      lines.push(row.map((v) => this.csvEscape(v)).join(','));
    });
    this.downloadFile(`工资单_${document.getElementById('reportMonth').value}.csv`, '\uFEFF' + lines.join('\n'), 'text/csv');
  }

  /* ============================================================
     设置 Tab
     ============================================================ */
  bindSettingsTab() {
    ['s_name', 's_car', 's_site'].forEach((id) => {
      document.getElementById(id).addEventListener('change', (e) => {
        const key = id.replace('s_', '');
        this.state.profile[key] = e.target.value;
        this.save(false);
        document.getElementById('siteSubtitle').textContent = this.state.profile.site || '未设置货场名称';
      });
    });
    ['sal_base', 'sal_meal', 'sal_night', 'sal_bonus', 'sal_deduct'].forEach((id) => {
      document.getElementById(id).addEventListener('change', (e) => {
        const key = id.replace('sal_', '');
        this.state.salary[key] = +e.target.value || 0;
        this.save(false);
        this.renderReport();
      });
    });
    document.getElementById('goal_day').addEventListener('change', (e) => {
      this.state.cfg.dayGoal = +e.target.value || 0; this.save(false); this.renderToday();
    });
    document.getElementById('goal_month').addEventListener('change', (e) => {
      this.state.cfg.moGoal = +e.target.value || 0; this.save(false);
    });
    document.getElementById('hideAmtSwitch').addEventListener('change', (e) => {
      this.state.cfg.hideAmt = e.target.checked; this.save(false); this.renderAll();
    });
    document.getElementById('themeMode').addEventListener('change', (e) => {
      this.state.cfg.theme = e.target.value; this.save(false); this.applyTheme();
    });
    document.getElementById('addTypeBtn').addEventListener('click', () => this.addType());

    document.getElementById('exportJsonBtn').addEventListener('click', () => this.exportJson());
    document.getElementById('exportCsvBtn2').addEventListener('click', () => this.exportRecordsCsv(this.state.records));
    document.getElementById('importJsonBtn').addEventListener('click', () => this.triggerImport('json'));
    document.getElementById('importCsvBtn').addEventListener('click', () => this.triggerImport('csv'));
    document.getElementById('loadSampleBtn').addEventListener('click', () => this.loadSampleData());
    document.getElementById('clearAllBtn').addEventListener('click', () => this.clearAllData());
    document.getElementById('fileInput').addEventListener('change', (e) => this.handleFileImport(e));
  }

  renderSettings() {
    document.getElementById('s_name').value = this.state.profile.name || '';
    document.getElementById('s_car').value = this.state.profile.car || '';
    document.getElementById('s_site').value = this.state.profile.site || '';
    document.getElementById('sal_base').value = this.state.salary.base || '';
    document.getElementById('sal_meal').value = this.state.salary.meal || '';
    document.getElementById('sal_night').value = this.state.salary.night || '';
    document.getElementById('sal_bonus').value = this.state.salary.bonus || '';
    document.getElementById('sal_deduct').value = this.state.salary.deduct || '';
    document.getElementById('goal_day').value = this.state.cfg.dayGoal || '';
    document.getElementById('goal_month').value = this.state.cfg.moGoal || '';
    document.getElementById('hideAmtSwitch').checked = !!this.state.cfg.hideAmt;
    document.getElementById('themeMode').value = this.state.cfg.theme || 'system';

    const colorPicker = document.getElementById('colorPicker');
    colorPicker.innerHTML = TINT_COLORS.map((c) =>
      `<div class="color-dot ${this.state.cfg.tint === c ? 'selected' : ''}" data-color="${c}" style="background:${c}"></div>`
    ).join('');
    colorPicker.querySelectorAll('.color-dot').forEach((dot) => dot.addEventListener('click', () => {
      this.state.cfg.tint = dot.dataset.color;
      this.save(false);
      this.applyTheme();
      this.renderSettings();
    }));

    const typeList = document.getElementById('typeManageList');
    typeList.innerHTML = this.state.types.map((t) => `
      <div class="type-manage-row" data-tid="${t.id}">
        <span class="type-dot" style="background:${t.color}"></span>
        <input type="text" class="tname" value="${t.name}">
        <input type="number" class="tprice" value="${this.state.prices[t.id] || 0}" style="max-width:80px;">
        <div class="icon-btn" data-deltype="${t.id}">✕</div>
      </div>`).join('') || '<div class="empty-hint">暂无作业类型</div>';

    typeList.querySelectorAll('.type-manage-row').forEach((row) => {
      const tid = row.dataset.tid;
      row.querySelector('.tname').addEventListener('change', (e) => {
        const t = this.state.types.find((x) => x.id === tid);
        if (t) { t.name = e.target.value; this.save(false); this.renderStepperListIfIdle(); }
      });
      row.querySelector('.tprice').addEventListener('change', (e) => {
        this.state.prices[tid] = +e.target.value || 0;
        this.save(false);
        this.renderStepperListIfIdle();
        this.renderReport();
      });
    });
    typeList.querySelectorAll('[data-deltype]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const tid = btn.dataset.deltype;
        this.confirmSheet('删除该作业类型？已有记录中的数据不会被删除。', () => {
          this.state.types = this.state.types.filter((t) => t.id !== tid);
          delete this.state.prices[tid];
          this.save(false);
          this.renderSettings();
          this.renderStepperListIfIdle();
        });
      });
    });
  }

  renderStepperListIfIdle() {
    if (this.currentTab === 'today' && !this.editingId) this.renderStepperList({});
  }

  addType() {
    const nameInput = document.getElementById('newTypeName');
    const priceInput = document.getElementById('newTypePrice');
    const name = nameInput.value.trim();
    const price = +priceInput.value || 0;
    if (!name) { this.toast('请输入类型名称'); return; }
    const id = 't_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 5);
    const color = TINT_COLORS[this.state.types.length % TINT_COLORS.length];
    this.state.types.push({ id, name, group: 'custom', color, icon: 'box' });
    this.state.prices[id] = price;
    this.save(false);
    nameInput.value = ''; priceInput.value = '';
    this.toast('已添加作业类型');
    this.renderSettings();
    this.renderStepperListIfIdle();
  }

  exportJson() {
    const data = JSON.stringify(this.state, null, 2);
    this.downloadFile(`货场记账备份_${todayStr()}.json`, data, 'application/json');
  }

  triggerImport(type) {
    this._importType = type;
    const input = document.getElementById('fileInput');
    input.accept = type === 'json' ? '.json' : '.csv';
    input.value = '';
    input.click();
  }

  handleFileImport(e) {
    const file = e.target.files[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      try {
        if (this._importType === 'json') this.importJson(reader.result);
        else this.importCsv(reader.result);
      } catch (err) {
        this.toast('导入失败：' + err.message);
      }
    };
    reader.readAsText(file, 'UTF-8');
  }

  importJson(text) {
    const data = JSON.parse(text);
    this.confirmSheet('导入将覆盖当前所有数据，确认导入？', () => {
      this.state.types = data.types || this.state.types;
      this.state.prices = data.prices || this.state.prices;
      this.state.records = data.records || this.state.records;
      this.state.profile = data.profile || this.state.profile;
      this.state.salary = data.salary || this.state.salary;
      this.state.cfg = { ...this.state.cfg, ...(data.cfg || {}) };
      this.save(false);
      this.toast('导入成功');
      this.renderAll();
      this.applyTheme();
    }, '确认导入');
  }

  importCsv(text) {
    const lines = text.replace(/\r/g, '').split('\n').filter((l) => l.trim());
    if (lines.length < 2) { this.toast('CSV内容为空'); return; }
    const parseLine = (line) => {
      const out = []; let cur = ''; let inQ = false;
      for (let i = 0; i < line.length; i++) {
        const ch = line[i];
        if (ch === '"') { inQ = !inQ; }
        else if (ch === ',' && !inQ) { out.push(cur); cur = ''; }
        else cur += ch;
      }
      out.push(cur);
      return out.map((s) => s.replace(/^"|"$/g, ''));
    };
    const headers = parseLine(lines[0]).map((h) => h.replace(/"/g, ''));
    const idxDate = headers.findIndex((h) => h.includes('日期'));
    const idxShift = headers.findIndex((h) => h.includes('班次'));
    const idxName = headers.findIndex((h) => h.includes('姓名'));
    const idxCar = headers.findIndex((h) => h.includes('车号'));
    const idxNote = headers.findIndex((h) => h.includes('备注'));
    const typeColIdx = this.state.types.map((t) => ({ id: t.id, idx: headers.indexOf(t.name) }));

    let imported = 0;
    this.pushUndo();
    for (let i = 1; i < lines.length; i++) {
      const cols = parseLine(lines[i]);
      if (!cols.length) continue;
      const counts = {};
      typeColIdx.forEach((t) => {
        if (t.idx >= 0) {
          const v = parseInt(cols[t.idx], 10);
          if (v > 0) counts[t.id] = v;
        }
      });
      if (Object.keys(counts).length === 0) continue;
      const shiftRaw = idxShift >= 0 ? cols[idxShift] : '';
      this.state.records.unshift({
        id: uid(),
        date: idxDate >= 0 ? cols[idxDate] : todayStr(),
        name: idxName >= 0 ? cols[idxName] : '',
        car: idxCar >= 0 ? cols[idxCar] : '',
        shift: shiftRaw.includes('夜') ? 'night' : 'day',
        counts, note: idxNote >= 0 ? cols[idxNote] : '', versions: [], upd: Date.now(),
      });
      imported++;
    }
    this.save(false);
    this.toast(`已导入 ${imported} 条记录`);
    this.renderAll();
  }

  loadSampleData() {
    this.confirmSheet('载入4条示例记录？', () => {
      const t = this.state.types;
      const today = todayStr();
      const yest = todayStr(-1);
      this.pushUndo();
      const samples = [
        { id: uid(), date: today, name: '张三', car: '京A12345', shift: 'day', counts: { [t[0]?.id]: 20, [t[1]?.id]: 5 }, note: '', versions: [], upd: Date.now() },
        { id: uid(), date: today, name: '李四', car: '京B54321', shift: 'night', counts: { [t[2]?.id]: 15 }, note: '', versions: [], upd: Date.now() },
        { id: uid(), date: yest, name: '张三', car: '京A12345', shift: 'day', counts: { [t[0]?.id]: 18, [t[3]?.id]: 8 }, note: '示例数据', versions: [], upd: Date.now() },
        { id: uid(), date: yest, name: '王五', car: '京C99999', shift: 'night', counts: { [t[4]?.id]: 12 }, note: '', versions: [], upd: Date.now() },
      ];
      this.state.records.unshift(...samples);
      this.save(false);
      this.toast('已载入示例数据');
      this.renderAll();
    }, '确认载入');
  }

  clearAllData() {
    this.confirmSheet('确认清空所有数据？此操作不可恢复。', () => {
      this.confirmSheet('再次确认：真的要清空所有数据吗？', () => {
        localStorage.removeItem(LS_KEY);
        localStorage.removeItem(LS_BACKUP_KEY);
        this.state = this.loadState();
        this.undoStack = [];
        this.selectedIds.clear();
        this.editingId = null;
        this.toast('已清空所有数据');
        this.renderAll();
        this.applyTheme();
      }, '彻底清空');
    }, '继续');
  }
}

document.addEventListener('DOMContentLoaded', () => {
  window.hcApp = new HCApp();
});
