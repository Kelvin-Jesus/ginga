# ConnectDemo

Demo clicável do fluxo de conexão: um MacBook e um Galaxy Tab lado a lado sob um céu, com a UI nova dos dois apps.

**O consumidor fornece** nada: é uma página de vitrine (site, apresentação, testes de usabilidade). Carrega tokens.css, bundle.css e bundle.js.

- Caminho Wi‑Fi: ligar o toggle no Mac → o tablet encontra o Mac → Conectar → código nas duas telas → Parear → cometa, warp, área de trabalho estendida. Desconectar e Reconectar mostra o atalho de tablet já pareado.
- Caminho USB: “Prefiro o cabo USB” ou o toggle USB → o cabo se desenha, o Android pede para abrir o Ginga → Abrir → pulso no cabo, warp.
- Um anel `star` pulsante com rótulo aponta sempre o próximo clique; a narração embaixo explica o passo.
- Seletor Claro / Escuro / Black espacial no topo troca o tema das duas UIs.
- Performance: um canvas de céu (pausa fora da tela), cometa e warp só durante a conexão, resto em `transform`/`opacity`. Movimento reduzido pula cometa e warp.
