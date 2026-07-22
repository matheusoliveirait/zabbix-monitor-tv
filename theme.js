(() => {
  const DEFAULT_THEME = "graphite";
  const STORAGE_KEY = "central-incidentes-theme-v1";
  const THEMES = new Set(["graphite", "light", "blue"]);
  const DEFAULT_SEVERITY_COLORS = Object.freeze({
    2: "#eab308",
    3: "#f59e0b",
    4: "#f97316",
    5: "#ef4444",
  });
  const assets = {
    graphite: { logo: "assets/logo-mark.svg?v=6", favicon: "assets/favicon.svg?v=6" },
    light: { logo: "assets/logo-mark-light.svg?v=1", favicon: "assets/favicon-light.svg?v=1" },
    blue: { logo: "assets/logo-mark-blue.svg?v=1", favicon: "assets/favicon-blue.svg?v=1" },
  };

  function normalize(value) {
    return THEMES.has(value) ? value : DEFAULT_THEME;
  }

  function getStored() {
    try {
      return normalize(localStorage.getItem(STORAGE_KEY));
    } catch {
      return DEFAULT_THEME;
    }
  }

  function normalizeHexColor(value, fallback) {
    const candidate = String(value || "").trim().toLowerCase();
    return /^#[0-9a-f]{6}$/.test(candidate) ? candidate : fallback;
  }

  function normalizeSeverityColors(value) {
    const colors = value && typeof value === "object" ? value : {};
    return Object.fromEntries(
      Object.entries(DEFAULT_SEVERITY_COLORS).map(([severity, fallback]) => [
        severity,
        normalizeHexColor(colors[severity], fallback),
      ]),
    );
  }

  function contrastColor(value) {
    const color = normalizeHexColor(value, "#000000").slice(1);
    const channels = [0, 2, 4].map(index => {
      const channel = Number.parseInt(color.slice(index, index + 2), 16) / 255;
      return channel <= 0.04045
        ? channel / 12.92
        : ((channel + 0.055) / 1.055) ** 2.4;
    });
    const luminance = (0.2126 * channels[0]) + (0.7152 * channels[1]) + (0.0722 * channels[2]);
    const whiteContrast = 1.05 / (luminance + 0.05);
    const darkContrast = (luminance + 0.05) / 0.057;
    return whiteContrast >= darkContrast ? "#ffffff" : "#111827";
  }

  function updateAssets(theme) {
    const selectedAssets = assets[theme];
    document.querySelectorAll("[data-theme-logo]").forEach(image => {
      if (image.getAttribute("src") !== selectedAssets.logo) image.setAttribute("src", selectedAssets.logo);
    });

    const favicon = document.querySelector('link[rel="icon"]');
    if (favicon) favicon.setAttribute("href", selectedAssets.favicon);
  }

  function apply(value, store = true) {
    const theme = normalize(value);
    document.documentElement.dataset.theme = theme;
    updateAssets(theme);

    if (store) {
      try {
        localStorage.setItem(STORAGE_KEY, theme);
      } catch {
        // The selected theme still applies when storage is unavailable.
      }
    }

    return theme;
  }

  const initialTheme = getStored();
  document.documentElement.dataset.theme = initialTheme;
  document.addEventListener("DOMContentLoaded", () => updateAssets(initialTheme), { once: true });
  window.addEventListener("storage", event => {
    if (event.key === STORAGE_KEY && event.newValue) apply(event.newValue, false);
  });

  window.IncidentTheme = Object.freeze({
    DEFAULT_THEME,
    DEFAULT_SEVERITY_COLORS,
    apply,
    contrastColor,
    getStored,
    normalize,
    normalizeHexColor,
    normalizeSeverityColors,
  });
})();
