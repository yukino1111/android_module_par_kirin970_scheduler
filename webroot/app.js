let callbackCounter = 0;

function bridgeExec(command, options = {}) {
  return new Promise((resolve, reject) => {
    const callbackName = `par_exec_${Date.now()}_${callbackCounter++}`;
    window[callbackName] = (errno, stdout, stderr) => {
      delete window[callbackName];
      resolve({ errno, stdout, stderr });
    };
    try {
      window.ksu.exec(command, JSON.stringify(options), callbackName);
    } catch (error) {
      delete window[callbackName];
      reject(error);
    }
  });
}

function bridgeListPackages(type) {
  try { return JSON.parse(window.ksu.listPackages(type)); }
  catch (_) { return []; }
}

function bridgeGetPackagesInfo(packages) {
  try { return JSON.parse(window.ksu.getPackagesInfo(JSON.stringify(packages))); }
  catch (_) { return []; }
}

function bridgeToast(message) {
  try { window.ksu.toast(message); } catch (_) {}
}

const ksu = {
  exec: bridgeExec,
  listPackages: bridgeListPackages,
  getPackagesInfo: bridgeGetPackagesInfo,
  toast: bridgeToast
};

const CONTROL = '/data/adb/modules/par_kirin970_scheduler/bin/control.sh';
const profiles = ['powersave', 'balanced', 'performance'];
const labels = { powersave: '省电', balanced: '均衡', performance: '性能' };
const descriptions = { powersave: '降频与温和响应', balanced: '接近设备原厂状态', performance: '显式高性能' };
const littleFreqs = ['509000','1018000','1210000','1402000','1556000','1690000','1844000'];
const bigFreqs = ['682000','1018000','1210000','1364000','1498000','1652000','1863000','2093000','2362000'];
const gpuFreqs = ['103750000','150909000','237143000','332000000','415000000','550000000','667000000','767000000'];
const fields = [
  ['little_min','小核最低频率','select',littleFreqs], ['little_max','小核最高频率','select',littleFreqs],
  ['little_hispeed','小核 Hispeed','select',littleFreqs], ['little_go_hispeed_load','小核升频负载','number'],
  ['little_target_loads','小核 Target loads','text','full'], ['little_above_hispeed_delay','小核升频延迟','text','full'],
  ['little_min_sample_time','小核最短采样时间','number'],
  ['big_min','大核最低频率','select',bigFreqs], ['big_max','大核最高频率','select',bigFreqs],
  ['big_hispeed','大核 Hispeed','select',bigFreqs], ['big_go_hispeed_load','大核升频负载','number'],
  ['big_target_loads','大核 Target loads','text','full'], ['big_above_hispeed_delay','大核升频延迟','text','full'],
  ['big_min_sample_time','大核最短采样时间','number'],
  ['gpu_min','GPU 最低频率','select',gpuFreqs], ['gpu_max','GPU 最高频率','select',gpuFreqs],
  ['eas_boost','EAS Boost（0~100）','number']
];

let state = {};
let profileData = {};
let rules = new Map();
let installedApps = [];
let editorProfile = 'balanced';
let noticeTimer;
const pageTitles = { home: '调度控制台', apps: '应用规则', params: '自定义参数' };

const $ = id => document.getElementById(id);

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

async function run(args) {
  const result = await ksu.exec(`${CONTROL} ${args}`);
  if (result.errno !== 0) throw new Error(result.stderr || `命令失败：${result.errno}`);
  return result.stdout.trim();
}

function notify(message, error = false) {
  clearTimeout(noticeTimer);
  const node = $('notice');
  node.textContent = message;
  node.className = `show${error ? ' error' : ''}`;
  try { if (typeof ksu.toast === 'function') ksu.toast(message); } catch (_) {}
  noticeTimer = setTimeout(() => { node.className = ''; }, 2600);
}

function navigate(page, updateHash = true) {
  if (!pageTitles[page]) page = 'home';
  document.querySelectorAll('[data-page]').forEach(node => node.classList.toggle('active', node.dataset.page === page));
  $('pageTitle').textContent = pageTitles[page];
  $('back').classList.toggle('visible', page !== 'home');
  if (updateHash && location.hash !== `#${page}`) location.hash = page;
  window.scrollTo(0, 0);
  if (page === 'apps' && !installedApps.length) loadApps();
}

function decode64(value = '') {
  try { return atob(value); } catch (_) { return ''; }
}

function encode64(value) {
  return btoa(value);
}

function parseKeyValues(text) {
  const result = {};
  for (const line of text.split('\n')) {
    const split = line.indexOf('=');
    if (split > 0) result[line.slice(0, split)] = line.slice(split + 1);
  }
  return result;
}

function parseConf(text) {
  return parseKeyValues(text);
}

function parseRules(text) {
  const result = new Map();
  for (const line of text.split('\n')) {
    if (!line || line.startsWith('#')) continue;
    const [pkg, profile] = line.split('|');
    if (pkg && profiles.includes(profile)) result.set(pkg, profile);
  }
  return result;
}

function renderProfileCards() {
  $('profileCards').innerHTML = profiles.map(profile => `
    <button class="profile-card ${state.global_profile === profile ? 'selected' : ''}" data-profile="${profile}">
      <strong>${labels[profile]}</strong><small>${descriptions[profile]}</small>
    </button>`).join('');
  document.querySelectorAll('[data-profile]').forEach(button => {
    button.onclick = async () => {
      try {
        await run(`set-global ${button.dataset.profile}`);
        state.global_profile = button.dataset.profile;
        renderProfileCards();
        notify(`全局档位已切换为${labels[button.dataset.profile]}`);
        setTimeout(loadStatus, 500);
      } catch (error) { notify(error.message, true); }
    };
  });
}

function renderEditorTabs() {
  $('editorTabs').innerHTML = profiles.map(profile => `
    <button class="${editorProfile === profile ? 'active' : ''}" data-editor="${profile}">${labels[profile]}</button>`).join('');
  document.querySelectorAll('[data-editor]').forEach(button => {
    button.onclick = () => {
      editorProfile = button.dataset.editor;
      renderEditorTabs();
      renderEditor();
    };
  });
}

function renderEditor() {
  const values = profileData[editorProfile] || {};
  $('profileEditor').innerHTML = fields.map(([key, title, type, extra]) => {
    const full = extra === 'full' ? ' full' : '';
    if (type === 'select') {
      return `<label class="field${full}"><span>${title}</span><select name="${key}">${extra.map(value =>
        `<option value="${value}" ${values[key] === value ? 'selected' : ''}>${value}</option>`).join('')}</select></label>`;
    }
    const constraints = key.includes('go_hispeed') ? 'min="1" max="100"' :
      key === 'eas_boost' ? 'min="0" max="100"' :
      type === 'number' ? 'min="1000" max="500000"' : '';
    return `<label class="field${full}"><span>${title}</span><input name="${key}" type="${type}" ${constraints} value="${values[key] || ''}"></label>`;
  }).join('');
}

function renderUniPerf() {
  document.querySelectorAll('[data-uniperf]').forEach(button => {
    button.classList.toggle('active', button.dataset.uniperf === state.uniperf_mode);
    button.onclick = async () => {
      const mode = button.dataset.uniperf;
      try {
        await run(`set-uniperf ${mode}`);
        state.uniperf_mode = mode;
        state.reboot_required = '1';
        renderUniPerf();
        notify('UniPerf 策略已保存，重启后生效');
      } catch (error) { notify(error.message, true); }
    };
  });
  const context = state.mounted_context || '未知标签';
  const bridge = state.uniperf_bridge_enabled === '1' ? '事件已启用' : '事件已停用';
  $('mountState').textContent = `覆盖挂载：${state.mounted === '1' ? '已检测' : '待重启检测'} · ${bridge} · ${context}${state.reboot_required === '1' ? ' · 需要重启' : ''}`;
}

function renderStatus() {
  $('activeBadge').textContent = labels[state.active_profile] || '等待应用';
  $('runtime').textContent = `守护进程：${state.daemon_running === '1' ? '运行中' : '未运行'} · 全局：${labels[state.global_profile] || '未知'}`;
  $('foreground').textContent = `前台应用：${state.foreground_package || '未检测/未启用规则'}`;
  $('dynamicEnabled').checked = state.dynamic_enabled === '1';
  $('pollInterval').value = state.poll_interval || '2';
  renderProfileCards();
  renderUniPerf();
}

async function loadStatus() {
  try {
    state = parseKeyValues(await run('status'));
    for (const profile of profiles) profileData[profile] = parseConf(decode64(state[`profile_${profile}_b64`]));
    rules = parseRules(decode64(state.rules_b64));
    renderStatus();
    renderEditorTabs();
    renderEditor();
    if (installedApps.length) renderApps();
  } catch (error) {
    $('runtime').textContent = '无法连接模块控制脚本';
    notify(error.message, true);
  }
}

async function saveRules() {
  const content = [...rules.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([pkg, profile]) => `${pkg}|${profile}`).join('\n');
  await run(`save-rules ${shellQuote(encode64(content ? `${content}\n` : ''))}`);
}

function renderApps() {
  const query = $('appSearch').value.trim().toLowerCase();
  const visible = installedApps.filter(app => !query || app.packageName.toLowerCase().includes(query) || (app.appLabel || '').toLowerCase().includes(query));
  $('appList').innerHTML = visible.length ? visible.map(app => `
    <div class="app-row">
      <img loading="lazy" src="ksu://icon/${app.packageName}" alt="">
      <div><strong>${escapeHtml(app.appLabel || app.packageName)}</strong><small>${app.packageName}${app.isSystem ? ' · 系统' : ''}</small></div>
      <select data-package="${app.packageName}">
        <option value="">跟随全局</option>
        ${profiles.map(profile => `<option value="${profile}" ${rules.get(app.packageName) === profile ? 'selected' : ''}>${labels[profile]}</option>`).join('')}
      </select>
    </div>`).join('') : '<p class="empty">没有匹配的软件</p>';
  document.querySelectorAll('[data-package]').forEach(select => {
    select.onchange = async () => {
      const pkg = select.dataset.package;
      const previous = rules.get(pkg) || '';
      if (select.value) rules.set(pkg, select.value); else rules.delete(pkg);
      try {
        await saveRules();
        notify(select.value ? `${pkg} → ${labels[select.value]}` : `${pkg} 跟随全局`);
      } catch (error) {
        if (previous) rules.set(pkg, previous); else rules.delete(pkg);
        select.value = previous;
        notify(error.message, true);
      }
    };
  });
}

function escapeHtml(value) {
  const div = document.createElement('div');
  div.textContent = value;
  return div.innerHTML;
}

async function loadApps() {
  $('loadApps').disabled = true;
  $('loadApps').textContent = '读取中…';
  try {
    let packageNames = [];
    const systemHints = new Map();
    let usedShellFallback = false;

    if (typeof ksu.listPackages === 'function') {
      const all = ksu.listPackages('all');
      if (Array.isArray(all)) packageNames = all;
      if (!packageNames.length) {
        const user = ksu.listPackages('user');
        const system = ksu.listPackages('system');
        if (Array.isArray(user)) user.forEach(pkg => systemHints.set(pkg, false));
        if (Array.isArray(system)) system.forEach(pkg => systemHints.set(pkg, true));
        packageNames = [...systemHints.keys()];
      }
    }

    if (!packageNames.length) {
      usedShellFallback = true;
      const rows = await run('list-apps');
      for (const line of rows.split('\n')) {
        const [pkg, isSystem] = line.split('|');
        if (/^[A-Za-z0-9_][A-Za-z0-9._]*$/.test(pkg || '')) systemHints.set(pkg, isSystem === '1');
      }
      packageNames = [...systemHints.keys()];
    }

    const infoByPackage = new Map();
    if (typeof ksu.getPackagesInfo === 'function') {
      for (let index = 0; index < packageNames.length; index += 80) {
        const info = ksu.getPackagesInfo(packageNames.slice(index, index + 80));
        if (Array.isArray(info)) {
          info.forEach(app => { if (app?.packageName) infoByPackage.set(app.packageName, app); });
        }
      }
    }

    installedApps = packageNames.map(packageName => infoByPackage.get(packageName) || {
      packageName,
      appLabel: packageName,
      isSystem: systemHints.get(packageName) === true
    }).sort((a, b) => (a.appLabel || a.packageName).localeCompare(b.appLabel || b.packageName, 'zh-CN'));

    if (!installedApps.length) throw new Error('系统包管理器没有返回应用');
    $('appSearch').disabled = false;
    renderApps();
    notify(`已读取 ${installedApps.length} 个软件${usedShellFallback ? '（兼容模式）' : ''}`);
  } catch (error) {
    notify(`读取软件列表失败：${error.message}`, true);
  } finally {
    $('loadApps').disabled = false;
    $('loadApps').textContent = '重新读取';
  }
}

$('refresh').onclick = loadStatus;
$('back').onclick = () => navigate('home');
document.querySelectorAll('[data-nav]').forEach(button => {
  button.onclick = () => navigate(button.dataset.nav);
});
window.addEventListener('hashchange', () => navigate(location.hash.slice(1) || 'home', false));
$('loadApps').onclick = loadApps;
$('appSearch').oninput = renderApps;
$('dynamicEnabled').onchange = async event => {
  try {
    await run(`set-dynamic ${event.target.checked ? 1 : 0}`);
    state.dynamic_enabled = event.target.checked ? '1' : '0';
    notify(`动态切换已${event.target.checked ? '启用' : '停用'}`);
  } catch (error) { event.target.checked = !event.target.checked; notify(error.message, true); }
};
$('pollInterval').onchange = async event => {
  try { await run(`set-interval ${event.target.value}`); notify(`检测间隔：${event.target.value} 秒`); }
  catch (error) { notify(error.message, true); }
};
$('saveProfile').onclick = async () => {
  try {
    const form = new FormData($('profileEditor'));
    const content = fields.map(([key]) => `${key}=${String(form.get(key) || '').trim()}`).join('\n') + '\n';
    await run(`save-profile ${editorProfile} ${shellQuote(encode64(content))}`);
    profileData[editorProfile] = parseConf(content);
    notify(`${labels[editorProfile]}档参数已保存`);
  } catch (error) { notify(`保存失败：${error.message}`, true); }
};

$('resetProfile').onclick = async () => {
  if (!window.confirm(`恢复${labels[editorProfile]}档的模块默认参数？`)) return;
  try {
    await run(`reset-profile ${editorProfile}`);
    await loadStatus();
    notify(`${labels[editorProfile]}档已恢复默认`);
  } catch (error) { notify(`恢复失败：${error.message}`, true); }
};

$('resetAllProfiles').onclick = async () => {
  if (!window.confirm('将省电、均衡、性能三档全部恢复为模块默认参数？')) return;
  try {
    await run('reset-profile all');
    await loadStatus();
    notify('三档参数已全部恢复默认');
  } catch (error) { notify(`恢复失败：${error.message}`, true); }
};

navigate(location.hash.slice(1) || 'home', false);
loadStatus();
