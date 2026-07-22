const settingsForm = document.getElementById("settingsFormAdmin");
const messagePanel = document.getElementById("messagePanel");
const messageText = document.getElementById("messageText");
const sessionText = document.getElementById("sessionText");
const tokenHint = document.getElementById("tokenHint");
const tokenHintText = document.getElementById("tokenHintText");
const logoutButton = document.getElementById("logoutButton");
const tokenInput = document.getElementById("zabbixToken");
const tokenActionButton = document.getElementById("tokenActionButton");
const zabbixApiUrl = document.getElementById("zabbixApiUrl");
const zabbixProtocol = document.getElementById("zabbixProtocol");
const zabbixHostInput = document.getElementById("zabbixHostInput");
const zabbixFullUrl = document.getElementById("zabbixFullUrl");
const urlQuickFields = document.getElementById("urlQuickFields");
const urlPreview = document.getElementById("urlPreview");
const urlFieldLabel = document.getElementById("urlFieldLabel");
const urlModeButtons = Array.from(document.querySelectorAll("[data-url-mode]"));
const adminTabButtons = Array.from(document.querySelectorAll("[data-admin-tab]"));
const adminViews = Array.from(document.querySelectorAll("[data-admin-view]"));
const saveHint = document.getElementById("saveHint");
const saveSettingsButton = document.getElementById("saveSettingsButton");
const discardChangesButton = document.getElementById("discardChangesButton");
const resetCustomizationButton = document.getElementById("resetCustomizationButton");
const resetSeverityColorsButton = document.getElementById("resetSeverityColorsButton");
const severityColorControls = Array.from(document.querySelectorAll("[data-severity-color]"));
const incidentFontScale = document.getElementById("incidentFontScale");
const incidentFontScaleValue = document.getElementById("incidentFontScaleValue");
const cardFontScale = document.getElementById("cardFontScale");
const cardFontScaleValue = document.getElementById("cardFontScaleValue");
const backToPanelLink = document.getElementById("backToPanelLink");
const homeLinks = Array.from(document.querySelectorAll("[data-home-link]"));
const adminLayout = document.querySelector(".admin-layout");
const DEFAULT_API_PATH = "/zabbix/api_jsonrpc.php";
const TOKEN_MASK = "TOKEN_ARMAZENADO";
const PREVIEW_STORAGE_KEY = "central-incidentes-preview-settings-v1";
const DEFAULT_SEVERITY_COLORS = window.IncidentTheme.DEFAULT_SEVERITY_COLORS;
const DEFAULT_CUSTOMIZATION = {
  dashboard_theme: "graphite",
  refresh_seconds: 10,
  page_interval_seconds: 15,
  sort_mode: "recent",
  page_transition: "fade",
  incident_font_scale: 100,
  card_font_scale: 100,
};
const previewMode = new URLSearchParams(window.location.search).has("preview");
let activeUrlMode = "quick";
let hasStoredToken = false;
let editingStoredToken = false;
let loadedSettings = null;
let savedSnapshot = "";

function waitForThemeAnimation() {
  return new Promise(resolve => {
    let timeoutId;
    const finish = event => {
      if (event && event.target !== adminLayout) return;
      adminLayout.removeEventListener("animationend", finish);
      clearTimeout(timeoutId);
      resolve();
    };

    adminLayout.addEventListener("animationend", finish);
    timeoutId = setTimeout(finish, 260);
  });
}

async function transitionAdminTheme(value) {
  const theme = window.IncidentTheme.normalize(value);
  if (document.documentElement.dataset.theme === theme) {
    window.IncidentTheme.apply(theme);
    return;
  }

  document.documentElement.classList.add("theme-fade-out");
  await waitForThemeAnimation();
  window.IncidentTheme.apply(theme);
  document.documentElement.classList.remove("theme-fade-out");
  document.documentElement.classList.add("theme-fade-in");
  await waitForThemeAnimation();
  document.documentElement.classList.remove("theme-fade-in");
}

const PREVIEW_DEFAULT_SETTINGS = {
  zabbix_api_url: "http://zabbix.exemplo.local/zabbix/api_jsonrpc.php",
  has_zabbix_token: true,
  refresh_seconds: 10,
  api_limit: 500,
  page_interval_seconds: 15,
  sort_mode: "recent",
  dashboard_theme: "graphite",
  page_transition: "fade",
  incident_font_scale: 100,
  card_font_scale: 100,
  severity_colors: DEFAULT_SEVERITY_COLORS,
  fetch_mode: "incidents",
  monitored_group_ids: [],
  monitored_host_ids: [],
};

function formField(name) {
  return settingsForm.elements.namedItem(name);
}

function setAdminTab(tabName, updateHash = true) {
  const tabExists = adminViews.some(view => view.dataset.adminView === tabName);
  const selectedTab = tabExists ? tabName : "zabbix";

  adminTabButtons.forEach(button => {
    const isActive = button.dataset.adminTab === selectedTab;
    button.classList.toggle("is-active", isActive);
    button.setAttribute("aria-selected", String(isActive));
  });
  adminViews.forEach(view => {
    view.hidden = view.dataset.adminView !== selectedTab;
  });

  if (updateHash) {
    const hash = selectedTab === "customization" ? "personalizacao" : "zabbix";
    window.history.replaceState(null, "", `${window.location.pathname}${window.location.search}#${hash}`);
  }
}

function showMessage(message, type = "info") {
  messagePanel.hidden = false;
  messagePanel.dataset.type = type;
  messageText.textContent = message;
}

function clearMessage() {
  messagePanel.hidden = true;
  messageText.textContent = "";
}

function updateScaleOutputs() {
  incidentFontScaleValue.textContent = `${incidentFontScale.value}%`;
  cardFontScaleValue.textContent = `${cardFontScale.value}%`;
}

function updateSeverityPreview(control, color) {
  const sample = control.querySelector("[data-color-sample]");
  sample.style.setProperty("--sample-color", color);
  sample.style.setProperty("--sample-text", window.IncidentTheme.contrastColor(color));
}

function setSeverityColorControl(control, value) {
  const severity = control.dataset.severityColor;
  const color = window.IncidentTheme.normalizeHexColor(value, DEFAULT_SEVERITY_COLORS[severity]);
  const picker = control.querySelector("[data-color-picker]");
  const hexInput = control.querySelector("[data-color-hex]");

  picker.value = color;
  hexInput.value = color.toUpperCase();
  hexInput.setCustomValidity("");
  updateSeverityPreview(control, color);
}

function setSeverityColors(colors) {
  const normalized = window.IncidentTheme.normalizeSeverityColors(colors);
  severityColorControls.forEach(control => {
    setSeverityColorControl(control, normalized[control.dataset.severityColor]);
  });
}

function readSeverityColors() {
  const colors = Object.fromEntries(severityColorControls.map(control => [
    control.dataset.severityColor,
    control.querySelector("[data-color-hex]").value,
  ]));
  return window.IncidentTheme.normalizeSeverityColors(colors);
}

function formSnapshot() {
  syncUrlValue();
  const values = Object.fromEntries(new FormData(settingsForm).entries());
  values.zabbix_token = hasStoredToken && !editingStoredToken
    ? "stored-token"
    : String(values.zabbix_token || "");
  return JSON.stringify(values);
}

function updateDirtyState() {
  if (!savedSnapshot) return false;
  const isDirty = formSnapshot() !== savedSnapshot;
  saveSettingsButton.disabled = !isDirty;
  discardChangesButton.disabled = !isDirty;
  saveHint.dataset.state = isDirty ? "dirty" : "clean";
  saveHint.textContent = isDirty
    ? "Alterações pendentes. Salve ou descarte antes de sair."
    : "Nenhuma alteração pendente.";
  return isDirty;
}

function captureSavedState(settings) {
  loadedSettings = JSON.parse(JSON.stringify(settings));
  savedSnapshot = formSnapshot();
  updateDirtyState();
}

function loadPreviewSettings() {
  try {
    const saved = JSON.parse(localStorage.getItem(PREVIEW_STORAGE_KEY) || "{}");
    return { ...PREVIEW_DEFAULT_SETTINGS, ...saved, has_zabbix_token: true };
  } catch {
    return { ...PREVIEW_DEFAULT_SETTINGS };
  }
}

function savePreviewSettings(settings) {
  const safeSettings = { ...settings };
  delete safeSettings.zabbix_token;
  delete safeSettings.has_zabbix_token;
  localStorage.setItem(PREVIEW_STORAGE_KEY, JSON.stringify(safeSettings));
}

function redirectToLogin() {
  window.location.replace(`login.html?next=${encodeURIComponent("admin.html")}`);
}

async function api(path, options = {}) {
  const { headers = {}, ...requestOptions } = options;
  const response = await fetch(path, {
    credentials: "same-origin",
    ...requestOptions,
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
      ...headers,
    },
  });
  const data = await response.json().catch(() => ({}));

  if (!response.ok || data.ok === false) {
    const error = new Error(data.error || `HTTP ${response.status}`);
    error.status = response.status;
    throw error;
  }

  return data;
}

async function submitForm(event, action) {
  event.preventDefault();
  clearMessage();
  const submitButton = event.submitter;
  if (submitButton) submitButton.disabled = true;

  try {
    await action();
  } catch (error) {
    if (error.status === 401) {
      redirectToLogin();
      return;
    }
    showMessage(error.message, "error");
  } finally {
    if (submitButton) submitButton.disabled = false;
    updateDirtyState();
  }
}

function idsToText(ids) {
  return Array.isArray(ids) ? ids.join(", ") : "";
}

function textToIds(value) {
  return String(value || "")
    .split(",")
    .map(item => item.trim())
    .filter(Boolean);
}

function quickUrl() {
  const host = zabbixHostInput.value.trim();
  return host ? `${zabbixProtocol.value}://${host}${DEFAULT_API_PATH}` : "";
}

function syncUrlValue() {
  const value = activeUrlMode === "quick" ? quickUrl() : zabbixFullUrl.value.trim();
  zabbixApiUrl.value = value;
  urlPreview.textContent = value || "Informe o IP ou DNS do servidor Zabbix.";
  urlPreview.classList.toggle("has-value", Boolean(value));
  return value;
}

function standardUrlParts(value) {
  try {
    const parsed = new URL(value);
    const isStandard = ["http:", "https:"].includes(parsed.protocol)
      && parsed.pathname.replace(/\/$/, "") === DEFAULT_API_PATH
      && !parsed.username
      && !parsed.password
      && !parsed.search
      && !parsed.hash;

    return isStandard
      ? { protocol: parsed.protocol.slice(0, -1), host: parsed.host }
      : null;
  } catch {
    return null;
  }
}

function setUrlMode(mode, options = {}) {
  const { preserveValue = true } = options;
  const nextMode = mode === "full" ? "full" : "quick";

  if (nextMode === "full" && preserveValue && !zabbixFullUrl.value.trim()) {
    zabbixFullUrl.value = quickUrl();
  }

  if (nextMode === "quick" && preserveValue && zabbixFullUrl.value.trim()) {
    const parts = standardUrlParts(zabbixFullUrl.value.trim());
    if (!parts) {
      showMessage("Essa URL usa um caminho personalizado. Continue no modo URL completa.", "warning");
      return false;
    }
    zabbixProtocol.value = parts.protocol;
    zabbixHostInput.value = parts.host;
  }

  activeUrlMode = nextMode;
  urlQuickFields.hidden = nextMode !== "quick";
  zabbixFullUrl.hidden = nextMode !== "full";
  urlFieldLabel.htmlFor = nextMode === "quick" ? "zabbixHostInput" : "zabbixFullUrl";
  urlModeButtons.forEach(button => {
    const isActive = button.dataset.urlMode === nextMode;
    button.classList.toggle("is-active", isActive);
    button.setAttribute("aria-pressed", String(isActive));
  });
  syncUrlValue();
  return true;
}

function populateUrlEditor(value) {
  const savedValue = String(value || "").trim();
  const isTemplate = savedValue.includes("DIGITE-O-IP-DO-ZABBIX")
    || savedValue.includes("DIGITE O IP DO ZABBIX");
  const parts = standardUrlParts(savedValue);

  if (parts && !isTemplate) {
    zabbixProtocol.value = parts.protocol;
    zabbixHostInput.value = parts.host;
    zabbixFullUrl.value = savedValue;
    setUrlMode("quick", { preserveValue: false });
    return;
  }

  zabbixProtocol.value = "http";
  zabbixHostInput.value = "";
  zabbixFullUrl.value = isTemplate ? "" : savedValue;
  setUrlMode(savedValue && !isTemplate ? "full" : "quick", { preserveValue: false });
}

function setTokenHint(message, state) {
  tokenHint.dataset.state = state;
  tokenHintText.textContent = message;
}

function populateTokenState(stored) {
  hasStoredToken = Boolean(stored);
  editingStoredToken = false;
  tokenInput.readOnly = hasStoredToken;
  tokenInput.value = hasStoredToken ? TOKEN_MASK : "";
  tokenActionButton.hidden = !hasStoredToken;
  tokenActionButton.textContent = "Substituir token";
  setTokenHint(
    hasStoredToken ? "Token salvo e criptografado." : "Nenhum token salvo.",
    hasStoredToken ? "saved" : "empty",
  );
}

function populateSettings(settings) {
  populateUrlEditor(settings.zabbix_api_url);
  populateTokenState(settings.has_zabbix_token);
  formField("refresh_seconds").value = settings.refresh_seconds || 10;
  formField("api_limit").value = settings.api_limit || 500;
  formField("page_interval_seconds").value = settings.page_interval_seconds || 15;
  formField("sort_mode").value = settings.sort_mode || "recent";
  const dashboardTheme = window.IncidentTheme.normalize(settings.dashboard_theme);
  formField("dashboard_theme").value = dashboardTheme;
  window.IncidentTheme.apply(dashboardTheme);
  formField("page_transition").value = settings.page_transition || "fade";
  formField("incident_font_scale").value = settings.incident_font_scale || 100;
  formField("card_font_scale").value = settings.card_font_scale || 100;
  setSeverityColors(settings.severity_colors || DEFAULT_SEVERITY_COLORS);
  formField("fetch_mode").value = settings.fetch_mode || "incidents";
  formField("monitored_group_ids").value = idsToText(settings.monitored_group_ids);
  formField("monitored_host_ids").value = idsToText(settings.monitored_host_ids);
  updateScaleOutputs();
  captureSavedState(settings);
}

async function loadSettings() {
  const data = await api("api/settings.php");
  populateSettings(data.settings);

  if (data.usingExampleConfig) {
    showMessage("Crie config/app.php a partir de config/app.example.php e troque o app_key antes de usar em producao.", "warning");
  }
}

async function loadAdmin() {
  clearMessage();

  try {
    const session = await api("api/auth.php");
    if (session.needsSetup || !session.user) {
      redirectToLogin();
      return;
    }

    sessionText.textContent = `Logado como ${session.user.name || session.user.username}`;
    await loadSettings();
  } catch (error) {
    if (error.status === 401) {
      redirectToLogin();
      return;
    }
    showMessage(error.message, "error");
  }
}

settingsForm.addEventListener("submit", event => {
  submitForm(event, async () => {
    const apiUrl = syncUrlValue();

    if (!apiUrl) {
      setAdminTab("zabbix");
      showMessage("Informe o IP, DNS ou a URL completa do servidor Zabbix.", "error");
      (activeUrlMode === "quick" ? zabbixHostInput : zabbixFullUrl).focus();
      return;
    }

    const payload = Object.fromEntries(new FormData(settingsForm).entries());
    payload.monitored_group_ids = textToIds(payload.monitored_group_ids);
    payload.monitored_host_ids = textToIds(payload.monitored_host_ids);
    payload.severity_colors = readSeverityColors();
    Object.keys(DEFAULT_SEVERITY_COLORS).forEach(severity => {
      delete payload[`severity_color_${severity}`];
    });

    if (hasStoredToken && !editingStoredToken) {
      delete payload.zabbix_token;
    } else if (!String(payload.zabbix_token || "").trim()) {
      delete payload.zabbix_token;
    }

    if (previewMode) {
      const previewSettings = {
        ...loadedSettings,
        ...payload,
        zabbix_api_url: apiUrl,
        has_zabbix_token: true,
      };
      savePreviewSettings(previewSettings);
      await transitionAdminTheme(previewSettings.dashboard_theme);
      populateSettings(previewSettings);
      showMessage("Preferências salvas neste navegador para o modo demonstração.", "success");
      return;
    }

    await api("api/settings.php", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    await transitionAdminTheme(payload.dashboard_theme);
    showMessage("Configuracoes salvas.", "success");
    await loadSettings();
  });
});

logoutButton.addEventListener("click", async () => {
  clearMessage();
  logoutButton.disabled = true;

  try {
    await api("api/auth.php", { method: "DELETE" });
    window.location.replace("login.html");
  } catch (error) {
    showMessage(error.message, "error");
    logoutButton.disabled = false;
  }
});

adminTabButtons.forEach(button => {
  button.addEventListener("click", () => setAdminTab(button.dataset.adminTab));
});

urlModeButtons.forEach(button => {
  button.addEventListener("click", () => {
    clearMessage();
    if (!setUrlMode(button.dataset.urlMode)) return;
    updateDirtyState();
    (activeUrlMode === "quick" ? zabbixHostInput : zabbixFullUrl).focus();
  });
});

[zabbixProtocol, zabbixHostInput, zabbixFullUrl].forEach(input => {
  input.addEventListener("input", syncUrlValue);
  input.addEventListener("change", syncUrlValue);
});

zabbixHostInput.addEventListener("paste", event => {
  const pastedValue = event.clipboardData?.getData("text")?.trim() || "";
  if (!/^https?:\/\//i.test(pastedValue)) return;

  event.preventDefault();
  zabbixFullUrl.value = pastedValue;
  populateUrlEditor(pastedValue);
});

tokenActionButton.addEventListener("click", () => {
  clearMessage();

  if (!editingStoredToken) {
    editingStoredToken = true;
    tokenInput.readOnly = false;
    tokenInput.value = "";
    tokenActionButton.textContent = "Manter token atual";
    setTokenHint("Informe o novo token. Ele será criptografado ao salvar.", "editing");
    updateDirtyState();
    tokenInput.focus();
    return;
  }

  populateTokenState(true);
  updateDirtyState();
});

tokenInput.addEventListener("input", () => {
  if (hasStoredToken && !editingStoredToken) return;
  const hasValue = Boolean(tokenInput.value.trim());
  setTokenHint(
    hasValue ? "Novo token pronto para ser criptografado." : "Informe um token para conectar a API.",
    hasValue ? "editing" : "empty",
  );
});

severityColorControls.forEach(control => {
  const picker = control.querySelector("[data-color-picker]");
  const hexInput = control.querySelector("[data-color-hex]");

  picker.addEventListener("input", () => {
    setSeverityColorControl(control, picker.value);
  });

  hexInput.addEventListener("input", () => {
    const value = hexInput.value.trim().toUpperCase();
    hexInput.value = value;
    const isValid = /^#[0-9A-F]{6}$/.test(value);
    hexInput.setCustomValidity(isValid ? "" : "Use uma cor no formato #RRGGBB.");
    if (isValid) {
      picker.value = value.toLowerCase();
      updateSeverityPreview(control, value);
    }
  });

  hexInput.addEventListener("change", () => {
    const value = hexInput.value.trim();
    const candidate = /^[0-9A-Fa-f]{6}$/.test(value) ? `#${value}` : value;
    if (/^#[0-9A-Fa-f]{6}$/.test(candidate)) {
      setSeverityColorControl(control, candidate);
    }
  });
});

settingsForm.addEventListener("input", event => {
  if (event.target === incidentFontScale || event.target === cardFontScale) {
    updateScaleOutputs();
  }
  updateDirtyState();
});

settingsForm.addEventListener("change", updateDirtyState);

discardChangesButton.addEventListener("click", () => {
  if (!loadedSettings) return;
  clearMessage();
  populateSettings(loadedSettings);
  showMessage("Alteracoes descartadas.", "info");
});

resetCustomizationButton.addEventListener("click", () => {
  Object.entries(DEFAULT_CUSTOMIZATION).forEach(([name, value]) => {
    formField(name).value = value;
  });
  setSeverityColors(DEFAULT_SEVERITY_COLORS);
  updateScaleOutputs();
  const isDirty = updateDirtyState();
  showMessage(
    isDirty ? "Padrões de personalização aplicados. Salve para confirmar." : "A personalização já está no padrão.",
    isDirty ? "warning" : "info",
  );
});

resetSeverityColorsButton.addEventListener("click", () => {
  clearMessage();
  setSeverityColors(DEFAULT_SEVERITY_COLORS);
  const isDirty = updateDirtyState();
  showMessage(
    isDirty ? "Paleta padrão aplicada. Salve para confirmar." : "As cores já estão no padrão.",
    isDirty ? "warning" : "info",
  );
});

window.addEventListener("beforeunload", event => {
  if (!savedSnapshot || formSnapshot() === savedSnapshot) return;
  event.preventDefault();
  event.returnValue = "";
});

const initialTab = window.location.hash === "#personalizacao" ? "customization" : "zabbix";
setAdminTab(initialTab, false);

if (previewMode) {
  sessionText.textContent = "Modo demonstração - preferências locais";
  backToPanelLink.href = "index.html?demo=long";
  homeLinks.forEach(link => {
    link.href = "index.html?demo=long";
  });
  populateSettings(loadPreviewSettings());
} else {
  loadAdmin();
}
