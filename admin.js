const settingsForm = document.getElementById("settingsFormAdmin");
const messagePanel = document.getElementById("messagePanel");
const messageText = document.getElementById("messageText");
const sessionText = document.getElementById("sessionText");
const tokenHint = document.getElementById("tokenHint");
const logoutButton = document.getElementById("logoutButton");
const zabbixUrlButton = document.getElementById("zabbixUrlButton");
const ZABBIX_URL_TEMPLATE = "http://DIGITE-O-IP-DO-ZABBIX/zabbix/api_jsonrpc.php";
const previewMode = new URLSearchParams(window.location.search).has("preview");

function showMessage(message, type = "info") {
  messagePanel.hidden = false;
  messagePanel.dataset.type = type;
  messageText.textContent = message;
}

function clearMessage() {
  messagePanel.hidden = true;
  messageText.textContent = "";
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

function focusZabbixUrlTemplate() {
  const input = settingsForm.zabbix_api_url;
  if (!input.value.trim()) input.value = ZABBIX_URL_TEMPLATE;

  input.focus();
  const tokenStart = input.value.indexOf("DIGITE-O-IP-DO-ZABBIX");
  if (tokenStart >= 0) {
    input.setSelectionRange(tokenStart, tokenStart + "DIGITE-O-IP-DO-ZABBIX".length);
    return;
  }
  input.select();
}

function populateSettings(settings) {
  settingsForm.zabbix_api_url.value = settings.zabbix_api_url || ZABBIX_URL_TEMPLATE;
  settingsForm.zabbix_token.value = "";
  settingsForm.refresh_seconds.value = settings.refresh_seconds || 10;
  settingsForm.api_limit.value = settings.api_limit || 500;
  settingsForm.page_interval_seconds.value = settings.page_interval_seconds || 15;
  settingsForm.sort_mode.value = settings.sort_mode || "recent";
  settingsForm.fetch_mode.value = settings.fetch_mode || "incidents";
  settingsForm.monitored_group_ids.value = idsToText(settings.monitored_group_ids);
  settingsForm.monitored_host_ids.value = idsToText(settings.monitored_host_ids);
  tokenHint.textContent = settings.has_zabbix_token
    ? "Token ja salvo. Preencha apenas se quiser substituir."
    : "Nenhum token salvo.";
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
    const payload = Object.fromEntries(new FormData(settingsForm).entries());
    payload.monitored_group_ids = textToIds(payload.monitored_group_ids);
    payload.monitored_host_ids = textToIds(payload.monitored_host_ids);

    if (String(payload.zabbix_api_url || "").includes("DIGITE-O-IP-DO-ZABBIX")) {
      showMessage("Substitua o modelo pelo IP ou DNS real do Zabbix antes de salvar.", "error");
      focusZabbixUrlTemplate();
      return;
    }

    await api("api/settings.php", {
      method: "POST",
      body: JSON.stringify(payload),
    });
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

zabbixUrlButton.addEventListener("click", focusZabbixUrlTemplate);

if (previewMode) {
  sessionText.textContent = "Logado como Administrador";
  populateSettings({
    zabbix_api_url: "http://zabbix.exemplo.local/zabbix/api_jsonrpc.php",
    has_zabbix_token: true,
    refresh_seconds: 10,
    api_limit: 500,
    page_interval_seconds: 15,
    sort_mode: "recent",
    fetch_mode: "incidents",
    monitored_group_ids: [],
    monitored_host_ids: [],
  });
} else {
  loadAdmin();
}
