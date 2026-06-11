# Skill Navegador

Configure o Codex ou o Claude Code para controlar o Google Chrome do Windows por meio de um único comando: `navegador`.

A instalação cria um perfil persistente em `%USERPROFILE%\Navegador`. Logins, cookies e sessões ficam salvos entre execuções, sem exigir que a pessoa configure Playwright, Chrome, perfis ou WSL2 manualmente.

## Decisões do projeto

- Funciona no Windows 10 e no Windows 11.
- O Chrome e os dados do usuário ficam no Windows, não no WSL2.
- Todas as automações usam o mesmo Google Chrome e o mesmo perfil: `%USERPROFILE%\Navegador`.
- O instalador cria a função `navegador` no `$PROFILE` do PowerShell.
- A função `navegador` reutiliza o Chrome do Navegador quando ele já está aberto; se estiver fechado, abre o Chrome real com o perfil persistente e então conecta pela porta CDP detectada.
- A função `navegador` não deve fechar nem recriar a sessão aberta só porque um comando `open`, `goto` ou `navigate` demorou para responder.
- O projeto não usa navegador alternativo: se o Google Chrome real não estiver disponível ou um comando não responder, deve falhar explicitamente.
- O instalador cria apenas um atalho `Navegador` na área de trabalho do Windows.
- O instalador não cria, não fixa e não altera atalhos na taskbar.
- O atalho da área de trabalho usa o ícone do projeto, salvo em `%USERPROFILE%\Navegador\navegador.ico`.
- `agent-browser` é instalado globalmente no Windows com `npm install -g`.
- `Node.js`, `npm`, `agent-browser` e Google Chrome podem ser instalados automaticamente quando `winget` estiver disponível.
- A instalação sempre começa no PowerShell do Windows.
- WSL2 é opcional. Se existir uma ou mais distros Ubuntu 24+, o mesmo instalador PowerShell cria um executável `navegador` em `~/.local/bin` de cada uma, remove wrappers antigos do `.bashrc` e registra a skill nos diretórios Linux do Codex/Claude quando eles existirem. Outras distros são ignoradas.
- Se Codex e Claude Code estiverem instalados, a skill é registrada nos dois.
- A skill é instalada com escopo global e pode ser usada em qualquer projeto.

## Requisitos

- Windows 10 ou Windows 11.
- `winget` e opcional, mas quando estiver indisponivel talvez seja necessario instalar Node.js LTS e Google Chrome manualmente.
- PowerShell disponível.
- Codex ou Claude Code instalado.
- Plano pago ativo do Codex ou Claude Code.
- Acesso à internet durante a instalação.

## Instalação rápida

Rode no PowerShell do Windows. Esse é o unico caminho suportado para instalar. O script faz instalacao nova e tambem atualiza instalacoes antigas.

```powershell
$tmp = Join-Path $env:TEMP "install-navegador.ps1"
try {
    Invoke-WebRequest "https://raw.githubusercontent.com/giovannefeitosa/navegador/main/scripts/install-navegador.ps1" -OutFile $tmp
    powershell -ExecutionPolicy Bypass -File $tmp
}
finally {
    Remove-Item $tmp -ErrorAction SilentlyContinue
}
```

Depois da instalacao, feche e abra novamente o Codex ou o Claude Code para carregar a skill global.

Ao final, o instalador deixa um único atalho `Navegador` na área de trabalho do Windows, já com o ícone do projeto baixado do repositório público.

> Peca para o seu agente instalar manualmente, veja [INSTALL_PROMPT.md](INSTALL_PROMPT.md). Esse caminho e referencia; o script acima e o caminho recomendado.

## Como testar

No PowerShell, rode:

```powershell
navegador open https://example.com
navegador wait body
navegador get title
navegador close
```

Resultado esperado: o Chrome abre com janela visível, `navegador get title` retorna o título da página, e o comando usa o perfil `%USERPROFILE%\Navegador`.

Para testar login no Google, rode `navegador open https://accounts.google.com`. A página de login deve carregar sem aviso de "navegador inseguro" ou "acesso bloqueado".

## Atualização de instalação antiga

Se o login no Google ou em outros sites continuar bloqueado após atualizar o repositório, a máquina provavelmente ainda está usando uma função `navegador` antiga no `$PROFILE` do PowerShell.

Após atualizar, confirme que `(Get-Command navegador).Definition` contém `--cdp` e `--remote-debugging-port=0`. Depois rode `agent-browser close`, recarregue o `$PROFILE` com `. $PROFILE` e teste de novo.

O daemon reutiliza a configuração antiga enquanto continuar rodando.
