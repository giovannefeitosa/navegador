param(
    [string]$SkillSourcePath,
    [string]$SkillUrl = "https://raw.githubusercontent.com/giovannefeitosa/navegador/main/skills/navegador/SKILL.md",
    [string]$IconSourcePath,
    [string]$IconUrl = "https://raw.githubusercontent.com/giovannefeitosa/navegador/main/navegador-logo.ico"
)

$ErrorActionPreference = "Stop"

$beginMarker = "# >>> navegador >>>"
$endMarker = "# <<< navegador <<<"

function Refresh-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $joined = @($machinePath, $userPath) | Where-Object { $_ } | Select-Object -Unique
    if ($joined.Count -gt 0) {
        $env:Path = ($joined -join ";")
    }
}

function Find-Command {
    param(
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) {
            return $command
        }
    }

    return $null
}

function Ensure-Winget {
    $winget = Find-Command -Names @("winget.exe", "winget")
    if (-not $winget) {
        throw "winget nao esta disponivel nesta maquina. Instale manualmente o Node.js LTS e o Google Chrome, ou rode este instalador em uma maquina com winget disponivel."
    }

    return $winget
}

function Install-WingetPackage {
    param(
        [string]$Id
    )

    $null = Ensure-Winget
    & winget.exe install --id $Id --exact --accept-package-agreements --accept-source-agreements --silent
    Refresh-ProcessPath
}

function Get-RealChromePath {
    $chromePaths = @(
        "$env:PROGRAMFILES\Google\Chrome\Application\chrome.exe",
        "${env:PROGRAMFILES(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )

    return $chromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Read-Utf8TextFile {
    param(
        [string]$Path
    )

    $reader = New-Object System.IO.StreamReader(
        $Path,
        (New-Object System.Text.UTF8Encoding($false, $true)),
        $true
    )

    try {
        return $reader.ReadToEnd()
    } finally {
        $reader.Dispose()
    }
}

function Read-Utf8HttpResponse {
    param(
        $Response
    )

    $reader = New-Object System.IO.StreamReader(
        $Response.RawContentStream,
        (New-Object System.Text.UTF8Encoding($false, $true)),
        $true
    )

    try {
        return $reader.ReadToEnd()
    } finally {
        $reader.Dispose()
    }
}

function Write-Utf8TextFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    [System.IO.File]::WriteAllText(
        $Path,
        $Content,
        (New-Object System.Text.UTF8Encoding($false))
    )
}

function Resolve-SkillContent {
    param(
        [string]$RequestedPath,
        [string]$RequestedUrl
    )

    $localCandidates = @()
    if ($RequestedPath) {
        $localCandidates += $RequestedPath
    }

    foreach ($candidate in $localCandidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return (Read-Utf8TextFile -Path $candidate)
        }
    }

    $response = Invoke-WebRequest -Uri $RequestedUrl -UseBasicParsing
    $content = Read-Utf8HttpResponse -Response $response
    if ($response.StatusCode -ne 200 -or [string]::IsNullOrWhiteSpace($content)) {
        throw "Nao foi possivel obter o arquivo SKILL.md em $RequestedUrl."
    }

    return $content
}

function Install-IconFile {
    param(
        [string]$RequestedPath,
        [string]$RequestedUrl,
        [string]$DestinationPath
    )

    $localCandidates = @()
    if ($RequestedPath) {
        $localCandidates += $RequestedPath
    }

    $repoIconPath = Join-Path (Split-Path -Parent $PSScriptRoot) "navegador-logo.ico"
    if (Test-Path $repoIconPath) {
        $localCandidates += $repoIconPath
    }

    $destinationDir = Split-Path -Parent $DestinationPath
    if ($destinationDir -and -not (Test-Path $destinationDir)) {
        New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
    }

    foreach ($candidate in $localCandidates | Select-Object -Unique) {
        if ($candidate -and (Test-Path $candidate)) {
            Copy-Item -Path $candidate -Destination $DestinationPath -Force
            return $DestinationPath
        }
    }

    Invoke-WebRequest -Uri $RequestedUrl -OutFile $DestinationPath -UseBasicParsing
    if (-not (Test-Path $DestinationPath) -or (Get-Item $DestinationPath).Length -le 0) {
        throw "Nao foi possivel obter o icone do Navegador em $RequestedUrl."
    }

    return $DestinationPath
}

function Install-SkillIfBaseExists {
    param(
        [string]$BaseDir,
        [string]$SkillContent
    )

    if (-not (Test-Path $BaseDir)) {
        return $false
    }

    $skillDir = Join-Path $BaseDir "navegador"
    New-Item -ItemType Directory -Path $skillDir -Force | Out-Null
    Write-Utf8TextFile -Path (Join-Path $skillDir "SKILL.md") -Content $SkillContent
    return $true
}

function Stop-AgentBrowserDaemon {
    param(
        $Command
    )

    if (-not $Command) {
        return
    }

    try {
        & $Command.Source close 2>$null | Out-Null
    } catch {
    }
}

function Stop-AgentBrowserProcesses {
    $processes = @(Get-Process -Name "agent-browser-win32-x64" -ErrorAction SilentlyContinue)
    foreach ($process in $processes) {
        try {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
        } catch {
        }
    }
}

function Convert-WinPathToMnt {
    param(
        [string]$Path
    )

    $drive = $Path.Substring(0, 1).ToLower()
    $rest = $Path.Substring(2) -replace "\\", "/"
    return "/mnt/$drive$rest"
}

function Set-Shortcut {
    param(
        [string]$ShortcutPath,
        [string]$TargetPath,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [string]$IconLocation,
        [string]$Description
    )

    $shortcutDir = Split-Path -Parent $ShortcutPath
    if ($shortcutDir -and -not (Test-Path $shortcutDir)) {
        New-Item -ItemType Directory -Path $shortcutDir -Force | Out-Null
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $TargetPath
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $WorkingDirectory
    $shortcut.IconLocation = $IconLocation
    $shortcut.Description = $Description
    $shortcut.Save()
}

function Get-NavegadorShortcutArguments {
    param(
        [string]$ChromePath
    )

    $profilePath = Join-Path $env:USERPROFILE "Navegador"
    $arguments = @(
        '--user-data-dir'
        ('"{0}"' -f $profilePath)
        '--remote-debugging-port=0'
        '--no-first-run'
        '--no-default-browser-check'
        '--disable-blink-features=AutomationControlled'
        'about:blank'
    )

    return ($arguments -join ' ')
}

function Install-NavegadorShortcuts {
    param(
        [string]$AgentBrowserExe,
        [string]$ChromePath,
        [string]$IconSourcePath,
        [string]$IconUrl,
        $Report
    )

    $shortcutName = "Navegador.lnk"
    $desktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) $shortcutName
    $arguments = Get-NavegadorShortcutArguments -ChromePath $ChromePath
    $iconPath = Join-Path (Join-Path $env:USERPROFILE "Navegador") "navegador.ico"
    $iconLocation = Install-IconFile -RequestedPath $IconSourcePath -RequestedUrl $IconUrl -DestinationPath $iconPath
    $description = "Abre o Navegador com o perfil persistente do Windows."

    Set-Shortcut `
        -ShortcutPath $desktopShortcut `
        -TargetPath $ChromePath `
        -Arguments $arguments `
        -WorkingDirectory $env:USERPROFILE `
        -IconLocation $iconLocation `
        -Description $description

    if (Test-Path $desktopShortcut) {
        $Report.desktopShortcutPath = $desktopShortcut
        $Report.shortcutIconPath = $iconPath
    }
}

$report = [ordered]@{
    nodeVersion          = $null
    npmVersion           = $null
    agentBrowserVersion  = $null
    chromeUsed           = $null
    profilePath          = $PROFILE
    profileCreated       = $false
    executionPolicy      = $null
    desktopShortcutPath  = $null
    shortcutIconPath     = $null
    windowsSkillTargets  = @()
    wslSkillTargets      = @()
    wslDistros           = @()
    wslStatus            = $null
}

Write-Host "==> Verificando Node.js e npm"
Refresh-ProcessPath
$nodeCommand = Find-Command -Names @("node", "node.exe")
$npmCommand = Find-Command -Names @("npm", "npm.cmd", "npm.exe")

if (-not $nodeCommand -or -not $npmCommand) {
    Write-Host "Node.js/npm nao encontrados. Tentando instalar via winget..."
    Install-WingetPackage -Id "OpenJS.NodeJS.LTS"
    $nodeJsDir = Join-Path $env:ProgramFiles "nodejs"
    if ((Test-Path $nodeJsDir) -and $env:Path -notlike "*$nodeJsDir*") {
        $env:Path = "$nodeJsDir;$env:Path"
    }
    $nodeCommand = Find-Command -Names @("node", "node.exe")
    $npmCommand = Find-Command -Names @("npm", "npm.cmd", "npm.exe")
}

if (-not $nodeCommand -or -not $npmCommand) {
    throw "Nao foi possivel localizar Node.js/npm mesmo apos a tentativa de instalacao automatica."
}

$report.nodeVersion = (& $nodeCommand.Source --version).Trim()
$report.npmVersion = (& $npmCommand.Source --version).Trim()

Write-Host "==> Instalando/atualizando agent-browser"
if ($agentBrowserBefore = Find-Command -Names @("agent-browser", "agent-browser.cmd", "agent-browser.ps1")) {
    Stop-AgentBrowserDaemon -Command $agentBrowserBefore
}
Stop-AgentBrowserProcesses
& $npmCommand.Source install -g agent-browser
Refresh-ProcessPath
if ((Test-Path (Join-Path $env:APPDATA "npm")) -and $env:Path -notlike "*$env:APPDATA\npm*") {
    $env:Path = "$env:APPDATA\npm;$env:Path"
}

$agentBrowserCommand = Find-Command -Names @("agent-browser", "agent-browser.cmd", "agent-browser.ps1")
if (-not $agentBrowserCommand) {
    throw "O comando agent-browser nao ficou disponivel apos a instalacao."
}
$npmPrefix = (& $npmCommand.Source config get prefix).Trim()
$agentBrowserExe = Join-Path $npmPrefix "node_modules\agent-browser\bin\agent-browser-win32-x64.exe"
if (-not (Test-Path $agentBrowserExe)) {
    throw "Nao foi possivel localizar o executavel do agent-browser em $agentBrowserExe."
}

$report.agentBrowserVersion = (& $agentBrowserCommand.Source --version).Trim()

Write-Host "==> Verificando Google Chrome"
$chromeReal = Get-RealChromePath
if (-not $chromeReal) {
    try {
        Write-Host "Google Chrome nao encontrado. Tentando instalar via winget..."
        Install-WingetPackage -Id "Google.Chrome"
        $chromeReal = Get-RealChromePath
    } catch {
        Write-Warning "Falha ao instalar Google Chrome via winget: $($_.Exception.Message)"
    }
}

if ($chromeReal) {
    $report.chromeUsed = $chromeReal
} else {
    throw "Google Chrome real nao encontrado. Instale o Google Chrome e execute o instalador novamente."
}

Write-Host "==> Atualizando funcao navegador no PowerShell"
$profileDir = Split-Path -Parent $PROFILE
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
}
if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
    $report.profileCreated = $true
}

$policyBefore = Get-ExecutionPolicy -Scope CurrentUser
if ($policyBefore -in @("Restricted", "Undefined", "AllSigned")) {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
    $report.executionPolicy = "$policyBefore -> RemoteSigned"
} else {
    $report.executionPolicy = "$policyBefore -> $policyBefore"
}

$block = @"
$beginMarker
function navegador {
    param(
        [Parameter(ValueFromRemainingArguments = `$true)]
        [string[]] `$Argumentos
    )

    function ConvertTo-NavegadorCliArgument {
        param(
            [string]`$Value
        )

        if (`$null -eq `$Value) {
            return '""'
        }

        if (`$Value -match '[\s"]') {
            return '"' + (`$Value -replace '"', '\"') + '"'
        }

        return `$Value
    }

    `$chromePaths = @(
        "`$env:PROGRAMFILES\Google\Chrome\Application\chrome.exe",
        "`${env:PROGRAMFILES(x86)}\Google\Chrome\Application\chrome.exe",
        "`$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    )
    `$chromeExe = `$chromePaths | Where-Object { Test-Path `$_ } | Select-Object -First 1

    if (-not `$chromeExe) {
        throw "Chrome not found. Install Google Chrome or check its installation path."
    }

    `$agentBrowserExe = Join-Path "`$env:APPDATA" "npm\node_modules\agent-browser\bin\agent-browser-win32-x64.exe"
    if (-not (Test-Path `$agentBrowserExe)) {
        throw "agent-browser-win32-x64.exe not found. Reinstale o Navegador para restaurar a CLI."
    }

    if (`$Argumentos.Count -gt 0 -and `$Argumentos[0] -eq 'close') {
        & `$agentBrowserExe @Argumentos
        if (`$LASTEXITCODE -ne 0) {
            throw ("agent-browser falhou com codigo {0}." -f `$LASTEXITCODE)
        }
        return
    }

    `$profilePath = Join-Path "`$env:USERPROFILE" "Navegador"
    `$devToolsActivePortPath = Join-Path `$profilePath "DevToolsActivePort"

    if (-not (Test-Path `$profilePath)) {
        New-Item -ItemType Directory -Path `$profilePath -Force | Out-Null
    }

    function Test-NavegadorCdpPort {
        param(
            [string]`$Port
        )

        if ([string]::IsNullOrWhiteSpace(`$Port)) {
            return `$false
        }

        try {
            `$null = Invoke-WebRequest -Uri "http://127.0.0.1:`$Port/json/version" -UseBasicParsing -TimeoutSec 2
            return `$true
        } catch {
            return `$false
        }
    }

    function Get-NavegadorChromeProcess {
        Get-CimInstance Win32_Process -Filter "name = 'chrome.exe'" | Where-Object {
            `$_.CommandLine -and
            `$_.CommandLine -notlike '*--type=*' -and
            (
                `$_.CommandLine -like ('*user-data-dir=' + `$profilePath + '*') -or
                `$_.CommandLine -like ('*user-data-dir="' + `$profilePath + '"*')
            )
        } | Select-Object -First 1
    }

    function Start-NavegadorChrome {
        Remove-Item -LiteralPath `$devToolsActivePortPath -Force -ErrorAction SilentlyContinue

        `$chromeArgs = @(
            "--user-data-dir=`$profilePath",
            "--remote-debugging-port=0",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-blink-features=AutomationControlled"
        )

        Start-Process -FilePath `$chromeExe -ArgumentList `$chromeArgs -WindowStyle Normal | Out-Null
    }

    `$chromeProcess = Get-NavegadorChromeProcess
    if (-not `$chromeProcess) {
        Start-NavegadorChrome
    }

    `$cdpPort = `$null
    `$deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt `$deadline) {
        if (Test-Path `$devToolsActivePortPath) {
            `$cdpPort = (Get-Content -LiteralPath `$devToolsActivePortPath -ErrorAction SilentlyContinue | Select-Object -First 1)
            if (Test-NavegadorCdpPort -Port `$cdpPort) {
                break
            }
        }

        if (-not (Get-NavegadorChromeProcess)) {
            Start-NavegadorChrome
        }

        Start-Sleep -Milliseconds 200
    }

    if (-not (Test-NavegadorCdpPort -Port `$cdpPort)) {
        throw "Chrome do Navegador abriu, mas a porta CDP nao ficou disponivel."
    }

    if (`$Argumentos.Count -gt 0 -and `$Argumentos[0] -in @('open', 'goto', 'navigate')) {
        if (`$Argumentos.Count -gt 1) {
            Start-Process -FilePath `$chromeExe -ArgumentList @("--user-data-dir=`$profilePath", `$Argumentos[1]) -WindowStyle Normal | Out-Null
        }

        `$deadline = (Get-Date).AddSeconds(10)
        do {
            try {
                `$tabsResponse = Invoke-WebRequest -Uri "http://127.0.0.1:`$cdpPort/json/list" -UseBasicParsing -TimeoutSec 2
                `$tabs = `$tabsResponse.Content | ConvertFrom-Json
                `$currentUrl = `$tabs | Where-Object { `$_.type -eq 'page' -and `$_.url -and `$_.url -notlike 'chrome://*' } | Select-Object -First 1 -ExpandProperty url
                if (-not [string]::IsNullOrWhiteSpace(`$currentUrl)) {
                    [Console]::Out.Write((`$currentUrl | Out-String))
                    return
                }
            } catch {
            }

            Start-Sleep -Milliseconds 200
        } until ((Get-Date) -ge `$deadline)

        return
    }

    `$agentBrowserArgs = @(
        '--cdp'
        `$cdpPort
    ) + `$Argumentos

    & `$agentBrowserExe @agentBrowserArgs
    if (`$LASTEXITCODE -ne 0) {
        throw ("agent-browser falhou com codigo {0}." -f `$LASTEXITCODE)
    }
}
$endMarker
"@

$profileContent = if (Test-Path $PROFILE) { Get-Content -Path $PROFILE -Raw } else { "" }
if ($profileContent -match "(?ms)$([regex]::Escape($beginMarker)).*?$([regex]::Escape($endMarker))") {
    $escapedBlock = $block -replace "\$", '$$$$'
    $newContent = [regex]::Replace(
        $profileContent,
        "(?ms)$([regex]::Escape($beginMarker)).*?$([regex]::Escape($endMarker))",
        $escapedBlock
    )
    Set-Content -Path $PROFILE -Value $newContent -Encoding UTF8
} else {
    Add-Content -Path $PROFILE -Value "`r`n$block`r`n" -Encoding UTF8
}

Stop-AgentBrowserDaemon -Command $agentBrowserCommand
. $PROFILE

$navegadorCommand = Get-Command navegador -ErrorAction SilentlyContinue
if (-not $navegadorCommand) {
    throw "A funcao navegador nao ficou disponivel apos carregar o `$PROFILE."
}
if ($navegadorCommand.Definition -notmatch "--cdp" -or $navegadorCommand.Definition -notmatch "--remote-debugging-port=0") {
    throw "A definicao da funcao navegador nao contem as flags esperadas."
}

Write-Host "==> Registrando a skill globalmente no Windows"
$skillContent = Resolve-SkillContent -RequestedPath $SkillSourcePath -RequestedUrl $SkillUrl
$codexSkills = Join-Path $env:USERPROFILE ".codex\skills"
$claudeSkills = Join-Path $env:USERPROFILE ".claude\skills"
$hasWindowsClient = $false

if (Install-SkillIfBaseExists -BaseDir $codexSkills -SkillContent $skillContent) {
    $report.windowsSkillTargets += (Join-Path $codexSkills "navegador\SKILL.md")
    $hasWindowsClient = $true
}
if (Install-SkillIfBaseExists -BaseDir $claudeSkills -SkillContent $skillContent) {
    $report.windowsSkillTargets += (Join-Path $claudeSkills "navegador\SKILL.md")
    $hasWindowsClient = $true
}

if (-not $hasWindowsClient) {
    Write-Warning "Nenhum diretorio global de skills foi encontrado no Windows. Vou continuar e tentar registrar a skill nas distros WSL suportadas, se existirem."
}

Write-Host "==> Integrando com WSL2 (quando aplicavel)"
$wslDistrosOk = @()
$wslMotivoIgnorado = $null
$wslAvailable = $false
$wslWorkdir = $env:USERPROFILE
Push-Location $wslWorkdir
try {
    try {
        $null = wsl --status 2>$null
        if ($LASTEXITCODE -eq 0) {
            $wslAvailable = $true
        }
    } catch {
    }

    if (-not $wslAvailable) {
        $wslMotivoIgnorado = "WSL2 nao detectado neste computador."
    } else {
        $encBefore = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        try {
            $distros = (wsl -l -q) -split "`r?`n" |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -and $_ -notmatch "^\s*$" }
        } finally {
            [Console]::OutputEncoding = $encBefore
        }

        foreach ($distro in $distros) {
            $distroVersion = (wsl -d $distro -- sh -lc "lsb_release -rs 2>/dev/null" 2>$null) -as [string]
            $distroVersion = ($distroVersion -replace "\s", "")
            $distroId = (wsl -d $distro -- sh -lc "lsb_release -is 2>/dev/null" 2>$null) -as [string]
            $distroId = ($distroId -replace "\s", "")
            if ($distroId -ieq "Ubuntu" -and $distroVersion -match "^\d+(\.\d+)?$") {
                if ([int]([double]$distroVersion) -ge 24) {
                    $wslDistrosOk += $distro
                }
            }
        }

        if ($wslDistrosOk.Count -eq 0) {
            $wslMotivoIgnorado = "WSL2 detectado, mas nenhuma distro e Ubuntu 24+."
        }
    }

    if ($wslDistrosOk.Count -gt 0) {
        $agentBrowserExeLinux = Convert-WinPathToMnt -Path $agentBrowserExe
        $profileWin = Join-Path $env:USERPROFILE "Navegador"
        $chromeWin = if ($chromeReal) { $chromeReal } else { "" }
        $wslWrapper = @'
#!/usr/bin/env bash
set -euo pipefail

AGENT_BROWSER_EXE='__AGENT_BROWSER_EXE__'
PROFILE_WIN='__PROFILE_WIN__'
CHROME_WIN='__CHROME_WIN__'

if [ "${1:-}" = "close" ]; then
    "$AGENT_BROWSER_EXE" "$@"
    exit $?
fi

has_navegador_chrome() {
    powershell.exe -NoProfile -Command "\$profilePath = '$PROFILE_WIN'; [bool](Get-CimInstance Win32_Process -Filter \"name = 'chrome.exe'\" | Where-Object { \$_.CommandLine -and \$_.CommandLine -notlike '*--type=*' -and (\$_.CommandLine -like \"*user-data-dir=\$profilePath*\" -or \$_.CommandLine -like \"*user-data-dir=\`\"\$profilePath\`\"*\") } | Select-Object -First 1)" | tr -d '\r' | grep -qi '^true$'
}

if ! has_navegador_chrome; then
    if [ -n "$CHROME_WIN" ]; then
        powershell.exe -NoProfile -Command "Start-Process -FilePath '$CHROME_WIN' -ArgumentList @('--user-data-dir=$PROFILE_WIN','--remote-debugging-port=0','--no-first-run','--no-default-browser-check','--disable-blink-features=AutomationControlled') -WindowStyle Normal" >/dev/null
    else
        echo "Chrome real nao configurado para o Navegador." >&2
        exit 1
    fi
fi

CDP_PORT="$(powershell.exe -NoProfile -Command "\$deadline = (Get-Date).AddSeconds(15); \$path = Join-Path '$PROFILE_WIN' 'DevToolsActivePort'; do { if (Test-Path \$path) { \$port = Get-Content -LiteralPath \$path -ErrorAction SilentlyContinue | Select-Object -First 1; if (\$port) { try { Invoke-WebRequest -Uri \"http://127.0.0.1:\$port/json/version\" -UseBasicParsing -TimeoutSec 2 | Out-Null; Write-Output \$port; exit 0 } catch {} } }; Start-Sleep -Milliseconds 200 } until ((Get-Date) -ge \$deadline); exit 1" | tr -d '\r')"
if [ "${1:-}" = "open" ] || [ "${1:-}" = "goto" ] || [ "${1:-}" = "navigate" ]; then
    if [ -n "${2:-}" ]; then
        powershell.exe -NoProfile -Command "Start-Process -FilePath '$CHROME_WIN' -ArgumentList @('--user-data-dir=$PROFILE_WIN','$2') -WindowStyle Normal" >/dev/null
    fi
    powershell.exe -NoProfile -Command "\$port = '$CDP_PORT'; \$tabs = (Invoke-WebRequest -Uri \"http://127.0.0.1:\$port/json/list\" -UseBasicParsing).Content | ConvertFrom-Json; \$tabs | Where-Object { \$_.type -eq 'page' -and \$_.url -and \$_.url -notlike 'chrome://*' } | Select-Object -First 1 -ExpandProperty url" | tr -d '\r'
    exit 0
fi

"$AGENT_BROWSER_EXE" --cdp "$CDP_PORT" "$@"
'@
        $wslWrapper = $wslWrapper.Replace("__AGENT_BROWSER_EXE__", $agentBrowserExeLinux)
        $wslWrapper = $wslWrapper.Replace("__PROFILE_WIN__", $profileWin)
        $wslWrapper = $wslWrapper.Replace("__CHROME_WIN__", $chromeWin)
        $tmpSkillWin = Join-Path $env:TEMP "navegador-skill.md"
        Write-Utf8TextFile -Path $tmpSkillWin -Content ($skillContent -replace "`r`n", "`n")
        $tmpSkillLinux = Convert-WinPathToMnt -Path $tmpSkillWin

        $tmpWrapperWin = Join-Path $env:TEMP "navegador-wsl-wrapper.sh"
        Write-Utf8TextFile -Path $tmpWrapperWin -Content ($wslWrapper -replace "`r`n", "`n")

        $tmpWrapperLinux = Convert-WinPathToMnt -Path $tmpWrapperWin
        $installer = @'
#!/usr/bin/env bash
set -euo pipefail
BEGIN_MARK='# >>> navegador >>>'
END_MARK='# <<< navegador <<<'
LOCAL_BIN="$HOME/.local/bin"
TARGET="$LOCAL_BIN/navegador"
WRAPPER_SOURCE="__WRAPPER__"
SKILL_SOURCE="__SKILL__"
BASHRC="$HOME/.bashrc"

mkdir -p "$LOCAL_BIN"
cp "$WRAPPER_SOURCE" "$TARGET"
chmod 755 "$TARGET"

if [ -f "$BASHRC" ] && grep -qF "$BEGIN_MARK" "$BASHRC"; then
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
        index($0,b)==1 {skip=1; next}
        skip && index($0,e)==1 {skip=0; next}
        !skip {print}
    ' "$BASHRC" > "$BASHRC.tmp" && mv "$BASHRC.tmp" "$BASHRC"
fi

for base in "$HOME/.codex/skills" "$HOME/.claude/skills"; do
    if [ -d "$base" ]; then
        mkdir -p "$base/navegador"
        cp "$SKILL_SOURCE" "$base/navegador/SKILL.md"
    fi
done

'@
        $installer = $installer.Replace("__WRAPPER__", $tmpWrapperLinux)
        $installer = $installer.Replace("__SKILL__", $tmpSkillLinux)

        $tmpInstallerWin = Join-Path $env:TEMP "navegador-bashrc-install.sh"
        Write-Utf8TextFile -Path $tmpInstallerWin -Content ($installer -replace "`r`n", "`n")
        $tmpInstallerLinux = Convert-WinPathToMnt -Path $tmpInstallerWin

        try {
            foreach ($distro in $wslDistrosOk) {
                wsl -d $distro -- bash "$tmpInstallerLinux"
                if ($LASTEXITCODE -eq 0) {
                    $report.wslDistros += $distro
                    $skillTargets = (wsl -d $distro -- sh -lc 'for base in "$HOME/.codex/skills" "$HOME/.claude/skills"; do if [ -f "$base/navegador/SKILL.md" ]; then printf "%s\n" "$base/navegador/SKILL.md"; fi; done' 2>$null) -as [string]
                    if ($skillTargets) {
                        (($skillTargets -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ }) | ForEach-Object {
                            $report.wslSkillTargets += "${distro}:$_"
                        }
                    }
                }
            }
        } finally {
            Remove-Item -Path $tmpSkillWin, $tmpWrapperWin, $tmpInstallerWin -ErrorAction SilentlyContinue
        }

        foreach ($distro in $wslDistrosOk) {
            $commandOutput = (wsl -d $distro -- sh -lc "command -v navegador 2>/dev/null" 2>$null) -as [string]
            $commandOutput = ($commandOutput -replace "\s", "")
            if ([string]::IsNullOrWhiteSpace($commandOutput) -or $commandOutput -notmatch "/navegador$") {
                Write-Warning "navegador nao ficou disponivel na distro '$distro'."
            }
        }

        $report.wslStatus = "Integrado em: $($report.wslDistros -join ', ')"
    } else {
        $report.wslStatus = $wslMotivoIgnorado
    }
} finally {
    Pop-Location
}

if ($report.windowsSkillTargets.Count -eq 0 -and $report.wslSkillTargets.Count -eq 0) {
    Write-Warning "Nenhum diretorio global de skills do Codex ou Claude Code foi encontrado no Windows ou nas distros WSL integradas."
}

Write-Host "==> Criando atalho na area de trabalho do Windows"
Install-NavegadorShortcuts -AgentBrowserExe $agentBrowserExe -ChromePath $chromeReal -IconSourcePath $IconSourcePath -IconUrl $IconUrl -Report $report

Write-Host ""
Write-Host "=== Relatorio de instalacao - skill navegador ==="
Write-Host "Node.js: $($report.nodeVersion)"
Write-Host "npm: $($report.npmVersion)"
Write-Host "agent-browser: $($report.agentBrowserVersion)"
Write-Host "Chrome usado: $($report.chromeUsed)"
Write-Host "PROFILE: $($report.profilePath)"
Write-Host "PROFILE criado agora: $($report.profileCreated)"
Write-Host "ExecutionPolicy: $($report.executionPolicy)"
Write-Host "Atalho na area de trabalho: $(if ($report.desktopShortcutPath) { $report.desktopShortcutPath } else { 'nao criado' })"
Write-Host "Icone do atalho: $(if ($report.shortcutIconPath) { $report.shortcutIconPath } else { 'nao instalado' })"
if ($report.windowsSkillTargets.Count -gt 0) {
    Write-Host "Skills registradas no Windows:"
    $report.windowsSkillTargets | ForEach-Object { Write-Host " - $_" }
} else {
    Write-Host "Skills registradas no Windows: nenhuma"
}
if ($report.wslSkillTargets.Count -gt 0) {
    Write-Host "Skills registradas no WSL:"
    $report.wslSkillTargets | ForEach-Object { Write-Host " - $_" }
} else {
    Write-Host "Skills registradas no WSL: nenhuma"
}
Write-Host "WSL2: $($report.wslStatus)"
Write-Host ""
Write-Host "Reinicie completamente o Codex e/ou Claude Code para carregar a skill global."
