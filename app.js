    const DEFAULT_CONFIG = {
      ZABBIX_API_URL: "http://192.168.0.7/zabbix/api_jsonrpc.php",
      ZABBIX_TOKEN: "",
      CONFIG_VERSION: 6,
      REFRESH_SECONDS: 10,
      API_LIMIT: 500,
      PAGE_SIZE: 6,
      PAGE_INTERVAL_SECONDS: 15,
      SORT_MODE: "recent",
      FETCH_MODE: "incidents",
      SEVERITIES: [2, 3, 4, 5],
      MONITORED_GROUP_IDS: [],
      MONITORED_HOST_IDS: []
    };

    const STORAGE_KEY = "hpro-zabbix-tv-panel-config-v2";
    const DEMO_VARIANT = new URLSearchParams(window.location.search).get("demo");
    const DEMO_MODE = DEMO_VARIANT !== null;

    const state = {
      config: loadConfig(),
      problems: [],
      ignoredInactiveCount: 0,
      loading: false,
      error: null,
      lastRefreshAt: null,
      refreshTimer: null,
      pageTimer: null,
      currentPage: 0
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
      panelSubtitle: document.getElementById("panelSubtitle"),
      statusPill: document.getElementById("statusPill"),
      problemList: document.getElementById("problemList"),
      sortButtons: document.querySelectorAll("[data-sort-mode]"),
      footerStatus: document.getElementById("footerStatus"),
      settingsDrawer: document.getElementById("settingsDrawer"),
      settingsForm: document.getElementById("settingsForm"),
      closeSettings: document.getElementById("closeSettings")
    };

    function loadConfig() {
      try {
        const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}");
        const savedVersion = Number(saved.CONFIG_VERSION || 0);
        const migratedRefreshSeconds = saved.CONFIG_VERSION
          ? saved.REFRESH_SECONDS
          : Math.min(Number(saved.REFRESH_SECONDS || DEFAULT_CONFIG.REFRESH_SECONDS), DEFAULT_CONFIG.REFRESH_SECONDS);
        const migratedSortMode = savedVersion >= DEFAULT_CONFIG.CONFIG_VERSION
          ? saved.SORT_MODE
          : DEFAULT_CONFIG.SORT_MODE;

        return {
          ...DEFAULT_CONFIG,
          ...saved,
          CONFIG_VERSION: DEFAULT_CONFIG.CONFIG_VERSION,
          REFRESH_SECONDS: clampNumber(migratedRefreshSeconds, 5, 900, DEFAULT_CONFIG.REFRESH_SECONDS),
          API_LIMIT: clampNumber(saved.API_LIMIT, 20, 5000, DEFAULT_CONFIG.API_LIMIT),
          PAGE_SIZE: DEFAULT_CONFIG.PAGE_SIZE,
          PAGE_INTERVAL_SECONDS: clampNumber(
            saved.PAGE_INTERVAL_SECONDS,
            5,
            120,
            DEFAULT_CONFIG.PAGE_INTERVAL_SECONDS
          ),
          SORT_MODE: ["recent", "severity", "duration", "client", "problem"].includes(migratedSortMode) ? migratedSortMode : DEFAULT_CONFIG.SORT_MODE,
          FETCH_MODE: ["incidents", "problems"].includes(saved.FETCH_MODE) ? saved.FETCH_MODE : DEFAULT_CONFIG.FETCH_MODE,
          SEVERITIES: DEFAULT_CONFIG.SEVERITIES,
          MONITORED_GROUP_IDS: Array.isArray(saved.MONITORED_GROUP_IDS) ? saved.MONITORED_GROUP_IDS : [],
          MONITORED_HOST_IDS: Array.isArray(saved.MONITORED_HOST_IDS) ? saved.MONITORED_HOST_IDS : []
        };
      } catch {
        return { ...DEFAULT_CONFIG };
      }
    }

    function saveConfig(config) {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(config));
      state.config = config;
    }

    async function zabbixRequest(method, params) {
      const response = await fetch(state.config.ZABBIX_API_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json-rpc",
          "Authorization": `Bearer ${state.config.ZABBIX_TOKEN}`
        },
        body: JSON.stringify({
          jsonrpc: "2.0",
          method,
          params,
          id: Date.now()
        })
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status} - ${response.statusText}`);
      }

      const data = await response.json();

      if (data.error) {
        throw new Error(data.error.data || data.error.message || "Erro desconhecido na API");
      }

      return data.result;
    }

    async function loadProblems() {
      if (state.loading) return;

      if (DEMO_MODE) {
        loadDemoProblems();
        return;
      }

      if (!state.config.ZABBIX_API_URL || !state.config.ZABBIX_TOKEN) {
        renderSetup();
        openSettings();
        return;
      }

      state.loading = true;
      state.error = null;
      elements.refreshButton.disabled = true;
      elements.footerStatus.textContent = "Consultando API do Zabbix...";

      try {
        const problemParams = {
          output: [
            "eventid",
            "objectid",
            "name",
            "severity",
            "clock",
            "r_eventid",
            "r_clock",
            "acknowledged",
            "suppressed",
            "cause_eventid",
            "opdata"
          ],
          selectTags: "extend",
          severities: state.config.SEVERITIES,
          source: 0,
          object: 0,
          recent: true,
          suppressed: false,
          sortfield: "eventid",
          sortorder: "DESC",
          limit: Number(state.config.API_LIMIT)
        };

        if (state.config.MONITORED_GROUP_IDS.length > 0) {
          problemParams.groupids = state.config.MONITORED_GROUP_IDS;
        }

        if (state.config.MONITORED_HOST_IDS.length > 0) {
          problemParams.hostids = state.config.MONITORED_HOST_IDS;
        }

        const problems = await getProblems(problemParams);
        const rootProblems = state.config.FETCH_MODE === "incidents"
          ? problems.filter(problem => isRootCauseEvent(problem.cause_eventid))
          : problems;
        const triggerIds = [...new Set(rootProblems.map(problem => String(problem.objectid)).filter(Boolean))];

        let triggerMap = new Map();
        let hostMap = new Map();

        if (triggerIds.length > 0) {
          const triggers = await zabbixRequest("trigger.get", {
            output: ["triggerid", "description", "priority", "status"],
            triggerids: triggerIds,
            selectHosts: ["hostid", "host", "name", "status"],
            selectItems: ["itemid", "name", "key_", "status"],
            expandDescription: true
          });

          triggerMap = new Map(triggers.map(trigger => [String(trigger.triggerid), trigger]));

          const hostIds = [
            ...new Set(
              triggers
                .flatMap(trigger => trigger.hosts || [])
                .map(host => String(host.hostid))
                .filter(Boolean)
            )
          ];

          if (hostIds.length > 0) {
            const hosts = await getHostsWithGroups(hostIds);
            hostMap = new Map(hosts.map(host => [String(host.hostid), host]));
          }
        }

        const monitoredProblems = rootProblems.filter(problem => isProblemMonitored(problem, triggerMap, hostMap));
        state.ignoredInactiveCount = rootProblems.length - monitoredProblems.length;
        state.problems = monitoredProblems.map(problem => normalizeProblem(problem, triggerMap, hostMap));
        state.problems.sort(sortProblems);
        state.lastRefreshAt = new Date();
        render();
      } catch (error) {
        console.error(error);
        state.error = error;
        state.problems = [];
        state.ignoredInactiveCount = 0;
        render();
      } finally {
        state.loading = false;
        elements.refreshButton.disabled = false;
      }
    }

    async function getHostsWithGroups(hostIds) {
      try {
        return await zabbixRequest("host.get", {
          output: ["hostid", "host", "name", "status"],
          hostids: hostIds,
          selectHostGroups: ["groupid", "name"]
        });
      } catch (error) {
        console.warn("Falha usando selectHostGroups. Tentando selectGroups...", error);

        return await zabbixRequest("host.get", {
          output: ["hostid", "host", "name", "status"],
          hostids: hostIds,
          selectGroups: ["groupid", "name"]
        });
      }
    }

    async function getProblems(problemParams) {
      try {
        return await zabbixRequest("problem.get", problemParams);
      } catch (error) {
        const message = String(error.message || "");
        const canFallback = state.config.FETCH_MODE === "incidents" &&
          (message.includes("/source") || message.includes("/object") || message.includes("Invalid parameter"));

        if (!canFallback) {
          throw error;
        }

        console.warn("Modo incidentes estrito nao suportado por esta API. Repetindo consulta sem source/object.", error);
        const fallbackParams = { ...problemParams };
        delete fallbackParams.source;
        delete fallbackParams.object;

        return zabbixRequest("problem.get", fallbackParams);
      }
    }

    function isProblemMonitored(problem, triggerMap, hostMap) {
      const trigger = triggerMap.get(String(problem.objectid));

      if (!trigger || !isEnabledStatus(trigger.status)) {
        return false;
      }

      const triggerHosts = trigger.hosts || [];
      const hasDisabledHost = triggerHosts.some(host => {
        const enrichedHost = hostMap.get(String(host.hostid)) || host;
        return !isEnabledStatus(enrichedHost.status);
      });

      if (hasDisabledHost) {
        return false;
      }

      const triggerItems = trigger.items || [];
      return triggerItems.every(item => isEnabledStatus(item.status));
    }

    function isEnabledStatus(status) {
      return status === undefined ||
        status === null ||
        status === "" ||
        String(status) === "0";
    }

    function normalizeProblem(problem, triggerMap, hostMap) {
      const trigger = triggerMap.get(String(problem.objectid));
      const primaryHostFromTrigger = trigger?.hosts?.[0] || null;
      const hostFromMap = primaryHostFromTrigger ? hostMap.get(String(primaryHostFromTrigger.hostid)) : null;
      const host = hostFromMap || primaryHostFromTrigger;
      const hostName = host ? (host.name || host.host || "Host nao identificado") : "Host nao identificado";
      const hostGroups = host ? (host.hostgroups || host.groups || []) : [];

      return {
        eventid: problem.eventid,
        name: problem.name || trigger?.description || "Problema sem nome",
        severity: Number(problem.severity),
        clock: Number(problem.clock),
        rEventId: problem.r_eventid,
        rClock: Number(problem.r_clock) || 0,
        acknowledged: problem.acknowledged,
        suppressed: problem.suppressed,
        causeEventId: problem.cause_eventid,
        opdata: problem.opdata || "",
        hostName,
        clientName: getClientName(problem.tags, hostGroups, hostName),
        status: isResolvedProblem(problem) ? "RESOLVIDO" : "INCIDENTE"
      };
    }

    function isRootCauseEvent(causeEventId) {
      return causeEventId === undefined ||
        causeEventId === null ||
        causeEventId === "" ||
        causeEventId === "0" ||
        causeEventId === 0;
    }

    function isResolvedProblem(problem) {
      return hasNonZeroValue(problem.r_eventid) || hasNonZeroValue(problem.r_clock);
    }

    function hasNonZeroValue(value) {
      return value !== undefined &&
        value !== null &&
        value !== "" &&
        value !== "0" &&
        value !== 0;
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
      if (state.error) {
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

      elements.statusPill.textContent = total > 0 ? "Em alerta" : "Operacional";
      elements.statusPill.classList.toggle("alerting", total > 0);
      const sortLabel = sortModeLabel[state.config.SORT_MODE] || sortModeLabel.severity;
      const pagination = getPaginationState(total);
      elements.panelSubtitle.textContent =
        `Ordenacao: ${sortLabel} | Pagina ${pagination.currentPage + 1} de ${pagination.totalPages}`;
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
              <div class="empty-title">Nenhum incidente ativo</div>
              <div class="empty-sub">Todos os ambientes monitorados estao operando normalmente.</div>
            </div>
          </div>
        `;
        return;
      }

      const pagination = getPaginationState(problems.length);
      const pageStart = pagination.currentPage * pagination.pageSize;
      const visibleProblems = problems.slice(pageStart, pageStart + pagination.pageSize);
      elements.problemList.classList.toggle("compact", problems.length >= pagination.pageSize);
      const rowHeight = calculateRowHeight(visibleProblems.length);
      elements.problemList.style.setProperty("--row-height", rowHeight);
      elements.problemList.innerHTML = visibleProblems.map(problem => `
        <div class="problem-row ${problem.status === "RESOLVIDO" ? "resolved" : "incident"}">
          <div class="event-time">${formatEventTime(problem.clock)}</div>
          <div class="severity-badge sev-${problem.severity}">${severityMap[problem.severity] || "N/D"}</div>
          <div class="status-badge ${problem.status === "RESOLVIDO" ? "resolved" : "incident"}">${problem.status}</div>
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
      const minimumHeight = effectiveRows >= pageSize ? 56 : 84;
      return Math.max(minimumHeight, Math.floor(panel.height / effectiveRows));
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
      elements.statusPill.classList.remove("alerting");
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
      state.problems = [
        {
          eventid: "9004",
          severity: 3,
          clock: now - 115,
          rEventId: "9104",
          rClock: now - 5,
          hostName: "HPRO - AP - Infra",
          clientName: "HPro",
          name: "O DVR NR - Pisense esta indisponivel.",
          opdata: "Recuperado recentemente",
          status: "RESOLVIDO"
        },
        {
          eventid: "9003",
          severity: 2,
          clock: now - 474,
          rEventId: "0",
          rClock: 0,
          hostName: "HPRO - AP - Refeitorio",
          clientName: "HPro",
          name: "Interface wifi1ap5: High error rate (>2 for 5m)",
          opdata: "Interface com degradacao",
          status: "INCIDENTE"
        },
        {
          eventid: "9002",
          severity: 4,
          clock: now - 5435,
          rEventId: "0",
          rClock: 0,
          hostName: "Hpro - Truenas Bancada",
          clientName: "HPro",
          name: "TrueNAS CORE: Unavailable by ICMP ping",
          opdata: "Host indisponivel",
          status: "INCIDENTE"
        },
        {
          eventid: "9001",
          severity: 3,
          clock: now - 143940,
          rEventId: "0",
          rClock: 0,
          hostName: "Hpro - Truenas Bancada",
          clientName: "HPro",
          name: "TrueNAS CORE: Pool [Dados]: Status is not online",
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
            rEventId: "0",
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

      state.ignoredInactiveCount = 0;
      state.problems.sort(sortProblems);
      state.lastRefreshAt = new Date();
      elements.settingsDrawer.classList.remove("open");
      render();
      elements.footerStatus.textContent += " - modo demo";
    }

    function renderFooter() {
      if (!state.lastRefreshAt) return;
      elements.footerStatus.textContent = `Sincronizado ${state.lastRefreshAt.toLocaleTimeString("pt-BR")}`;
    }

    function countBySeverity(problems) {
      return problems.reduce((counts, problem) => {
        if (counts[problem.severity] !== undefined) counts[problem.severity] += 1;
        return counts;
      }, { 2: 0, 3: 0, 4: 0, 5: 0 });
    }

    function getClientName(tags, hostgroups, hostName) {
      const tagNamesForClient = ["cliente", "client", "customer", "empresa", "tenant"];
      const clientTag = (tags || []).find(tag => tagNamesForClient.includes(String(tag.tag || "").toLowerCase().trim()));

      if (clientTag && clientTag.value) {
        return clientTag.value;
      }

      const ignoredGroups = [
        "templates",
        "linux servers",
        "windows servers",
        "zabbix servers",
        "discovered hosts",
        "network devices",
        "servidores",
        "clientes",
        "infraestrutura",
        "hypervisors",
        "switches",
        "firewalls",
        "roteadores",
        "appliances",
        "vmware",
        "snmp"
      ];

      const validGroup = (hostgroups || []).find(group => {
        const groupName = String(group.name || "").toLowerCase().trim();
        return groupName && !ignoredGroups.includes(groupName);
      });

      if (validGroup && validGroup.name) {
        return validGroup.name;
      }

      if (hostName.includes(" - ")) {
        return hostName.split(" - ")[0].trim();
      }

      return hostName;
    }

    function updateClock() {
      const now = new Date();
      elements.clockTime.textContent = now.toLocaleTimeString("pt-BR");
      elements.clockDate.textContent = now.toLocaleDateString("pt-BR");
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

    function parseIds(value) {
      return String(value || "")
        .split(",")
        .map(item => item.trim())
        .filter(Boolean);
    }

    function clampNumber(value, min, max, fallback) {
      const number = Number(value);
      if (!Number.isFinite(number)) return fallback;
      return Math.max(min, Math.min(max, number));
    }

    function openSettings() {
      fillSettingsForm();
      elements.settingsDrawer.classList.add("open");
      document.getElementById("apiUrl").focus();
    }

    function closeSettings() {
      elements.settingsDrawer.classList.remove("open");
    }

    function fillSettingsForm() {
      const form = elements.settingsForm;
      form.apiUrl.value = state.config.ZABBIX_API_URL || "";
      form.apiToken.value = state.config.ZABBIX_TOKEN || "";
      form.refreshSeconds.value = state.config.REFRESH_SECONDS;
      form.apiLimit.value = state.config.API_LIMIT;
      form.pageIntervalSeconds.value = state.config.PAGE_INTERVAL_SECONDS;
      form.sortMode.value = state.config.SORT_MODE;
      form.fetchMode.value = state.config.FETCH_MODE;
      form.groupIds.value = state.config.MONITORED_GROUP_IDS.join(", ");
      form.hostIds.value = state.config.MONITORED_HOST_IDS.join(", ");
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

    elements.settingsForm.addEventListener("submit", event => {
      event.preventDefault();
      const form = elements.settingsForm;

      saveConfig({
        ...state.config,
        ZABBIX_API_URL: form.apiUrl.value.trim(),
        ZABBIX_TOKEN: form.apiToken.value.trim(),
        CONFIG_VERSION: DEFAULT_CONFIG.CONFIG_VERSION,
        REFRESH_SECONDS: clampNumber(form.refreshSeconds.value, 5, 900, DEFAULT_CONFIG.REFRESH_SECONDS),
        API_LIMIT: clampNumber(form.apiLimit.value, 20, 5000, DEFAULT_CONFIG.API_LIMIT),
        PAGE_SIZE: DEFAULT_CONFIG.PAGE_SIZE,
        PAGE_INTERVAL_SECONDS: clampNumber(
          form.pageIntervalSeconds.value,
          5,
          120,
          DEFAULT_CONFIG.PAGE_INTERVAL_SECONDS
        ),
        SORT_MODE: form.sortMode.value,
        FETCH_MODE: form.fetchMode.value,
        MONITORED_GROUP_IDS: parseIds(form.groupIds.value),
        MONITORED_HOST_IDS: parseIds(form.hostIds.value)
      });

      scheduleAutoRefresh();
      schedulePageRotation();
      state.currentPage = 0;
      closeSettings();
      loadProblems();
    });

    elements.refreshButton.addEventListener("click", loadProblems);
    elements.settingsButton.addEventListener("click", openSettings);
    elements.closeSettings.addEventListener("click", closeSettings);
    elements.sortButtons.forEach(button => {
      button.addEventListener("click", () => {
        const sortMode = button.dataset.sortMode;
        if (!sortMode || sortMode === state.config.SORT_MODE) return;

        saveConfig({
          ...state.config,
          SORT_MODE: sortMode
        });

        state.problems.sort(sortProblems);
        state.currentPage = 0;
        render();
      });
    });
    elements.settingsDrawer.addEventListener("click", event => {
      if (event.target === elements.settingsDrawer) closeSettings();
    });

    document.addEventListener("visibilitychange", () => {
      if (!document.hidden && state.lastRefreshAt) {
        const ageMs = Date.now() - state.lastRefreshAt.getTime();
        if (ageMs > Math.max(5, Number(state.config.REFRESH_SECONDS)) * 1000) {
          loadProblems();
        }
      }
    });

    updateClock();
    renderSetup();
    scheduleAutoRefresh();
    schedulePageRotation();
    loadProblems();
    setInterval(updateClock, 1000);
