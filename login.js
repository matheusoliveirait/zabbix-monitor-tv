const panels = {
  setup: document.getElementById("setupPanel"),
  login: document.getElementById("loginPanel"),
};
const forms = {
  setup: document.getElementById("setupForm"),
  login: document.getElementById("loginForm"),
};
const messagePanel = document.getElementById("messagePanel");
const messageText = document.getElementById("messageText");
const nextUrl = new URLSearchParams(window.location.search).get("next");
const previewMode = new URLSearchParams(window.location.search).get("preview");
const homeLinks = Array.from(document.querySelectorAll("[data-home-link]"));

async function loadAppearance() {
  try {
    const appearance = await api("api/appearance.php");
    window.IncidentTheme.apply(appearance.theme);
  } catch {
    window.IncidentTheme.apply(window.IncidentTheme.getStored());
  }
}

function showPanel(name) {
  Object.entries(panels).forEach(([key, panel]) => {
    panel.hidden = key !== name;
  });
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

async function api(path, options = {}) {
  const response = await fetch(path, {
    credentials: "same-origin",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    ...options,
  });
  const data = await response.json().catch(() => ({}));

  if (!response.ok || data.ok === false) {
    throw new Error(data.error || `HTTP ${response.status}`);
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
    showMessage(error.message, "error");
  } finally {
    if (submitButton) submitButton.disabled = false;
  }
}

function getSafeNextUrl() {
  if (!nextUrl) return "";

  try {
    const url = new URL(nextUrl, window.location.href);
    if (url.origin !== window.location.origin) return "";
    if (url.pathname.endsWith("/login.html")) return "";
    return url.href;
  } catch {
    return "";
  }
}

function redirectAuthenticated(fallback = "index.html") {
  window.location.replace(getSafeNextUrl() || fallback);
}

async function loadLogin() {
  clearMessage();

  try {
    const session = await api("api/auth.php");
    if (session.needsSetup) {
      showPanel("setup");
      return;
    }
    if (session.user) {
      redirectAuthenticated();
      return;
    }
    showPanel("login");
  } catch (error) {
    showPanel("login");
    showMessage(error.message, "error");
  }
}

forms.setup.addEventListener("submit", event => {
  submitForm(event, async () => {
    await api("api/auth.php", {
      method: "POST",
      body: JSON.stringify({ ...Object.fromEntries(new FormData(forms.setup).entries()), setup: true }),
    });
    window.location.replace("admin.html");
  });
});

forms.login.addEventListener("submit", event => {
  submitForm(event, async () => {
    await api("api/auth.php", {
      method: "POST",
      body: JSON.stringify(Object.fromEntries(new FormData(forms.login).entries())),
    });
    redirectAuthenticated();
  });
});

if (previewMode === "setup" || previewMode === "login") {
  homeLinks.forEach(link => {
    link.href = "index.html?demo=long";
  });
  window.IncidentTheme.apply(window.IncidentTheme.getStored());
  showPanel(previewMode);
} else {
  loadAppearance();
  loadLogin();
}
