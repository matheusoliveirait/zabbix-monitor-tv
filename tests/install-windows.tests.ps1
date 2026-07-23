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
    Assert-True ($setupDefinition -match "'database_notice' =>") "motivo do banco manual salvo"

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

    $appConfig = Join-Path $installDirectory "config\app.php"
    $installLock = Join-Path $installDirectory "config\installed.lock"
    $obsoleteFile = Join-Path $installDirectory "obsolete.txt"
    [IO.File]::WriteAllText($appConfig, "<?php return ['marker' => 'preserved'];")
    [IO.File]::WriteAllText($installLock, "installed")
    [IO.File]::WriteAllText($obsoleteFile, "remove-on-update")
    Remove-Item -LiteralPath (Join-Path $installDirectory "config\setup.php") -Force

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $installer `
        -ApacheRoot $apacheRoot `
        -InstallDir $installDirectory `
        -Source $repositoryRoot `
        -Port $configuredPort `
        -ServerName "invalid/name" `
        -Replace `
        -TestMode 2>$null
    Assert-True ($LASTEXITCODE -ne 0) "falha durante substituicao deveria restaurar a instalacao"
    Assert-True ((Get-Content -LiteralPath $appConfig -Raw) -match "preserved") "rollback preservou app.php"
    Assert-True (Test-Path -LiteralPath $installLock) "rollback preservou installed.lock"

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $installer `
        -ApacheRoot $apacheRoot `
        -InstallDir $installDirectory `
        -Source $repositoryRoot `
        -Port $configuredPort `
        -ServerName "localhost" `
        -Update `
        -TestMode
    Assert-True ($LASTEXITCODE -eq 0) "atualizacao simulada deveria concluir"
    Assert-True ((Get-Content -LiteralPath $appConfig -Raw) -match "preserved") "update preservou app.php"
    Assert-True (Test-Path -LiteralPath $installLock) "update preservou installed.lock"
    Assert-True (-not (Test-Path -LiteralPath $obsoleteFile)) "update removeu arquivo obsoleto"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $installDirectory "config\setup.php"))) "update nao reabriu wizard"

    & powershell.exe `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $installer `
        -ApacheRoot $apacheRoot `
        -InstallDir $installDirectory `
        -Source $repositoryRoot `
        -Port $configuredPort `
        -ServerName "localhost" `
        -Replace `
        -TestMode
    Assert-True ($LASTEXITCODE -eq 0) "reinstalacao explicita deveria concluir"
    Assert-True (-not (Test-Path -LiteralPath $appConfig)) "replace removeu configuracao anterior"
    Assert-True (-not (Test-Path -LiteralPath $installLock)) "replace removeu lock anterior"
    Assert-True (Test-Path -LiteralPath (Join-Path $installDirectory "config\setup.php")) "replace criou novo wizard"

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

exit 0
