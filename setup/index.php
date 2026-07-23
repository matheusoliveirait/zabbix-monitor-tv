<?php

declare(strict_types=1);

require dirname(__DIR__) . '/includes/installation.php';

if (application_is_installed()) {
    header('Location: ../login.html', true, 302);
    exit;
}

header('Content-Type: text/html; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
header('X-Frame-Options: DENY');
?>
<!DOCTYPE html>
<html lang="pt-BR" data-theme="graphite">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta name="robots" content="noindex,nofollow" />
  <title>Instalação - Central de Incidentes</title>
  <link rel="icon" href="../assets/favicon.svg" type="image/svg+xml" />
  <link rel="stylesheet" href="setup.css?v=1" />
</head>
<body>
  <main class="setup-shell">
    <aside class="setup-sidebar">
      <a class="setup-brand" href="../" aria-label="Central de Incidentes">
        <img src="../assets/logo-mark.svg" alt="" />
        <span>
          <strong>Central de Incidentes</strong>
          <small>Instalação guiada</small>
        </span>
      </a>

      <nav class="setup-progress" aria-label="Etapas da instalação">
        <ol>
          <li data-step-nav="unlock"><span>1</span><div><strong>Acesso</strong><small>Código temporário</small></div></li>
          <li data-step-nav="requirements"><span>2</span><div><strong>Ambiente</strong><small>PHP e permissões</small></div></li>
          <li data-step-nav="database"><span>3</span><div><strong>Banco de dados</strong><small>Conexão e tabelas</small></div></li>
          <li data-step-nav="admin"><span>4</span><div><strong>Administrador</strong><small>Primeiro acesso</small></div></li>
          <li data-step-nav="zabbix"><span>5</span><div><strong>Zabbix</strong><small>API e token</small></div></li>
          <li data-step-nav="finish"><span>6</span><div><strong>Concluir</strong><small>Bloquear instalador</small></div></li>
        </ol>
      </nav>

      <div class="setup-security">
        <span class="security-indicator" aria-hidden="true"></span>
        <p>As credenciais permanecem neste servidor e não são enviadas ao GitHub.</p>
      </div>
    </aside>

    <section class="setup-workspace">
      <header class="setup-header">
        <div>
          <span class="eyebrow">Configuração inicial</span>
          <h1>Prepare seu painel</h1>
        </div>
        <span class="setup-state" id="setupState">Verificando servidor</span>
      </header>

      <section class="setup-message" id="messagePanel" role="status" aria-live="polite" hidden>
        <strong id="messageTitle"></strong>
        <span id="messageText"></span>
      </section>

      <div class="setup-content">
        <section class="setup-step" data-step="unprepared" hidden>
          <div class="step-heading">
            <span class="step-number">Antes de começar</span>
            <h2>Prepare os arquivos no servidor</h2>
            <p>Execute somente o comando do seu sistema. O instalador prepara o servidor e libera este assistente.</p>
          </div>
          <div class="setup-platforms">
            <div class="command-panel">
              <span>Ubuntu ou Debian</span>
              <code>(arquivo=$(mktemp) &amp;&amp; trap 'rm -f "$arquivo"' EXIT &amp;&amp; wget -qO "$arquivo" https://github.com/matheusoliveirait/zabbix-monitor-tv/releases/latest/download/install.sh &amp;&amp; sudo bash "$arquivo")</code>
            </div>
            <div class="command-panel">
              <span>Windows PowerShell</span>
              <code>&amp; { $ErrorActionPreference = 'Stop'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; $arquivo = Join-Path $env:TEMP ("central-incidentes-" + [guid]::NewGuid().ToString("N") + ".ps1"); try { Invoke-WebRequest 'https://github.com/matheusoliveirait/zabbix-monitor-tv/releases/latest/download/install-windows.ps1' -UseBasicParsing -OutFile $arquivo; powershell -NoProfile -ExecutionPolicy Bypass -File $arquivo } finally { Remove-Item $arquivo -Force -ErrorAction SilentlyContinue } }</code>
            </div>
          </div>
          <div class="setup-install-actions">
            <div class="setup-action-block">
              <p class="field-help">Prefere revisar cada etapa? Consulte o processo detalhado no projeto.</p>
              <a class="button secondary" href="https://github.com/matheusoliveirait/zabbix-monitor-tv#instalacao-manual-assistida"
                target="_blank" rel="noopener">Ver instalação manual</a>
            </div>
            <div class="setup-action-block">
              <p class="field-help">Já executou o script? Recarregue usando o endereço mostrado no terminal.</p>
              <button class="button primary" type="button" data-reload>Verificar novamente</button>
            </div>
          </div>
        </section>

        <section class="setup-step" data-step="unlock" hidden>
          <div class="step-heading">
            <span class="step-number">Etapa 1 de 6</span>
            <h2>Confirme esta instalação</h2>
            <p>Digite o código temporário exibido no terminal. Ele identifica quem iniciou a preparação do servidor.</p>
          </div>
          <form id="unlockForm" class="setup-form narrow">
            <label for="setupToken">Código temporário</label>
            <input id="setupToken" name="token" class="setup-token" type="text" inputmode="text"
              maxlength="32" autocomplete="one-time-code" placeholder="ABCD-EFGH-IJKL-MNOP" required autofocus />
            <button class="button primary" type="submit">Validar código</button>
          </form>
        </section>

        <section class="setup-step" data-step="requirements" hidden>
          <div class="step-heading">
            <span class="step-number">Etapa 2 de 6</span>
            <h2>Validação do ambiente</h2>
            <p>O servidor precisa concluir todas as verificações para continuar.</p>
          </div>
          <div class="requirement-list" id="requirementList"></div>
          <div class="step-actions">
            <button class="button secondary" type="button" data-reload>Verificar novamente</button>
            <button class="button primary" id="requirementsContinue" type="button">Continuar</button>
          </div>
        </section>

        <section class="setup-step" data-step="database" hidden>
          <div class="step-heading">
            <span class="step-number">Etapa 3 de 6</span>
            <h2>Banco de dados</h2>
            <p>Use o banco local preparado pelo script ou conecte uma instância MySQL/MariaDB existente.</p>
          </div>

          <div class="segmented" role="group" aria-label="Origem do banco">
            <button type="button" data-db-mode="prepared" aria-pressed="true">Banco preparado</button>
            <button type="button" data-db-mode="custom" aria-pressed="false">Banco existente</button>
          </div>
          <p class="database-guidance" id="preparedDatabaseNotice" role="status" hidden></p>

          <form id="databaseForm" class="setup-form">
            <div id="preparedDatabase" class="prepared-database">
              <div><span>Servidor</span><strong data-prepared="host">127.0.0.1</strong></div>
              <div><span>Banco</span><strong data-prepared="database">central_incidentes</strong></div>
              <div><span>Usuário</span><strong data-prepared="username">central_incidentes</strong></div>
            </div>

            <div id="customDatabase" class="form-grid" hidden>
              <label class="span-2">Servidor
                <input name="host" type="text" value="127.0.0.1" maxlength="255" />
              </label>
              <label>Porta
                <input name="port" type="number" value="3306" min="1" max="65535" />
              </label>
              <label>Banco
                <input name="database" type="text" value="central_incidentes" maxlength="64" />
              </label>
              <label>Usuário
                <input name="username" type="text" maxlength="80" autocomplete="username" />
                <small>Usuário do MySQL/MariaDB com acesso ao banco. Não é o login do Zabbix nem do painel.</small>
              </label>
              <label>Senha
                <input name="password" type="password" autocomplete="current-password" />
                <small>Senha desse usuário do banco. Em um XAMPP novo, o usuário root geralmente começa sem senha.</small>
              </label>
            </div>

            <button class="button primary" type="submit">Testar e preparar tabelas</button>
          </form>
        </section>

        <section class="setup-step" data-step="admin" hidden>
          <div class="step-heading">
            <span class="step-number">Etapa 4 de 6</span>
            <h2>Administrador do painel</h2>
            <p>Crie a conta que poderá acessar o dashboard e alterar configurações.</p>
          </div>
          <form id="adminForm" class="setup-form">
            <label>Nome
              <input name="name" type="text" value="Administrador" minlength="2" maxlength="120" autocomplete="name" required />
            </label>
            <label>Usuário
              <input name="username" type="text" value="admin" minlength="3" maxlength="80" autocomplete="username" required />
            </label>
            <div class="form-grid">
              <label>Senha
                <input name="password" type="password" minlength="10" autocomplete="new-password" required />
              </label>
              <label>Confirmar senha
                <input name="passwordConfirmation" type="password" minlength="10" autocomplete="new-password" required />
              </label>
            </div>
            <p class="field-help">Use pelo menos 10 caracteres. A senha é armazenada somente como hash.</p>
            <button class="button primary" type="submit">Criar administrador</button>
          </form>
        </section>

        <section class="setup-step" data-step="zabbix" hidden>
          <div class="step-heading">
            <span class="step-number">Etapa 5 de 6</span>
            <h2>Conexão com o Zabbix</h2>
            <p>O teste confirma o endereço da API e as permissões do token antes de salvar.</p>
          </div>

          <form id="zabbixForm" class="setup-form">
            <div class="segmented url-mode" role="group" aria-label="Formato da URL">
              <button type="button" data-url-mode="quick" aria-pressed="true">IP ou DNS</button>
              <button type="button" data-url-mode="full" aria-pressed="false">URL completa</button>
            </div>

            <div id="quickUrlFields">
              <label>URL da API para conexão ao Zabbix</label>
              <div class="url-composer">
                <select id="zabbixProtocol" aria-label="Protocolo">
                  <option value="http">http://</option>
                  <option value="https">https://</option>
                </select>
                <input id="zabbixHost" type="text" placeholder="IP ou DNS do Zabbix" />
                <span>/zabbix/api_jsonrpc.php</span>
              </div>
            </div>

            <label id="fullUrlField" hidden>URL completa da API
              <input id="zabbixFullUrl" type="url" placeholder="https://zabbix.exemplo.com/api_jsonrpc.php" />
            </label>

            <label>Token da API
              <input name="token" type="password" maxlength="8192" autocomplete="off" required />
            </label>
            <p class="field-help">O token será criptografado antes de ser armazenado no banco.</p>

            <div class="step-actions">
              <button class="button secondary" id="skipZabbix" type="button">Configurar depois</button>
              <button class="button primary" type="submit">Testar conexão e salvar</button>
            </div>
          </form>
        </section>

        <section class="setup-step" data-step="finish" hidden>
          <div class="finish-mark" aria-hidden="true"><span></span></div>
          <div class="step-heading centered">
            <span class="step-number">Etapa 6 de 6</span>
            <h2>Pronto para monitorar</h2>
            <p>Ao concluir, o assistente será bloqueado e você será encaminhado para o login.</p>
          </div>
          <div class="finish-summary">
            <div><span>Banco de dados</span><strong>Configurado</strong></div>
            <div><span>Administrador</span><strong>Criado</strong></div>
            <div><span>Zabbix</span><strong id="zabbixSummary">Configurado</strong></div>
          </div>
          <button class="button primary wide" id="finishButton" type="button">Concluir instalação</button>
        </section>
      </div>

      <footer class="setup-footer">
        <span>Central de Incidentes</span>
        <a href="https://github.com/matheusoliveirait/zabbix-monitor-tv" target="_blank" rel="noopener noreferrer">Código-fonte no GitHub</a>
      </footer>
    </section>
  </main>

  <script src="setup.js?v=1"></script>
</body>
</html>
