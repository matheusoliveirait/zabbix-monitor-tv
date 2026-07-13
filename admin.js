const panels = {
  setup: document.getElementById("setupPanel"),
  login: document.getElementById("loginPanel"),
  settings: document.getElementById("settingsPanel"),
  message: document.getElementById("messagePanel"),
};

const forms = {
  setup: document.getElementById("setupForm"),
  login: document.getElementById("loginForm"),
  settings: document.getElementById("settingsFormAdmin"),
};

const messageText = document.getElementById("messageText");
const sessionText = document.getElementById("sessionText");
const tokenHint = document.getElementById("tokenHint");
const logoutButton = document.getElementById("logoutButton");

function showPanel(name) {
  Object.entries(panels).forEach(([key, panel]) => {
    if (key !== "message") panel.hidden = key !== name;
  });
}

function showMessage(message, type = "info") {
  panels.message.hidden = false;
  panels.message.dataset.type = type;
  messageText.textContent = message;
}

function clearMessage() {
  panels.message.hidden = true;
  messageText.textContent = "";
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    credentials: "same-origin",
    headers: {
      "Content-Type": "application/json",
      ...(options.headers || {}),
    },
    ...options,
  });
  const data = await response.json().catch(() => ({}));

  if (!response.ok || data.ok === false) {
    throw new Error(data.error || `HTTP ${response.status}`);
  }

  return data;
}

function formJson(form) {
  return Object.fromEntries(new FormData(form).entries());
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

async function loadSession() {
  clearMessage();

  try {
    const session = await api("api/auth.php");

    if (session.needsSetup) {
      showPanel("setup");
      return;
    }

    if (!session.user) {
      showPanel("login");
      return;
    }

    sessionText.textContent = `Logado como ${session.user.name || session.user.username}`;
    showPanel("settings");
    await loadSettings();
  } catch (error) {
    showPanel("login");
    showMessage(error.message, "error");
  }
}

async function loadSettings() {
  const data = await api("api/settings.php");
  const settings = data.settings;
  const form = forms.settings;

  form.zabbix_api_url.value = settings.zabbix_api_url || "";
  form.zabbix_token.value = "";
  form.refresh_seconds.value = settings.refresh_seconds || 10;
  form.api_limit.value = settings.api_limit || 500;
  form.page_interval_seconds.value = settings.page_interval_seconds || 15;
  form.sort_mode.value = settings.sort_mode || "recent";
  form.fetch_mode.value = settings.fetch_mode || "incidents";
  form.monitored_group_ids.value = idsToText(settings.monitored_group_ids);
  form.monitored_host_ids.value = idsToText(settings.monitored_host_ids);
  tokenHint.textContent = settings.has_zabbix_token
    ? "Token ja salvo. Preencha apenas se quiser substituir."
    : "Nenhum token salvo.";

  if (data.usingExampleConfig) {
    showMessage("Crie config/app.php a partir de config/app.example.php e troque o app_key antes de usar em producao.", "warning");
  }
}

forms.setup.addEventListener("submit", async event => {
  event.preventDefault();
  clearMessage();

  try {
    await api("api/auth.php", {
      method: "POST",
      body: JSON.stringify({ ...formJson(forms.setup), setup: true }),
    });
    showMessage("Administrador criado com sucesso.", "success");
    await loadSession();
  } catch (error) {
    showMessage(error.message, "error");
  }
});

forms.login.addEventListener("submit", async event => {
  event.preventDefault();
  clearMessage();

  try {
    await api("api/auth.php", {
      method: "POST",
      body: JSON.stringify(formJson(forms.login)),
    });
    await loadSession();
  } catch (error) {
    showMessage(error.message, "error");
  }
});

forms.settings.addEventListener("submit", async event => {
  event.preventDefault();
  clearMessage();
  const payload = formJson(forms.settings);
  payload.monitored_group_ids = textToIds(payload.monitored_group_ids);
  payload.monitored_host_ids = textToIds(payload.monitored_host_ids);

  try {
    await api("api/settings.php", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    showMessage("Configuracoes salvas.", "success");
    await loadSettings();
  } catch (error) {
    showMessage(error.message, "error");
  }
});

logoutButton.addEventListener("click", async () => {
  clearMessage();

  try {
    await api("api/auth.php", { method: "DELETE" });
    showPanel("login");
    showMessage("Sessao encerrada.", "success");
  } catch (error) {
    showMessage(error.message, "error");
  }
});

loadSession();
