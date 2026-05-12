(function () {
  const state = {
    view: "dashboard",
    loading: true,
    error: "",
    toast: "",
    auth: {
      checked: false,
      setupRequired: false,
      user: null,
      roles: [],
      csrfToken: ""
    },
    settings: null,
    summary: null,
    devices: [],
    events: [],
    alerts: [],
    users: [],
    audit: [],
    backups: [],
    report: null,
    historyReport: null,
    auditReport: null,
    reportSnapshots: [],
    integrations: [],
    theme: window.localStorage.getItem("sword-theme") || "system",
    lastBeepAt: 0,
    soundArmed: false,
    filters: {
      search: "",
      status: "all",
      type: "all",
      criticality: "all"
    },
    reportFilters: {
      device: "all",
      from: "",
      to: ""
    },
    auditFilters: {
      user: "all",
      action: "",
      from: "",
      to: ""
    },
    historyFilters: {
      device: "all",
      status: "all",
      criticality: "all",
      from: "",
      to: ""
    },
    modal: null,
    userModal: null,
    passwordModal: null,
    integrationModal: null
  };

  const DEVICE_TYPES = [
    "Computador",
    "Notebook",
    "Servidor",
    "Servidor Windows",
    "Servidor Linux",
    "Banco de Dados",
    "Firewall",
    "Switch",
    "Roteador",
    "Proxy",
    "Link Internet",
    "Access Point",
    "Controladora Wi-Fi",
    "Impressora",
    "Storage/NAS",
    "Virtualizador",
    "Camera IP",
    "DVR/NVR",
    "Telefone IP",
    "Nobreak/UPS",
    "Thin Client",
    "Terminal POS",
    "Relogio de Ponto",
    "Catraca",
    "Sensor IoT",
    "Gateway",
    "Servico",
    "Outro"
  ];

  const CHECK_METHODS = [
    ["ping", "Ping / ICMP"],
    ["tcp", "Porta TCP"],
    ["http", "HTTP"],
    ["https", "HTTPS"]
  ];

  const app = document.getElementById("app");
  document.documentElement.dataset.theme = state.theme;
  document.addEventListener("pointerdown", () => {
    state.soundArmed = true;
  }, { once: true });
  const api = {
    get: (url) => request(url),
    post: (url, body) => request(url, { method: "POST", body }),
    put: (url, body) => request(url, { method: "PUT", body }),
    delete: (url) => request(url, { method: "DELETE" })
  };

  function request(url, options = {}) {
    const method = options.method || "GET";
    const init = {
      method,
      headers: { "Content-Type": "application/json" },
      credentials: "same-origin"
    };

    if (state.auth.csrfToken && !["GET", "HEAD", "OPTIONS"].includes(method)) {
      init.headers["X-CSRF-Token"] = state.auth.csrfToken;
    }

    if (options.body) {
      init.body = JSON.stringify(options.body);
    }

    return fetch(url, init).then(async (response) => {
      const text = await response.text();
      let data = null;
      if (text) {
        try {
          data = JSON.parse(text);
        } catch (error) {
          data = { error: "Resposta invalida do servidor." };
        }
      }
      if (!response.ok) {
        if (response.status === 401) {
          state.auth.user = null;
          state.auth.setupRequired = false;
          state.loading = false;
          state.error = "";
          render();
        }
        throw new Error((data && data.error) || "Falha na requisicao.");
      }
      return data;
    });
  }

  function canOperate() {
    return state.auth.user && ["admin", "operator"].includes(state.auth.user.role);
  }

  function isAdmin() {
    return state.auth.user && state.auth.user.role === "admin";
  }

  function roleLabel(role) {
    const map = {
      admin: "Administrador",
      operator: "Operador",
      viewer: "Visualizador"
    };
    return map[role] || role || "-";
  }

  function asSettings(value) {
    return {
      app_name: value?.app_name || "Sword",
      security_mode: value?.security_mode || "hardened-local",
      session_hours: Number(value?.session_hours || 8),
      login_rate_limit_window_minutes: Number(value?.login_rate_limit_window_minutes || 15),
      login_rate_limit_max_attempts: Number(value?.login_rate_limit_max_attempts || 5),
      audit_retention_days: Number(value?.audit_retention_days || 180),
      event_retention_days: Number(value?.event_retention_days || 365),
      backup_retention_days: Number(value?.backup_retention_days || 30),
      check_interval_seconds: Number(value?.check_interval_seconds || 30),
      check_attempts: Number(value?.check_attempts || 3),
      check_timeout_ms: Number(value?.check_timeout_ms || 900),
      require_csrf: value?.require_csrf !== false,
      allow_viewer_export: Boolean(value?.allow_viewer_export),
      critical_sound_enabled: value?.critical_sound_enabled !== false,
      critical_sound_minutes: Number(value?.critical_sound_minutes || 5),
      ui_theme: value?.ui_theme || "system",
      updated_at: value?.updated_at || new Date().toISOString()
    };
  }

  function asArray(value) {
    return Array.isArray(value) ? value : [];
  }

  function asSummary(value) {
    return {
      total: Number(value?.total || 0),
      online: Number(value?.online || 0),
      offline: Number(value?.offline || 0),
      critical_offline: Number(value?.critical_offline || 0),
      open_alerts: Number(value?.open_alerts || 0),
      generated_at: value?.generated_at || new Date().toISOString()
    };
  }

  function formatDate(value) {
    if (!value) return "-";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "-";
    return date.toLocaleString("pt-BR", {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit"
    });
  }

  function toDateTimeLocal(value) {
    if (!value) return "";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "";
    const local = new Date(date.getTime() - date.getTimezoneOffset() * 60000);
    return local.toISOString().slice(0, 16);
  }

  function methodLabel(value) {
    const method = String(value || "ping").toLowerCase();
    const found = CHECK_METHODS.find((item) => item[0] === method);
    return found ? found[1] : method;
  }

  function isMaintenanceActive(device) {
    if (!device || !device.maintenance_until) return false;
    const date = new Date(device.maintenance_until);
    return !Number.isNaN(date.getTime()) && date.getTime() > Date.now();
  }

  function timeAgo(value) {
    if (!value) return "-";
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "-";
    const seconds = Math.max(0, Math.floor((Date.now() - date.getTime()) / 1000));
    if (seconds < 60) return `ha ${seconds}s`;
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60) return `ha ${minutes} min`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return `ha ${hours} h`;
    const days = Math.floor(hours / 24);
    return `ha ${days} d`;
  }

  function formatDuration(seconds) {
    if (seconds === null || seconds === undefined || seconds === "") return "-";
    const total = Number(seconds);
    if (!Number.isFinite(total)) return "-";
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = total % 60;
    const parts = [];
    if (h) parts.push(`${h}h`);
    if (m) parts.push(`${m}min`);
    parts.push(`${s}s`);
    return parts.join(" ");
  }

  function reportRows() {
    return asArray(state.report?.rows);
  }

  function historyRows() {
    return asArray(state.historyReport?.rows);
  }

  function auditRows() {
    return asArray(state.auditReport?.rows);
  }

  function buildQuery(filters, kind) {
    const params = new URLSearchParams();
    if (filters.from) params.set("from", filters.from);
    if (filters.to) params.set("to", filters.to);
    if (filters.device && filters.device !== "all") params.set("device_id", filters.device);
    if (kind === "audit") {
      if (filters.user && filters.user !== "all") params.set("user_id", filters.user);
      if (filters.action) params.set("action", filters.action);
    }
    const query = params.toString();
    return query ? `?${query}` : "";
  }

  function downloadUrl(url) {
    const link = document.createElement("a");
    link.href = url;
    link.download = "";
    document.body.appendChild(link);
    link.click();
    link.remove();
  }

  function readFileAsDataUrl(file) {
    return new Promise((resolve, reject) => {
      if (!file) return resolve("");
      if (file.size > 250000) return reject(new Error("Foto do usuario deve ter ate 250 KB."));
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result || ""));
      reader.onerror = () => reject(new Error("Nao foi possivel ler a foto."));
      reader.readAsDataURL(file);
    });
  }

  function applyTheme(theme) {
    state.theme = theme || "system";
    window.localStorage.setItem("sword-theme", state.theme);
    document.documentElement.dataset.theme = state.theme;
  }

  function renderAvatar(user) {
    if (user?.avatar_data_url) {
      return `<div class="avatar image"><img src="${escapeHtml(user.avatar_data_url)}" alt=""></div>`;
    }
    return `<div class="avatar">${escapeHtml(getInitials(user?.name))}</div>`;
  }

  function playCriticalBeep() {
    if (!state.soundArmed) return;
    const now = Date.now();
    if (now - state.lastBeepAt < 60000) return;
    state.lastBeepAt = now;
    try {
      const AudioContext = window.AudioContext || window.webkitAudioContext;
      if (!AudioContext) return;
      const ctx = new AudioContext();
      const gain = ctx.createGain();
      gain.gain.value = 0.05;
      gain.connect(ctx.destination);
      [0, 180, 360].forEach((delay) => {
        const osc = ctx.createOscillator();
        osc.frequency.value = 880;
        osc.type = "sine";
        osc.connect(gain);
        const start = ctx.currentTime + delay / 1000;
        osc.start(start);
        osc.stop(start + 0.12);
      });
      window.setTimeout(() => ctx.close(), 900);
    } catch (error) {}
  }

  function evaluateCriticalSound() {
    const settings = asSettings(state.settings);
    if (!settings.critical_sound_enabled) return;
    const thresholdMs = Math.max(1, settings.critical_sound_minutes) * 60000;
    const needsSound = openAlerts().some((alert) => {
      const critical = ["critical", "high"].includes(alert.priority) || ["critica", "alta"].includes(alert.device?.criticality);
      const age = Date.now() - new Date(alert.created_at || Date.now()).getTime();
      return critical && age >= thresholdMs;
    });
    if (needsSound) playCriticalBeep();
  }

  function labelCriticality(value) {
    const map = {
      baixa: "Baixa",
      media: "Media",
      alta: "Alta",
      critica: "Critica"
    };
    return map[value] || value || "-";
  }

  function criticalityClass(value) {
    return {
      baixa: "low",
      media: "medium",
      alta: "high",
      critica: "critical"
    }[value] || "inactive";
  }

  function deviceById(id) {
    return asArray(state.devices).find((device) => device.id === id) || null;
  }

  function filteredDevices() {
    const search = state.filters.search.trim().toLowerCase();
    return asArray(state.devices).filter((device) => {
      const matchesSearch = !search || [device.name, device.host, device.type, device.location, device.serial_number, device.asset_tag, device.model, device.owner, device.tags]
        .join(" ")
        .toLowerCase()
        .includes(search);
      const matchesStatus = state.filters.status === "all" || device.current_status === state.filters.status;
      const matchesType = state.filters.type === "all" || device.type === state.filters.type;
      const matchesCriticality = state.filters.criticality === "all" || device.criticality === state.filters.criticality;
      return matchesSearch && matchesStatus && matchesType && matchesCriticality;
    });
  }

  function filteredEvents() {
    return asArray(state.events)
      .map((event) => ({ ...event, device: deviceById(event.device_id) }))
      .filter((event) => {
        const deviceMatch = state.historyFilters.device === "all" || event.device_id === state.historyFilters.device;
        const statusMatch = state.historyFilters.status === "all" || event.status === state.historyFilters.status;
        const criticalityMatch = state.historyFilters.criticality === "all" || event.criticality === state.historyFilters.criticality;
        return deviceMatch && statusMatch && criticalityMatch;
      })
      .sort((a, b) => new Date(b.down_at || 0) - new Date(a.down_at || 0));
  }

  function openAlerts() {
    return asArray(state.alerts)
      .filter((alert) => alert.status === "open")
      .map((alert) => ({ ...alert, device: deviceById(alert.device_id) }))
      .filter((alert) => alert.device)
      .sort((a, b) => new Date(b.created_at || 0) - new Date(a.created_at || 0));
  }

  function options(values, selected, labelAll) {
    return [`<option value="all"${selected === "all" ? " selected" : ""}>${labelAll}</option>`]
      .concat(values.map((value) => `<option value="${escapeHtml(value)}"${selected === value ? " selected" : ""}>${escapeHtml(value)}</option>`))
      .join("");
  }

  function deviceOptions(selected, labelAll) {
    return [`<option value="all"${selected === "all" ? " selected" : ""}>${labelAll}</option>`]
      .concat(asArray(state.devices).map((device) => `
        <option value="${escapeHtml(device.id)}"${selected === device.id ? " selected" : ""}>${escapeHtml(device.name)}</option>
      `))
      .join("");
  }

  function escapeHtml(value) {
    return String(value ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  async function loadData({ silent = false } = {}) {
    if (!state.auth.user) {
      state.loading = false;
      render();
      return;
    }

    if (!silent) {
      state.loading = true;
      state.error = "";
      render();
    }

    try {
      const [summary, devices, events, alerts] = await Promise.all([
        api.get("/api/summary"),
        api.get("/api/devices"),
        api.get("/api/events"),
        api.get("/api/alerts")
      ]);
      state.summary = asSummary(summary);
      state.devices = asArray(devices);
      state.events = asArray(events);
      state.alerts = asArray(alerts);
      if (!state.settings) {
        state.settings = asSettings(await api.get("/api/settings"));
      }
      state.error = "";
      evaluateCriticalSound();
    } catch (error) {
      state.error = error.message;
    } finally {
      state.loading = false;
      render();
    }
  }

  function setToast(message) {
    state.toast = message;
    render();
    window.clearTimeout(setToast.timer);
    setToast.timer = window.setTimeout(() => {
      state.toast = "";
      render();
    }, 2600);
  }

  async function loadAuthStatus() {
    try {
      const status = await api.get("/api/auth/status");
      state.auth.checked = true;
      state.auth.setupRequired = Boolean(status?.setup_required);
      state.auth.user = status?.authenticated ? status.user : null;
      state.auth.roles = asArray(status?.roles);
      state.auth.csrfToken = status?.csrf_token || "";
      state.settings = asSettings(status?.settings);
      if (!window.localStorage.getItem("sword-theme")) {
        applyTheme(state.settings.ui_theme || "system");
      }
      if (state.auth.user) {
        await loadData({ silent: true });
      } else {
        state.loading = false;
        render();
      }
    } catch (error) {
      state.auth.checked = true;
      state.loading = false;
      state.error = error.message;
      render();
    }
  }

  async function loadUsers() {
    if (!isAdmin()) {
      state.users = [];
      return;
    }

    state.users = asArray(await api.get("/api/users"));
  }

  async function loadAudit() {
    if (!isAdmin()) {
      state.audit = [];
      return;
    }

    state.audit = asArray(await api.get("/api/audit"));
    if (!state.users.length) {
      state.users = asArray(await api.get("/api/users"));
    }
    state.auditReport = await api.get(`/api/audit/report${buildQuery(state.auditFilters, "audit")}`);
  }

  async function loadSecurityData() {
    state.settings = asSettings(await api.get("/api/settings"));
    if (isAdmin()) {
      state.backups = asArray(await api.get("/api/backups"));
    }
  }

  async function loadReport() {
    state.report = await api.get(`/api/reports/availability${buildQuery(state.reportFilters, "report")}`);
    state.reportSnapshots = asArray(await api.get("/api/report-snapshots"));
  }

  async function loadHistoryReport() {
    state.historyReport = await api.get(`/api/history/report${buildQuery(state.historyFilters, "history")}`);
  }

  async function loadIntegrations() {
    if (!isAdmin()) {
      state.integrations = [];
      return;
    }
    state.integrations = asArray(await api.get("/api/integrations"));
  }

  function pageTitle() {
    const map = {
      dashboard: ["Dashboard", "Visao geral da infraestrutura"],
      operation: ["Operacao", "Disponibilidade, metodos e prioridades"],
      devices: ["Dispositivos", "Cadastro e operacao dos ativos monitorados"],
      alerts: ["Alertas", "Ocorrencias criticas em aberto"],
      history: ["Historico", "Eventos de disponibilidade e indisponibilidade"],
      reports: ["Relatorios", "Disponibilidade e SLA operacional"],
      users: ["Usuarios", "Controle de acesso e cargos"],
      audit: ["Auditoria", "Rastro de seguranca e operacao"],
      integrations: ["Integracoes", "Webhooks e automacoes externas"],
      security: ["Seguranca", "Configuracoes, backup e protecoes do Sword"]
    };
    return map[state.view] || map.dashboard;
  }

  function render() {
    try {
      if (!state.auth.checked) {
        app.innerHTML = `<div class="fatal-screen"><section class="panel">Carregando seguranca...</section></div>`;
        return;
      }

      if (state.auth.setupRequired) {
        app.innerHTML = renderSetupScreen();
        bindAuthEvents();
        return;
      }

      if (!state.auth.user) {
        app.innerHTML = renderLoginScreen();
        bindAuthEvents();
        return;
      }

      const [title, subtitle] = pageTitle();
      app.innerHTML = `
        <div class="app-shell">
          ${renderSidebar()}
          <main class="main">
            <header class="topbar">
              <div>
                <h1 class="page-title">${title}</h1>
                <div class="page-subtitle">${subtitle}</div>
              </div>
              <div class="top-actions">
                <div class="live-pill"><span class="live-dot"></span>Monitoramento ativo</div>
                <div class="timestamp">Atualizado: ${state.summary ? timeAgo(state.summary.generated_at) : "-"}</div>
                ${canOperate() ? `<button class="button" data-action="run-monitor">Verificar agora</button>` : ""}
                <select class="select compact-select" data-theme-select aria-label="Tema">
                  <option value="system"${state.theme === "system" ? " selected" : ""}>Sistema</option>
                  <option value="light"${state.theme === "light" ? " selected" : ""}>Claro</option>
                  <option value="dark"${state.theme === "dark" ? " selected" : ""}>Escuro</option>
                  <option value="blackout"${state.theme === "blackout" ? " selected" : ""}>Blackout</option>
                  <option value="steel"${state.theme === "steel" ? " selected" : ""}>Steel</option>
                  <option value="contrast"${state.theme === "contrast" ? " selected" : ""}>Contraste</option>
                </select>
                <button class="button" data-action="test-sound">Bipe</button>
                <button class="button" data-action="open-password-modal">Senha</button>
                <div class="user-chip">
                  ${renderAvatar(state.auth.user)}
                  <div>
                    <strong>${escapeHtml(state.auth.user.name)}</strong>
                    <div class="mini-text">${roleLabel(state.auth.user.role)}</div>
                  </div>
                </div>
                <button class="button" data-action="logout">Sair</button>
              </div>
            </header>
            <section class="content">
              ${state.loading ? `<div class="panel loading-panel">Carregando interface...</div>` : ""}
              ${state.error ? `<div class="panel error-panel"><strong>Erro:</strong> ${escapeHtml(state.error)} <button class="button" data-action="reload">Tentar novamente</button></div>` : ""}
              ${!state.loading && !state.error ? renderView() : ""}
            </section>
          </main>
          ${state.modal ? renderModal() : ""}
          ${state.userModal ? renderUserModal() : ""}
          ${state.passwordModal ? renderPasswordModal() : ""}
          ${state.integrationModal ? renderIntegrationModal() : ""}
          ${state.toast ? `<div class="toast">${escapeHtml(state.toast)}</div>` : ""}
        </div>
      `;

      bindEvents();
    } catch (error) {
      state.loading = false;
      app.innerHTML = `
        <div class="fatal-screen">
          <section class="panel">
            <h1 class="page-title">Falha ao renderizar a interface</h1>
            <p>${escapeHtml(error.message)}</p>
            <button class="button primary" id="fatal-reload">Recarregar dados</button>
          </section>
        </div>
      `;
      const button = document.getElementById("fatal-reload");
      if (button) button.addEventListener("click", () => loadData());
    }
  }

  function getInitials(name) {
    return String(name || "U")
      .trim()
      .split(/\s+/)
      .slice(0, 2)
      .map((part) => part[0] || "")
      .join("")
      .toUpperCase() || "U";
  }

  function swordLogo() {
    return `
      <svg viewBox="0 0 64 64" aria-hidden="true" focusable="false" class="sword-logo-svg">
        <path class="logo-halo" d="M32 4l7 7-3 8v22l12-9 7 8-17 8 2 6-8 6-8-6 2-6-17-8 7-8 12 9V19l-3-8 7-7z"></path>
        <path class="logo-blade" d="M32 4l6 10-4 8v27l-2 9-2-9V22l-4-8 6-10z"></path>
        <path class="logo-blade-line" d="M32 14v40"></path>
        <path class="logo-guard" d="M13 36c8-1 13 1 17 6h4c4-5 9-7 17-6"></path>
        <path class="logo-grip" d="M27 44h10M28 50h8M30 56h4"></path>
      </svg>
    `;
  }

  function deviceIcon(type) {
    const key = String(type || "Outro").toLowerCase();
    let shape = `<rect x="10" y="16" width="44" height="30" rx="4"></rect><path d="M24 54h16M29 46v8M35 46v8"></path>`;
    if (key.includes("servidor")) shape = `<rect x="18" y="8" width="28" height="48" rx="4"></rect><path d="M24 18h16M24 30h16M24 42h16"></path><circle cx="39" cy="50" r="2"></circle>`;
    if (key.includes("banco")) shape = `<ellipse cx="32" cy="14" rx="18" ry="7"></ellipse><path d="M14 14v30c0 4 8 7 18 7s18-3 18-7V14"></path><path d="M14 29c0 4 8 7 18 7s18-3 18-7"></path>`;
    if (key.includes("firewall")) shape = `<path d="M12 18h40v30H12z"></path><path d="M12 28h40M22 18v10M34 18v10M46 28v10M12 38h40M28 38v10M40 38v10"></path>`;
    if (key.includes("switch") || key.includes("roteador")) shape = `<rect x="10" y="24" width="44" height="20" rx="4"></rect><circle cx="19" cy="34" r="2"></circle><circle cx="27" cy="34" r="2"></circle><circle cx="35" cy="34" r="2"></circle><path d="M44 31l6 6M50 31l-6 6"></path>`;
    if (key.includes("access")) shape = `<circle cx="32" cy="42" r="4"></circle><path d="M18 30a20 20 0 0128 0M24 36a11 11 0 0116 0M12 24a29 29 0 0140 0"></path>`;
    if (key.includes("impressora")) shape = `<path d="M18 24V10h28v14"></path><rect x="12" y="24" width="40" height="22" rx="4"></rect><path d="M20 42h24v12H20zM20 18h24"></path>`;
    if (key.includes("notebook")) shape = `<rect x="14" y="14" width="36" height="28" rx="3"></rect><path d="M8 50h48l-6-8H14z"></path>`;
    if (key.includes("camera")) shape = `<rect x="14" y="22" width="28" height="18" rx="4"></rect><path d="M42 28l10-6v18l-10-6z"></path><circle cx="28" cy="31" r="5"></circle>`;
    if (key.includes("telefone") || key.includes("celular")) shape = `<rect x="22" y="8" width="20" height="48" rx="5"></rect><path d="M29 48h6"></path>`;
    if (key.includes("storage") || key.includes("nas")) shape = `<rect x="14" y="10" width="36" height="44" rx="4"></rect><path d="M20 22h24M20 34h24M20 46h24"></path><circle cx="41" cy="17" r="2"></circle>`;
    if (key.includes("nobreak") || key.includes("ups")) shape = `<rect x="18" y="10" width="28" height="44" rx="4"></rect><path d="M32 18l-6 14h7l-3 14 8-18h-7z"></path>`;
    return `<span class="equipment-icon"><svg viewBox="0 0 64 64" aria-hidden="true" focusable="false">${shape}</svg></span>`;
  }

  function renderAuthShell(title, subtitle, formHtml) {
    return `
      <div class="auth-screen">
        <section class="auth-panel">
          <div class="auth-brand">
            <div class="brand-mark sword-mark">${swordLogo()}</div>
            <div>
              <div class="brand-title">Sword</div>
              <div class="brand-subtitle">Acesso seguro ao painel</div>
            </div>
          </div>
          <h1>${title}</h1>
          <p>${subtitle}</p>
          ${state.error ? `<div class="auth-error">${escapeHtml(state.error)}</div>` : ""}
          ${formHtml}
        </section>
      </div>
    `;
  }

  function renderSetupScreen() {
    return renderAuthShell(
      "Criar administrador",
      "Configure o primeiro usuario com permissao total para iniciar o Sword 5.0.",
      `
        <form class="auth-form" id="setup-form">
          <label>Nome<input class="input" name="name" required autocomplete="name"></label>
          <label>Email<input class="input" name="email" required type="email" autocomplete="email"></label>
          <label>Senha<input class="input" name="password" required type="password" minlength="6" autocomplete="new-password"></label>
          <button class="button primary" type="submit">Criar administrador</button>
        </form>
      `
    );
  }

  function renderLoginScreen() {
    return renderAuthShell(
      "Entrar no sistema",
      "Use seu usuario para acessar o dashboard, alertas e historico.",
      `
        <form class="auth-form" id="login-form">
          <label>Email<input class="input" name="email" required type="email" autocomplete="email"></label>
          <label>Senha<input class="input" name="password" required type="password" autocomplete="current-password"></label>
          <button class="button primary" type="submit">Entrar</button>
        </form>
      `
    );
  }

  function bindAuthEvents() {
    const setupForm = document.getElementById("setup-form");
    if (setupForm) setupForm.addEventListener("submit", handleSetupSubmit);

    const loginForm = document.getElementById("login-form");
    if (loginForm) loginForm.addEventListener("submit", handleLoginSubmit);
  }

  function renderSidebar() {
    const count = openAlerts().length;
    const items = [
      ["dashboard", "DB", "Dashboard"],
      ["operation", "OP", "Operacao"],
      ["devices", "DV", "Dispositivos"],
      ["alerts", "AL", "Alertas"],
      ["history", "EV", "Historico"],
      ["reports", "RP", "Relatorios"],
      ["security", "SC", "Seguranca"]
    ];
    if (isAdmin()) {
      items.push(["integrations", "IN", "Integracoes"]);
      items.push(["users", "US", "Usuarios"]);
      items.push(["audit", "AU", "Auditoria"]);
    }

    return `
      <aside class="sidebar">
        <div class="brand">
          <div class="brand-mark sword-mark">${swordLogo()}</div>
          <div>
            <div class="brand-title">Sword</div>
            <div class="brand-subtitle">Infraestrutura protegida</div>
          </div>
        </div>
        <nav class="nav">
          ${items.map(([view, icon, label]) => `
            <button class="nav-button ${state.view === view ? "active" : ""}" data-view="${view}">
              <span class="nav-icon">${icon}</span>
              <span class="nav-label">${label}</span>
              ${view === "alerts" && count ? `<span class="nav-badge">${count}</span>` : ""}
            </button>
          `).join("")}
        </nav>
        <div class="sidebar-spacer"></div>
        <div class="sidebar-info">
          <div class="mini-panel">
            <div class="mini-title">Sessao segura</div>
            <div class="mini-text">${escapeHtml(state.auth.user.email)}</div>
          </div>
          <div class="mini-panel">
            <div class="mini-title">Base de dados</div>
            <div class="mini-text">data/store.json</div>
          </div>
        </div>
      </aside>
    `;
  }

  function renderView() {
    if (state.view === "devices") return renderDevicesPage();
    if (state.view === "operation") return renderOperationPage();
    if (state.view === "alerts") return renderAlertsPage();
    if (state.view === "history") return renderHistoryPage();
    if (state.view === "reports") return renderReportsPage();
    if (state.view === "users") return renderUsersPage();
    if (state.view === "audit") return renderAuditPage();
    if (state.view === "integrations") return renderIntegrationsPage();
    if (state.view === "security") return renderSecurityPage();
    return renderDashboard();
  }

  function renderMetrics() {
    const summary = state.summary || { total: 0, online: 0, offline: 0, critical_offline: 0 };
    const onlinePercent = summary.total ? Math.round((summary.online / summary.total) * 100) : 0;
    const offlinePercent = summary.total ? Math.round((summary.offline / summary.total) * 100) : 0;

    return `
      <div class="metric-grid">
        <article class="metric-card">
          <div class="metric-icon">ALL</div>
          <div>
            <div class="metric-label">Total de dispositivos</div>
            <div class="metric-value">${summary.total}</div>
            <div class="metric-help">Dispositivos ativos monitorados</div>
          </div>
        </article>
        <article class="metric-card">
          <div class="metric-icon green">ON</div>
          <div>
            <div class="metric-label">Online</div>
            <div class="metric-value">${summary.online}</div>
            <div class="metric-help">${onlinePercent}% do total</div>
          </div>
        </article>
        <article class="metric-card">
          <div class="metric-icon red">OFF</div>
          <div>
            <div class="metric-label">Offline</div>
            <div class="metric-value">${summary.offline}</div>
            <div class="metric-help">${offlinePercent}% do total</div>
          </div>
        </article>
        <article class="metric-card">
          <div class="metric-icon amber">!</div>
          <div>
            <div class="metric-label">Criticos offline</div>
            <div class="metric-value">${summary.critical_offline}</div>
            <div class="metric-help">Requer atencao imediata</div>
          </div>
        </article>
      </div>
    `;
  }

  function renderDashboard() {
    if (asArray(state.devices).length === 0) {
      return `
        ${renderMetrics()}
        ${renderEmptyOnboarding()}
      `;
    }

    return `
      ${renderMetrics()}
      <div class="dashboard-grid">
        <div class="stack">
          ${renderDevicesTable({ dashboard: true })}
          ${renderTimeline()}
        </div>
        <div class="stack">
          ${renderCriticalAlerts()}
          ${renderStatusDonut()}
          ${renderRecentEvents()}
        </div>
      </div>
    `;
  }

  function renderEmptyOnboarding() {
    return `
      <section class="panel empty-onboarding">
        <div>
          <div class="empty-kicker">Base limpa</div>
          <h2>Nenhum dispositivo cadastrado</h2>
          <p>Cadastre os ativos reais da rede para iniciar as verificacoes de disponibilidade.</p>
        </div>
        <div class="empty-actions">
          ${canOperate() ? `<button class="button primary" data-action="new-device">Cadastrar dispositivo</button>` : ""}
          <button class="button" data-view="devices">Abrir cadastro</button>
        </div>
      </section>
    `;
  }

  function renderDevicesPage() {
    return `
      ${renderMetrics()}
      ${renderDevicesTable({ dashboard: false })}
    `;
  }

  function renderOperationPage() {
    const currentRows = reportRows();
    const report = currentRows.length ? currentRows : asArray(state.devices).map((device) => ({
      device_id: device.id,
      name: device.name,
      host: device.host,
      type: device.type,
      criticality: device.criticality,
      current_status: device.current_status,
      check_method: device.check_method || "ping",
      availability_percent: device.current_status === "online" ? 100 : 0,
      down_seconds: 0,
      open_incident: device.current_status === "offline"
    }));
    const worst = report.slice(0, 8);
    return `
      ${renderMetrics()}
      <section class="table-panel">
        <div class="section-header" style="padding: 18px 18px 0;">
          <h2 class="section-title">Painel operacional</h2>
          <button class="button" data-action="refresh-report">Atualizar relatorio</button>
        </div>
        <div class="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Ativo</th>
                <th>Metodo</th>
                <th>Criticidade</th>
                <th>Status</th>
                <th>Disponibilidade 24h</th>
                <th>Indisponibilidade 24h</th>
                <th>Incidente</th>
              </tr>
            </thead>
            <tbody>
              ${worst.map((row) => `
                <tr>
                  <td><div class="device-name">${deviceIcon(row.type)}<span>${escapeHtml(row.name)}</span></div><div class="mini-text">${escapeHtml(row.host)}</div></td>
                  <td><span class="badge inactive">${escapeHtml(methodLabel(row.check_method))}</span></td>
                  <td><span class="badge ${criticalityClass(row.criticality)}">${labelCriticality(row.criticality)}</span></td>
                  <td><span class="badge ${row.current_status}">${String(row.current_status || "-").toUpperCase()}</span></td>
                  <td><strong>${Number(row.availability_percent || row.availability_24h || 0).toFixed(2)}%</strong></td>
                  <td>${formatDuration(row.down_seconds || row.down_seconds_24h || 0)}</td>
                  <td>${row.open_incident ? `<span class="badge offline">ABERTO</span>` : `<span class="badge online">OK</span>`}</td>
                </tr>
              `).join("") || `<tr><td colspan="7"><div class="empty-state">Sem dados operacionais ainda.</div></td></tr>`}
            </tbody>
          </table>
        </div>
      </section>
    `;
  }

  function renderFilters() {
    const types = [...new Set(DEVICE_TYPES.concat(asArray(state.devices).map((device) => device.type).filter(Boolean)))].sort();
    return `
      <div class="filters">
        <input class="input" data-filter="search" placeholder="Buscar dispositivo..." value="${escapeHtml(state.filters.search)}">
        <select class="select" data-filter="status">
          <option value="all"${state.filters.status === "all" ? " selected" : ""}>Todos os status</option>
          <option value="online"${state.filters.status === "online" ? " selected" : ""}>Online</option>
          <option value="offline"${state.filters.status === "offline" ? " selected" : ""}>Offline</option>
        </select>
        <select class="select" data-filter="type">${options(types, state.filters.type, "Todos os tipos")}</select>
        <select class="select" data-filter="criticality">
          <option value="all"${state.filters.criticality === "all" ? " selected" : ""}>Todas as criticidades</option>
          <option value="baixa"${state.filters.criticality === "baixa" ? " selected" : ""}>Baixa</option>
          <option value="media"${state.filters.criticality === "media" ? " selected" : ""}>Media</option>
          <option value="alta"${state.filters.criticality === "alta" ? " selected" : ""}>Alta</option>
          <option value="critica"${state.filters.criticality === "critica" ? " selected" : ""}>Critica</option>
        </select>
        ${canOperate() ? `<button class="button primary" data-action="new-device">Novo dispositivo</button>` : ""}
      </div>
    `;
  }

  function renderDevicesTable({ dashboard }) {
    const devices = filteredDevices();
    const visible = dashboard ? devices.slice(0, 8) : devices;
    const hasAnyDevice = asArray(state.devices).length > 0;
    const emptyText = hasAnyDevice ? "Nenhum dispositivo encontrado para os filtros atuais." : "Nenhum dispositivo cadastrado.";

    return `
      <section class="table-panel">
        <div class="section-header" style="padding: 18px 18px 0;">
          <h2 class="section-title">Dispositivos monitorados</h2>
          ${renderFilters()}
        </div>
        <div class="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Nome</th>
                <th>IP/Host</th>
                <th>Tipo</th>
                <th>Localizacao</th>
                <th>Criticidade</th>
                <th>Ultima verificacao</th>
                <th>Status</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              ${visible.map(renderDeviceRow).join("") || `<tr><td colspan="8"><div class="empty-state">${emptyText}${canOperate() ? `<br><button class="button primary" data-action="new-device">Cadastrar dispositivo</button>` : ""}</div></td></tr>`}
            </tbody>
          </table>
        </div>
        <div class="mini-text" style="padding: 0 18px 18px;">Exibindo ${visible.length} de ${devices.length} dispositivo(s)</div>
      </section>
    `;
  }

  function renderDeviceRow(device) {
    const maintenance = isMaintenanceActive(device);
    const status = device.is_active ? (maintenance ? "maintenance" : device.current_status) : "inactive";
    const lastCheck = device.last_check_at ? timeAgo(device.last_check_at) : "Nunca verificado";
    const endpoint = [methodLabel(device.check_method), device.port ? `porta ${device.port}` : "", device.url_path && device.url_path !== "/" ? device.url_path : ""]
      .filter(Boolean)
      .join(" - ");
    return `
      <tr>
        <td>
          <div class="device-name">
            <span class="status-dot ${device.current_status}"></span>
            ${deviceIcon(device.type)}
            ${escapeHtml(device.name)}
          </div>
          <div class="mini-text">${escapeHtml([device.serial_number, device.asset_tag, device.model].filter(Boolean).join(" - "))}</div>
        </td>
        <td>${escapeHtml(device.host)}<div class="mini-text">${escapeHtml(endpoint)}</div></td>
        <td>${escapeHtml(device.type)}</td>
        <td>${escapeHtml(device.location)}</td>
        <td><span class="badge ${criticalityClass(device.criticality)}">${labelCriticality(device.criticality)}</span></td>
        <td>${lastCheck}</td>
        <td><span class="badge ${status}">${status === "inactive" ? "INATIVO" : status === "maintenance" ? "MANUTENCAO" : device.current_status.toUpperCase()}</span></td>
        <td>
          ${canOperate() ? `
            <div class="row-actions">
              <button class="button compact" title="Verificar agora" data-action="check-device" data-id="${device.id}">Verificar</button>
              <button class="button compact" title="Editar" data-action="edit-device" data-id="${device.id}">Editar</button>
              <button class="button compact danger" title="Remover" data-action="delete-device" data-id="${device.id}">Excluir</button>
            </div>
          ` : ""}
        </td>
      </tr>
    `;
  }

  function renderCriticalAlerts() {
    const alerts = openAlerts().slice(0, 6);
    return `
      <section class="panel">
        <div class="section-header">
          <h2 class="section-title">Alertas criticos</h2>
          <button class="button" data-view="alerts">Ver todos (${openAlerts().length})</button>
        </div>
        <div class="alert-list">
          ${alerts.map(renderAlertItem).join("") || `<div class="empty-state">Nenhum alerta critico aberto.</div>`}
        </div>
      </section>
    `;
  }

  function renderAlertItem(alert) {
    const device = alert.device || {};
    const priorityClass = alert.priority === "high" ? "high" : "";
    return `
      <article class="alert-item ${priorityClass}">
        <span class="status-dot offline"></span>
        <div>
          <div class="alert-title">${escapeHtml(alert.title)}</div>
          <div class="alert-meta">${escapeHtml(device.location || "-")} - ${escapeHtml(device.host || "-")} - ${timeAgo(alert.created_at)}</div>
        </div>
        ${canOperate() ? `<button class="button" data-action="resolve-alert" data-id="${alert.id}">Resolver</button>` : ""}
      </article>
    `;
  }

  function renderStatusDonut() {
    const summary = state.summary || { total: 0, online: 0, offline: 0, critical_offline: 0 };
    const total = Math.max(1, summary.total);
    const onlineDeg = (summary.online / total) * 360;
    const offlineDeg = onlineDeg + (summary.offline / total) * 360;
    const attention = Math.max(0, summary.critical_offline);
    const donutClass = summary.total === 0 ? "donut empty" : "donut";

    return `
      <section class="panel">
        <h2 class="section-title">Status geral dos dispositivos</h2>
        <div class="donut-wrap" style="margin-top: 16px;">
          <div class="${donutClass}" style="--online:${onlineDeg}deg;--offline:${offlineDeg}deg;"></div>
          <div class="legend">
            <div class="legend-row"><span class="status-dot online"></span><span>Online</span><strong>${summary.online}</strong></div>
            <div class="legend-row"><span class="status-dot offline"></span><span>Offline</span><strong>${summary.offline}</strong></div>
            <div class="legend-row"><span class="status-dot" style="background: var(--amber);"></span><span>Atencao</span><strong>${attention}</strong></div>
            <div class="mini-text">Total: ${summary.total} dispositivo(s)</div>
          </div>
        </div>
      </section>
    `;
  }

  function renderTimeline() {
    const rows = asArray(state.devices).slice(0, 6).map((device) => {
      const cls = device.current_status === "offline" ? "offline" : (device.criticality === "alta" || device.criticality === "critica" ? "attention" : "");
      return `
        <div class="timeline-row">
          <strong>${escapeHtml(device.name)}</strong>
          <div class="timeline-track"><div class="timeline-fill ${cls}"></div></div>
        </div>
      `;
    }).join("");

    return `
      <section class="panel">
        <div class="section-header">
          <h2 class="section-title">Linha do tempo de disponibilidade (24h)</h2>
          <div class="mini-text">Online - Offline - Atencao</div>
        </div>
        <div class="timeline">${rows || `<div class="empty-state">Sem dispositivos cadastrados.</div>`}</div>
      </section>
    `;
  }

  function renderRecentEvents() {
    const events = filteredEvents().slice(0, 5);
    return `
      <section class="panel">
        <div class="section-header">
          <h2 class="section-title">Historico recente de eventos</h2>
          <button class="button" data-view="history">Abrir</button>
        </div>
        <div class="table-scroll">
          <table>
            <thead>
              <tr><th>Dispositivo</th><th>Evento</th><th>Data/Hora</th><th>Duracao</th></tr>
            </thead>
            <tbody>
              ${events.map((event) => `
                <tr>
                  <td><span class="status-dot ${event.status === "open" ? "offline" : "online"}"></span> ${escapeHtml(event.device?.name || event.device_id)}</td>
                  <td>${event.status === "open" ? "down_at" : "up_at"}</td>
                  <td>${formatDate(event.status === "open" ? event.down_at : event.up_at)}</td>
                  <td>${event.status === "open" ? timeAgo(event.down_at) : formatDuration(event.duration_seconds)}</td>
                </tr>
              `).join("") || `<tr><td colspan="4"><div class="empty-state">Sem eventos registrados.</div></td></tr>`}
            </tbody>
          </table>
        </div>
      </section>
    `;
  }

  function renderAlertsPage() {
    const alerts = openAlerts();
    return `
      ${renderMetrics()}
      <section class="panel">
        <div class="section-header">
          <h2 class="section-title">Alertas criticos em aberto</h2>
          ${canOperate() ? `<button class="button" data-action="run-monitor">Atualizar monitoramento</button>` : ""}
        </div>
        <div class="alert-list">
          ${alerts.map(renderAlertItem).join("") || `<div class="empty-state">Nenhum alerta aberto neste momento.</div>`}
        </div>
      </section>
    `;
  }

  function renderHistoryPage() {
    let rows = historyRows().length ? historyRows() : filteredEvents().map((event) => ({
      device_name: event.device?.name || event.device_id,
      host: event.device?.host || "",
      event_type: event.status === "open" ? "down_aberto" : "down_up_resolvido",
      down_at: event.down_at,
      up_at: event.up_at,
      duration_seconds: event.status === "open" ? null : event.duration_seconds,
      criticality: event.criticality,
      status: event.status
    }));
    rows = rows.filter((row) => {
      const statusMatch = state.historyFilters.status === "all" || row.status === state.historyFilters.status;
      const criticalityMatch = state.historyFilters.criticality === "all" || row.criticality === state.historyFilters.criticality;
      return statusMatch && criticalityMatch;
    });
    const summary = state.historyReport?.summary || {};
    return `
      <section class="table-panel">
        <div class="section-header" style="padding: 18px 18px 0;">
          <h2 class="section-title">Historico de disponibilidade</h2>
          <div class="filters">
            <select class="select" data-history-filter="device">
              ${deviceOptions(state.historyFilters.device, "Todos os dispositivos")}
            </select>
            <select class="select" data-history-filter="status">
              <option value="all"${state.historyFilters.status === "all" ? " selected" : ""}>Todos os status</option>
              <option value="open"${state.historyFilters.status === "open" ? " selected" : ""}>Aberto</option>
              <option value="resolved"${state.historyFilters.status === "resolved" ? " selected" : ""}>Resolvido</option>
            </select>
            <select class="select" data-history-filter="criticality">
              <option value="all"${state.historyFilters.criticality === "all" ? " selected" : ""}>Todas as criticidades</option>
              <option value="baixa"${state.historyFilters.criticality === "baixa" ? " selected" : ""}>Baixa</option>
              <option value="media"${state.historyFilters.criticality === "media" ? " selected" : ""}>Media</option>
              <option value="alta"${state.historyFilters.criticality === "alta" ? " selected" : ""}>Alta</option>
              <option value="critica"${state.historyFilters.criticality === "critica" ? " selected" : ""}>Critica</option>
            </select>
            <input class="input compact-date" type="datetime-local" data-history-filter="from" value="${escapeHtml(state.historyFilters.from)}">
            <input class="input compact-date" type="datetime-local" data-history-filter="to" value="${escapeHtml(state.historyFilters.to)}">
            <button class="button" data-action="apply-history-report">Filtrar</button>
            <button class="button" data-action="download-history">Baixar Excel</button>
            ${isAdmin() ? `<button class="button danger" data-action="clear-history">Limpar historico</button>` : ""}
          </div>
        </div>
        <div class="report-strip">
          <span><strong>${Number(summary.events || rows.length)}</strong> evento(s)</span>
          <span><strong>${Number(summary.open_events || 0)}</strong> aberto(s)</span>
          <span><strong>${formatDuration(summary.total_duration_seconds || 0)}</strong> indisponibilidade total</span>
        </div>
        <div class="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Dispositivo</th>
                <th>Host</th>
                <th>Evento</th>
                <th>Down</th>
                <th>Up</th>
                <th>Duracao</th>
                <th>Criticidade</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              ${rows.map(renderHistoryRow).join("") || `<tr><td colspan="8"><div class="empty-state">Sem eventos para os filtros atuais.</div></td></tr>`}
            </tbody>
          </table>
        </div>
      </section>
    `;
  }

  function renderHistoryRow(event) {
    const type = event.event_type || (event.status === "open" ? "down" : "up");
    return `
      <tr>
        <td>${escapeHtml(event.device_name || event.device?.name || event.device_id)}</td>
        <td>${escapeHtml(event.host || event.device?.host || "-")}</td>
        <td>${escapeHtml(type)}</td>
        <td>${formatDate(event.down_at)}</td>
        <td>${formatDate(event.up_at)}</td>
        <td>${event.status === "open" ? timeAgo(event.down_at) : formatDuration(event.duration_seconds)}</td>
        <td><span class="badge ${criticalityClass(event.criticality)}">${labelCriticality(event.criticality)}</span></td>
        <td><span class="badge ${event.status === "open" ? "offline" : "online"}">${event.status === "open" ? "ABERTO" : "RESOLVIDO"}</span></td>
      </tr>
    `;
  }

  function renderReportsPage() {
    const report = reportRows();
    const summary = state.report?.summary || {};
    const avg = Number(summary.availability_percent || (report.length ? report.reduce((sum, item) => sum + Number(item.availability_percent || 0), 0) / report.length : 0));
    const down = Number(summary.total_down_seconds || report.reduce((sum, item) => sum + Number(item.down_seconds || 0), 0));
    return `
      <div class="metric-grid">
        <article class="metric-card"><div class="metric-icon green">SLA</div><div><div class="metric-label">Disponibilidade</div><div class="metric-value">${avg.toFixed(2)}%</div><div class="metric-help">Periodo filtrado</div></div></article>
        <article class="metric-card"><div class="metric-icon red">DOWN</div><div><div class="metric-label">Indisponibilidade</div><div class="metric-value">${formatDuration(down)}</div><div class="metric-help">Soma no periodo</div></div></article>
        <article class="metric-card"><div class="metric-icon amber">INC</div><div><div class="metric-label">Incidentes abertos</div><div class="metric-value">${Number(summary.open_incidents || report.filter((item) => item.open_incident).length)}</div><div class="metric-help">Ativos com queda aberta</div></div></article>
        <article class="metric-card"><div class="metric-icon">REP</div><div><div class="metric-label">Ativos avaliados</div><div class="metric-value">${report.length}</div><div class="metric-help">Base do relatorio</div></div></article>
      </div>
      <section class="table-panel">
        <div class="section-header" style="padding: 18px 18px 0;">
          <h2 class="section-title">Relatorio de disponibilidade por ativo</h2>
          <div class="filters">
            <select class="select" data-report-filter="device">${deviceOptions(state.reportFilters.device, "Todos os dispositivos")}</select>
            <input class="input compact-date" type="datetime-local" data-report-filter="from" value="${escapeHtml(state.reportFilters.from)}">
            <input class="input compact-date" type="datetime-local" data-report-filter="to" value="${escapeHtml(state.reportFilters.to)}">
            <button class="button" data-action="refresh-report">Filtrar</button>
            <button class="button primary" data-action="download-report">Baixar Excel</button>
            ${isAdmin() ? `<button class="button danger" data-action="clear-reports">Limpar relatorios</button>` : ""}
          </div>
        </div>
        <div class="report-strip">
          <span><strong>${formatDuration(summary.total_up_seconds || 0)}</strong> online</span>
          <span><strong>${formatDuration(summary.total_down_seconds || 0)}</strong> offline</span>
          <span><strong>${Number(summary.attention || 0)}</strong> em atencao</span>
          <span><strong>${Number(summary.events || 0)}</strong> evento(s)</span>
        </div>
        <div class="table-scroll">
          <table>
            <thead><tr><th>Ativo</th><th>Host</th><th>Metodo</th><th>Disponibilidade</th><th>Online</th><th>Offline</th><th>MTTR</th><th>Atencao</th><th>Incidente</th></tr></thead>
            <tbody>
              ${report.map((row) => `
                <tr>
                  <td><div class="device-name">${deviceIcon(row.type)}<span>${escapeHtml(row.name)}</span></div><div class="mini-text">${escapeHtml([row.serial_number, row.asset_tag, row.model].filter(Boolean).join(" - "))}</div></td>
                  <td>${escapeHtml(row.host)}<div class="mini-text">${escapeHtml(row.location || "-")}</div></td>
                  <td><span class="badge inactive">${escapeHtml(methodLabel(row.check_method))}</span></td>
                  <td><strong>${Number(row.availability_percent || 0).toFixed(2)}%</strong></td>
                  <td>${formatDuration(row.up_seconds || 0)}</td>
                  <td>${formatDuration(row.down_seconds || 0)}</td>
                  <td>${formatDuration(row.mttr_seconds || 0)}</td>
                  <td><span class="badge ${row.attention_level === "critica" ? "critical" : row.attention_level === "alta" ? "high" : row.attention_level === "media" ? "medium" : "low"}">${escapeHtml(row.attention_label || "Normal")}</span></td>
                  <td>${row.open_incident ? `<span class="badge offline">ABERTO</span>` : `<span class="badge online">OK</span>`}</td>
                </tr>
              `).join("") || `<tr><td colspan="9"><div class="empty-state">Sem dados de relatorio.</div></td></tr>`}
            </tbody>
          </table>
        </div>
      </section>
      <section class="panel">
        <div class="section-header">
          <h2 class="section-title">Arquivos gerados</h2>
          <span class="mini-text">${asArray(state.reportSnapshots).length} registro(s)</span>
        </div>
        <div class="snapshot-grid">
          ${asArray(state.reportSnapshots).slice(0, 8).map((item) => `
            <article class="mini-panel">
              <div class="mini-title">${escapeHtml(item.kind)}</div>
              <div class="mini-text">${formatDate(item.created_at)} - ${Number(item.row_count || 0)} linha(s)</div>
            </article>
          `).join("") || `<div class="empty-state">Nenhum arquivo gerado ainda.</div>`}
        </div>
      </section>
    `;
  }

  function renderIntegrationsPage() {
    if (!isAdmin()) return `<section class="panel">Apenas administradores podem acessar integracoes.</section>`;
    return `
      <section class="table-panel">
        <div class="section-header" style="padding: 18px 18px 0;">
          <h2 class="section-title">Integracoes por webhook</h2>
          <button class="button primary" data-action="new-integration">Nova integracao</button>
        </div>
        <div class="table-scroll">
          <table>
            <thead><tr><th>Nome</th><th>Tipo</th><th>URL</th><th>Segredo</th><th>Status</th><th>Atualizado</th><th></th></tr></thead>
            <tbody>
              ${asArray(state.integrations).map((integration) => `
                <tr>
                  <td><strong>${escapeHtml(integration.name)}</strong></td>
                  <td><span class="badge inactive">${escapeHtml(integration.type)}</span></td>
                  <td>${escapeHtml(integration.url)}</td>
                  <td><span class="badge ${integration.secret_configured ? "online" : "inactive"}">${integration.secret_configured ? "CONFIGURADO" : "VAZIO"}</span></td>
                  <td><span class="badge ${integration.enabled ? "online" : "inactive"}">${integration.enabled ? "ATIVA" : "INATIVA"}</span></td>
                  <td>${integration.updated_at ? timeAgo(integration.updated_at) : "-"}</td>
                  <td><div class="row-actions"><button class="button compact" data-action="edit-integration" data-id="${integration.id}">Editar</button><button class="button compact danger" data-action="delete-integration" data-id="${integration.id}">Excluir</button></div></td>
                </tr>
              `).join("") || `<tr><td colspan="7"><div class="empty-state">Nenhuma integracao cadastrada.</div></td></tr>`}
            </tbody>
          </table>
        </div>
      </section>
    `;
  }

  function renderUsersPage() {
    if (!isAdmin()) {
      return `<section class="panel">Apenas administradores podem acessar usuarios.</section>`;
    }

    return `
      <section class="table-panel">
        <div class="section-header" style="padding: 18px 18px 0;">
          <h2 class="section-title">Usuarios e cargos</h2>
          <button class="button primary" data-action="new-user">Novo usuario</button>
        </div>
        <div class="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Nome</th>
                <th>Email</th>
                <th>Cargo</th>
                <th>Status</th>
                <th>Ultimo login</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              ${asArray(state.users).map(renderUserRow).join("") || `<tr><td colspan="6"><div class="empty-state">Nenhum usuario encontrado.</div></td></tr>`}
            </tbody>
          </table>
        </div>
      </section>
    `;
  }

  function renderUserRow(user) {
    const isSelf = state.auth.user && state.auth.user.id === user.id;
    return `
      <tr>
        <td><div class="user-inline">${renderAvatar(user)}<strong>${escapeHtml(user.name)}</strong>${isSelf ? ` <span class="badge inactive">VOCE</span>` : ""}</div></td>
        <td>${escapeHtml(user.email)}</td>
        <td><span class="badge ${user.role === "admin" ? "critical" : user.role === "operator" ? "high" : "low"}">${roleLabel(user.role)}</span></td>
        <td><span class="badge ${user.status === "active" ? "online" : "inactive"}">${user.status === "active" ? "ATIVO" : "INATIVO"}</span></td>
        <td>${user.last_login_at ? timeAgo(user.last_login_at) : "Nunca"}</td>
        <td>
          <div class="row-actions">
            <button class="button compact" data-action="edit-user" data-id="${user.id}">Editar</button>
            <button class="button compact danger" data-action="delete-user" data-id="${user.id}" ${isSelf ? "disabled" : ""}>Excluir</button>
          </div>
        </td>
      </tr>
    `;
  }

  function renderAuditPage() {
    if (!isAdmin()) {
      return `<section class="panel">Apenas administradores podem acessar auditoria.</section>`;
    }
    const rows = auditRows().length ? auditRows() : asArray(state.audit);
    const summary = state.auditReport?.summary || {};

    return `
      <div class="metric-grid">
        <article class="metric-card"><div class="metric-icon">AUD</div><div><div class="metric-label">Registros</div><div class="metric-value">${Number(summary.entries || rows.length)}</div><div class="metric-help">Periodo filtrado</div></div></article>
        <article class="metric-card"><div class="metric-icon red">FAIL</div><div><div class="metric-label">Falhas login</div><div class="metric-value">${Number(summary.failed_logins || 0)}</div><div class="metric-help">Tentativas invalidas</div></div></article>
        <article class="metric-card"><div class="metric-icon amber">CSRF</div><div><div class="metric-label">CSRF bloqueado</div><div class="metric-value">${Number(summary.blocked_csrf || 0)}</div><div class="metric-help">Escritas recusadas</div></div></article>
        <article class="metric-card"><div class="metric-icon green">USR</div><div><div class="metric-label">Usuarios</div><div class="metric-value">${Number(summary.users || 0)}</div><div class="metric-help">Com eventos</div></div></article>
      </div>
      <section class="table-panel">
        <div class="section-header" style="padding: 18px 18px 0;">
          <h2 class="section-title">Auditoria de seguranca</h2>
          <div class="filters">
            <select class="select" data-audit-filter="user">${[`<option value="all"${state.auditFilters.user === "all" ? " selected" : ""}>Todos os usuarios</option>`].concat(asArray(state.users).map((user) => `<option value="${escapeHtml(user.id)}"${state.auditFilters.user === user.id ? " selected" : ""}>${escapeHtml(user.name)}</option>`)).join("")}</select>
            <input class="input" data-audit-filter="action" placeholder="Acao..." value="${escapeHtml(state.auditFilters.action)}">
            <input class="input compact-date" type="datetime-local" data-audit-filter="from" value="${escapeHtml(state.auditFilters.from)}">
            <input class="input compact-date" type="datetime-local" data-audit-filter="to" value="${escapeHtml(state.auditFilters.to)}">
            <button class="button" data-action="refresh-audit">Filtrar</button>
            <button class="button primary" data-action="download-audit">Baixar Excel</button>
          </div>
        </div>
        <div class="table-scroll">
          <table>
            <thead>
              <tr>
                <th>Data</th>
                <th>Usuario</th>
                <th>Acao</th>
                <th>Entidade</th>
                <th>ID</th>
              </tr>
            </thead>
            <tbody>
              ${rows.map((row) => `
                <tr>
                  <td>${formatDate(row.created_at)}</td>
                  <td>${escapeHtml(row.user_name || "Sistema")}</td>
                  <td><span class="badge inactive">${escapeHtml(row.action)}</span></td>
                  <td>${escapeHtml(row.entity_type || "-")}</td>
                  <td>${escapeHtml(row.entity_id || "-")}</td>
                </tr>
              `).join("") || `<tr><td colspan="5"><div class="empty-state">Nenhum evento de auditoria encontrado.</div></td></tr>`}
            </tbody>
          </table>
        </div>
      </section>
    `;
  }

  function renderSecurityPage() {
    const settings = asSettings(state.settings);
    return `
      <div class="dashboard-grid">
        <section class="panel">
          <div class="section-header">
            <h2 class="section-title">Postura de seguranca</h2>
            <span class="badge online">HARDENED LOCAL</span>
          </div>
          <div class="security-grid">
            <div class="security-item"><strong>CSRF</strong><span>${settings.require_csrf ? "Ativo" : "Inativo"}</span></div>
            <div class="security-item"><strong>Sessao</strong><span>${settings.session_hours}h</span></div>
            <div class="security-item"><strong>Rate limit</strong><span>${settings.login_rate_limit_max_attempts} tentativas / ${settings.login_rate_limit_window_minutes}min</span></div>
            <div class="security-item"><strong>Auditoria</strong><span>${settings.audit_retention_days} dias</span></div>
          </div>
          <div class="empty-state security-note">Para producao, execute atras de HTTPS/reverse proxy e proteja o arquivo de dados e backups no sistema operacional.</div>
        </section>
        <section class="panel">
          <div class="section-header">
            <h2 class="section-title">Backups</h2>
            ${isAdmin() ? `<button class="button primary" data-action="create-backup">Criar backup</button>` : ""}
          </div>
          <div class="alert-list">
            ${asArray(state.backups).slice(0, 6).map((backup) => `
              <article class="mini-panel">
                <div class="mini-title">${escapeHtml(backup.file)}</div>
                <div class="mini-text">${formatDate(backup.created_at)} - ${Math.round(Number(backup.size || 0) / 1024)} KB</div>
              </article>
            `).join("") || `<div class="empty-state">Nenhum backup criado nesta versao.</div>`}
          </div>
        </section>
      </div>
      ${isAdmin() ? renderSettingsForm(settings) : ""}
    `;
  }

  function renderSettingsForm(settings) {
    return `
      <section class="panel">
        <div class="section-header">
          <h2 class="section-title">Configuracoes do Sword</h2>
          <button class="button" data-action="export-data">Exportar dados</button>
        </div>
        <form class="form-grid" id="settings-form">
          <div class="field"><label>Nome da aplicacao</label><input class="input" name="app_name" value="${escapeHtml(settings.app_name)}"></div>
          <div class="field"><label>Sessao (horas)</label><input class="input" name="session_hours" type="number" min="1" value="${settings.session_hours}"></div>
          <div class="field"><label>Tentativas de login</label><input class="input" name="login_rate_limit_max_attempts" type="number" min="1" value="${settings.login_rate_limit_max_attempts}"></div>
          <div class="field"><label>Janela do rate limit (min)</label><input class="input" name="login_rate_limit_window_minutes" type="number" min="1" value="${settings.login_rate_limit_window_minutes}"></div>
          <div class="field"><label>Intervalo de checagem (s)</label><input class="input" name="check_interval_seconds" type="number" min="1" value="${settings.check_interval_seconds}"></div>
          <div class="field"><label>Tentativas por dispositivo</label><input class="input" name="check_attempts" type="number" min="1" value="${settings.check_attempts}"></div>
          <div class="field"><label>Timeout de ping (ms)</label><input class="input" name="check_timeout_ms" type="number" min="50" value="${settings.check_timeout_ms}"></div>
          <div class="field"><label>Retencao de auditoria (dias)</label><input class="input" name="audit_retention_days" type="number" min="1" value="${settings.audit_retention_days}"></div>
          <div class="field"><label>Retencao de eventos (dias)</label><input class="input" name="event_retention_days" type="number" min="1" value="${settings.event_retention_days}"></div>
          <div class="field"><label>Retencao de backup (dias)</label><input class="input" name="backup_retention_days" type="number" min="1" value="${settings.backup_retention_days}"></div>
          <div class="field"><label>Bipe critico apos (min)</label><input class="input" name="critical_sound_minutes" type="number" min="1" value="${settings.critical_sound_minutes}"></div>
          <div class="field"><label>Tema padrao</label><select class="select" name="ui_theme">
            <option value="system"${settings.ui_theme === "system" ? " selected" : ""}>Sistema</option>
            <option value="light"${settings.ui_theme === "light" ? " selected" : ""}>Claro</option>
            <option value="dark"${settings.ui_theme === "dark" ? " selected" : ""}>Escuro</option>
            <option value="blackout"${settings.ui_theme === "blackout" ? " selected" : ""}>Blackout</option>
            <option value="steel"${settings.ui_theme === "steel" ? " selected" : ""}>Steel</option>
            <option value="contrast"${settings.ui_theme === "contrast" ? " selected" : ""}>Contraste</option>
          </select></div>
          <div class="field full">
            <label class="checkbox-field"><input type="checkbox" name="require_csrf" ${settings.require_csrf ? "checked" : ""}> Exigir token anti-CSRF nas acoes de escrita</label>
            <label class="checkbox-field"><input type="checkbox" name="allow_viewer_export" ${settings.allow_viewer_export ? "checked" : ""}> Permitir exportacao para visualizadores</label>
            <label class="checkbox-field"><input type="checkbox" name="critical_sound_enabled" ${settings.critical_sound_enabled ? "checked" : ""}> Ativar bipe para criticidade alta prolongada</label>
          </div>
          <div class="field full"><button class="button primary" type="submit">Salvar configuracoes</button></div>
        </form>
      </section>
    `;
  }

  function renderModal() {
    const device = state.modal.device || {
      name: "",
      host: "",
      type: "Computador",
      location: "",
      criticality: "media",
      check_method: "ping",
      port: "",
      url_path: "/",
      expected_status: 200,
      owner: "",
      tags: "",
      notes: "",
      serial_number: "",
      asset_tag: "",
      model: "",
      maintenance_until: "",
      is_active: true
    };
    const isEdit = Boolean(device.id);

    return `
      <div class="modal-backdrop">
        <form class="modal" id="device-form">
          <div class="modal-header">
            <h2 class="section-title">${isEdit ? "Editar dispositivo" : "Novo dispositivo"}</h2>
            <button class="button icon-only" type="button" data-action="close-modal">X</button>
          </div>
          <div class="form-grid">
            <div class="field">
              <label for="name">Nome do dispositivo</label>
              <input class="input" id="name" name="name" required value="${escapeHtml(device.name)}">
            </div>
            <div class="field">
              <label for="host">IP ou hostname</label>
              <input class="input" id="host" name="host" required value="${escapeHtml(device.host)}" autocomplete="off">
              <div class="field-help">Use apenas o host ou IP, sem http://.</div>
            </div>
            <div class="field">
              <label for="type">Tipo</label>
              <select class="select" id="type" name="type">
                ${DEVICE_TYPES.map((type) => `<option value="${type}"${device.type === type ? " selected" : ""}>${type}</option>`).join("")}
              </select>
            </div>
            <div class="field">
              <label for="location">Localizacao</label>
              <input class="input" id="location" name="location" value="${escapeHtml(device.location)}">
            </div>
            <div class="field">
              <label for="criticality">Criticidade</label>
              <select class="select" id="criticality" name="criticality">
                <option value="baixa"${device.criticality === "baixa" ? " selected" : ""}>Baixa</option>
                <option value="media"${device.criticality === "media" ? " selected" : ""}>Media</option>
                <option value="alta"${device.criticality === "alta" ? " selected" : ""}>Alta</option>
                <option value="critica"${device.criticality === "critica" ? " selected" : ""}>Critica</option>
              </select>
            </div>
            <div class="field">
              <label for="check_method">Metodo de verificacao</label>
              <select class="select" id="check_method" name="check_method">
                ${CHECK_METHODS.map(([value, label]) => `<option value="${value}"${(device.check_method || "ping") === value ? " selected" : ""}>${label}</option>`).join("")}
              </select>
              <div class="field-help">Ping para rede local; TCP/HTTP/HTTPS para servicos especificos.</div>
            </div>
            <div class="field">
              <label for="port">Porta</label>
              <input class="input" id="port" name="port" type="number" min="1" max="65535" value="${escapeHtml(device.port ?? "")}" placeholder="Ex: 80, 443, 3389">
              <div class="field-help">Obrigatoria para TCP. Opcional para HTTP/HTTPS.</div>
            </div>
            <div class="field">
              <label for="url_path">Caminho HTTP</label>
              <input class="input" id="url_path" name="url_path" value="${escapeHtml(device.url_path || "/")}" placeholder="/">
            </div>
            <div class="field">
              <label for="expected_status">Status esperado</label>
              <input class="input" id="expected_status" name="expected_status" type="number" min="100" max="599" value="${escapeHtml(device.expected_status ?? 200)}" placeholder="200">
            </div>
            <div class="field">
              <label for="owner">Responsavel</label>
              <input class="input" id="owner" name="owner" value="${escapeHtml(device.owner || "")}" placeholder="Equipe, pessoa ou fornecedor">
            </div>
            <div class="field">
              <label for="tags">Tags</label>
              <input class="input" id="tags" name="tags" value="${escapeHtml(device.tags || "")}" placeholder="erp, matriz, windows">
            </div>
            <div class="field">
              <label for="serial_number">Numero serial</label>
              <input class="input" id="serial_number" name="serial_number" value="${escapeHtml(device.serial_number || "")}" placeholder="Serial, service tag ou SN">
            </div>
            <div class="field">
              <label for="asset_tag">Patrimonio</label>
              <input class="input" id="asset_tag" name="asset_tag" value="${escapeHtml(device.asset_tag || "")}" placeholder="Etiqueta interna">
            </div>
            <div class="field">
              <label for="model">Modelo</label>
              <input class="input" id="model" name="model" value="${escapeHtml(device.model || "")}" placeholder="Fabricante / modelo">
            </div>
            <div class="field">
              <label for="maintenance_until">Manutencao ate</label>
              <input class="input" id="maintenance_until" name="maintenance_until" type="datetime-local" value="${toDateTimeLocal(device.maintenance_until)}">
              <div class="field-help">Enquanto estiver em manutencao, o Sword pausa a checagem automatica.</div>
            </div>
            <div class="field full">
              <label class="checkbox-field">
                <input type="checkbox" name="is_active" ${device.is_active ? "checked" : ""}>
                Ativo para monitoramento automatico
              </label>
              <div class="field-help">Dispositivos ativos entram nos ciclos de verificacao. Inativos permanecem cadastrados, mas nao sao testados.</div>
            </div>
            <div class="field full">
              <label for="notes">Observacoes</label>
              <textarea class="textarea" id="notes" name="notes" rows="3" maxlength="500" placeholder="Informacoes operacionais, janela de manutencao, dependencia ou procedimento interno">${escapeHtml(device.notes || "")}</textarea>
            </div>
          </div>
          <div class="modal-footer">
            <button class="button" type="button" data-action="close-modal">Cancelar</button>
            <button class="button primary" type="submit">${isEdit ? "Salvar alteracoes" : "Cadastrar"}</button>
          </div>
        </form>
      </div>
    `;
  }

  function renderUserModal() {
    const user = state.userModal.user || {
      name: "",
      email: "",
      role: "viewer",
      status: "active",
      avatar_data_url: ""
    };
    const isEdit = Boolean(user.id);

    return `
      <div class="modal-backdrop">
        <form class="modal" id="user-form">
          <div class="modal-header">
            <h2 class="section-title">${isEdit ? "Editar usuario" : "Novo usuario"}</h2>
            <button class="button icon-only" type="button" data-action="close-user-modal">X</button>
          </div>
          <div class="form-grid">
            <div class="field">
              <label for="user-name">Nome</label>
              <input class="input" id="user-name" name="name" required value="${escapeHtml(user.name)}">
            </div>
            <div class="field">
              <label for="user-email">Email</label>
              <input class="input" id="user-email" name="email" type="email" required value="${escapeHtml(user.email)}">
            </div>
            <div class="field">
              <label for="user-role">Cargo</label>
              <select class="select" id="user-role" name="role">
                <option value="admin"${user.role === "admin" ? " selected" : ""}>Administrador</option>
                <option value="operator"${user.role === "operator" ? " selected" : ""}>Operador</option>
                <option value="viewer"${user.role === "viewer" ? " selected" : ""}>Visualizador</option>
              </select>
            </div>
            <div class="field">
              <label for="user-status">Status</label>
              <select class="select" id="user-status" name="status">
                <option value="active"${user.status === "active" ? " selected" : ""}>Ativo</option>
                <option value="inactive"${user.status === "inactive" ? " selected" : ""}>Inativo</option>
              </select>
            </div>
            <div class="field full">
              <label for="user-password">${isEdit ? "Nova senha" : "Senha"}</label>
              <input class="input" id="user-password" name="password" type="password" ${isEdit ? "" : "required"} minlength="6" autocomplete="new-password">
              <div class="field-help">${isEdit ? "Deixe em branco para manter a senha atual." : "Minimo de 6 caracteres."}</div>
            </div>
            <div class="field full">
              <label for="user-avatar">Foto do usuario</label>
              <div class="avatar-field">
                ${renderAvatar(user)}
                <input class="input" id="user-avatar" name="avatar" type="file" accept="image/png,image/jpeg,image/webp">
              </div>
              <div class="field-help">PNG, JPG ou WEBP ate 250 KB.</div>
            </div>
          </div>
          <div class="modal-footer">
            <button class="button" type="button" data-action="close-user-modal">Cancelar</button>
            <button class="button primary" type="submit">${isEdit ? "Salvar usuario" : "Criar usuario"}</button>
          </div>
        </form>
      </div>
    `;
  }

  function renderPasswordModal() {
    return `
      <div class="modal-backdrop">
        <form class="modal" id="password-form">
          <div class="modal-header">
            <h2 class="section-title">Alterar senha</h2>
            <button class="button icon-only" type="button" data-action="close-password-modal">X</button>
          </div>
          <div class="form-grid">
            <div class="field full">
              <label>Senha atual</label>
              <input class="input" name="current_password" type="password" required autocomplete="current-password">
            </div>
            <div class="field full">
              <label>Nova senha</label>
              <input class="input" name="new_password" type="password" required minlength="6" autocomplete="new-password">
              <div class="field-help">Mantive o limite simples como voce pediu; ainda recomendamos senhas fortes em ambiente real.</div>
            </div>
          </div>
          <div class="modal-footer">
            <button class="button" type="button" data-action="close-password-modal">Cancelar</button>
            <button class="button primary" type="submit">Atualizar senha</button>
          </div>
        </form>
      </div>
    `;
  }

  function renderIntegrationModal() {
    const integration = state.integrationModal.integration || {
      name: "",
      type: "webhook",
      url: "",
      secret_configured: false,
      enabled: true
    };
    const isEdit = Boolean(integration.id);

    return `
      <div class="modal-backdrop">
        <form class="modal" id="integration-form">
          <div class="modal-header">
            <h2 class="section-title">${isEdit ? "Editar integracao" : "Nova integracao"}</h2>
            <button class="button icon-only" type="button" data-action="close-integration-modal">X</button>
          </div>
          <div class="form-grid">
            <div class="field">
              <label for="integration-name">Nome</label>
              <input class="input" id="integration-name" name="name" required value="${escapeHtml(integration.name)}" placeholder="Webhook NOC">
            </div>
            <div class="field">
              <label for="integration-type">Tipo</label>
              <select class="select" id="integration-type" name="type">
                <option value="webhook"${integration.type === "webhook" ? " selected" : ""}>Webhook JSON</option>
              </select>
            </div>
            <div class="field full">
              <label for="integration-url">URL do webhook</label>
              <input class="input" id="integration-url" name="url" required value="${escapeHtml(integration.url)}" placeholder="https://exemplo.local/webhook/sword">
              <div class="field-help">O Sword envia alertas criticos em JSON quando um ativo alto ou critico cai.</div>
            </div>
            <div class="field full">
              <label for="integration-secret">Segredo opcional</label>
              <input class="input" id="integration-secret" name="secret" type="password" autocomplete="new-password" placeholder="${isEdit && integration.secret_configured ? "Ja configurado; deixe em branco para manter" : "X-Sword-Secret"}">
              <div class="field-help">${isEdit && integration.secret_configured ? "Existe um segredo configurado. Preencha apenas para substituir." : "Quando preenchido, ele sera enviado no header X-Sword-Secret."}</div>
            </div>
            <div class="field full">
              <label class="checkbox-field">
                <input type="checkbox" name="enabled" ${integration.enabled !== false ? "checked" : ""}>
                Integracao ativa
              </label>
            </div>
          </div>
          <div class="modal-footer">
            <button class="button" type="button" data-action="close-integration-modal">Cancelar</button>
            <button class="button primary" type="submit">${isEdit ? "Salvar integracao" : "Criar integracao"}</button>
          </div>
        </form>
      </div>
    `;
  }

  function bindEvents() {
    app.querySelectorAll("[data-view]").forEach((button) => {
      button.addEventListener("click", async () => {
        state.view = button.dataset.view;
        if (state.view === "users") {
          try {
            await loadUsers();
          } catch (error) {
            setToast(error.message);
          }
        }
        if (state.view === "audit") {
          try {
            await loadAudit();
          } catch (error) {
            setToast(error.message);
          }
        }
        if (state.view === "history") {
          try {
            await loadHistoryReport();
          } catch (error) {
            setToast(error.message);
          }
        }
        if (state.view === "reports" || state.view === "operation") {
          try {
            await loadReport();
          } catch (error) {
            setToast(error.message);
          }
        }
        if (state.view === "integrations") {
          try {
            await loadIntegrations();
          } catch (error) {
            setToast(error.message);
          }
        }
        if (state.view === "security") {
          try {
            await loadSecurityData();
          } catch (error) {
            setToast(error.message);
          }
        }
        render();
      });
    });

    app.querySelectorAll("[data-filter]").forEach((field) => {
      field.addEventListener("input", () => {
        state.filters[field.dataset.filter] = field.value;
        render();
      });
      field.addEventListener("change", () => {
        state.filters[field.dataset.filter] = field.value;
        render();
      });
    });

    app.querySelectorAll("[data-history-filter]").forEach((field) => {
      field.addEventListener("change", () => {
        state.historyFilters[field.dataset.historyFilter] = field.value;
        render();
      });
    });

    app.querySelectorAll("[data-report-filter]").forEach((field) => {
      field.addEventListener("change", () => {
        state.reportFilters[field.dataset.reportFilter] = field.value;
      });
    });

    app.querySelectorAll("[data-audit-filter]").forEach((field) => {
      field.addEventListener("input", () => {
        state.auditFilters[field.dataset.auditFilter] = field.value;
      });
      field.addEventListener("change", () => {
        state.auditFilters[field.dataset.auditFilter] = field.value;
      });
    });

    const themeSelect = app.querySelector("[data-theme-select]");
    if (themeSelect) {
      themeSelect.addEventListener("change", () => {
        applyTheme(themeSelect.value);
        render();
      });
    }

    app.querySelectorAll("[data-action]").forEach((button) => {
      button.addEventListener("click", handleAction);
    });

    const form = app.querySelector("#device-form");
    if (form) {
      form.addEventListener("submit", handleDeviceSubmit);
    }

    const userForm = app.querySelector("#user-form");
    if (userForm) {
      userForm.addEventListener("submit", handleUserSubmit);
    }

    const settingsForm = app.querySelector("#settings-form");
    if (settingsForm) {
      settingsForm.addEventListener("submit", handleSettingsSubmit);
    }

    const passwordForm = app.querySelector("#password-form");
    if (passwordForm) {
      passwordForm.addEventListener("submit", handlePasswordSubmit);
    }

    const integrationForm = app.querySelector("#integration-form");
    if (integrationForm) {
      integrationForm.addEventListener("submit", handleIntegrationSubmit);
    }
  }

  async function handleAction(event) {
    const action = event.currentTarget.dataset.action;
    const id = event.currentTarget.dataset.id;

    try {
      if (action === "reload") {
        await loadData();
        return;
      }

      if (action === "open-password-modal") {
        state.passwordModal = {};
        render();
      }

      if (action === "close-password-modal") {
        state.passwordModal = null;
        render();
      }

      if (action === "test-sound") {
        state.soundArmed = true;
        state.lastBeepAt = 0;
        playCriticalBeep();
        setToast("Bipe de alerta testado.");
      }

      if (action === "logout") {
        await api.post("/api/auth/logout");
        state.auth.user = null;
        state.auth.csrfToken = "";
        state.auth.setupRequired = false;
        state.view = "dashboard";
        state.devices = [];
        state.events = [];
        state.alerts = [];
        state.users = [];
        render();
        return;
      }

      if (action === "refresh-audit") {
        await loadAudit();
        setToast("Auditoria atualizada.");
        render();
      }

      if (action === "refresh-report") {
        await loadReport();
        setToast("Relatorio atualizado.");
        render();
      }

      if (action === "apply-history-report") {
        await loadHistoryReport();
        setToast("Historico filtrado.");
        render();
      }

      if (action === "download-report") {
        downloadUrl(`/api/reports/availability/export${buildQuery(state.reportFilters, "report")}`);
        await loadReport();
        setToast("Relatorio preparado para Excel.");
      }

      if (action === "download-history") {
        downloadUrl(`/api/history/export${buildQuery(state.historyFilters, "history")}`);
        await loadHistoryReport();
        setToast("Historico preparado para Excel.");
      }

      if (action === "download-audit") {
        downloadUrl(`/api/audit/export${buildQuery(state.auditFilters, "audit")}`);
        await loadAudit();
        setToast("Auditoria preparada para Excel.");
      }

      if (action === "clear-history") {
        if (window.confirm("Limpar historico resolvido? Incidentes abertos serao preservados.")) {
          await api.delete("/api/events?scope=resolved");
          await loadData({ silent: true });
          await loadHistoryReport();
          setToast("Historico resolvido limpo.");
          render();
        }
      }

      if (action === "clear-reports") {
        if (window.confirm("Limpar a lista de relatorios gerados?")) {
          await api.delete("/api/report-snapshots");
          await loadReport();
          setToast("Relatorios gerados limpos.");
          render();
        }
      }

      if (action === "create-backup") {
        await api.post("/api/backups");
        await loadSecurityData();
        setToast("Backup criado.");
        render();
      }

      if (action === "export-data") {
        const exported = await api.get("/api/export");
        const blob = new Blob([JSON.stringify(exported, null, 2)], { type: "application/json" });
        const url = URL.createObjectURL(blob);
        const link = document.createElement("a");
        link.href = url;
        link.download = `sword-export-${new Date().toISOString().slice(0, 10)}.json`;
        link.click();
        URL.revokeObjectURL(url);
        setToast("Exportacao preparada.");
      }

      if (action === "new-integration") {
        state.integrationModal = { integration: null };
        render();
      }

      if (action === "edit-integration") {
        const integration = asArray(state.integrations).find((item) => item.id === id);
        if (integration) {
          state.integrationModal = { integration: { ...integration } };
          render();
        }
      }

      if (action === "close-integration-modal") {
        state.integrationModal = null;
        render();
      }

      if (action === "delete-integration") {
        const integration = asArray(state.integrations).find((item) => item.id === id);
        if (integration && window.confirm(`Excluir a integracao ${integration.name}?`)) {
          await api.delete(`/api/integrations/${id}`);
          await loadIntegrations();
          setToast("Integracao removida.");
          render();
        }
      }

      if (action === "new-user") {
        state.userModal = { user: null };
        render();
      }

      if (action === "edit-user") {
        const user = asArray(state.users).find((item) => item.id === id);
        if (user) {
          state.userModal = { user: { ...user } };
          render();
        }
      }

      if (action === "close-user-modal") {
        state.userModal = null;
        render();
      }

      if (action === "delete-user") {
        const user = asArray(state.users).find((item) => item.id === id);
        if (user && window.confirm(`Excluir o usuario ${user.name}?`)) {
          await api.delete(`/api/users/${id}`);
          await loadUsers();
          setToast("Usuario removido.");
          render();
        }
      }

      if (action === "new-device") {
        state.modal = { device: null };
        render();
      }

      if (action === "edit-device") {
        const device = deviceById(id);
        if (device) {
          state.modal = { device: { ...device } };
          render();
        }
      }

      if (action === "close-modal") {
        state.modal = null;
        render();
      }

      if (action === "delete-device") {
        const device = deviceById(id);
        if (device && window.confirm(`Excluir ${device.name} e seus eventos vinculados?`)) {
          await api.delete(`/api/devices/${id}`);
          await loadData({ silent: true });
          setToast("Dispositivo removido.");
        }
      }

      if (action === "check-device") {
        await api.post(`/api/devices/${id}/check`);
        await loadData({ silent: true });
        setToast("Verificacao concluida.");
      }

      if (action === "run-monitor") {
        await api.post("/api/monitor/run");
        await loadData({ silent: true });
        setToast("Monitoramento executado.");
      }

      if (action === "resolve-alert") {
        await api.post(`/api/alerts/${id}/resolve`);
        await loadData({ silent: true });
        setToast("Alerta marcado como resolvido.");
      }
    } catch (error) {
      setToast(error.message);
    }
  }

  async function handleSetupSubmit(event) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const payload = {
      name: form.get("name"),
      email: form.get("email"),
      password: form.get("password")
    };

    try {
      state.error = "";
      const response = await api.post("/api/auth/setup", payload);
      state.auth.user = response.user;
      state.auth.csrfToken = response.csrf_token || "";
      state.auth.setupRequired = false;
      await loadData({ silent: true });
      setToast("Administrador criado.");
    } catch (error) {
      state.error = error.message;
      render();
    }
  }

  async function handleLoginSubmit(event) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const payload = {
      email: form.get("email"),
      password: form.get("password")
    };

    try {
      state.error = "";
      const response = await api.post("/api/auth/login", payload);
      state.auth.user = response.user;
      state.auth.csrfToken = response.csrf_token || "";
      state.auth.setupRequired = false;
      await loadData({ silent: true });
      setToast("Login realizado.");
    } catch (error) {
      state.error = error.message;
      render();
    }
  }

  async function handleDeviceSubmit(event) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const payload = {
      name: form.get("name"),
      host: form.get("host"),
      type: form.get("type"),
      location: form.get("location"),
      criticality: form.get("criticality"),
      check_method: form.get("check_method"),
      port: form.get("port"),
      url_path: form.get("url_path"),
      expected_status: form.get("expected_status"),
      owner: form.get("owner"),
      tags: form.get("tags"),
      notes: form.get("notes"),
      serial_number: form.get("serial_number"),
      asset_tag: form.get("asset_tag"),
      model: form.get("model"),
      maintenance_until: form.get("maintenance_until"),
      is_active: form.get("is_active") === "on"
    };

    try {
      if (state.modal.device && state.modal.device.id) {
        await api.put(`/api/devices/${state.modal.device.id}`, payload);
        setToast("Dispositivo atualizado.");
      } else {
        const created = await api.post("/api/devices", payload);
        if (payload.is_active && created?.id) {
          await api.post(`/api/devices/${created.id}/check`);
          setToast("Dispositivo cadastrado e verificado.");
        } else {
          setToast("Dispositivo cadastrado.");
        }
      }
      state.modal = null;
      await loadData({ silent: true });
    } catch (error) {
      setToast(error.message);
    }
  }

  async function handleUserSubmit(event) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const password = form.get("password");
    const payload = {
      name: form.get("name"),
      email: form.get("email"),
      role: form.get("role"),
      status: form.get("status")
    };
    if (password) {
      payload.password = password;
    }

    try {
      const avatarFile = event.currentTarget.querySelector('input[name="avatar"]')?.files?.[0];
      const avatarData = await readFileAsDataUrl(avatarFile);
      if (avatarData) {
        payload.avatar_data_url = avatarData;
      }
      if (state.userModal.user && state.userModal.user.id) {
        await api.put(`/api/users/${state.userModal.user.id}`, payload);
        setToast("Usuario atualizado.");
      } else {
        payload.password = password;
        await api.post("/api/users", payload);
        setToast("Usuario criado.");
      }
      state.userModal = null;
      await loadUsers();
      const current = asArray(state.users).find((user) => state.auth.user && user.id === state.auth.user.id);
      if (current) state.auth.user = current;
      render();
    } catch (error) {
      setToast(error.message);
    }
  }

  async function handleIntegrationSubmit(event) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const payload = {
      name: form.get("name"),
      type: form.get("type"),
      url: form.get("url"),
      secret: form.get("secret"),
      enabled: form.get("enabled") === "on"
    };

    try {
      if (state.integrationModal.integration && state.integrationModal.integration.id) {
        await api.put(`/api/integrations/${state.integrationModal.integration.id}`, payload);
        setToast("Integracao atualizada.");
      } else {
        await api.post("/api/integrations", payload);
        setToast("Integracao criada.");
      }
      state.integrationModal = null;
      await loadIntegrations();
      render();
    } catch (error) {
      setToast(error.message);
    }
  }

  async function handleSettingsSubmit(event) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const payload = {
      app_name: form.get("app_name"),
      session_hours: Number(form.get("session_hours")),
      login_rate_limit_max_attempts: Number(form.get("login_rate_limit_max_attempts")),
      login_rate_limit_window_minutes: Number(form.get("login_rate_limit_window_minutes")),
      check_interval_seconds: Number(form.get("check_interval_seconds")),
      check_attempts: Number(form.get("check_attempts")),
      check_timeout_ms: Number(form.get("check_timeout_ms")),
      audit_retention_days: Number(form.get("audit_retention_days")),
      event_retention_days: Number(form.get("event_retention_days")),
      backup_retention_days: Number(form.get("backup_retention_days")),
      critical_sound_minutes: Number(form.get("critical_sound_minutes")),
      ui_theme: form.get("ui_theme"),
      require_csrf: form.get("require_csrf") === "on",
      allow_viewer_export: form.get("allow_viewer_export") === "on",
      critical_sound_enabled: form.get("critical_sound_enabled") === "on"
    };

    try {
      state.settings = asSettings(await api.put("/api/settings", payload));
      applyTheme(state.settings.ui_theme || state.theme);
      await loadSecurityData();
      setToast("Configuracoes salvas.");
      render();
    } catch (error) {
      setToast(error.message);
    }
  }

  async function handlePasswordSubmit(event) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const payload = {
      current_password: form.get("current_password"),
      new_password: form.get("new_password")
    };

    try {
      await api.put("/api/auth/password", payload);
      state.passwordModal = null;
      setToast("Senha alterada.");
      render();
    } catch (error) {
      setToast(error.message);
    }
  }

  loadAuthStatus();
  window.setInterval(() => {
    if (state.auth.user && !state.modal && !state.userModal && !state.passwordModal && !state.integrationModal) {
      loadData({ silent: true });
    }
  }, 5000);
})();

