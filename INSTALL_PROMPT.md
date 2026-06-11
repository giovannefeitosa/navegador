Configure a skill Navegador neste computador.

O unico caminho suportado de instalacao e pelo PowerShell do Windows. Se houver WSL2 Ubuntu 24+, a mesma instalacao deve deixar o comando e a skill funcionando la tambem, sem exigir um segundo instalador em bash.

## Guardrails

- Se o PowerShell não estiver disponível, pare e avise que este prompt só pode rodar em Claude Code ou OpenAI Codex com acesso ao terminal.
- Se não for possível instalar algum software necessário, pare e avise o usuário.
- Se algo der errado, remova os artefatos próprios do Navegador que este prompt criou: arquivos adicionados e alterações feitas em arquivos existentes. Não desinstale Node.js nem Google Chrome automaticamente, pois podem ser dependências compartilhadas.
- Não esconda erros. Se a instalação não puder terminar e o usuário puder resolver o problema, peça a correção. Se o usuário não quiser corrigir, execute a limpeza.
- Ao final, mostre um relatório curto com o que foi instalado, removido, criado, alterado e o status final.
- Se você não conseguir executar comandos no PowerShell do Windows, não continue. Avise que a skill precisa ser instalada no Windows, não apenas dentro do WSL.
- Você tem permissão para usar o PowerShell para instalar os softwares descritos aqui.

## Reinicialização do ambiente

Depois de instalar softwares ou alterar variáveis de ambiente, a sessão atual pode não enxergar os comandos novos. Tente recarregar o `$PROFILE` do Windows. Se isso não bastar, peça ao usuário para reiniciar o terminal ou o computador, explicar o motivo e voltar nesta conversa com "continuar".

Se o comando continuar indisponível após a reinicialização, confira se ele está no local esperado. Se ainda assim não funcionar, pare e explique que a reinicialização não resolveu.

Ao pedir reinicialização, diga que o usuário pode pedir para abortar e desinstalar tudo a qualquer momento.

## 1. Verificar requisitos

Verifique se Node.js e npm estão disponíveis no PowerShell.

Se `npm --version` ou `npm.exe --version` não funcionarem, tente instalar Node.js LTS via `winget`:

```powershell
winget install --id OpenJS.NodeJS.LTS --exact --accept-package-agreements --accept-source-agreements --silent
```

Depois atualize o `PATH` da sessão atual e tente novamente. O instalador do Node.js via `winget` pode gravar o `PATH` no Windows, mas a sessão PowerShell aberta antes da instalação normalmente não recebe essa alteração automaticamente.

```powershell
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
$env:Path = (@($machinePath, $userPath) | Where-Object { $_ }) -join ";"

$nodeJsDir = Join-Path $env:ProgramFiles "nodejs"
if ((Test-Path $nodeJsDir) -and $env:Path -notlike "*$nodeJsDir*") {
    $env:Path = "$nodeJsDir;$env:Path"
}
```

Só peça para reiniciar o terminal se `node` ou `npm` continuarem indisponíveis depois dessa atualização explícita do `PATH`.

## 2. Instalar agent-browser e Chrome

Instale o `agent-browser` pelo npm do Windows:

```powershell
$agentBrowserExistente = Get-Command agent-browser,agent-browser.cmd,agent-browser.ps1 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($agentBrowserExistente) {
    & $agentBrowserExistente.Source close 2>$null | Out-Null
}
npm install -g agent-browser
```

Verifique se o Google Chrome real já está instalado. O Navegador não usa navegador alternativo: se o Chrome real não estiver disponível e não puder ser instalado, pare com erro.

```powershell
$chromePaths = @(
    "$env:PROGRAMFILES\Google\Chrome\Application\chrome.exe",
    "${env:PROGRAMFILES(x86)}\Google\Chrome\Application\chrome.exe",
    "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
)
$chromeReal = $chromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($chromeReal) {
    Write-Host "Chrome real encontrado: $chromeReal — login no Google e outros sites funcionará normalmente."
} else {
    Write-Host "Chrome real não encontrado. Tentando instalar Google Chrome via winget..."
    winget install --id Google.Chrome --exact --accept-package-agreements --accept-source-agreements --silent
    $chromeReal = $chromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $chromeReal) {
        throw "Nao foi possivel instalar o Chrome real automaticamente. Instale o Google Chrome e execute a instalacao novamente."
    }
}
```

Nao use `agent-browser install` para baixar Chrome for Testing. O comportamento correto e falhar e pedir a instalacao do Google Chrome real.

## 3. Criar a função navegador no PowerShell

Adicione a função `navegador` ao `$PROFILE` do PowerShell. Ela sempre reutiliza o perfil `%USERPROFILE%\Navegador`.

### 3.1 Garantir que o `$PROFILE` existe

Em máquinas novas, o arquivo `$PROFILE` pode não existir e a `ExecutionPolicy` do `CurrentUser` pode bloquear o carregamento do perfil.

Rode:

```powershell
if (-not (Test-Path $PROFILE)) {
    New-Item -ItemType File -Path $PROFILE -Force | Out-Null
}
$policy = Get-ExecutionPolicy -Scope CurrentUser
if ($policy -in @('Restricted', 'Undefined', 'AllSigned')) {
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
}
```

### 3.2 Inserir ou substituir o bloco da função

O bloco usa os marcadores `# >>> navegador >>>` e `# <<< navegador <<<`. Se o bloco já existir, substitua. Se não existir, adicione ao final. Isso mantém a instalação idempotente e facilita rollback.

Importante: a função `navegador` deve reutilizar o Chrome do Navegador quando ele já estiver aberto. Se estiver fechado, abra o Google Chrome real com `%USERPROFILE%\Navegador`, `--remote-debugging-port=0` e `--disable-blink-features=AutomationControlled`, detecte a porta CDP e chame o `agent-browser` com essa porta. Ela não deve abrir outro navegador ou outra janela alternativa quando `open`, `goto` ou `navigate` falharem ou demorarem demais; se o comando não responder em tempo razoável, interrompa o processo e falhe explicitamente.

```powershell
$beginMarker = '# >>> navegador >>>'
$endMarker   = '# <<< navegador <<<'
$bloco = @"
$beginMarker
function navegador {
    param(
        [Parameter(ValueFromRemainingArguments = `$true)]
        [string[]] `$Argumentos
    )

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

    `$chromeProcess = Get-CimInstance Win32_Process -Filter "name = 'chrome.exe'" | Where-Object {
        `$_.CommandLine -and
        `$_.CommandLine -notlike '*--type=*' -and
        (`$_.CommandLine -like ('*user-data-dir=' + `$profilePath + '*') -or `$_.CommandLine -like ('*user-data-dir="' + `$profilePath + '"*'))
    } | Select-Object -First 1

    if (-not `$chromeProcess) {
        Remove-Item -LiteralPath `$devToolsActivePortPath -Force -ErrorAction SilentlyContinue
        Start-Process -FilePath `$chromeExe -ArgumentList @(
            "--user-data-dir=`$profilePath",
            "--remote-debugging-port=0",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-blink-features=AutomationControlled"
        ) -WindowStyle Normal | Out-Null
    }

    `$deadline = (Get-Date).AddSeconds(15)
    do {
        `$cdpPort = if (Test-Path `$devToolsActivePortPath) {
            Get-Content -LiteralPath `$devToolsActivePortPath -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        `$cdpReady = `$false
        if (-not [string]::IsNullOrWhiteSpace(`$cdpPort)) {
            try {
                `$null = Invoke-WebRequest -Uri "http://127.0.0.1:`$cdpPort/json/version" -UseBasicParsing -TimeoutSec 2
                `$cdpReady = `$true
            } catch {
            }
        }
        if (-not `$cdpReady) {
            Start-Sleep -Milliseconds 200
        }
    } until (`$cdpReady -or (Get-Date) -ge `$deadline)

    if (-not `$cdpReady) {
        throw "Chrome do Navegador abriu, mas a porta CDP nao ficou disponivel."
    }

    & `$agentBrowserExe --cdp `$cdpPort @Argumentos
    if (`$LASTEXITCODE -ne 0) {
        throw ("agent-browser falhou com codigo {0}." -f `$LASTEXITCODE)
    }
}
$endMarker
"@

$profileContent = if (Test-Path $PROFILE) { Get-Content $PROFILE -Raw } else { '' }
if ($profileContent -match "(?ms)$([regex]::Escape($beginMarker)).*?$([regex]::Escape($endMarker))") {
    # Escapa os '$' do bloco para que [regex]::Replace nao os interprete como backreferences (ex: ${env:...})
    $blocoEscapado = $bloco -replace '\$', '$$$$'
    $novoConteudo = [regex]::Replace(
        $profileContent,
        "(?ms)$([regex]::Escape($beginMarker)).*?$([regex]::Escape($endMarker))",
        $blocoEscapado
    )
    Set-Content -Path $PROFILE -Value $novoConteudo -Encoding UTF8
} else {
    Add-Content -Path $PROFILE -Value "`r`n$bloco`r`n" -Encoding UTF8
}
```

Se existir uma instalação antiga que chame `agent-browser --profile "$env:USERPROFILE\Navegador" --headed ...`, trate como desatualizada: substitua o bloco, feche o daemon e recarregue o `$PROFILE`.

### 3.3 Fechar o daemon e carregar a função

O `agent-browser` usa daemon. Depois de iniciado, ele pode reutilizar a configuração da sessão anterior. Em upgrades, feche o daemon para reiniciar com as novas opções:

```powershell
agent-browser close 2>$null
```

Depois carregue o `$PROFILE` atualizado na sessão atual:

```powershell
. $PROFILE
if (-not (Get-Command navegador -ErrorAction SilentlyContinue)) {
    throw "A funcao navegador nao ficou disponivel apos carregar o `$PROFILE. Verifique a ExecutionPolicy e se ha outra funcao/alias com o mesmo nome."
}
```

Para validar a versão carregada:

```powershell
(Get-Command navegador).Definition
```

A definição deve conter `--cdp` e `--remote-debugging-port=0`.

Depois disso, este comando:

```powershell
navegador open myapp.com
```

equivale a algo como:

```powershell
agent-browser --cdp <porta-detectada> open myapp.com
```

A flag `--disable-blink-features=AutomationControlled` oculta o marcador `navigator.webdriver`, usado por alguns sites para detectar automação.

## 4. Testar o navegador

Rode no PowerShell. Se houver integração com WSL2, rode também dentro de cada distro Ubuntu 24+ para confirmar o executável instalado em `~/.local/bin`.

- `navegador open https://example.com`: abre o Chrome e navega até a página.
- `navegador wait body`: espera o seletor `body` aparecer no DOM.
- `navegador get title`: deve devolver o `<title>` da página.
- `navegador close`: fecha o navegador.

Teste obrigatório de login no Google:

```powershell
navegador open https://accounts.google.com
```

O Google não deve exibir aviso de "navegador inseguro" ou "acesso bloqueado". Se exibir, o daemon ainda pode estar usando a configuração antiga ou o `$PROFILE` atualizado pode não ter sido recarregado. Rode `agent-browser close`, recarregue com `. $PROFILE`, confirme `(Get-Command navegador).Definition` e teste novamente.

Evite `wait 5000` como prova de carregamento. Prefira esperar por um seletor ou estado observável, como `body`, `h1` ou outro seletor específico da página.

## 5. Registrar a skill globalmente

Não use git, GitHub CLI nem peça conta do GitHub ao usuário.

Baixe o arquivo `SKILL.md` diretamente da URL raw:

```text
https://raw.githubusercontent.com/giovannefeitosa/navegador/main/skills/navegador/SKILL.md
```

### 5.1 Verificar Codex e Claude Code

No PowerShell, rode:

```powershell
$codexSkills = Join-Path $env:USERPROFILE ".codex\skills"
$claudeSkills = Join-Path $env:USERPROFILE ".claude\skills"
$hasCodex = Test-Path $codexSkills
$hasClaude = Test-Path $claudeSkills
[pscustomobject]@{
    CodexSkillsPath  = $codexSkills
    CodexInstalado   = $hasCodex
    ClaudeSkillsPath = $claudeSkills
    ClaudeInstalado  = $hasClaude
}
```

Se `CodexInstalado` e `ClaudeInstalado` forem ambos `False`, pare e explique que o computador precisa ter Codex ou Claude Code instalado antes de registrar a skill globalmente.

Se ambos forem `False`, nao pare ainda. O cliente pode estar rodando apenas dentro do WSL, e a verificacao/registro dos diretorios Linux deve acontecer mais adiante pelo proprio PowerShell via `wsl`.

### 5.2 Baixar a skill

No PowerShell, rode:

```powershell
$skillUrl = "https://raw.githubusercontent.com/giovannefeitosa/navegador/main/skills/navegador/SKILL.md"
try {
    $response = Invoke-WebRequest -Uri $skillUrl -UseBasicParsing
}
catch {
    throw "Nao foi possivel baixar o arquivo da skill em $skillUrl. Verifique sua internet e se o repositorio ja esta publicado."
}
if ($response.StatusCode -ne 200) {
    throw "Download da skill falhou com status HTTP $($response.StatusCode)."
}
$skillContent = $response.Content
if ([string]::IsNullOrWhiteSpace($skillContent)) {
    throw "O arquivo SKILL.md veio vazio."
}
if ($skillContent -notmatch "(?m)^name:" -or $skillContent -notmatch "(?m)^description:") {
    throw "O arquivo baixado nao parece ser uma skill valida."
}
```

Se o download falhar, pare e explique que a skill não pôde ser baixada.

### 5.3 Gravar a skill

Como a skill tem apenas um arquivo, crie a pasta `navegador` dentro dos diretórios globais existentes e salve `SKILL.md` nela.

No PowerShell, rode:

```powershell
$codexSkills = Join-Path $env:USERPROFILE ".codex\skills"
$claudeSkills = Join-Path $env:USERPROFILE ".claude\skills"
$hasCodex = Test-Path $codexSkills
$hasClaude = Test-Path $claudeSkills
if ($hasCodex) {
    $codexSkillDir = Join-Path $codexSkills "navegador"
    New-Item -ItemType Directory -Path $codexSkillDir -Force | Out-Null
    Set-Content -Path (Join-Path $codexSkillDir "SKILL.md") -Value $skillContent -Encoding UTF8
}
if ($hasClaude) {
    $claudeSkillDir = Join-Path $claudeSkills "navegador"
    New-Item -ItemType Directory -Path $claudeSkillDir -Force | Out-Null
    Set-Content -Path (Join-Path $claudeSkillDir "SKILL.md") -Value $skillContent -Encoding UTF8
}
```

Nao rode um segundo instalador em bash. Se houver clientes Unix/WSL, a mesma sessao PowerShell deve registrar a skill neles durante a etapa de integracao com WSL.

### 5.4 Verificar registro global

No PowerShell, rode:

```powershell
Get-Content "$env:USERPROFILE\.codex\skills\navegador\SKILL.md" -ErrorAction SilentlyContinue | Select-Object -First 5
Get-Content "$env:USERPROFILE\.claude\skills\navegador\SKILL.md" -ErrorAction SilentlyContinue | Select-Object -First 5
```

Se apenas um cliente estiver instalado no Windows, e normal que o outro comando nao retorne nada.

## 6. Integrar com WSL2, se existir

Se o computador tiver WSL2 com pelo menos uma distro Ubuntu 24+, a mesma instalacao PowerShell deve:

- instalar um executavel `navegador` em `~/.local/bin` de cada distro suportada;
- registrar `SKILL.md` em `~/.codex/skills/navegador` e `~/.claude/skills/navegador` quando esses diretorios existirem;
- abrir o Google Chrome real com o perfil `%USERPROFILE%\Navegador`, quando ele ainda não estiver aberto, detectar a porta CDP e então chamar diretamente o executavel Windows do `agent-browser` com `--cdp`.

Se não houver WSL2, ou se nenhuma distro for Ubuntu 24+, ignore este passo e registre o motivo no relatório final. Nunca interrompa a instalação por causa do WSL2.

Notas importantes:

- O nome de usuário do WSL costuma ser diferente do nome do Windows. Isso não impede a instalação, porque o wrapper é gravado no `$HOME` da própria distro.
- Evite chamar `powershell.exe` para executar `navegador` dentro do WSL. Na prática isso pode concluir a automação e ainda deixar o processo Unix pendurado.
- O wrapper do WSL deve chamar diretamente `agent-browser-win32-x64.exe --cdp <porta-detectada>`. Quando o Chrome do Navegador estiver fechado, o wrapper deve abrir antes o Google Chrome real do Windows com `%USERPROFILE%\Navegador`, `--remote-debugging-port=0` e `--disable-blink-features=AutomationControlled`.
- Prefira um executável em `~/.local/bin` em vez de uma função no `.bashrc`. Assim o comando funciona em shells não interativos e evita a necessidade de `bash -ic`, que pode deixar processos pendurados em agentes que rodam sem TTY.
- Se o PowerShell estiver rodando a partir de `\\wsl.localhost\...`, mude antes para um diretório do Windows com `Push-Location $env:USERPROFILE`. Sem isso, o `wsl.exe` pode falhar ao tentar traduzir o diretório atual.
- Quoting entre PowerShell e bash é frágil para here-docs, regex e caminhos Windows. Por isso este passo grava arquivos temporários em `$env:TEMP`, converte o caminho para `/mnt/c/...` e chama `wsl`.
- Verifique o comando com `bash -lc 'command -v navegador'`. Não use `bash -ic`, porque o objetivo desta etapa e justamente evitar depender de shell interativo.
- O instalador remove blocos antigos entre `# >>> navegador >>>` e `# <<< navegador <<<` no `.bashrc`, caso uma versao anterior tenha instalado a funcao por la.

### 6.1 Detectar WSL2

```powershell
$wslDistrosOk = @()       # distros Ubuntu 24+ encontradas
$wslMotivoIgnorado = $null
$wslDisponivel = $false
$wslWorkdir = $env:USERPROFILE
Push-Location $wslWorkdir
try {
    $null = wsl --status 2>$null
    if ($LASTEXITCODE -eq 0) { $wslDisponivel = $true }
}
catch { }
if (-not $wslDisponivel) {
    $wslMotivoIgnorado = "WSL2 nao detectado neste computador."
}
```

### 6.2 Filtrar distros Ubuntu 24+

`wsl -l -q` emite saída em UTF-16. Ajuste a codificação antes de capturar a lista.

```powershell
if ($wslDisponivel) {
    $encAntes = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
    try {
        $distros = (wsl -l -q) -split "`r?`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and $_ -notmatch '^\s*$' }
    } finally {
        [Console]::OutputEncoding = $encAntes
    }

    foreach ($distro in $distros) {
        $ver = (wsl -d $distro -- sh -lc "lsb_release -rs 2>/dev/null" 2>$null) -as [string]
        $ver = ($ver -replace '\s', '')
        $distroId = (wsl -d $distro -- sh -lc "lsb_release -is 2>/dev/null" 2>$null) -as [string]
        $distroId = ($distroId -replace '\s', '')
        if ($distroId -ieq 'Ubuntu' -and $ver -match '^\d+(\.\d+)?$') {
            if ([int]([double]$ver) -ge 24) {
                $wslDistrosOk += $distro
            }
        }
    }

    if ($wslDistrosOk.Count -eq 0) {
        $wslMotivoIgnorado = "WSL2 detectado, mas nenhuma distro e Ubuntu 24+. Integracao com wrapper Unix ignorada."
    }
}
```

### 6.3 Instalar o executavel em `~/.local/bin`

O arquivo `~/.local/bin/navegador` deixa o comando disponivel tambem em shells nao interativos. O instalador tambem remove o bloco antigo do `.bashrc`, se existir, para evitar conflitos com instalacoes anteriores.

```powershell
if ($wslDistrosOk.Count -gt 0) {
    # Conversao manual do caminho Windows para /mnt/<letra>/...
    # Evita wslpath, que ja deu problemas com caminhos contendo espaco/acento.
    function Convert-WinPathToMnt([string]$p) {
        $drive = $p.Substring(0,1).ToLower()
        $rest  = $p.Substring(2) -replace '\\','/'
        return "/mnt/$drive$rest"
    }

    # 1. Wrapper executavel dentro da distro WSL.
    #    IMPORTANTE: chama o executavel Windows do agent-browser diretamente.
    #    Isso evita o caminho WSL -> PowerShell -> shim do npm, que pode
    #    concluir a automacao e ainda assim deixar o processo Unix preso.
    $agentBrowserExeWin = Join-Path $env:APPDATA "npm\node_modules\agent-browser\bin\agent-browser-win32-x64.exe"
    if (-not (Test-Path $agentBrowserExeWin)) {
        throw "Nao foi possivel localizar o executavel do agent-browser em $agentBrowserExeWin."
    }
    $agentBrowserExeLinux = Convert-WinPathToMnt $agentBrowserExeWin
    $profileWin = Join-Path $env:USERPROFILE "Navegador"
    $chromeWin = if ($chromeReal) { $chromeReal } else { "" }
    $wrapperWsl = @'
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
"$AGENT_BROWSER_EXE" --cdp "$CDP_PORT" "$@"
'@
    $wrapperWsl = $wrapperWsl.Replace('__AGENT_BROWSER_EXE__', $agentBrowserExeLinux)
    $wrapperWsl = $wrapperWsl.Replace('__PROFILE_WIN__', $profileWin)
    $wrapperWsl = $wrapperWsl.Replace('__CHROME_WIN__', $chromeWin)

    $tmpWrapperWin = Join-Path $env:TEMP "navegador-wsl-wrapper.sh"
    [System.IO.File]::WriteAllText(
        $tmpWrapperWin,
        ($wrapperWsl -replace "`r`n","`n"),
        (New-Object System.Text.UTF8Encoding($false))
    )

    $tmpWrapperLinux = Convert-WinPathToMnt $tmpWrapperWin

    # 2. Script instalador escrito como aspas simples ('@...'@) para que
    #    nada seja interpolado por PowerShell. Trocamos o placeholder no fim.
    $instalador = @'
#!/usr/bin/env bash
set -euo pipefail
BEGIN_MARK='# >>> navegador >>>'
END_MARK='# <<< navegador <<<'
LOCAL_BIN="$HOME/.local/bin"
TARGET="$LOCAL_BIN/navegador"
WRAPPER_SOURCE="__WRAPPER__"
BASHRC="$HOME/.bashrc"
SKILL_SOURCE="__SKILL__"

mkdir -p "$LOCAL_BIN"
cp "$WRAPPER_SOURCE" "$TARGET"
chmod 755 "$TARGET"

# Remove qualquer bloco anterior entre os marcadores (inclusive linhas residuais "EOF"
# que possam ter vazado de tentativas antigas de here-doc).
if [ -f "$BASHRC" ] && grep -qF "$BEGIN_MARK" "$BASHRC"; then
    awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
        index($0,b)==1 {skip=1; next}
        skip && index($0,e)==1 {skip=0; next}
        !skip {print}
    ' "$BASHRC" > "$BASHRC.tmp" && mv "$BASHRC.tmp" "$BASHRC"
fi

# Limpeza defensiva: se sobrou linha "EOF" solta no final do arquivo, remove.
if [ -f "$BASHRC" ]; then
    sed -i -E '/^EOF[[:space:]]*$/d' "$BASHRC"
fi

for base in "$HOME/.codex/skills" "$HOME/.claude/skills"; do
    if [ -d "$base" ]; then
        mkdir -p "$base/navegador"
        cp "$SKILL_SOURCE" "$base/navegador/SKILL.md"
    fi
done
'@
    $instalador = $instalador.Replace('__WRAPPER__', $tmpWrapperLinux)
    $instalador = $instalador.Replace('__SKILL__', $tmpSkillLinux)

    $tmpInstaladorWin = Join-Path $env:TEMP "navegador-bashrc-install.sh"
    [System.IO.File]::WriteAllText(
        $tmpInstaladorWin,
        ($instalador -replace "`r`n","`n"),
        (New-Object System.Text.UTF8Encoding($false))
    )
    $tmpInstaladorLinux = Convert-WinPathToMnt $tmpInstaladorWin

    foreach ($distro in $wslDistrosOk) {
        wsl -d $distro -- bash $tmpInstaladorLinux
        if ($LASTEXITCODE -ne 0) {
            if ($wslMotivoIgnorado) {
                $wslMotivoIgnorado += " | Falha ao instalar em '$distro'."
            } else {
                $wslMotivoIgnorado = "Falha ao instalar em '$distro'."
            }
        }
    }

    Remove-Item -Path $tmpWrapperWin, $tmpInstaladorWin -ErrorAction SilentlyContinue
}
```

### 6.4 Verificar cada distro

Use `bash -lc`, nao `bash -ic`. O objetivo e verificar que `navegador` funciona em shell normal, sem depender do carregamento interativo do `.bashrc`.

```powershell
foreach ($distro in $wslDistrosOk) {
    $caminho = (wsl -d $distro -- sh -lc "command -v navegador 2>/dev/null" 2>$null) -as [string]
    $caminho = ($caminho -replace '\s', '')
    if ([string]::IsNullOrWhiteSpace($caminho) -or $caminho -notmatch '/navegador$') {
        Write-Warning "navegador nao ficou disponivel na distro '$distro'. Verifique PATH e ~/.local/bin."
    } else {
        Write-Host "OK navegador disponivel em '$distro': $caminho"
    }
}
Pop-Location
```

Verifique tambem se a skill foi registrada quando houver cliente Linux:

```powershell
foreach ($distro in $wslDistrosOk) {
    wsl -d $distro -- sh -lc 'test -f "$HOME/.codex/skills/navegador/SKILL.md" && sed -n "1,5p" "$HOME/.codex/skills/navegador/SKILL.md"'
    wsl -d $distro -- sh -lc 'test -f "$HOME/.claude/skills/navegador/SKILL.md" && sed -n "1,5p" "$HOME/.claude/skills/navegador/SKILL.md"'
}
```

Se a escrita do wrapper ou o registro/verificacao da skill falhar em alguma distro, registre o motivo no relatorio final e continue. A skill do Windows ainda funciona.

## 7. Reiniciar o cliente de IA

Peça ao usuário para fechar completamente o Claude Code e/ou o Codex, incluindo janelas e processos em segundo plano, e abrir novamente.

Isso é necessário para que o cliente carregue a skill global recém-instalada.

Depois de reiniciar, o usuário pode testar com:

```text
use a skill navegador para abrir google.com
```

A IA deve reconhecer a skill e usar a função `navegador`.

Também informe que, para desfazer a instalação no futuro, basta pedir:

```text
rode o rollback da skill navegador
```

O procedimento está no apêndice deste prompt.

## 8. Relatório final

Depois de concluir os passos, mostre um relatório neste formato. Preencha cada campo com o que aconteceu na máquina. Não invente versões nem status.

```text
=== Relatório de instalação - skill navegador ===

Softwares instalados:
- Node.js: <versão obtida em `node --version`>
- npm: <versão obtida em `npm --version`>
- agent-browser: <versão obtida em `agent-browser --version` ou `npm list -g agent-browser`>
- Chrome usado: <caminho do Chrome real detectado, ex: C:\Program Files\Google\Chrome\Application\chrome.exe>

Arquivos criados:
- <caminho do $PROFILE, se foi criado neste passo>
- <%USERPROFILE%\.codex\skills\navegador\SKILL.md, se aplicável>
- <%USERPROFILE%\.claude\skills\navegador\SKILL.md, se aplicável>

Arquivos modificados:
- $PROFILE: bloco `# >>> navegador >>>` ... `# <<< navegador <<<` inserido/atualizado
- ~/.local/bin/navegador das distros Ubuntu 24+: <lista das distros em que foi criado/atualizado | não aplicável>
- ~/.bashrc das distros Ubuntu 24+: <bloco antigo removido, se existia | não aplicável>
- ExecutionPolicy do CurrentUser: <alterada de X para RemoteSigned | inalterada>

Clientes em que a skill foi registrada:
- Codex: <sim/não>
- Claude Code: <sim/não>

Status do WSL2:
- <distros Ubuntu 24+ integradas: nome1, nome2... | ignorado: <motivo> | não detectado>

Status geral: <sucesso | sucesso parcial: <motivo> | falha: <motivo>>
```

Termine lembrando o usuário de reiniciar o cliente de IA, caso ainda não tenha feito.

## Apêndice — rollback

Use este bloco para desfazer a instalação. Ele é idempotente e pode rodar mais de uma vez.

Por design, o rollback remove apenas o que pertence diretamente ao Navegador: função/bloco do `$PROFILE`, wrapper do WSL, `agent-browser`, perfil `%USERPROFILE%\Navegador` e skills globais. Ele não desinstala Node.js nem Google Chrome, mesmo quando foram instalados via `winget`, porque são dependências compartilhadas que podem ser usadas por outros aplicativos.

```powershell
$beginMarker = '# >>> navegador >>>'
$endMarker   = '# <<< navegador <<<'

# 1. Remove o bloco do $PROFILE
if (Test-Path $PROFILE) {
    $conteudo = Get-Content $PROFILE -Raw
    if ($conteudo -match "(?ms)$([regex]::Escape($beginMarker)).*?$([regex]::Escape($endMarker))") {
        $novo = [regex]::Replace(
            $conteudo,
            "(?ms)\r?\n?$([regex]::Escape($beginMarker)).*?$([regex]::Escape($endMarker))\r?\n?",
            ''
        )
        Set-Content -Path $PROFILE -Value $novo -Encoding UTF8
    }
}

# 2. Remove o executavel do WSL e limpa o bloco legado do ~/.bashrc
try {
    $null = wsl --status 2>$null
    if ($LASTEXITCODE -eq 0) {
        $encAntes = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        try {
            $distros = (wsl -l -q) -split "`r?`n" |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -and $_ -notmatch '^\s*$' }
        } finally {
            [Console]::OutputEncoding = $encAntes
        }

        # Grava o script de limpeza em arquivo (mesma razao do step 6.3: quoting fragil).
        $cleanup = @'
#!/usr/bin/env bash
TARGET="$HOME/.local/bin/navegador"
BASHRC="$HOME/.bashrc"
rm -f "$TARGET"
if [ -f "$BASHRC" ] && grep -qF "# >>> navegador >>>" "$BASHRC"; then
    awk '
        index($0,"# >>> navegador >>>")==1 {skip=1; next}
        skip && index($0,"# <<< navegador <<<")==1 {skip=0; next}
        !skip {print}
    ' "$BASHRC" > "$BASHRC.tmp" && mv "$BASHRC.tmp" "$BASHRC"
fi
[ -f "$BASHRC" ] && sed -i -E '/^EOF[[:space:]]*$/d' "$BASHRC"
'@
        $cleanupWin = Join-Path $env:TEMP "navegador-bashrc-cleanup.sh"
        [System.IO.File]::WriteAllText(
            $cleanupWin,
            ($cleanup -replace "`r`n","`n"),
            (New-Object System.Text.UTF8Encoding($false))
        )
        $cleanupLinux = '/mnt/' + $cleanupWin.Substring(0,1).ToLower() + ($cleanupWin.Substring(2) -replace '\\','/')

        foreach ($distro in $distros) {
            wsl -d $distro -- bash $cleanupLinux 2>$null | Out-Null
        }
        Remove-Item $cleanupWin -ErrorAction SilentlyContinue
    }
}
catch { }

# 3. Desinstala o agent-browser globalmente
npm uninstall -g agent-browser 2>$null | Out-Null

# 4. Apaga o diretório de perfil do Chrome
$perfil = Join-Path $env:USERPROFILE "Navegador"
if (Test-Path $perfil) {
    Remove-Item -Path $perfil -Recurse -Force -ErrorAction SilentlyContinue
}

# 5. Apaga as skills globais
$codexSkill  = Join-Path $env:USERPROFILE ".codex\skills\navegador"
$claudeSkill = Join-Path $env:USERPROFILE ".claude\skills\navegador"
foreach ($p in @($codexSkill, $claudeSkill)) {
    if (Test-Path $p) {
        Remove-Item -Path $p -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Rollback concluido. Caso o cliente de IA esteja aberto, reinicie-o para que a skill desapareca da lista."
```

Depois do rollback, peça ao usuário para reiniciar o Claude Code e/ou Codex para que a skill desapareça da lista de skills carregadas.
