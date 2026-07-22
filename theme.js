(() => {
  const DEFAULT_THEME = "graphite";
  const STORAGE_KEY = "central-incidentes-theme-v1";
  const THEMES = new Set(["graphite", "light", "blue"]);
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

  window.IncidentTheme = Object.freeze({ DEFAULT_THEME, apply, getStored, normalize });
})();
