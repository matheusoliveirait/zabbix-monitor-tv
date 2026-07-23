#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$ApacheRoot = $env:CENTRAL_INCIDENTES_APACHE_ROOT,
    [string]$PhpPath = $env:CENTRAL_INCIDENTES_PHP,
    [string]$InstallDir = $env:CENTRAL_INCIDENTES_DIR,
    [ValidateRange(0, 65535)]
    [int]$Port = 0,
    [string]$ServerName = "",
    [string]$Version = "latest",
    [string]$Source,
    [switch]$NonInteractive,
    [switch]$NoLocalDb,
    [switch]$NoBrowser,
    [switch]$SkipApacheRestart,
    [switch]$CheckOnly,
    [switch]$OpenFirewall,
    [string]$DatabaseName = "central_incidentes",
    [string]$DatabaseUser = "central_incidentes",
    [switch]$TestMode
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$script:Repository = "matheusoliveirait/zabbix-monitor-tv"
$script:TemporaryDirectory = $null
$script:CreatedInstallDirectory = $false
$script:ApacheConfigBackup = $null
$script:ApacheConfigPath = $null
$script:ResolvedApacheRoot = $null

function Write-Info([string]$Message) {
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Success([string]$Message) {
    Write-Host $Message -ForegroundColor Green
}

function Write-WarningMessage([string]$Message) {
    Write-Host "Aviso: $Message" -ForegroundColor Yellow
}

function Stop-Installer([string]$Message) {
    throw $Message
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-NormalizedPath([string]$Path) {
    return [IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($Path.Replace("/", "\"))
    ).TrimEnd("\")
}

function Resolve-ApacheInstallation([string]$RequestedRoot) {
    $candidates = New-Object Collections.Generic.List[string]

    if ($RequestedRoot) {
        $candidates.Add($RequestedRoot)
    }

    try {
        Get-Process -Name httpd -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Path) {
                $candidates.Add((Split-Path -Parent (Split-Path -Parent $_.Path)))
            }
        }
    } catch {
        # Process paths can require elevation. Common locations are checked below.
    }

    foreach ($drive in Get-PSDrive -PSProvider FileSystem) {
        $candidates.Add((Join-Path $drive.Root "xampp\apache"))
    }

    if ($env:XAMPP_HOME) {
        $candidates.Add((Join-Path $env:XAMPP_HOME "apache"))
    }

    try {
        $command = Get-Command httpd.exe -ErrorAction SilentlyContinue
        if ($command -and $command.Source) {
            $candidates.Add((Split-Path -Parent (Split-Path -Parent $command.Source)))
        }
    } catch {
        # PATH discovery is optional.
    }

    $valid = @(
        $candidates |
            Where-Object { $_ } |
            ForEach-Object {
                try { ConvertTo-NormalizedPath $_ } catch { $null }
            } |
            Where-Object {
                $_ -and
                (Test-Path -LiteralPath (Join-Path $_ "bin\httpd.exe")) -and
                (Test-Path -LiteralPath (Join-Path $_ "conf\httpd.conf"))
            } |
            Select-Object -Unique
    )

    if ($valid.Count -eq 0) {
        Stop-Installer "Apache nao encontrado. Informe a pasta com -ApacheRoot, por exemplo C:\xampp\apache."
    }

    if ($valid.Count -eq 1 -or $NonInteractive -or $RequestedRoot) {
        return $valid[0]
    }

    Write-Host ""
    Write-Host "Instalacoes do Apache encontradas:"
    for ($index = 0; $index -lt $valid.Count; $index++) {
        Write-Host "  [$($index + 1)] $($valid[$index])"
    }

    $selection = Read-Host "Escolha o Apache [1]"
    if (-not $selection) {
        $selection = "1"
    }
    $selectedIndex = 0
    if (-not [int]::TryParse($selection, [ref]$selectedIndex) -or
        $selectedIndex -lt 1 -or $selectedIndex -gt $valid.Count) {
        Stop-Installer "Selecao de Apache invalida."
    }

    return $valid[$selectedIndex - 1]
}

function Read-ApacheConfiguration([string]$Root) {
    $configPath = Join-Path $Root "conf\httpd.conf"
    $content = [IO.File]::ReadAllText($configPath)

    $srvRoot = $Root
    $srvMatch = [regex]::Match(
        $content,
        '(?im)^\s*Define\s+SRVROOT\s+"?([^"\r\n]+)"?\s*$'
    )
    if ($srvMatch.Success) {
        $srvRoot = ConvertTo-NormalizedPath $srvMatch.Groups[1].Value
    }

    $documentMatch = [regex]::Match(
        $content,
        '(?im)^\s*DocumentRoot\s+"?([^"\r\n]+)"?\s*$'
    )
    if (-not $documentMatch.Success) {
        Stop-Installer "DocumentRoot nao encontrado em $configPath."
    }

    $documentRoot = $documentMatch.Groups[1].Value
    $documentRoot = $documentRoot.Replace('${SRVROOT}', $srvRoot)
    $documentRoot = ConvertTo-NormalizedPath $documentRoot

    $listenPorts = @(
        [regex]::Matches($content, '(?im)^\s*Listen\s+(?:[^:\s]+:|\[[^\]]+\]:)?(\d+)\s*$') |
            ForEach-Object { [int]$_.Groups[1].Value } |
            Where-Object { $_ -ne 443 } |
            Select-Object -Unique
    )

    return @{
        Path = $configPath
        Content = $content
        DocumentRoot = $documentRoot
        ListenPorts = $listenPorts
    }
}

function Get-ListeningPort([int]$RequestedPort) {
    try {
        $connection = Get-NetTCPConnection -State Listen -LocalPort $RequestedPort -ErrorAction Stop |
            Select-Object -First 1
        if ($connection) {
            $processName = "processo desconhecido"
            try {
                $processName = (Get-Process -Id $connection.OwningProcess -ErrorAction Stop).ProcessName
            } catch {
                # The owning process can be protected.
            }
            return @{
                InUse = $true
                ProcessId = [int]$connection.OwningProcess
                ProcessName = $processName
            }
        }
    } catch {
        $listeners = [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().
            GetActiveTcpListeners()
        if ($listeners | Where-Object { $_.Port -eq $RequestedPort } | Select-Object -First 1) {
            return @{
                InUse = $true
                ProcessId = 0
                ProcessName = "processo desconhecido"
            }
        }
    }

    return @{
        InUse = $false
        ProcessId = 0
        ProcessName = ""
    }
}

function Get-ApacheProcessIds([string]$HttpdPath) {
    $expected = ConvertTo-NormalizedPath $HttpdPath
    $ids = New-Object Collections.Generic.List[int]

    Get-Process -Name httpd -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if ($_.Path -and (ConvertTo-NormalizedPath $_.Path) -eq $expected) {
                $ids.Add([int]$_.Id)
            }
        } catch {
            # A process with an inaccessible path is not assumed to be this Apache.
        }
    }

    return @($ids)
}

function Select-HttpPort(
    [int]$RequestedPort,
    [int[]]$ConfiguredPorts,
    [int[]]$ApacheProcessIds
) {
    if ($RequestedPort -eq 443) {
        Stop-Installer "A porta 443 exige configuracao HTTPS. Escolha uma porta HTTP."
    }

    $candidates = if ($RequestedPort -gt 0) {
        @($RequestedPort)
    } else {
        @($ConfiguredPorts + @(80, 8080, 8081, 8888) | Select-Object -Unique)
    }

    foreach ($candidate in $candidates) {
        if ($candidate -eq 443) {
            continue
        }

        $listener = Get-ListeningPort $candidate
        if (-not $listener.InUse) {
            return @{
                Port = $candidate
                AlreadyServedByApache = $false
            }
        }

        if ($listener.ProcessId -and $ApacheProcessIds -contains $listener.ProcessId) {
            return @{
                Port = $candidate
                AlreadyServedByApache = $true
            }
        }

        if ($ApacheProcessIds.Count -eq 0 -and
            $listener.ProcessName -match '^(httpd|apache)') {
            return @{
                Port = $candidate
                AlreadyServedByApache = $true
            }
        }

        if ($RequestedPort -gt 0) {
            Stop-Installer "A porta $candidate esta em uso por $($listener.ProcessName). Escolha outra porta."
        }
    }

    Stop-Installer "As portas 80, 8080, 8081 e 8888 estao ocupadas. Informe outra com -Port."
}

function Add-ApacheListenPort(
    [hashtable]$ApacheConfiguration,
    [int]$SelectedPort
) {
    if ($ApacheConfiguration.ListenPorts -contains $SelectedPort) {
        return $false
    }

    $script:ApacheConfigPath = $ApacheConfiguration.Path
    $script:ApacheConfigBackup = "$($ApacheConfiguration.Path).central-incidentes.$(
        Get-Date -Format 'yyyyMMddHHmmss'
    ).bak"
    Copy-Item -LiteralPath $ApacheConfiguration.Path -Destination $script:ApacheConfigBackup

    $newline = if ($ApacheConfiguration.Content.Contains("`r`n")) { "`r`n" } else { "`n" }
    $addition = "$newline# Central de Incidentes - instalador$newline" +
        "Listen $SelectedPort$newline"
    [IO.File]::WriteAllText(
        $ApacheConfiguration.Path,
        $ApacheConfiguration.Content.TrimEnd() + $addition,
        (New-Object Text.UTF8Encoding($false))
    )

    return $true
}

function Test-ApacheConfiguration([string]$Root) {
    if ($TestMode) {
        return
    }

    $httpd = Join-Path $Root "bin\httpd.exe"
    $config = Join-Path $Root "conf\httpd.conf"
    & $httpd -t -f $config
    if ($LASTEXITCODE -ne 0) {
        Stop-Installer "O Apache rejeitou a configuracao. Nenhum reinicio foi realizado."
    }
}

function Restart-Apache([string]$Root, [bool]$ConfigurationChanged) {
    if ($TestMode -or $SkipApacheRestart) {
        if ($ConfigurationChanged) {
            Write-WarningMessage "Reinicie o Apache para ativar a nova porta."
        }
        return
    }

    $httpd = Join-Path $Root "bin\httpd.exe"
    $apacheProcesses = @(Get-Process -Name httpd -ErrorAction SilentlyContinue)

    if ($apacheProcesses.Count -gt 0 -and -not $ConfigurationChanged) {
        return
    }

    if ($apacheProcesses.Count -gt 0) {
        & $httpd -k restart
        if ($LASTEXITCODE -eq 0) {
            return
        }

        $xamppRoot = Split-Path -Parent $Root
        $stopBatch = Join-Path $xamppRoot "apache_stop.bat"
        $startBatch = Join-Path $xamppRoot "apache_start.bat"
        if ((Test-Path -LiteralPath $stopBatch) -and
            (Test-Path -LiteralPath $startBatch)) {
            & cmd.exe /c "`"$stopBatch`""
            Start-Sleep -Seconds 1
            Start-Process -FilePath "cmd.exe" `
                -ArgumentList "/c", "`"$startBatch`"" `
                -WindowStyle Hidden
            Start-Sleep -Seconds 2
            return
        }

        Stop-Installer "Nao foi possivel reiniciar o Apache. Execute o script como administrador."
    }

    $xamppRoot = Split-Path -Parent $Root
    $startBatch = Join-Path $xamppRoot "apache_start.bat"
    if (Test-Path -LiteralPath $startBatch) {
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$startBatch`"" -WindowStyle Hidden
        Start-Sleep -Seconds 2
        return
    }

    & $httpd -k start
    if ($LASTEXITCODE -ne 0) {
        Stop-Installer "Nao foi possivel iniciar o Apache. Execute o script como administrador."
    }
}

function Resolve-PhpExecutable([string]$ResolvedApacheRoot, [string]$RequestedPath) {
    $xamppRoot = Split-Path -Parent $ResolvedApacheRoot
    $candidates = @(
        $RequestedPath,
        (Join-Path $xamppRoot "php\php.exe"),
        (Join-Path $ResolvedApacheRoot "php\php.exe")
    )

    try {
        $command = Get-Command php.exe -ErrorAction SilentlyContinue
        if ($command -and $command.Source) {
            $candidates += $command.Source
        }
    } catch {
        # PATH discovery is optional.
    }

    $php = $candidates |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
        Select-Object -First 1

    if (-not $php) {
        Stop-Installer "PHP nao encontrado. Informe o executavel com -PhpPath."
    }
    return ConvertTo-NormalizedPath $php
}

function Test-PhpEnvironment([string]$Executable) {
    if ($TestMode) {
        return
    }

    $probe = @'
$required = ['pdo', 'pdo_mysql', 'curl', 'openssl', 'mbstring'];
$missing = array_values(array_filter($required, static fn(string $name): bool => !extension_loaded($name)));
echo json_encode(['version' => PHP_VERSION_ID, 'missing' => $missing]);
'@
    $raw = & $Executable -r $probe
    if ($LASTEXITCODE -ne 0) {
        Stop-Installer "Nao foi possivel executar o PHP em $Executable."
    }

    try {
        $result = $raw | ConvertFrom-Json
    } catch {
        Stop-Installer "O PHP retornou uma resposta inesperada durante a validacao."
    }

    if ([int]$result.version -lt 80100) {
        Stop-Installer "PHP 8.1 ou superior e obrigatorio."
    }
    if (@($result.missing).Count -gt 0) {
        Stop-Installer "Extensoes PHP ausentes: $(@($result.missing) -join ', ')."
    }
}

function Get-PreferredServerName {
    if ($ServerName) {
        return $ServerName
    }

    try {
        $address = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object {
                $_.IPAddress -ne "127.0.0.1" -and
                $_.AddressState -eq "Preferred" -and
                $_.PrefixOrigin -ne "WellKnown"
            } |
            Sort-Object InterfaceMetric |
            Select-Object -First 1 -ExpandProperty IPAddress
        if ($address) {
            return $address
        }
    } catch {
        # localhost is a safe fallback.
    }

    return "localhost"
}

function Test-SetupEndpoint([string]$Url) {
    if ($TestMode -or $SkipApacheRestart) {
        return
    }

    for ($attempt = 0; $attempt -lt 10; $attempt++) {
        try {
            $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3
            if ($response.StatusCode -eq 200 -and
                $response.Content -notmatch '<\?php' -and
                $response.Content -match 'Central de Incidentes') {
                return
            }
        } catch {
            Start-Sleep -Milliseconds 500
            continue
        }
        Start-Sleep -Milliseconds 500
    }

    Stop-Installer "O Apache iniciou, mas o wizard nao respondeu corretamente em $Url."
}

function Set-PanelFirewallRule([int]$SelectedPort) {
    if ($TestMode) {
        return
    }

    if (-not $OpenFirewall) {
        Write-WarningMessage "Para acesso pela rede, confirme se a porta $SelectedPort esta liberada no Firewall do Windows."
        return
    }

    if (-not (Test-IsAdministrator)) {
        Write-WarningMessage "Execute como administrador para criar a regra de firewall da porta $SelectedPort."
        return
    }

    $displayName = "Central de Incidentes (TCP $SelectedPort)"
    $existing = Get-NetFirewallRule -DisplayName $displayName -ErrorAction SilentlyContinue
    if (-not $existing) {
        New-NetFirewallRule `
            -DisplayName $displayName `
            -Direction Inbound `
            -Action Allow `
            -Protocol TCP `
            -LocalPort $SelectedPort | Out-Null
    }
}

function New-TemporaryDirectory {
    $path = Join-Path ([IO.Path]::GetTempPath()) (
        "central-incidentes-" + [Guid]::NewGuid().ToString("N")
    )
    New-Item -ItemType Directory -Path $path | Out-Null
    $script:TemporaryDirectory = $path
    return $path
}

function Copy-ProjectFiles([string]$From, [string]$Destination) {
    $excluded = @(".git", "work", "outputs", "backups")
    New-Item -ItemType Directory -Path $Destination | Out-Null
    $script:CreatedInstallDirectory = $true

    Get-ChildItem -LiteralPath $From -Force | Where-Object {
        $excluded -notcontains $_.Name
    } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }

    foreach ($localConfig in @(
        "config\app.php",
        "config\setup.php",
        "config\installed.lock"
    )) {
        $path = Join-Path $Destination $localConfig
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
    }
}

function Get-ProjectSource([string]$RequestedSource, [string]$RequestedVersion) {
    if ($RequestedSource) {
        $resolved = ConvertTo-NormalizedPath $RequestedSource
        if (-not (Test-Path -LiteralPath (Join-Path $resolved "index.php")) -or
            -not (Test-Path -LiteralPath (Join-Path $resolved "setup\index.php"))) {
            Stop-Installer "A pasta informada em -Source nao contem o projeto completo."
        }
        return $resolved
    }

    $temporary = New-TemporaryDirectory
    $baseUrl = if ($RequestedVersion -eq "latest") {
        "https://github.com/$($script:Repository)/releases/latest/download"
    } else {
        "https://github.com/$($script:Repository)/releases/download/$RequestedVersion"
    }

    $archive = Join-Path $temporary "central-incidentes.zip"
    $checksum = Join-Path $temporary "central-incidentes.zip.sha256"

    Write-Info "Baixando a versao $RequestedVersion pelo GitHub Releases..."
    Invoke-WebRequest -Uri "$baseUrl/central-incidentes.zip" -OutFile $archive -UseBasicParsing
    Invoke-WebRequest -Uri "$baseUrl/central-incidentes.zip.sha256" -OutFile $checksum -UseBasicParsing

    $expected = ([IO.File]::ReadAllText($checksum).Trim() -split '\s+')[0].ToLowerInvariant()
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash.ToLowerInvariant()
    if ($expected -ne $actual) {
        Stop-Installer "O pacote baixado nao passou na verificacao SHA-256."
    }

    $expanded = Join-Path $temporary "app"
    Expand-Archive -LiteralPath $archive -DestinationPath $expanded
    return $expanded
}

function Find-MySqlClient([string]$ResolvedApacheRoot) {
    $xamppRoot = Split-Path -Parent $ResolvedApacheRoot
    $candidates = @(
        (Join-Path $xamppRoot "mysql\bin\mysql.exe"),
        "C:\xampp\mysql\bin\mysql.exe"
    )

    try {
        $command = Get-Command mysql.exe -ErrorAction SilentlyContinue
        if ($command -and $command.Source) {
            $candidates += $command.Source
        }
    } catch {
        # PATH discovery is optional.
    }

    return $candidates |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
        Select-Object -First 1
}

function Test-TcpPort([string]$HostName, [int]$TcpPort) {
    $client = New-Object Net.Sockets.TcpClient
    try {
        $result = $client.BeginConnect($HostName, $TcpPort, $null, $null)
        if (-not $result.AsyncWaitHandle.WaitOne(1000)) {
            return $false
        }
        $client.EndConnect($result)
        return $true
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Start-XamppMySql([string]$ResolvedApacheRoot) {
    $xamppRoot = Split-Path -Parent $ResolvedApacheRoot
    $startBatch = Join-Path $xamppRoot "mysql_start.bat"
    if (-not (Test-Path -LiteralPath $startBatch)) {
        return $false
    }

    Write-Info "Iniciando o MySQL do XAMPP..."
    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", "`"$startBatch`"" -WindowStyle Hidden
    for ($attempt = 0; $attempt -lt 15; $attempt++) {
        Start-Sleep -Milliseconds 500
        if (Test-TcpPort "127.0.0.1" 3306) {
            return $true
        }
    }
    return $false
}

function Invoke-MySql(
    [string]$Executable,
    [string]$Sql,
    [Security.SecureString]$RootPassword
) {
    $plainPassword = ""
    if ($RootPassword) {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($RootPassword)
        try {
            $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        }
    }

    $previousPassword = $env:MYSQL_PWD
    try {
        if ($plainPassword) {
            $env:MYSQL_PWD = $plainPassword
        } else {
            Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
        }

        $output = & $Executable `
            --protocol=tcp `
            --host=127.0.0.1 `
            --port=3306 `
            --user=root `
            --batch `
            --skip-column-names `
            --execute=$Sql 2>&1
        return @{
            Ok = $LASTEXITCODE -eq 0
            Output = ($output -join [Environment]::NewLine)
        }
    } finally {
        if ($null -eq $previousPassword) {
            Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
        } else {
            $env:MYSQL_PWD = $previousPassword
        }
        $plainPassword = $null
    }
}

function New-RandomHex([int]$ByteCount) {
    $bytes = New-Object byte[] $ByteCount
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
    } finally {
        $generator.Dispose()
    }
    return ([BitConverter]::ToString($bytes)).Replace("-", "").ToLowerInvariant()
}

function Prepare-LocalDatabase([string]$ResolvedApacheRoot) {
    if ($NoLocalDb -or $TestMode) {
        return $null
    }

    if ($DatabaseName -notmatch '^[A-Za-z0-9_]+$' -or
        $DatabaseUser -notmatch '^[A-Za-z0-9_]+$') {
        Stop-Installer "Nome de banco e usuario devem conter apenas letras, numeros e sublinhado."
    }

    $mysql = Find-MySqlClient $ResolvedApacheRoot
    if (-not $mysql) {
        Write-WarningMessage "Cliente MySQL nao encontrado. O banco sera informado no wizard."
        return $null
    }

    if (-not (Test-TcpPort "127.0.0.1" 3306)) {
        if (-not (Start-XamppMySql $ResolvedApacheRoot)) {
            Write-WarningMessage "MySQL nao esta acessivel. O banco sera informado no wizard."
            return $null
        }
    }

    $rootPassword = $null
    $probe = Invoke-MySql $mysql "SELECT 1;" $null
    if (-not $probe.Ok -and -not $NonInteractive) {
        $rootPassword = Read-Host "Senha do usuario root do MySQL (nao sera armazenada)" -AsSecureString
        $probe = Invoke-MySql $mysql "SELECT 1;" $rootPassword
    }

    if (-not $probe.Ok) {
        Write-WarningMessage "Nao foi possivel preparar o banco como root. Use o modo personalizado no wizard."
        return $null
    }

    $existingSql = @"
SELECT CONCAT(
    (SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$DatabaseName'),
    ':',
    (SELECT COUNT(*) FROM mysql.user WHERE User = '$DatabaseUser' AND Host IN ('localhost', '127.0.0.1'))
);
"@
    $existing = Invoke-MySql $mysql $existingSql $rootPassword
    if (-not $existing.Ok -or $existing.Output.Trim() -ne "0:0") {
        Write-WarningMessage "O banco ou usuario solicitado ja existe. Nada foi alterado; informe as credenciais no wizard."
        return $null
    }

    $databasePassword = New-RandomHex 24
    $sql = @"
CREATE DATABASE ``$DatabaseName`` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '$DatabaseUser'@'localhost' IDENTIFIED BY '$databasePassword';
CREATE USER '$DatabaseUser'@'127.0.0.1' IDENTIFIED BY '$databasePassword';
GRANT ALL PRIVILEGES ON ``$DatabaseName``.* TO '$DatabaseUser'@'localhost';
GRANT ALL PRIVILEGES ON ``$DatabaseName``.* TO '$DatabaseUser'@'127.0.0.1';
FLUSH PRIVILEGES;
"@
    $created = Invoke-MySql $mysql $sql $rootPassword
    if (-not $created.Ok) {
        Write-WarningMessage "O banco automatico falhou. Use o modo personalizado no wizard."
        return $null
    }

    return @{
        host = "127.0.0.1"
        port = 3306
        database = $DatabaseName
        username = $DatabaseUser
        password = $databasePassword
        charset = "utf8mb4"
    }
}

function ConvertTo-PhpString([string]$Value) {
    return "'" + $Value.Replace("\", "\\").Replace("'", "\'") + "'"
}

function Write-SetupDefinition(
    [string]$Destination,
    [hashtable]$PreparedDatabase,
    [string]$RequestedVersion
) {
    $tokenRaw = (New-RandomHex 4).ToUpperInvariant()
    $token = $tokenRaw.Substring(0, 4) + "-" + $tokenRaw.Substring(4, 4)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $tokenHash = ([BitConverter]::ToString(
            $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($token))
        )).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }

    $expires = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 7200
    $lines = New-Object Collections.Generic.List[string]
    $lines.Add("<?php")
    $lines.Add("")
    $lines.Add("declare(strict_types=1);")
    $lines.Add("")
    $lines.Add("return [")
    $lines.Add("    'token_hash' => $(ConvertTo-PhpString $tokenHash),")
    $lines.Add("    'expires_at' => $expires,")
    $lines.Add("    'version' => $(ConvertTo-PhpString $RequestedVersion),")
    if ($PreparedDatabase) {
        $lines.Add("    'prepared_db' => [")
        foreach ($key in @("host", "port", "database", "username", "password", "charset")) {
            $value = $PreparedDatabase[$key]
            if ($value -is [int]) {
                $lines.Add("        '$key' => $value,")
            } else {
                $lines.Add("        '$key' => $(ConvertTo-PhpString ([string]$value)),")
            }
        }
        $lines.Add("    ],")
    }
    $lines.Add("];")
    $lines.Add("")

    $configDirectory = Join-Path $Destination "config"
    if (-not (Test-Path -LiteralPath $configDirectory)) {
        New-Item -ItemType Directory -Path $configDirectory | Out-Null
    }
    [IO.File]::WriteAllLines(
        (Join-Path $configDirectory "setup.php"),
        $lines,
        (New-Object Text.UTF8Encoding($false))
    )

    return $token
}

function Restore-InstallerChanges {
    if ($script:ApacheConfigBackup -and
        $script:ApacheConfigPath -and
        (Test-Path -LiteralPath $script:ApacheConfigBackup)) {
        Copy-Item -LiteralPath $script:ApacheConfigBackup `
            -Destination $script:ApacheConfigPath -Force
        if ($script:ResolvedApacheRoot -and -not $TestMode -and -not $SkipApacheRestart) {
            try {
                $httpd = Join-Path $script:ResolvedApacheRoot "bin\httpd.exe"
                & $httpd -k restart 2>$null
            } catch {
                Write-WarningMessage "Reinicie o Apache para concluir a restauracao do httpd.conf."
            }
        }
    }

    if ($script:CreatedInstallDirectory -and
        $InstallDir -and
        (Test-Path -LiteralPath $InstallDir)) {
        $resolved = ConvertTo-NormalizedPath $InstallDir
        if ($resolved.Length -gt 3) {
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}

function Remove-InstallerTemporaryFiles {
    if ($script:TemporaryDirectory -and
        (Test-Path -LiteralPath $script:TemporaryDirectory)) {
        Remove-Item -LiteralPath $script:TemporaryDirectory -Recurse -Force
    }
}

function Invoke-Installer {
    if (-not (Test-IsAdministrator) -and -not $TestMode) {
        Write-WarningMessage "O PowerShell nao esta como administrador. Algumas instalacoes do Apache podem exigir elevacao."
    }

    if ($TestMode) {
        $script:NonInteractive = $true
        $script:NoLocalDb = $true
        $script:NoBrowser = $true
        $script:SkipApacheRestart = $true
        if (-not $Source) {
            Stop-Installer "O modo de teste exige -Source."
        }
    }

    Write-Info "Localizando o Apache..."
    $resolvedApacheRoot = Resolve-ApacheInstallation $ApacheRoot
    $script:ResolvedApacheRoot = $resolvedApacheRoot
    $httpdPath = Join-Path $resolvedApacheRoot "bin\httpd.exe"
    $apacheConfiguration = Read-ApacheConfiguration $resolvedApacheRoot
    $resolvedPhp = Resolve-PhpExecutable $resolvedApacheRoot $PhpPath
    Test-PhpEnvironment $resolvedPhp

    $apacheProcessIds = Get-ApacheProcessIds $httpdPath
    $portSelection = Select-HttpPort $Port $apacheConfiguration.ListenPorts $apacheProcessIds
    $selectedPort = [int]$portSelection.Port
    Write-Info "Porta HTTP selecionada: $selectedPort"

    if ($CheckOnly) {
        Test-ApacheConfiguration $resolvedApacheRoot
        $mysql = Find-MySqlClient $resolvedApacheRoot
        Write-Host ""
        Write-Success "Ambiente Windows compativel."
        Write-Host ""
        Write-Host "  Apache:       $resolvedApacheRoot"
        Write-Host "  DocumentRoot: $($apacheConfiguration.DocumentRoot)"
        Write-Host "  PHP:          $resolvedPhp"
        Write-Host "  Porta:        $selectedPort"
        Write-Host "  MySQL:        $(if ($mysql) { $mysql } else { 'nao encontrado' })"
        return
    }

    if (-not $InstallDir) {
        $script:InstallDir = Join-Path $apacheConfiguration.DocumentRoot "central-incidentes"
    } else {
        $script:InstallDir = ConvertTo-NormalizedPath $InstallDir
    }

    $documentRootPrefix = $apacheConfiguration.DocumentRoot.TrimEnd("\") + "\"
    if (-not $InstallDir.StartsWith(
        $documentRootPrefix,
        [StringComparison]::OrdinalIgnoreCase
    )) {
        Stop-Installer "A pasta de instalacao precisa estar dentro de $($apacheConfiguration.DocumentRoot)."
    }
    if ($InstallDir -eq $apacheConfiguration.DocumentRoot) {
        Stop-Installer "Use uma subpasta do DocumentRoot para nao substituir o site principal."
    }
    if (Test-Path -LiteralPath (Join-Path $InstallDir "config\app.php")) {
        Stop-Installer "Ja existe uma instalacao em $InstallDir. Este instalador inicial nao realiza atualizacoes."
    }
    if (Test-Path -LiteralPath $InstallDir) {
        $existing = @(Get-ChildItem -LiteralPath $InstallDir -Force)
        if ($existing.Count -gt 0) {
            Stop-Installer "A pasta $InstallDir nao esta vazia."
        }
        Remove-Item -LiteralPath $InstallDir -Force
    }

    $projectSource = Get-ProjectSource $Source $Version
    $sourcePrefix = $projectSource.TrimEnd("\") + "\"
    if ($InstallDir.Equals($projectSource, [StringComparison]::OrdinalIgnoreCase) -or
        $InstallDir.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        Stop-Installer "A pasta de destino nao pode ser igual ou interna a pasta de origem."
    }
    Write-Info "Copiando arquivos para $InstallDir..."
    Copy-ProjectFiles $projectSource $InstallDir

    $configurationChanged = Add-ApacheListenPort $apacheConfiguration $selectedPort
    Test-ApacheConfiguration $resolvedApacheRoot
    Restart-Apache $resolvedApacheRoot $configurationChanged

    $relativePath = $InstallDir.Substring($apacheConfiguration.DocumentRoot.Length).
        TrimStart("\").Replace("\", "/")
    $urlPath = if ($relativePath) { "/$relativePath/setup/" } else { "/setup/" }
    $resolvedServerName = Get-PreferredServerName
    if ($resolvedServerName -notmatch '^[A-Za-z0-9.\-\[\]:]+$') {
        Stop-Installer "Nome ou IP do servidor invalido: $resolvedServerName."
    }
    $authority = if ($selectedPort -eq 80) {
        $resolvedServerName
    } else {
        "$resolvedServerName`:$selectedPort"
    }
    $setupUrl = "http://$authority$urlPath"
    $localAuthority = if ($selectedPort -eq 80) {
        "127.0.0.1"
    } else {
        "127.0.0.1`:$selectedPort"
    }
    Test-SetupEndpoint "http://$localAuthority$urlPath"

    $preparedDatabase = Prepare-LocalDatabase $resolvedApacheRoot
    $setupToken = Write-SetupDefinition $InstallDir $preparedDatabase $Version
    Set-PanelFirewallRule $selectedPort

    Write-Host ""
    Write-Success "Servidor preparado com sucesso."
    Write-Host ""
    Write-Host "  Acesse:  $setupUrl"
    Write-Host "  Codigo:  $setupToken"
    Write-Host ""
    Write-Host "O codigo expira em 2 horas e sera removido ao concluir o wizard."

    if (-not $NoBrowser -and -not $TestMode) {
        try {
            Start-Process $setupUrl
        } catch {
            Write-WarningMessage "Abra manualmente o endereco exibido acima."
        }
    }

    return @{
        Url = $setupUrl
        Token = $setupToken
        InstallDir = $InstallDir
        Port = $selectedPort
        ApacheRoot = $resolvedApacheRoot
        ApacheConfigurationChanged = $configurationChanged
    }
}

try {
    Invoke-Installer | Out-Null
} catch {
    Write-Host ""
    Write-Host "Erro: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Revertendo os arquivos criados por esta execucao..." -ForegroundColor Yellow
    Restore-InstallerChanges
    exit 1
} finally {
    Remove-InstallerTemporaryFiles
}
