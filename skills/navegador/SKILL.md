---
name: navegador
description: Controla o Google Chrome do usuário pelo terminal via o comando `navegador`. Use sempre que o usuário pedir para abrir sites, navegar, clicar, preencher formulários, ler conteúdo de páginas, mandar mensagens em redes sociais, controlar Netflix/YouTube, fazer login em serviços, ou qualquer automação de navegador. Use OBRIGATORIAMENTE esta skill sempre que o usuário mencionar "Navegador" na mensagem.
---

# Skill Navegador

Você controla o **Google Chrome do usuário humano** através de um único comando de terminal chamado `navegador`. O Chrome roda com um perfil persistente em `%USERPROFILE%\Navegador`, então logins, cookies e sessões ficam salvos entre execuções — o usuário só precisa entrar em cada site uma vez.

## Regra de ouro

**Sempre que precisar controlar o navegador, use o comando `navegador` no terminal.** Não use Playwright, Puppeteer, Selenium, MCP browser, nem qualquer outra ferramenta. Se você tem acesso a um terminal PowerShell (ou bash dentro de WSL2 Ubuntu 24+), o comando `navegador` está disponível e é o único caminho correto.

Se o usuário mencionar a palavra **"Navegador"** (ou disser `/navegador ...`), interprete como uma ordem explícita para usar esta skill — não pergunte, não sugira alternativas, vá direto para o comando `navegador`.

Busque usar o comando `navegador batch *` para executar múltiplas ações quando isso não for interferir no resultado.

Se você parar em um captcha que não consegue resolver ou tela de login, pare imediatamente e peça para o usuário continuar.

Sempre comece assumindo que o navegador já está aberto e o usuário já está logado nos sites que ele está pedindo para você acessar.

## Commands

### Core Commands

```
navegador open                    # Launch browser (no navigation); stays on about:blank
navegador open <url>              # Launch + navigate to URL (aliases: goto, navigate)
navegador click <sel>             # Click element (--new-tab to open in new tab)
navegador dblclick <sel>          # Double-click element
navegador focus <sel>             # Focus element
navegador type <sel> <text>       # Type into element
navegador fill <sel> <text>       # Clear and fill
navegador press <key>             # Press key (Enter, Tab, Control+a) (alias: key)
navegador keyboard type <text>    # Type with real keystrokes (no selector, current focus)
navegador keyboard inserttext <text>  # Insert text without key events (no selector)
navegador keydown <key>           # Hold key down
navegador keyup <key>             # Release key
navegador hover <sel>             # Hover element
navegador select <sel> <val>      # Select dropdown option
navegador check <sel>             # Check checkbox
navegador uncheck <sel>           # Uncheck checkbox
navegador scroll <dir> [px]       # Scroll (up/down/left/right, --selector <sel>)
navegador scrollintoview <sel>    # Scroll element into view (alias: scrollinto)
navegador drag <src> <tgt>        # Drag and drop
navegador upload <sel> <files>    # Upload files
navegador screenshot [path]       # Take screenshot (--full for full page, saves to a temporary directory if no path)
navegador screenshot --annotate   # Annotated screenshot with numbered element labels
navegador screenshot --screenshot-dir ./shots    # Save to custom directory
navegador screenshot --screenshot-format jpeg --screenshot-quality 80
navegador pdf <path>              # Save as PDF
navegador snapshot                # Accessibility tree with refs (best for AI)
navegador eval <js>               # Run JavaScript (-b for base64, --stdin for piped input)
navegador stream enable           # Start runtime WebSocket streaming
navegador stream status           # Show runtime streaming state and bound port
navegador stream disable          # Stop runtime WebSocket streaming
navegador close                   # Close browser (aliases: quit, exit)
navegador close --all             # Close all active sessions
navegador chat "<instruction>"    # AI chat: natural language browser control (single-shot)
navegador chat                    # AI chat: interactive REPL mode
```

### Get Info

```
navegador get text <sel>          # Get text content
navegador get html <sel>          # Get innerHTML
navegador get value <sel>         # Get input value
navegador get attr <sel> <attr>   # Get attribute
navegador get title               # Get page title
navegador get url                 # Get current URL
navegador get cdp-url             # Get CDP WebSocket URL (for DevTools, debugging)
navegador get count <sel>         # Count matching elements
navegador get box <sel>           # Get bounding box
navegador get styles <sel>        # Get computed styles
```

### Check State

```
navegador is visible <sel>        # Check if visible
navegador is enabled <sel>        # Check if enabled
navegador is checked <sel>        # Check if checked
```

### Find Elements (Semantic Locators)

```
navegador find role <role> <action> [value]       # By ARIA role
navegador find text <text> <action>               # By text content
navegador find label <label> <action> [value]     # By label
navegador find placeholder <ph> <action> [value]  # By placeholder
navegador find alt <text> <action>                # By alt text
navegador find title <text> <action>              # By title attr
navegador find testid <id> <action> [value]       # By data-testid
navegador find first <sel> <action> [value]       # First match
navegador find last <sel> <action> [value]        # Last match
navegador find nth <n> <sel> <action> [value]     # Nth match
```

**Actions:** click, fill, type, hover, focus, check, uncheck, text
**Options:** --name <name> (filter role by accessible name), --exact (require exact text match)
**Examples:**
```
navegador find role button click --name "Submit"
navegador find text "Sign In" click
navegador find label "Email" fill "test@test.com"
navegador find first ".item" click
navegador find nth 2 "a" text
```

### Wait

```
navegador wait <selector>         # Wait for element to be visible
navegador wait <ms>               # Wait for time (milliseconds)
navegador wait --text "Welcome"   # Wait for text to appear (substring match)
navegador wait --url "**/dash"    # Wait for URL pattern
navegador wait --load networkidle # Wait for load state
navegador wait --fn "window.ready === true"  # Wait for JS condition

# Wait for text/element to disappear
navegador wait --fn "!document.body.innerText.includes('Loading...')"
navegador wait "#spinner" --state hidden
```

**Load states:** load, domcontentloaded, networkidle

### Batch Execution

Execute multiple commands in a single invocation. Commands can be passed as quoted arguments or piped as JSON via stdin. This avoids per-command process startup overhead when running multi-step workflows.

```
# Argument mode: each quoted argument is a full command
navegador batch "open https://example.com" "snapshot -i" "screenshot"

# With --bail to stop on first error
navegador batch --bail "open https://example.com" "click @e1" "screenshot"

# Stdin mode: pipe commands as JSON
echo '[
  ["open", "https://example.com"],
  ["snapshot", "-i"],
  ["click", "@e1"],
  ["screenshot", "result.png"]
]' | navegador batch --json
```

### Clipboard

```
navegador clipboard read                      # Read text from clipboard
navegador clipboard write "Hello, World!"     # Write text to clipboard
navegador clipboard copy                      # Copy current selection (Ctrl+C)
navegador clipboard paste                     # Paste from clipboard (Ctrl+V)
```

### Mouse Control

```
navegador mouse move <x> <y>      # Move mouse
navegador mouse down [button]     # Press button (left/right/middle)
navegador mouse up [button]       # Release button
navegador mouse wheel <dy> [dx]   # Scroll wheel
```

### Browser Settings

```
navegador set viewport <w> <h> [scale]  # Set viewport size (scale for retina, e.g. 2)
navegador set device <name>       # Emulate device ("iPhone 14")
navegador set geo <lat> <lng>     # Set geolocation
navegador set offline [on|off]    # Toggle offline mode
navegador set headers <json>      # Extra HTTP headers
navegador set credentials <u> <p> # HTTP basic auth
navegador set media [dark|light]  # Emulate color scheme
```

### Cookies & Storage

```
navegador cookies                    # Get all cookies
navegador cookies set <name> <val>   # Set cookie
navegador cookies set --curl <file>  # Import cookies from a Copy-as-cURL dump,
                                         # JSON array, or bare Cookie header (auto-detected)
navegador cookies clear              # Clear cookies

navegador storage local              # Get all localStorage
navegador storage local <key>        # Get specific key
navegador storage local set <k> <v>  # Set value
navegador storage local clear        # Clear all

navegador storage session            # Same for sessionStorage
```

### Network

```
navegador network route <url>              # Intercept requests
navegador network route <url> --abort      # Block requests
navegador network route <url> --body <json>  # Mock response
navegador network route '*' --abort --resource-type script  # Block scripts only
navegador network unroute [url]            # Remove routes
navegador network requests                 # View tracked requests
navegador network requests --filter api    # Filter requests
navegador network requests --type xhr,fetch  # Filter by resource type
navegador network requests --method POST   # Filter by HTTP method
navegador network requests --status 2xx    # Filter by status (200, 2xx, 400-499)
navegador network request <requestId>      # View full request/response detail
navegador network har start                # Start HAR recording
navegador network har stop [output.har]    # Stop and save HAR (temp path if omitted)
```

### Tabs & Windows

```
navegador tab                              # List tabs (shows `tabId` and optional label)
navegador tab new [url]                    # New tab (optionally with URL)
navegador tab new --label docs [url]       # New tab with a user-assigned label
navegador tab <t<N>|label>                 # Switch to a tab by id or label
navegador tab close [t<N>|label]           # Close a tab (defaults to active)
navegador window new                       # New window
```

Tab ids are stable strings of the form `t1`, `t2`, `t3`. They're never reused within a session, so scripts and agents can keep referring to the same tab even after other tabs are opened or closed. Positional integers like `tab 2` are **not** accepted; the `t` prefix disambiguates handles from indices and mirrors the `@e1` convention used for element refs.

You can also assign a memorable label (`docs`, `app`, `admin`) and use it interchangeably with the id. Labels are never auto-generated and never rewritten on navigation — they're yours to name and keep:

```
navegador tab new --label docs https://docs.example.com
navegador tab docs               # switch to the docs tab
navegador snapshot               # populate refs for docs
navegador click @e3              # click uses docs's refs
navegador tab close docs         # close by label
```

### Frames

```
navegador frame <sel>             # Switch to iframe
navegador frame main              # Back to main frame
```

### Dialogs

```
navegador dialog accept [text]    # Accept (with optional prompt text)
navegador dialog dismiss          # Dismiss
navegador dialog status           # Check if a dialog is currently open
```

By default, `alert` and `beforeunload` dialogs are automatically accepted so they never block the agent. `confirm` and `prompt` dialogs still require explicit handling.

When a JavaScript dialog is pending, all command responses include a warning field with the dialog type and message.

### Diff

```
navegador diff snapshot                              # Compare current vs last snapshot
navegador diff snapshot --baseline before.txt        # Compare current vs saved snapshot file
navegador diff snapshot --selector "#main" --compact # Scoped snapshot diff
navegador diff screenshot --baseline before.png      # Visual pixel diff against baseline
navegador diff screenshot --baseline b.png -o d.png  # Save diff image to custom path
navegador diff screenshot --baseline b.png -t 0.2    # Adjust color threshold (0-1)
navegador diff url https://v1.com https://v2.com     # Compare two URLs (snapshot diff)
navegador diff url https://v1.com https://v2.com --screenshot  # Also visual diff
navegador diff url https://v1.com https://v2.com --wait-until networkidle  # Custom wait strategy
navegador diff url https://v1.com https://v2.com --selector "#main"  # Scope to element
```

### Debug

```
navegador trace start [path]      # Start recording trace
navegador trace stop [path]       # Stop and save trace
navegador profiler start          # Start Chrome DevTools profiling
navegador profiler stop [path]    # Stop and save profile (.json)
navegador console                 # View console messages (log, error, warn, info)
navegador console --json          # JSON output with raw CDP args for programmatic access
navegador console --clear         # Clear console
navegador errors                  # View page errors (uncaught JavaScript exceptions)
navegador errors --clear          # Clear errors
navegador highlight <sel>         # Highlight element
navegador inspect                 # Open Chrome DevTools for the active page
```

### Navigation

```
navegador back                    # Go back
navegador forward                 # Go forward
navegador reload                  # Reload page
navegador pushstate <url>         # SPA client-side nav; auto-detects window.next.router.push,
                                      # falls back to history.pushState + popstate
```

### Pre-navigation setup

Some flows (SSR debug, auth cookies for protected origins, init scripts) need state set up _before_ the first navigation. Use `open` with no URL to launch the browser, then stage cookies / routes / init scripts, then navigate. `batch` sends it all in one CLI call:

```
navegador batch \
  '["open"]' \
  '["network","route","*","--abort","--resource-type","script"]' \
  '["cookies","set","--curl","cookies.curl","--domain","localhost"]' \
  '["navigate","http://localhost:3000/target"]'
```

Without `batch` the same sequence is three commands that all reuse the same daemon (fast, but not one turn).

## Workflow padrão para qualquer tarefa

Siga esta sequência em quase todo pedido. Não tente adivinhar seletores CSS — use refs do `snapshot`, é mais robusto.

1. **Abrir o site:** `navegador open <url>` (ou verifique se já existe alguma tab aberta com `navegador tab list`)
2. **Esperar carregar:** `navegador wait <ms>` ou `navegador wait <seletor>`
3. **Tirar snapshot:** `navegador snapshot` — retorna a árvore de acessibilidade com `@refs` que você usa nas próximas ações.
4. **Agir nos elementos:** `navegador click @ref`, `navegador type @ref "texto"`, `navegador fill @ref "texto"`, `navegador press Enter`, etc.
5. **Conferir resultado:** tire outro `navegador snapshot` ou `navegador get text @ref` para confirmar.
6. **NÃO feche o navegador** ao final de uma tarefa, a menos que o usuário peça explicitamente. O perfil é persistente e o usuário pode querer continuar usando manualmente.

### Quando o site já estiver aberto

Antes de abrir um site novamente, considere `navegador snapshot` — se a sessão já estiver na URL certa, pule o `open`. Use `navegador tab list` para ver as abas e `navegador tab <n>` para trocar.

### Login em sites

O perfil é persistente, então normalmente o usuário **já está logado**. Se o snapshot mostrar tela de login, **peça ao humano para fazer login na janela do Chrome que abriu** e dizer "continuar" — não tente automatizar login com senha. Após o usuário logar uma vez, futuras execuções já estarão autenticadas.

### Lendo conteúdo de uma página

Para "leia meu perfil do X" ou "veja o que está em Y":

1. `navegador open <url>`
2. `navegador wait 2000` (ou espere por um elemento específico)
3. `navegador snapshot` — leia o conteúdo da árvore de acessibilidade
4. Para texto bruto de uma seção específica: `navegador get text @ref`

### Mandando mensagens em redes sociais (Facebook, Instagram, WhatsApp Web, LinkedIn)

1. Abra o site e tire um snapshot.
2. Procure o campo de busca de contatos pelo nome do destinatário.
3. Clique no contato correto (pelo `@ref` do snapshot).
4. Clique no campo de mensagem, use `navegador type @ref "mensagem"` ou `navegador fill @ref "mensagem"`.
5. Espere 2 segundos e comece a digitar a mensagem, depois clique no botão enviar.

### Controlando Netflix, YouTube, players de vídeo

Players costumam responder bem a atalhos de teclado. Use `navegador press` com a tecla certa em vez de procurar botões na tela:

- Netflix: próximo episódio costuma ser botão visível ao final; use `snapshot` + `click @ref`. Play/pause: `navegador press Space`.
- YouTube: `Space` play/pause, `Shift+N` próximo, `f` fullscreen, `m` mute.

Se o player estiver em foco errado, primeiro `navegador click @ref-do-player` e depois mande a tecla.

## Idempotência e estado

- O perfil é **único e compartilhado** entre todas as chamadas. Não crie outros perfis. Não passe flags de conexão (`--profile`, `--cdp`, `--remote-debugging-port`) manualmente — a função `navegador` já cuida disso (ela abre o Chrome real e o `agent-browser` conecta via CDP).
- Não rode `agent-browser` direto: sempre `navegador`. Isso garante que o perfil correto seja usado.
- Se algo parecer travado, `navegador close` e recomece do `open`. Como o perfil é persistente, logins continuam válidos.

## Quando algo não funcionar

Se uma tarefa **não for possível** com os subcomandos atuais de `navegador`, ou se você encontrar um bug, ou se identificar uma melhoria que beneficiaria todos os usuários da skill, **sugira ao usuário abrir uma issue no GitHub**:

> Esta tarefa esbarrou em uma limitação do navegador. Se quiser, abra uma issue em https://github.com/giovannefeitosa/navegador/issues descrevendo o que estava tentando fazer — isso ajuda a melhorar a skill para todo mundo.

Não abra a issue automaticamente. Apenas sugira, com o link, e siga em frente com o que for possível.

## O que NÃO fazer

- Não use Playwright, Puppeteer, Selenium ou MCP de navegador. Use sempre `navegador`.
- Não passe flags de conexão/launch (`--profile`, `--headed`, `--cdp`) manualmente — a função `navegador` já gerencia a conexão com o Chrome.
- Não feche o navegador no final, a menos que o usuário peça.
- Não tente automatizar logins com senha. Peça ao humano para logar.
- Não envie mensagens, faça compras, ou execute ações irreversíveis sem confirmação explícita do humano.
- Não invente seletores CSS — use `snapshot` e refs.
- Não feche o navegador a não ser que o usuário peça para você o fazer
