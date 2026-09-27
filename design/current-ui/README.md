# UI atual (26/09/2026): base para a nova UI Ginga

Prints do estado atual dos dois apps. A nova UI deve seguir a marca em `brand/README.md`.

## Mac (SwiftUI, `ControlPanelView.swift`, replaced by the Ginga main window)

| Arquivo | O que é |
|---|---|
| `mac-01-painel-real-escuro.png` | Painel de controle rodando de verdade: display ativo, Wi‑Fi anunciando, tablet pareado |
| `mac-02-painel-completo-claro.png`, `mac-03-painel-completo-escuro.png` | O painel inteiro, sem rolagem (renderizado fora da tela, sem sessão ativa). A linha “Settings come from --config” aparece só por causa desse modo de captura |

Não aparecem nos prints:
- **Menu da barra de menus** (`StatusItemController.swift`), ícone SF Symbol `rectangle.on.rectangle`. Itens: status do display, “Capture: …”, “Tablet: …”, separador, “Accept the Tablet over USB” / “Stop Accepting the Tablet”, “Create Display” ou “Remove Display” + “Show Debug Preview”, “Control Panel…”, “Displays Settings…”, separador, “Quit” (with the app's former name).
- **Alerta de pareamento** (`PairingPrompt.swift`, NSAlert): “Pair with “Galaxy Tab S11”?”, código de 6 dígitos em dois grupos (“482 913”), aviso para parear só tablets próprios, botões “Pair” / “Don’t Pair”.

## Android (Views XML, `android/app/src/main/res/layout/activity_main.xml`, `activity_stream.xml`)

| Arquivo | O que é |
|---|---|
| `android-01-inicio.png` | Tela inicial conectada e pausada (o Mac parou de enviar porque o display não está na tela) |
| `android-02-inicio-rolado.png` | O resto da tela inicial: Wi‑Fi, conexão direta, configurações |
| `android-03-stream-aguardando.png` | Tela de stream antes do primeiro quadro (“Streaming from …”) |

O botão flutuante `>_` nos prints do Android é de outro app instalado no tablet. Não faz parte do Ginga.

## Marca

`marca-icone.png` (A, ícone do app), `marca-logotipo.png` (C, marca no site e em cabeçalhos), `marca-monograma.png` (B, detalhes). Os SVGs estão em `brand/`.

| Token | Hex | Uso |
|---|---|---|
| Cobalto | `#2E47F5` | Cor primária: botões principais, toggles ligados, links, o tablet na marca |
| Cobalto noturno | `#6F82FF` | A primária no tema escuro |
| Noite | `#141830` | Texto no claro; fundo no escuro |
| Estrela | `#F2A900` claro / `#FFC43D` escuro | Só a estrela e pequenos destaques (ex.: “120 Hz”), nunca texto longo |
| Névoa | `#F2F3F8` | Fundo no claro |
| Superfície escura | `#171A33` | Cartões e seções no escuro |
| Linha | `#DCDFEA` claro / `#2A2E4D` escuro | Divisórias |
| Sucesso / Atenção / Erro | `#138A52` / `#B26A00` / `#C23B3B` (escuro: `#4FD08E` / `#F2B24C` / `#F07474`) | Estados de conexão |

Tipografia: **Unbounded** (títulos, só em peso SemiBold ou ExtraBold), **Figtree** (texto), **IBM Plex Mono** (números, specs, códigos). No Mac, a UI nativa pode seguir com SF Pro e usar Unbounded só na marca.
