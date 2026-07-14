    const DEFAULT_CONFIG = {
      REFRESH_SECONDS: 10,
      PAGE_SIZE: 6,
      PAGE_INTERVAL_SECONDS: 15,
      SORT_MODE: "recent",
      BACKEND_PROBLEMS_URL: "api/problems.php",
      ADMIN_URL: "admin.html"
    };

    const DEMO_VARIANT = new URLSearchParams(window.location.search).get("demo");
    const DEMO_MODE = DEMO_VARIANT !== null;

    const state = {
      config: { ...DEFAULT_CONFIG },
      problems: [],
      loading: false,
      error: null,
      lastRefreshAt: null,
      refreshTimer: null,
      pageTimer: null,
      currentPage: 0,
      sortModeOverride: null
    };

    const severityMap = {
      2: "Atencao",
      3: "Media",
      4: "Alta",
      5: "Desastre"
    };

    const sortModeLabel = {
      recent: "Mais recentes",
      severity: "Criticidade",
      duration: "Duracao",
      client: "Cliente",
      problem: "Problema"
    };

    const elements = {
      tv: document.querySelector(".tv"),
      clockTime: document.getElementById("clockTime"),
      clockDate: document.getElementById("clockDate"),
      refreshButton: document.getElementById("refreshButton"),
      settingsButton: document.getElementById("settingsButton"),
      totalCard: document.getElementById("totalCard"),
      totalProblems: document.getElementById("totalProblems"),
      totalNote: document.getElementById("totalNote"),
      countDisaster: document.getElementById("countDisaster"),
      countHigh: document.getElementById("countHigh"),
      countAverage: document.getElementById("countAverage"),
      countWarning: document.getElementById("countWarning"),
      noteDisaster: document.getElementById("noteDisaster"),
      noteHigh: document.getElementById("noteHigh"),
      noteAverage: document.getElementById("noteAverage"),
      noteWarning: document.getElementById("noteWarning"),
      pageTitle: document.getElementById("pageTitle"),
      panelSubtitle: document.getElementById("panelSubtitle"),
      statusPill: document.getElementById("statusPill"),
      problemList: document.getElementById("problemList"),
      sortButtons: document.querySelectorAll("[data-sort-mode]"),
      footerStatus: document.getElementById("footerStatus")
    };

    async function loadProblems() {
      if (state.loading) return;

      if (DEMO_MODE) {
        loadDemoProblems();
        return;
      }

      await loadProblemsFromBackend();
    }

    function redirectToLogin() {
      const adminUrl = state.config.ADMIN_URL || DEFAULT_CONFIG.ADMIN_URL;
      const next = `${window.location.pathname}${window.location.search}${window.location.hash}`;
      window.location.href = `${adminUrl}?next=${encodeURIComponent(next)}`;
    }

    function applyServerConfig(serverConfig) {
      const previousRefresh = Number(state.config.REFRESH_SECONDS);
      const previousPageInterval = Number(state.config.PAGE_INTERVAL_SECONDS);
      state.config = {
        ...state.config,
        ...serverConfig,
        SORT_MODE: state.sortModeOverride || serverConfig.SORT_MODE || state.config.SORT_MODE
      };

      // Timers start with defaults, then follow the values delivered by the backend.
      if (Number(state.config.REFRESH_SECONDS) !== previousRefresh) {
        scheduleAutoRefresh();
      }
      if (Number(state.config.PAGE_INTERVAL_SECONDS) !== previousPageInterval) {
        schedulePageRotation();
      }
    }

    async function loadProblemsFromBackend() {
      state.loading = true;
      state.error = null;
      elements.refreshButton.disabled = true;
      elements.footerStatus.textContent = "Consultando backend...";

      try {
        const response = await fetch(state.config.BACKEND_PROBLEMS_URL, {
          cache: "no-store",
          credentials: "same-origin"
        });
        const data = await response.json().catch(() => ({}));

        if (!response.ok || data.ok === false) {
          const error = new Error(data.error || `HTTP ${response.status}`);
          error.needsBackendConfig = response.status === 424;
          error.requiresLogin = response.status === 401;
          throw error;
        }

        if (data.config) applyServerConfig(data.config);

        state.problems = (data.problems || []).map(normalizeBackendProblem);
        state.problems.sort(sortProblems);
        state.lastRefreshAt = new Date();
        render();
      } catch (error) {
        console.error(error);
        if (error.requiresLogin) {
          redirectToLogin();
          return;
        }

        if (error.needsBackendConfig && !state.lastRefreshAt) {
          renderSetup();
          return;
        }

        // Keep the last valid snapshot visible during temporary Zabbix failures.
        state.error = error;
        if (!state.lastRefreshAt) {
          state.problems = [];
        }
        render();
      } finally {
        state.loading = false;
        elements.refreshButton.disabled = false;
      }
    }

    function normalizeBackendProblem(problem) {
      return {
        eventid: String(problem.eventid || ""),
        severity: Number(problem.severity),
        clock: Number(problem.clock),
        rClock: Number(problem.rClock) || 0,
        clientName: problem.clientName || "Cliente nao identificado",
        hostName: problem.hostName || "Host nao identificado",
        name: problem.name || "Problema sem nome",
        opdata: problem.opdata || "",
        status: problem.status || "INCIDENTE"
      };
    }

    function sortProblems(a, b) {
      if (state.config.SORT_MODE === "recent") {
        const eventDiff = compareEventIdDesc(a.eventid, b.eventid);
        if (eventDiff !== 0) return eventDiff;
        return b.clock - a.clock;
      }

      if (state.config.SORT_MODE === "duration") {
        const durationDiff = getProblemDurationSeconds(b) - getProblemDurationSeconds(a);
        if (durationDiff !== 0) return durationDiff;
        return b.severity - a.severity;
      }

      if (state.config.SORT_MODE === "client") {
        const clientDiff = a.clientName.localeCompare(b.clientName, "pt-BR", { sensitivity: "base" });
        if (clientDiff !== 0) return clientDiff;

        const hostDiff = a.hostName.localeCompare(b.hostName, "pt-BR", { sensitivity: "base" });
        if (hostDiff !== 0) return hostDiff;

        return b.severity - a.severity;
      }

      if (state.config.SORT_MODE === "problem") {
        const problemDiff = a.name.localeCompare(b.name, "pt-BR", { sensitivity: "base" });
        if (problemDiff !== 0) return problemDiff;
        return b.severity - a.severity;
      }

      const severityDiff = b.severity - a.severity;
      if (severityDiff !== 0) return severityDiff;
      return getProblemDurationSeconds(b) - getProblemDurationSeconds(a);
    }

    function compareEventIdDesc(a, b) {
      const aId = String(a || "0");
      const bId = String(b || "0");

      try {
        const aBig = BigInt(aId);
        const bBig = BigInt(bId);
        if (aBig === bBig) return 0;
        return aBig > bBig ? -1 : 1;
      } catch {
        if (aId.length !== bId.length) return bId.length - aId.length;
        return bId.localeCompare(aId);
      }
    }

    function getProblemDurationSeconds(problem) {
      const start = Number(problem.clock) || 0;
      const end = Number(problem.rClock) || Math.floor(Date.now() / 1000);
      return Math.max(0, end - start);
    }

    function render() {
      if (state.error && !state.lastRefreshAt) {
        renderSummary([]);
        renderError(state.error);
        return;
      }

      renderSummary(state.problems);
      renderList(state.problems);
      updateSortButtons();
      renderFooter();
    }

    function renderSummary(problems) {
      const counts = countBySeverity(problems);
      const total = problems.length;
      const oldest = [...problems].sort((a, b) => a.clock - b.clock)[0];

      elements.totalProblems.textContent = total;
      elements.countDisaster.textContent = counts[5];
      elements.countHigh.textContent = counts[4];
      elements.countAverage.textContent = counts[3];
      elements.countWarning.textContent = counts[2];
      elements.totalCard.classList.toggle("alerting", total > 0);
      elements.totalNote.textContent = oldest ? `Maior duracao: ${formatDuration(oldest.clock, oldest.rClock)}` : "Ambiente operacional";

      setCardNote(elements.noteDisaster, counts[5]);
      setCardNote(elements.noteHigh, counts[4]);
      setCardNote(elements.noteAverage, counts[3]);
      setCardNote(elements.noteWarning, counts[2]);

      elements.statusPill.classList.toggle("warning", Boolean(state.error && state.lastRefreshAt));
      elements.statusPill.classList.toggle("alerting", total > 0 && !(state.error && state.lastRefreshAt));
      elements.statusPill.textContent = state.error && state.lastRefreshAt
        ? "Sync falhou"
        : total > 0 ? "Em alerta" : "Operacional";
      const sortLabel = sortModeLabel[state.config.SORT_MODE] || sortModeLabel.severity;
      const pagination = getPaginationState(total);
      elements.pageTitle.textContent = total > 0
        ? `- Pagina ${pagination.currentPage + 1}/${pagination.totalPages}`
        : "";
      elements.panelSubtitle.textContent = state.error && state.lastRefreshAt
        ? `Ultimos dados bons - ordenacao: ${sortLabel}`
        : `Ordenacao: ${sortLabel}`;
    }

    function setCardNote(element, count) {
      element.textContent = count === 0 ? "Sem incidente" : `${count} ativo(s)`;
    }

    function renderList(problems) {
      if (problems.length === 0) {
        state.currentPage = 0;
        elements.problemList.classList.remove("compact");
        elements.problemList.innerHTML = `
          <div class="empty">
            <div>
              <div class="empty-title">Tudo operacional</div>
              <div class="empty-sub">Nenhum incidente ativo no momento.</div>
            </div>
          </div>
        `;
        return;
      }

      const pagination = getPaginationState(problems.length);
      const pageStart = pagination.currentPage * pagination.pageSize;
      const visibleProblems = problems.slice(pageStart, pageStart + pagination.pageSize);
      elements.problemList.classList.toggle("compact", problems.length >= 5);
      const rowHeight = calculateRowHeight(visibleProblems.length);
      elements.problemList.style.setProperty("--row-height", rowHeight);
      elements.problemList.innerHTML = visibleProblems.map(problem => `
        <div class="problem-row${problem.status === "RESOLVIDO" ? " resolved" : ""}">
          <div class="event-time">${formatEventTime(problem.clock)}</div>
          <div class="severity-badge sev-${problem.severity}">${severityMap[problem.severity] || "N/D"}</div>
          <div class="entity">
            <div class="primary" title="${escapeHtml(problem.clientName)}">${escapeHtml(problem.clientName)}</div>
            <div class="secondary" title="${escapeHtml(problem.hostName)}">${escapeHtml(problem.hostName)}</div>
          </div>
          <div class="problem-cell">
            <div class="problem-name" title="${escapeHtml(problem.name)}">${escapeHtml(problem.name)}</div>
            <div class="secondary" title="${escapeHtml(problem.opdata)}">${escapeHtml(problem.opdata || "Sem dados adicionais")}</div>
          </div>
          <div class="duration">${formatDuration(problem.clock, problem.rClock)}</div>
        </div>
      `).join("");
      elements.problemList.scrollTop = 0;
    }

    function updateSortButtons() {
      elements.sortButtons.forEach(button => {
        const isActive = button.dataset.sortMode === state.config.SORT_MODE;
        button.classList.toggle("active", isActive);
        button.setAttribute("aria-pressed", String(isActive));
        button.title = isActive
          ? `Ordenando por ${sortModeLabel[state.config.SORT_MODE]}`
          : `Ordenar por ${sortModeLabel[button.dataset.sortMode] || button.textContent}`;
      });
    }

    function calculateRowHeight(rowCount) {
      const panel = elements.problemList.getBoundingClientRect();
      const pageSize = Math.max(1, Number(state.config.PAGE_SIZE));
      const effectiveRows = Math.max(1, Math.min(rowCount || pageSize, pageSize));
      const minimumHeight = effectiveRows >= 5 ? 56 : 84;
      const availableHeight = Math.floor(panel.height / effectiveRows);
      return Math.max(minimumHeight, Math.min(140, availableHeight));
    }

    function getPaginationState(totalItems) {
      const pageSize = Math.max(1, Number(state.config.PAGE_SIZE) || DEFAULT_CONFIG.PAGE_SIZE);
      const totalPages = Math.max(1, Math.ceil(totalItems / pageSize));
      state.currentPage = Math.min(Math.max(0, state.currentPage), totalPages - 1);

      return {
        pageSize,
        totalPages,
        currentPage: state.currentPage
      };
    }

    function renderError(error) {
      updateSortButtons();
      elements.statusPill.textContent = "Erro";
      elements.statusPill.classList.add("alerting");
      elements.statusPill.classList.remove("warning");
      elements.pageTitle.textContent = "";
      elements.panelSubtitle.textContent = "Falha ao consultar API";
      elements.footerStatus.textContent = "Erro na atualizacao";
      elements.problemList.innerHTML = `
        <div class="error">
          <div>
            <div class="error-title">Falha ao carregar</div>
            <div class="error-sub">${escapeHtml(error.message)}</div>
          </div>
        </div>
      `;
    }

    function renderSetup() {
      renderSummary([]);
      updateSortButtons();
      elements.statusPill.textContent = "Configurar";
      elements.statusPill.classList.remove("alerting", "warning");
      elements.pageTitle.textContent = "";
      elements.panelSubtitle.textContent = "Configure URL e token da API";
      elements.footerStatus.textContent = "Aguardando configuracao da API";
      elements.problemList.innerHTML = `
        <div class="setup">
          <div>
            <div class="setup-title">Conecte ao Zabbix</div>
            <div class="setup-sub">Informe a URL da API e o token para iniciar o painel da TV.</div>
          </div>
        </div>
      `;
    }

    function loadDemoProblems() {
      const now = Math.floor(Date.now() / 1000);
      state.error = null;
      state.problems = [
        {
          eventid: "9004",
          severity: 3,
          clock: now - 115,
          rClock: now - 5,
          hostName: "Filial Norte - Gateway",
          clientName: "Filial Norte",
          name: "Gateway principal indisponivel.",
          opdata: "Recuperado recentemente",
          status: "RESOLVIDO"
        },
        {
          eventid: "9003",
          severity: 2,
          clock: now - 474,
          rClock: 0,
          hostName: "Matriz - Access Point 01",
          clientName: "Matriz",
          name: "Interface sem fio: alta taxa de erros por 5 minutos",
          opdata: "Interface com degradacao",
          status: "INCIDENTE"
        },
        {
          eventid: "9002",
          severity: 4,
          clock: now - 5435,
          rClock: 0,
          hostName: "Datacenter - Storage 01",
          clientName: "Datacenter",
          name: "Storage 01 indisponivel por ICMP ping",
          opdata: "Host indisponivel",
          status: "INCIDENTE"
        },
        {
          eventid: "9001",
          severity: 3,
          clock: now - 143940,
          rClock: 0,
          hostName: "Datacenter - Storage 01",
          clientName: "Datacenter",
          name: "Pool de dados nao esta online",
          opdata: "Storage pool offline",
          status: "INCIDENTE"
        }
      ];

      if (DEMO_VARIANT === "long") {
        const extraProblems = Array.from({ length: 12 }, (_, index) => {
          const severities = [5, 4, 3, 2];
          const severity = severities[index % severities.length];

          return {
            eventid: String(8999 - index),
            severity,
            clock: now - (7200 + index * 1880),
            rClock: 0,
            hostName: `Servidor demonstracao ${String(index + 1).padStart(2, "0")}`,
            clientName: index % 2 === 0 ? "Cliente Alfa" : "Cliente Beta",
            name: `Evento demonstrativo ${index + 1}: recurso em estado critico para teste de rolagem`,
            opdata: severity >= 4 ? "Acao imediata recomendada" : "Acompanhar comportamento",
            status: "INCIDENTE"
          };
        });

        state.problems = [...state.problems, ...extraProblems];
      }

      if (DEMO_VARIANT === "single") {
        state.problems = state.problems.slice(0, 1);
      }

      if (DEMO_VARIANT === "empty") {
        state.problems = [];
      }

      state.problems.sort(sortProblems);
      state.lastRefreshAt = new Date();
      render();
      elements.footerStatus.textContent += " - modo demo";
    }

    function renderFooter() {
      if (!state.lastRefreshAt) return;
      if (state.error) {
        elements.footerStatus.textContent = `Ultima sync OK ${state.lastRefreshAt.toLocaleTimeString("pt-BR")} - falha atual: ${state.error.message}`;
        return;
      }

      elements.footerStatus.textContent = `Sincronizado ${state.lastRefreshAt.toLocaleTimeString("pt-BR")}`;
    }

    function countBySeverity(problems) {
      return problems.reduce((counts, problem) => {
        if (counts[problem.severity] !== undefined) counts[problem.severity] += 1;
        return counts;
      }, { 2: 0, 3: 0, 4: 0, 5: 0 });
    }

    function updateClock() {
      const now = new Date();
      elements.clockTime.textContent = now.toLocaleTimeString("pt-BR");
      elements.clockDate.textContent = now.toLocaleDateString("pt-BR");
    }

    function updateViewportMode() {
      const isTv1080p = window.innerWidth >= 1600 && window.innerHeight >= 900 && window.innerHeight <= 1200;
      elements.tv.classList.toggle("tv-1080p", isTv1080p);
    }

    function formatEventTime(clock) {
      if (!clock) return "-";

      const date = new Date(Number(clock) * 1000);
      const now = new Date();
      const sameDay = date.toDateString() === now.toDateString();

      if (sameDay) {
        return date.toLocaleTimeString("pt-BR", {
          hour: "2-digit",
          minute: "2-digit",
          second: "2-digit"
        });
      }

      return date.toLocaleDateString("pt-BR", {
        day: "2-digit",
        month: "2-digit"
      }) + " " + date.toLocaleTimeString("pt-BR", {
        hour: "2-digit",
        minute: "2-digit"
      });
    }

    function formatDuration(clock, rClock = 0) {
      if (!clock) return "-";

      const endMs = rClock ? Number(rClock) * 1000 : Date.now();
      const totalMinutes = Math.max(0, Math.floor((endMs - clock * 1000) / 60000));
      const days = Math.floor(totalMinutes / 1440);
      const hours = Math.floor((totalMinutes % 1440) / 60);
      const minutes = totalMinutes % 60;

      if (days > 0) return `${days}d ${hours}h`;
      if (hours > 0) return `${hours}h ${minutes}m`;
      return `${minutes}m`;
    }

    function escapeHtml(value) {
      return String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#039;");
    }

    function clampNumber(value, min, max, fallback) {
      const number = Number(value);
      if (!Number.isFinite(number)) return fallback;
      return Math.max(min, Math.min(max, number));
    }

    function openSettings() {
      window.location.href = state.config.ADMIN_URL || DEFAULT_CONFIG.ADMIN_URL;
    }

    function scheduleAutoRefresh() {
      if (state.refreshTimer) {
        clearInterval(state.refreshTimer);
      }

      state.refreshTimer = setInterval(loadProblems, Math.max(5, Number(state.config.REFRESH_SECONDS)) * 1000);
    }

    function schedulePageRotation() {
      if (state.pageTimer) {
        clearInterval(state.pageTimer);
      }

      const intervalSeconds = clampNumber(
        state.config.PAGE_INTERVAL_SECONDS,
        5,
        120,
        DEFAULT_CONFIG.PAGE_INTERVAL_SECONDS
      );

      state.pageTimer = setInterval(() => {
        const pagination = getPaginationState(state.problems.length);
        if (pagination.totalPages <= 1 || document.hidden) return;

        state.currentPage = (state.currentPage + 1) % pagination.totalPages;
        render();
      }, intervalSeconds * 1000);
    }

    elements.refreshButton.addEventListener("click", loadProblems);
    elements.settingsButton.addEventListener("click", openSettings);
    elements.sortButtons.forEach(button => {
      button.addEventListener("click", () => {
        const sortMode = button.dataset.sortMode;
        if (!sortMode || sortMode === state.config.SORT_MODE) return;

        state.sortModeOverride = sortMode;
        state.config.SORT_MODE = sortMode;
        state.problems.sort(sortProblems);
        state.currentPage = 0;
        render();
      });
    });

    document.addEventListener("keydown", event => {
      if (event.key === "F2") {
        event.preventDefault();
        openSettings();
      }
    });

    document.addEventListener("visibilitychange", () => {
      if (!document.hidden && state.lastRefreshAt) {
        const ageMs = Date.now() - state.lastRefreshAt.getTime();
        if (ageMs > Math.max(5, Number(state.config.REFRESH_SECONDS)) * 1000) {
          loadProblems();
        }
      }
    });

    window.addEventListener("resize", updateViewportMode);

    updateViewportMode();
    updateClock();
    renderSetup();
    scheduleAutoRefresh();
    schedulePageRotation();
    loadProblems();
    setInterval(updateClock, 1000);
