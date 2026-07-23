#requires -Version 5.1

$ErrorActionPreference = "Stop"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw "Falha: $Message"
    }
}

function Get-FreePort {
    $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try {
        return ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    } finally {
        $listener.Stop()
    }
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $repositoryRoot "install-windows.ps1"
$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) (
    "central-incidentes-windows-test-" + [Guid]::NewGuid().ToString("N")
)

try {
    $xamppRoot = Join-Path $temporaryRoot "xampp"
    $apacheRoot = Join-Path $xamppRoot "apache"
    $documentRoot = Join-Path $xamppRoot "htdocs"
    $installDirectory = Join-Path $documentRoot "central-incidentes"

    New-Item -ItemType Directory -Path (Join-Path $apacheRoot "bin") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $apacheRoot "conf") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $xamppRoot "php") -Force | Out-Null
    New-Item -ItemType Directory -Path $documentRoot -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $apacheRoot "bin\httpd.exe") | Out-Null
    New-Item -ItemType File -Path (Join-Path $xamppRoot "php\php.exe") | Out-Null

    $configuredPort = Get-FreePort
    $apacheConfig = @"
Define SRVROOT "$($apacheRoot.Replace('\', '/'))"
Listen $configuredPort
DocumentRoot "$($documentRoot.Replace('\', '/'))"
<Directory "$($documentRoot.Replace('\', '/'))">
    AllowOverride All
    Require all granted
</Directory>
"@
    [IO.File]::WriteAllText(
        (Join-Path $apacheRoot "conf\httpd.conf"),
        $apacheConfig,
        (New-Object Text.UTF8Encoding($false))
    )

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $installer `
        -ApacheRoot $apacheRoot `
        -InstallDir $installDirectory `
        -Source $repositoryRoot `
        -ServerName "localhost" `
        -TestMode
    Assert-True ($LASTEXITCODE -eq 0) "instalacao simulada deveria concluir"

    Assert-True (Test-Path (Join-Path $installDirectory "index.php")) "index.php copiado"
    Assert-True (Test-Path (Join-Path $installDirectory "setup\index.php")) "wizard copiado"
    Assert-True (Test-Path (Join-Path $installDirectory "config\setup.php")) "codigo temporario criado"
    Assert-True (-not (Test-Path (Join-Path $installDirectory ".git"))) "metadados Git excluidos"

    $setupDefinition = [IO.File]::ReadAllText(
        (Join-Path $installDirectory "config\setup.php")
    )
    Assert-True ($setupDefinition -match "'token_hash' => '[a-f0-9]{64}'") "hash do codigo salvo"
    Assert-True ($setupDefinition -match "'expires_at' => \d{10}") "expiracao salva"

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $installer `
        -ApacheRoot $apacheRoot `
        -InstallDir $installDirectory `
        -Source $repositoryRoot `
        -Port $configuredPort `
        -TestMode 2>$null
    Assert-True ($LASTEXITCODE -ne 0) "reinstalacao sobre pasta preenchida deveria falhar"
    Assert-True (Test-Path (Join-Path $installDirectory "index.php")) "falha nao remove instalacao existente"

    $occupiedListener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    $occupiedListener.Start()
    try {
        $occupiedPort = ([Net.IPEndPoint]$occupiedListener.LocalEndpoint).Port
        $conflictDirectory = Join-Path $documentRoot "port-conflict"

        & powershell.exe `
            -NoProfile `
            -ExecutionPolicy Bypass `
            -File $installer `
            -ApacheRoot $apacheRoot `
            -InstallDir $conflictDirectory `
            -Source $repositoryRoot `
            -Port $occupiedPort `
            -TestMode 2>$null
        Assert-True ($LASTEXITCODE -ne 0) "porta ocupada deveria ser recusada"
        Assert-True (-not (Test-Path $conflictDirectory)) "conflito nao deveria copiar arquivos"
    } finally {
        $occupiedListener.Stop()
    }

    Write-Host "Windows installer tests: OK" -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
