const steps = Array.from(document.querySelectorAll("[data-step]"));
const stepNavigation = Array.from(document.querySelectorAll("[data-step-nav]"));
const messagePanel = document.getElementById("messagePanel");
const messageTitle = document.getElementById("messageTitle");
const messageText = document.getElementById("messageText");
const setupState = document.getElementById("setupState");
const requirementList = document.getElementById("requirementList");
const requirementsContinue = document.getElementById("requirementsContinue");
const preparedDatabase = document.getElementById("preparedDatabase");
const customDatabase = document.getElementById("customDatabase");
const zabbixSummary = document.getElementById("zabbixSummary");
const stepOrder = ["unlock", "requirements", "database", "admin", "zabbix", "finish"];

let state = null;
let csrf = "";
let currentStep = "";
let databaseMode = "prepared";
let urlMode = "quick";

function showMessage(title, message, type = "error") {
  messageTitle.textContent = title;
  messageText.textContent = message;
  messagePanel.dataset.type = type;
  messagePanel.hidden = false;
  messagePanel.scrollIntoView({ behavior: "smooth", block: "nearest" });
}

function clearMessage() {
  messagePanel.hidden = true;
  messageTitle.textContent = "";
  messageText.textContent = "";
}

function setBusy(element, busy) {
  if (!element) return;
  element.disabled = busy;
  element.dataset.originalText ||= element.textContent;
  element.textContent = busy ? "Aguarde..." : element.dataset.originalText;
}

async function request(options = {}) {
  const response = await fetch("api.php", {
    credentials: "same-origin",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    ...options,
  });
  const data = await response.json().catch(() => ({}));

  if (!response.ok || data.ok === false) {
    if (response.status === 419) {
      window.location.reload();
    }
    const error = new Error(data.error || `HTTP ${response.status}`);
    error.status = response.status;
    throw error;
  }

  return data;
}

async function action(name, payload = {}) {
  return request({
    method: "POST",
    body: JSON.stringify({ action: name, csrf, ...payload }),
  });
}

function updateNavigation(step) {
  const activeIndex = stepOrder.indexOf(step);

  stepNavigation.forEach(item => {
    const itemIndex = stepOrder.indexOf(item.dataset.stepNav);
    item.classList.toggle("is-current", item.dataset.stepNav === step);
    item.classList.toggle("is-complete", activeIndex > itemIndex);
  });
}

function showStep(name) {
  currentStep = name;
  clearMessage();
  steps.forEach(step => {
    step.hidden = step.dataset.step !== name;
  });
  updateNavigation(name);

  const stateLabels = {
    unprepared: "Preparação necessária",
    unlock: "Aguardando código",
    requirements: "Validando ambiente",
    database: "Configurando banco",
    admin: "Criando acesso",
    zabbix: "Conectando ao Zabbix",
    finish: "Pronto para concluir",
  };
  setupState.textContent = stateLabels[name] || "Instalação";
  setupState.dataset.state = name === "finish" ? "ready" : "";

  const focusTarget = document.querySelector(`[data-step="${name}"] input:not([type="hidden"])`);
  window.setTimeout(() => focusTarget?.focus(), 100);
}

function renderRequirements(requirements) {
  requirementList.replaceChildren();

  requirements.checks.forEach(check => {
    const item = document.createElement("div");
    item.className = `requirement ${check.ok ? "is-ready" : ""}`;

    const indicator = document.createElement("span");
    indicator.setAttribute("aria-hidden", "true");

    const label = document.createElement("strong");
    label.textContent = check.label;

    const value = document.createElement("small");
    value.textContent = check.value;

    item.append(indicator, label, value);
    requirementList.append(item);
  });

  requirementsContinue.disabled = !requirements.ready;
}

function renderPreparedDatabase(prepared) {
  const available = Boolean(prepared?.available);
  document.querySelector('[data-db-mode="prepared"]').disabled = !available;

  if (!available) {
    setDatabaseMode("custom");
    return;
  }

  ["host", "database", "username"].forEach(key => {
    document.querySelector(`[data-prepared="${key}"]`).textContent = prepared[key] || "-";
  });
}

function suggestedStep(status) {
  if (status.installed) return "installed";
  if (!status.prepared) return "unprepared";
  if (!status.unlocked) return "unlock";
  if (!status.requirements.ready) return "requirements";
  if (!status.appConfigured) return "database";
  if (status.databaseError) return "database";
  if (!status.adminCreated) return "admin";
  if (status.zabbixConfigured) return "finish";
  return "zabbix";
}

function applyStatus(status) {
  state = status;
  csrf = status.csrf || csrf;

  if (status.installed) {
    window.location.replace(status.loginUrl || "../login.html");
    return;
  }

  renderRequirements(status.requirements);
  if (status.unlocked) {
    renderPreparedDatabase(status.preparedDatabase);
  }
  showStep(suggestedStep(status));
}

async function loadStatus() {
  try {
    const status = await request();
    applyStatus(status);
  } catch (error) {
    showStep("unprepared");
    showMessage("Não foi possível iniciar", error.message);
  }
}

function setDatabaseMode(mode) {
  databaseMode = mode === "custom" ? "custom" : "prepared";
  document.querySelectorAll("[data-db-mode]").forEach(button => {
    button.setAttribute("aria-pressed", String(button.dataset.dbMode === databaseMode));
  });
  preparedDatabase.hidden = databaseMode !== "prepared";
  customDatabase.hidden = databaseMode !== "custom";
}

function quickZabbixUrl() {
  const protocol = document.getElementById("zabbixProtocol").value;
  const host = document.getElementById("zabbixHost").value.trim();
  return host ? `${protocol}://${host}/zabbix/api_jsonrpc.php` : "";
}

function setUrlMode(mode) {
  urlMode = mode === "full" ? "full" : "quick";
  document.querySelectorAll("[data-url-mode]").forEach(button => {
    button.setAttribute("aria-pressed", String(button.dataset.urlMode === urlMode));
  });
  document.getElementById("quickUrlFields").hidden = urlMode !== "quick";
  document.getElementById("fullUrlField").hidden = urlMode !== "full";

  if (urlMode === "full" && !document.getElementById("zabbixFullUrl").value) {
    document.getElementById("zabbixFullUrl").value = quickZabbixUrl();
  }
}

async function submit(event, callback) {
  event.preventDefault();
  clearMessage();
  const button = event.submitter;
  setBusy(button, true);

  try {
    await callback();
  } catch (error) {
    showMessage("Não foi possível continuar", error.message);
  } finally {
    setBusy(button, false);
  }
}

document.getElementById("unlockForm").addEventListener("submit", event => {
  submit(event, async () => {
    const form = new FormData(event.currentTarget);
    const result = await action("unlock", { token: String(form.get("token") || "").toUpperCase() });
    applyStatus(result);
  });
});

requirementsContinue.addEventListener("click", () => {
  if (!state?.requirements?.ready) return;
  if (state.appConfigured) {
    showStep(state.adminCreated ? "zabbix" : "admin");
    return;
  }
  showStep("database");
});

document.querySelectorAll("[data-db-mode]").forEach(button => {
  button.addEventListener("click", () => {
    if (button.disabled) return;
    setDatabaseMode(button.dataset.dbMode);
  });
});

document.getElementById("databaseForm").addEventListener("submit", event => {
  submit(event, async () => {
    const fields = Object.fromEntries(new FormData(event.currentTarget).entries());
    await action("database", {
      mode: databaseMode,
      database: fields,
    });
    showMessage("Banco preparado", "A conexão foi validada e as tabelas estão prontas.", "success");
    const status = await request();
    state = status;
    csrf = status.csrf;
    window.setTimeout(() => showStep("admin"), 350);
  });
});

document.getElementById("adminForm").addEventListener("submit", event => {
  submit(event, async () => {
    const fields = Object.fromEntries(new FormData(event.currentTarget).entries());
    await action("admin", fields);
    showMessage("Administrador criado", "Agora conecte o painel ao seu Zabbix.", "success");
    state.adminCreated = true;
    window.setTimeout(() => showStep("zabbix"), 350);
  });
});

document.querySelectorAll("[data-url-mode]").forEach(button => {
  button.addEventListener("click", () => setUrlMode(button.dataset.urlMode));
});

document.getElementById("zabbixForm").addEventListener("submit", event => {
  submit(event, async () => {
    const fields = Object.fromEntries(new FormData(event.currentTarget).entries());
    const url = urlMode === "quick"
      ? quickZabbixUrl()
      : document.getElementById("zabbixFullUrl").value.trim();

    if (!url) {
      throw new Error("Informe o IP, DNS ou a URL completa do Zabbix.");
    }

    await action("zabbix", { url, token: fields.token });
    state.zabbixConfigured = true;
    zabbixSummary.textContent = "Conexão validada";
    showStep("finish");
    showMessage("Zabbix conectado", "A URL e o token foram validados e salvos com segurança.", "success");
  });
});

document.getElementById("skipZabbix").addEventListener("click", () => {
  zabbixSummary.textContent = "Configuração pendente";
  showStep("finish");
  showMessage("Zabbix pendente", "Você poderá informar a API depois, na tela de configurações.", "warning");
});

document.getElementById("finishButton").addEventListener("click", async event => {
  clearMessage();
  setBusy(event.currentTarget, true);

  try {
    const result = await action("finish");
    setupState.textContent = "Instalação concluída";
    setupState.dataset.state = "ready";
    window.location.replace(result.loginUrl || "../login.html");
  } catch (error) {
    showMessage("Não foi possível finalizar", error.message);
    setBusy(event.currentTarget, false);
  }
});

document.querySelectorAll("[data-reload]").forEach(button => {
  button.addEventListener("click", () => window.location.reload());
});

loadStatus();
