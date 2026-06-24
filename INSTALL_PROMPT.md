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

### 2.1 Sobre DRM (Netflix e outros streamings)

Serviços com DRM dependem do componente Widevine. Há uma armadilha importante no Windows: quando o `agent-browser` **lança** o Chrome, ele injeta `--disable-component-update`, e essa flag impede o Chrome de **registrar** o Widevine. O resultado é que o EME falha (a Netflix pede para ativar `chrome://settings/content/protectedContent` mesmo já estando ativado). Copiar os arquivos do Widevine para o perfil **não resolve**, porque sem o component updater o Chrome nem registra um CDM já presente no disco.

Por isso a função `navegador` (passo 3) **não deixa o `agent-browser` lançar o Chrome**: ela abre o Chrome real **normalmente** (com `--remote-debugging-port=9333`) e faz o `agent-browser` apenas **conectar** via `--cdp`. Lançado normalmente, o Chrome registra o Widevine bundled e o DRM passa a funcionar. Não há passo de "provisionamento" aqui — a verificação de DRM acontece no passo 4, depois que a função existir.

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

Importante: a função `navegador` não pode abrir outro navegador ou outra janela alternativa quando `open`, `goto` ou `navigate` falharem ou demorarem demais. O comportamento correto é reutilizar a sessão existente; se o comando não responder em tempo razoável, interromper o processo e falhar explicitamente.

A função abre o Chrome real **normalmente** (sem `--disable-component-update`) com `--remote-debugging-port=9333` e faz o `agent-browser` apenas **conectar** via `--cdp`. Isso é o que permite DRM/Netflix (veja o passo 2.1). O `agent-browser` nunca lança o Chrome aqui; se lançasse, injetaria `--disable-component-update` e o Widevine não seria registrado.

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

    function ConvertTo-NavegadorCliArgument {
        param([string]`$Value)
        if (`$null -eq `$Value) { return '""' }
        if (`$Value -match '[\s"]') { return '"' + (`$Value -replace '"', '\"') + '"' }
        return `$Value
    }

    function Test-NavegadorPort {
        param([int]`$Port)
        return [bool](Get-NetTCPConnection -LocalPort `$Port -State Listen -ErrorAction SilentlyContinue)
    }

    function Get-NavegadorChromeProcs {
        param([string]`$ProfileDir)
        return @(Get-CimInstance Win32_Process -Filter "Name = 'chrome.exe'" -ErrorAction SilentlyContinue |
            Where-Object { `$_.CommandLine -and `$_.CommandLine -match [regex]::Escape(`$ProfileDir) })
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

    `$profileDir = "`$env:USERPROFILE\Navegador"
    `$debugPort = 9333

    if (`$Argumentos.Count -ge 1 -and `$Argumentos[0] -eq 'close') {
        try { & `$agentBrowserExe --cdp `$debugPort close 2>`$null | Out-Null } catch { }
        foreach (`$proc in (Get-NavegadorChromeProcs -ProfileDir `$profileDir)) {
            Stop-Process -Id `$proc.ProcessId -Force -ErrorAction SilentlyContinue
        }
        return
    }

    if (-not (Test-NavegadorPort -Port `$debugPort)) {
        foreach (`$proc in (Get-NavegadorChromeProcs -ProfileDir `$profileDir)) {
            Stop-Process -Id `$proc.ProcessId -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Milliseconds 400
        `$chromeArgumentLine = '--user-data-dir="' + `$profileDir + '" --no-first-run --no-default-browser-check --remote-debugging-port=' + `$debugPort + ' --disable-blink-features=AutomationControlled about:blank'
        Start-Process -FilePath `$chromeExe -ArgumentList `$chromeArgumentLine | Out-Null
        `$deadline = (Get-Date).AddSeconds(20)
        while (-not (Test-NavegadorPort -Port `$debugPort) -and (Get-Date) -lt `$deadline) {
            Start-Sleep -Milliseconds 300
        }
        if (-not (Test-NavegadorPort -Port `$debugPort)) {
            throw "Chrome nao abriu a porta de depuracao `$debugPort. Nenhum navegador alternativo foi aberto."
        }
    }

    `$stdoutPath = Join-Path "`$env:TEMP" ("agent-browser-" + [guid]::NewGuid().ToString() + ".out")
    `$stderrPath = Join-Path "`$env:TEMP" ("agent-browser-" + [guid]::NewGuid().ToString() + ".err")
    try {
        `$agentBrowserArgs = @('--cdp', "`$debugPort") + `$Argumentos
        `$agentBrowserArgumentLine = ((`$agentBrowserArgs | ForEach-Object { ConvertTo-NavegadorCliArgument -Value `$_ }) -join ' ')
        `$process = Start-Process -FilePath `$agentBrowserExe -ArgumentList `$agentBrowserArgumentLine -RedirectStandardOutput `$stdoutPath -RedirectStandardError `$stderrPath -PassThru -WindowStyle Hidden

        `$timeoutSeconds = 30
        if (-not `$process.WaitForExit(`$timeoutSeconds * 1000)) {
            try { Stop-Process -Id `$process.Id -Force -ErrorAction SilentlyContinue } catch { }
            throw ("agent-browser nao respondeu em {0} segundos. O comando foi interrompido sem abrir navegador alternativo." -f `$timeoutSeconds)
        }

        `$stdout = if (Test-Path `$stdoutPath) { Get-Content -Path `$stdoutPath -Raw } else { "" }
        `$stderr = if (Test-Path `$stderrPath) { Get-Content -Path `$stderrPath -Raw } else { "" }
        `$filteredStderr = ((`$stderr -split "\r?\n") | Where-Object {
            `$_ -and `$_ -notmatch 'ignored: daemon already running'
        }) -join [Environment]::NewLine

        if (-not [string]::IsNullOrWhiteSpace(`$stdout)) { [Console]::Out.Write(`$stdout) }
        if (-not [string]::IsNullOrWhiteSpace(`$filteredStderr)) { [Console]::Error.WriteLine(`$filteredStderr) }

        `$exitCode = `$null
        try { `$process.Refresh(); `$exitCode = `$process.ExitCode } catch { }
        if (`$null -ne `$exitCode -and `$exitCode -ne 0) {
            throw ("agent-browser falhou com codigo {0}." -f `$exitCode)
        }
    } finally {
        Remove-Item -LiteralPath `$stdoutPath, `$stderrPath -Force -ErrorAction SilentlyContinue
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

Se existir uma instalação antiga em que a função chame `agent-browser --profile ... --headed --executable-path ...` (ou seja, deixe o `agent-browser` lançar o Chrome), trate como desatualizada: substitua o bloco, encerre o Chrome/daemon e recarregue o `$PROFILE`.

### 3.3 Fechar o daemon e carregar a função

O `agent-browser` usa daemon. Em upgrades de uma instalação antiga (que deixava o `agent-browser` lançar o Chrome), feche o daemon e qualquer Chrome do perfil para que a nova função possa reabrir o Chrome com a porta de depuração:

```powershell
agent-browser close 2>$null
Get-CimInstance Win32_Process -Filter "Name = 'chrome.exe'" |
    Where-Object { $_.CommandLine -and $_.CommandLine -match [regex]::Escape("$env:USERPROFILE\Navegador") } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
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

A definição deve conter `--cdp`, `--remote-debugging-port` e `--disable-blink-features=AutomationControlled` (a função abre o Chrome e o `agent-browser` conecta via CDP).

Depois disso, este comando:

```powershell
navegador open myapp.com
```

faz, nos bastidores, algo equivalente a: abrir o Chrome real **normalmente** uma vez

```powershell
chrome.exe --user-data-dir="%USERPROFILE%\Navegador" --no-first-run --no-default-browser-check --remote-debugging-port=9333 --disable-blink-features=AutomationControlled about:blank
```

e então conectar o `agent-browser` a esse Chrome:

```powershell
agent-browser --cdp 9333 open myapp.com
```

A flag `--disable-blink-features=AutomationControlled` oculta o marcador `navigator.webdriver`, usado por alguns sites para detectar automação. Lançar o Chrome dessa forma (sem `--disable-component-update`) é o que mantém o Widevine registrado e o DRM funcionando.

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

### 4.1 Verificar DRM (Widevine / Netflix)

Confirme que o DRM está funcionando antes de finalizar. Com a função carregada, abra uma página qualquer e pergunte ao próprio Chrome se ele consegue negociar o Widevine via EME. Guarde o resultado em `$drmStatus`:

```powershell
navegador open https://example.com 2>$null | Out-Null
$drmJs = @'
(async () => {
  const cfg = [{ initDataTypes: ['cenc'], audioCapabilities: [{ contentType: 'audio/mp4; codecs="mp4a.40.2"' }], videoCapabilities: [{ contentType: 'video/mp4; codecs="avc1.42E01E"' }] }];
  try { const a = await navigator.requestMediaKeySystemAccess('com.widevine.alpha', cfg); await a.createMediaKeys(); return 'OK'; }
  catch (e) { return 'FAIL: ' + e.name; }
})()
'@
$drmOut = navegador eval $drmJs 2>$null
if ($drmOut -match 'OK') {
    $drmStatus = "OK: o Chrome do Navegador negocia o Widevine; Netflix e outros streamings com DRM devem funcionar."
} else {
    $drmStatus = "FALHA: o Widevine nao foi negociado ($drmOut). Verifique se a funcao abre o Chrome com --remote-debugging-port (sem --disable-component-update) e se o Chrome tem o WidevineCdm bundled."
}
Write-Host $drmStatus
```

Guarde o valor de `$drmStatus`. Você vai precisar dele no relatório final **e** na mensagem em texto para o usuário.

- Se começar com `OK:`, o DRM está funcionando — não há nada a fazer.
- Se começar com `FALHA:`, **avise o usuário explicitamente, por texto**, que Netflix e outros streamings com DRM podem não funcionar. Investigue: a causa quase sempre é a função ainda estar deixando o `agent-browser` lançar o Chrome (jeito antigo, com `--disable-component-update`). Confirme `(Get-Command navegador).Definition`, rode `navegador close`, recarregue o `$PROFILE` e teste de novo. Não trate como falha total da instalação — o resto da skill funciona.

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
- chamar diretamente o executavel Windows do `agent-browser` com o mesmo perfil e as mesmas flags definidas para o PowerShell.

Se não houver WSL2, ou se nenhuma distro for Ubuntu 24+, ignore este passo e registre o motivo no relatório final. Nunca interrompa a instalação por causa do WSL2.

Notas importantes:

- O nome de usuário do WSL costuma ser diferente do nome do Windows. Isso não impede a instalação, porque o wrapper é gravado no `$HOME` da própria distro.
- Evite chamar `powershell.exe` para executar `navegador` dentro do WSL. Na prática isso pode concluir a automação e ainda deixar o processo Unix pendurado.
- O wrapper do WSL deve garantir o Chrome real do Windows aberto **normalmente** (sem `--disable-component-update`) com `--remote-debugging-port=9333` e então chamar `agent-browser-win32-x64.exe --cdp 9333`. Ele usa `powershell.exe` só para checar a porta e subir o Chrome quando preciso. Não deixe o `agent-browser` lançar o Chrome, senão o Widevine (DRM/Netflix) não é registrado.
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
DEBUG_PORT=9333

# Garante o Chrome real do Windows aberto no perfil, lancado NORMALMENTE (sem
# --disable-component-update), para registrar o componente Widevine e permitir
# DRM/Netflix. Usamos o PowerShell do Windows para checar a porta de depuracao
# e subir o Chrome quando necessario.
if [ -n "$CHROME_WIN" ]; then
    powershell.exe -NoLogo -NoProfile -Command "if (-not (Get-NetTCPConnection -LocalPort $DEBUG_PORT -State Listen -ErrorAction SilentlyContinue)) { Start-Process -FilePath '$CHROME_WIN' -ArgumentList '--user-data-dir=\"$PROFILE_WIN\" --no-first-run --no-default-browser-check --remote-debugging-port=$DEBUG_PORT --disable-blink-features=AutomationControlled about:blank'; Start-Sleep -Seconds 2 }" >/dev/null 2>&1 || true
fi

# O agent-browser apenas CONECTA via --cdp; ele nunca lanca o Chrome (senao
# injetaria --disable-component-update e o Widevine nao seria registrado).
"$AGENT_BROWSER_EXE" --cdp "$DEBUG_PORT" "$@"
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

DRM (Widevine):
- <valor de $drmStatus do passo 4.1, ex: OK: o Chrome do Navegador negocia o Widevine... | FALHA: ...>

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

Além do relatório no terminal, escreva uma mensagem em texto para o usuário (na conversa, não só no terminal) resumindo o status geral e, obrigatoriamente, o status do DRM/Widevine do passo 4.1: diga se ficou `OK` ou `FALHA`. Se ficou `FALHA`, explique em texto que Netflix e outros streamings com DRM podem não funcionar e o que verificar (confirmar que a função abre o Chrome com `--remote-debugging-port` e conecta via `--cdp`, em vez de deixar o `agent-browser` lançar o Chrome). O usuário não deve precisar ler a saída do terminal para descobrir isso.

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
