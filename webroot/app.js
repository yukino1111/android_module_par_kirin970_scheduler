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

const messages = {
  en: {
    backHome: 'Back to home', refresh: 'Refresh', loadingStatus: 'Loading runtime status…', globalProfile: 'Global profile',
    globalProfileHint: 'Used when no app rule matches', dynamicSwitching: 'Dynamic switching',
    dynamicSwitchingHint: 'Select a profile from the kernel top-app cgroup',
    pollInterval: 'Top-app sample interval', seconds1: '1 second', seconds2: '2 seconds',
    seconds3: '3 seconds', seconds5: '5 seconds', seconds10: '10 seconds',
    pollHint: 'Reads the small top-app cgroup file directly; no repeated dumpsys calls.',
    appRules: 'App rules', appRulesHint: 'Assign a powersave, balanced, or performance profile',
    customParameters: 'Custom parameters', customParametersHint: 'Edit profiles or restore module defaults',
    uniperfPolicy: 'UniPerf event policy', uniperfPolicyHint: 'Huawei userspace performance events; systemless override',
    stockBalanced: 'Stock balanced', enhancedPerformance: 'Enhanced performance',
    uniperfHint: 'This is independent of the editable persistent CPU/GPU profiles. Reboot to apply changes.',
    appRulesStorageHint: 'Only package names and profile mappings are stored', loadApps: 'Load apps',
    searchApps: 'Search app name or package', appsAutoLoad: 'Apps load automatically when this page opens',
    profileParameters: 'Profile parameters', profileParametersHint: 'Saving immediately reapplies the active profile',
    saveProfile: 'Save current profile', resetProfile: 'Restore current profile defaults',
    resetAllProfiles: 'Restore all profile defaults',
    powersave: 'Powersave', balanced: 'Balanced', performance: 'Performance',
    powersaveDesc: 'Lower clocks and gentle response', balancedDesc: 'Fluid daily use without fixed high clocks',
    performanceDesc: 'Explicit high performance', homeTitle: 'Scheduler Console', appsTitle: 'App Rules',
    paramsTitle: 'Custom Parameters', commandFailed: 'Command failed: {code}', globalSwitched: 'Global profile changed to {profile}',
    uniperfSaved: 'UniPerf policy saved; reboot to apply', unknownContext: 'unknown context',
    eventEnabled: 'events enabled', eventDisabled: 'events disabled', overlayMounted: 'detected',
    overlayPending: 'pending reboot check', rebootRequired: 'reboot required',
    mountState: 'Overlay mount: {mount} · {bridge} · {context}{reboot}', waitingApp: 'Waiting for app',
    daemonRunning: 'running', daemonStopped: 'stopped', unknown: 'unknown',
    runtime: 'Daemon: {daemon} · Global: {profile}', foreground: 'Foreground app: {app}',
    foregroundNone: 'not detected/no rules enabled', cannotConnect: 'Cannot connect to module control script',
    systemApp: 'system', followGlobal: 'Follow global', noMatches: 'No matching apps', loading: 'Loading…',
    noApps: 'Package manager returned no apps', appsLoaded: 'Loaded {count} apps{fallback}',
    compatibilityMode: ' (compatibility mode)', loadAppsFailed: 'Failed to load apps: {error}', reload: 'Reload',
    dynamicChanged: 'Dynamic switching {state}', enabled: 'enabled', disabled: 'disabled',
    intervalChanged: 'Top-app sample interval: {seconds} seconds', profileSaved: '{profile} profile saved',
    saveFailed: 'Save failed: {error}', resetConfirm: 'Restore module defaults for the {profile} profile?',
    profileRestored: '{profile} profile restored to defaults', resetFailed: 'Restore failed: {error}',
    resetAllConfirm: 'Restore module defaults for all three profiles?', allRestored: 'All profiles restored to defaults',
    little_min: 'Little CPU minimum frequency', little_max: 'Little CPU maximum frequency',
    little_hispeed: 'Little CPU hispeed frequency', little_go_hispeed_load: 'Little CPU go-hispeed load',
    little_target_loads: 'Little CPU target loads', little_above_hispeed_delay: 'Little CPU above-hispeed delay',
    little_min_sample_time: 'Little CPU minimum sample time', big_min: 'Big CPU minimum frequency',
    big_max: 'Big CPU maximum frequency', big_hispeed: 'Big CPU hispeed frequency',
    big_go_hispeed_load: 'Big CPU go-hispeed load', big_target_loads: 'Big CPU target loads',
    big_above_hispeed_delay: 'Big CPU above-hispeed delay', big_min_sample_time: 'Big CPU minimum sample time',
    gpu_min: 'GPU minimum frequency', gpu_max: 'GPU maximum frequency', eas_boost: 'Kirin global EAS boost switch',
    stune_boost: 'Game cgroup schedtune boost', stune_prefer_idle: 'Game cgroup prefer-idle switch',
    ddr_latency_min: 'Huawei DDR latency minimum vote'
  },
  zh: {
    backHome: '返回首页', refresh: '刷新', loadingStatus: '正在读取运行状态…', globalProfile: '全局档位', globalProfileHint: '未命中应用规则时使用',
    dynamicSwitching: '动态切换', dynamicSwitchingHint: '直接按内核 top-app cgroup 选择前台应用档位',
    pollInterval: 'top-app 采样间隔', seconds1: '1 秒', seconds2: '2 秒', seconds3: '3 秒', seconds5: '5 秒', seconds10: '10 秒',
    pollHint: '只读取很小的 top-app cgroup 文件，不再反复调用 dumpsys。',
    appRules: '应用规则',
    appRulesHint: '为软件指定省电、均衡或性能档', customParameters: '自定义参数',
    customParametersHint: '编辑三档参数或恢复模块默认值', uniperfPolicy: 'UniPerf 事件策略',
    uniperfPolicyHint: '华为用户态性能事件配置；systemless 覆盖', stockBalanced: '原厂均衡',
    enhancedPerformance: '增强性能', uniperfHint: '它与下面可编辑的 CPU/GPU 常驻档位相互独立；切换后重启生效。',
    appRulesStorageHint: '仅保存包名与三档映射', loadApps: '读取应用', searchApps: '搜索应用名或包名',
    appsAutoLoad: '进入页面后自动读取软件列表', profileParameters: '三档参数',
    profileParametersHint: '保存后立即重新应用当前生效档', saveProfile: '保存当前档参数',
    resetProfile: '恢复当前档默认', resetAllProfiles: '三档全部恢复默认', powersave: '省电', balanced: '均衡',
    performance: '性能', powersaveDesc: '降频与温和响应', balancedDesc: '面向日常流畅，不常驻锁高频',
    performanceDesc: '显式高性能', homeTitle: '调度控制台', appsTitle: '应用规则', paramsTitle: '自定义参数',
    commandFailed: '命令失败：{code}', globalSwitched: '全局档位已切换为{profile}',
    uniperfSaved: 'UniPerf 策略已保存，重启后生效', unknownContext: '未知标签', eventEnabled: '事件已启用',
    eventDisabled: '事件已停用', overlayMounted: '已检测', overlayPending: '待重启检测', rebootRequired: '需要重启',
    mountState: '覆盖挂载：{mount} · {bridge} · {context}{reboot}', waitingApp: '等待应用', daemonRunning: '运行中',
    daemonStopped: '未运行', unknown: '未知', runtime: '守护进程：{daemon} · 全局：{profile}',
    foreground: '前台应用：{app}', foregroundNone: '未检测/未启用规则', cannotConnect: '无法连接模块控制脚本',
    systemApp: '系统', followGlobal: '跟随全局', noMatches: '没有匹配的软件', loading: '读取中…',
    noApps: '系统包管理器没有返回应用', appsLoaded: '已读取 {count} 个软件{fallback}', compatibilityMode: '（兼容模式）',
    loadAppsFailed: '读取软件列表失败：{error}', reload: '重新读取', dynamicChanged: '动态切换已{state}',
    enabled: '启用', disabled: '停用', intervalChanged: 'top-app 采样间隔：{seconds} 秒', profileSaved: '{profile}档参数已保存',
    saveFailed: '保存失败：{error}', resetConfirm: '恢复{profile}档的模块默认参数？',
    profileRestored: '{profile}档已恢复默认', resetFailed: '恢复失败：{error}',
    resetAllConfirm: '将省电、均衡、性能三档全部恢复为模块默认参数？', allRestored: '三档参数已全部恢复默认',
    little_min: '小核最低频率', little_max: '小核最高频率', little_hispeed: '小核 Hispeed',
    little_go_hispeed_load: '小核升频负载', little_target_loads: '小核 Target loads',
    little_above_hispeed_delay: '小核升频延迟', little_min_sample_time: '小核最短采样时间',
    big_min: '大核最低频率', big_max: '大核最高频率', big_hispeed: '大核 Hispeed',
    big_go_hispeed_load: '大核升频负载', big_target_loads: '大核 Target loads',
    big_above_hispeed_delay: '大核升频延迟', big_min_sample_time: '大核最短采样时间',
    gpu_min: 'GPU 最低频率', gpu_max: 'GPU 最高频率', eas_boost: 'Kirin 全局 EAS 加速开关',
    stune_boost: '游戏 cgroup schedtune boost', stune_prefer_idle: '游戏 cgroup 优先空闲核开关',
    ddr_latency_min: '华为 DDR 延迟最低频率投票'
  }
};

let storedLanguage = '';
try { storedLanguage = localStorage.getItem('par_scheduler_language') || ''; } catch (_) {}
let language = storedLanguage || ((navigator.language || '').toLowerCase().startsWith('zh') ? 'zh' : 'en');
if (!messages[language]) language = 'en';

function t(key, values = {}) {
  let result = messages[language][key] || messages.en[key] || key;
  for (const [name, value] of Object.entries(values)) result = result.replaceAll(`{${name}}`, value);
  return result;
}

const CONTROL = '/data/adb/modules/par_kirin970_scheduler/bin/control.sh';
const profiles = ['powersave', 'balanced', 'performance'];
let labels = {};
let descriptions = {};
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
  ['eas_boost','Kirin 全局 EAS 加速开关','select',['0','1']],
  ['stune_boost','游戏 cgroup schedtune boost','number'],
  ['stune_prefer_idle','游戏 cgroup 优先空闲核开关','select',['0','1']],
  ['ddr_latency_min','华为 DDR 延迟最低频率投票','select',['0','533000000','1244000000','1866000000']]
];

let state = {};
let profileData = {};
let rules = new Map();
let installedApps = [];
let editorProfile = 'balanced';
let noticeTimer;
let pageTitles = {};

const $ = id => document.getElementById(id);

function applyLanguage(nextLanguage, persist = true) {
  language = messages[nextLanguage] ? nextLanguage : 'en';
  if (persist) {
    try { localStorage.setItem('par_scheduler_language', language); } catch (_) {}
  }
  document.documentElement.lang = language === 'zh' ? 'zh-CN' : 'en';
  labels = { powersave: t('powersave'), balanced: t('balanced'), performance: t('performance') };
  descriptions = {
    powersave: t('powersaveDesc'), balanced: t('balancedDesc'), performance: t('performanceDesc')
  };
  pageTitles = { home: t('homeTitle'), apps: t('appsTitle'), params: t('paramsTitle') };
  document.querySelectorAll('[data-i18n]').forEach(node => { node.textContent = t(node.dataset.i18n); });
  document.querySelectorAll('[data-i18n-placeholder]').forEach(node => {
    node.placeholder = t(node.dataset.i18nPlaceholder);
  });
  document.querySelectorAll('[data-i18n-aria-label]').forEach(node => {
    node.setAttribute('aria-label', t(node.dataset.i18nAriaLabel));
  });
  $('language').textContent = language === 'zh' ? 'EN' : '中';
  $('language').setAttribute('aria-label', language === 'zh' ? 'Switch to English' : '切换到中文');
  const currentPage = document.querySelector('.page.active')?.dataset.page || 'home';
  $('pageTitle').textContent = pageTitles[currentPage];
  if (state.global_profile) renderStatus();
  renderEditorTabs();
  renderEditor();
  if (installedApps.length) renderApps();
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

async function run(args) {
  const result = await ksu.exec(`${CONTROL} ${args}`);
  if (result.errno !== 0) throw new Error(result.stderr || t('commandFailed', { code: result.errno }));
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
        notify(t('globalSwitched', { profile: labels[button.dataset.profile] }));
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
  $('profileEditor').innerHTML = fields.map(([key, _title, type, extra]) => {
    const title = t(key);
    const full = extra === 'full' ? ' full' : '';
    if (type === 'select') {
      return `<label class="field${full}"><span>${title}</span><select name="${key}">${extra.map(value =>
        `<option value="${value}" ${values[key] === value ? 'selected' : ''}>${value}</option>`).join('')}</select></label>`;
    }
    const constraints = key.includes('go_hispeed') ? 'min="1" max="100"' :
      key === 'stune_boost' ? 'min="0" max="100"' :
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
        notify(t('uniperfSaved'));
      } catch (error) { notify(error.message, true); }
    };
  });
  const context = state.mounted_context || t('unknownContext');
  const bridge = state.uniperf_bridge_enabled === '1' ? t('eventEnabled') : t('eventDisabled');
  $('mountState').textContent = t('mountState', {
    mount: state.mounted === '1' ? t('overlayMounted') : t('overlayPending'),
    bridge,
    context,
    reboot: state.reboot_required === '1' ? ` · ${t('rebootRequired')}` : ''
  });
}

function renderStatus() {
  $('activeBadge').textContent = labels[state.active_profile] || t('waitingApp');
  $('runtime').textContent = t('runtime', {
    daemon: state.daemon_running === '1' ? t('daemonRunning') : t('daemonStopped'),
    profile: labels[state.global_profile] || t('unknown')
  });
  $('foreground').textContent = t('foreground', { app: state.foreground_package || t('foregroundNone') });
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
    $('runtime').textContent = t('cannotConnect');
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
      <div><strong>${escapeHtml(app.appLabel || app.packageName)}</strong><small>${app.packageName}${app.isSystem ? ` · ${t('systemApp')}` : ''}</small></div>
      <select data-package="${app.packageName}">
        <option value="">${t('followGlobal')}</option>
        ${profiles.map(profile => `<option value="${profile}" ${rules.get(app.packageName) === profile ? 'selected' : ''}>${labels[profile]}</option>`).join('')}
      </select>
    </div>`).join('') : `<p class="empty">${t('noMatches')}</p>`;
  document.querySelectorAll('[data-package]').forEach(select => {
    select.onchange = async () => {
      const pkg = select.dataset.package;
      const previous = rules.get(pkg) || '';
      if (select.value) rules.set(pkg, select.value); else rules.delete(pkg);
      try {
        await saveRules();
        notify(select.value ? `${pkg} → ${labels[select.value]}` : `${pkg} · ${t('followGlobal')}`);
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
  $('loadApps').textContent = t('loading');
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
    }).sort((a, b) => (a.appLabel || a.packageName).localeCompare(
      b.appLabel || b.packageName, language === 'zh' ? 'zh-CN' : 'en'
    ));

    if (!installedApps.length) throw new Error(t('noApps'));
    $('appSearch').disabled = false;
    renderApps();
    notify(t('appsLoaded', {
      count: installedApps.length,
      fallback: usedShellFallback ? t('compatibilityMode') : ''
    }));
  } catch (error) {
    notify(t('loadAppsFailed', { error: error.message }), true);
  } finally {
    $('loadApps').disabled = false;
    $('loadApps').textContent = t('reload');
  }
}

$('refresh').onclick = loadStatus;
$('language').onclick = () => applyLanguage(language === 'zh' ? 'en' : 'zh');
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
    notify(t('dynamicChanged', { state: event.target.checked ? t('enabled') : t('disabled') }));
  } catch (error) { event.target.checked = !event.target.checked; notify(error.message, true); }
};
$('pollInterval').onchange = async event => {
  try { await run(`set-interval ${event.target.value}`); notify(t('intervalChanged', { seconds: event.target.value })); }
  catch (error) { notify(error.message, true); }
};
$('saveProfile').onclick = async () => {
  try {
    const form = new FormData($('profileEditor'));
    const content = fields.map(([key]) => `${key}=${String(form.get(key) || '').trim()}`).join('\n') + '\n';
    await run(`save-profile ${editorProfile} ${shellQuote(encode64(content))}`);
    profileData[editorProfile] = parseConf(content);
    notify(t('profileSaved', { profile: labels[editorProfile] }));
  } catch (error) { notify(t('saveFailed', { error: error.message }), true); }
};

$('resetProfile').onclick = async () => {
  if (!window.confirm(t('resetConfirm', { profile: labels[editorProfile] }))) return;
  try {
    await run(`reset-profile ${editorProfile}`);
    await loadStatus();
    notify(t('profileRestored', { profile: labels[editorProfile] }));
  } catch (error) { notify(t('resetFailed', { error: error.message }), true); }
};

$('resetAllProfiles').onclick = async () => {
  if (!window.confirm(t('resetAllConfirm'))) return;
  try {
    await run('reset-profile all');
    await loadStatus();
    notify(t('allRestored'));
  } catch (error) { notify(t('resetFailed', { error: error.message }), true); }
};

applyLanguage(language, false);
navigate(location.hash.slice(1) || 'home', false);
loadStatus();
