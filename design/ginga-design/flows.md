# Fluxos de UI/UX

Como os dois apps mudam com a marca Ginga. Base: a UI atual de 26/09/2026 (painel SwiftUI com 9 seções soltas; tela Android em Views XML com instruções longas e radio buttons). Objetivo: **uma decisão por tela, o técnico recolhido, o estado sempre visível**.

## Princípios

1. **O estado vem primeiro.** Um StatusOrbit no topo de cada tela diz onde a conexão está. Hoje “Virtual display / Capture / Connection” são três linhas que a pessoa precisa cruzar.
2. **Um caminho recomendado por vez.** Wi‑Fi pareado é o padrão; Cabo USB é a alternativa; Sem roteador aparece só quando não há rede. `adb` sai da tela inicial e vai para Avançado.
3. **Configurar ≠ conectar.** Ajustes de display (resolução, taxa, orientação) ficam numa tela de Ajustes; o painel principal só conecta e mostra o que está acontecendo.
4. **O que vale na hora é toggle; o que demora é botão com status.**

## Mac

### Barra de menus (ponto de entrada do dia a dia)

| Estado | Ícone (mark A, template) | Menu |
|---|---|---|
| Desligado | contorno | “Ginga está desligado” · **Aceitar tablets** · Abrir Ginga… · Sair |
| Procurando | estrela pisca | “Anunciando na rede” · tablets pareados (com ponto de estado) · Parar |
| Conectado | ponto `success` no canto | “Galaxy Tab S11 · 60 Hz · Wi‑Fi” · Pausar display · Desconectar · Ajustes de Telas… |
| Erro | ponto `danger` | a causa em palavras + a ação (“Cabo desconectado · Tentar de novo”) |

### Janela principal (substitui o painel de 9 seções)

1. **Cabeçalho**: monograma B + “Ginga” (`title`) + StatusOrbit.
2. **Conexão**: Aceitar tablets por Wi‑Fi (toggle) · Aceitar tablet por USB, sem modo desenvolvedor (toggle) · Sem roteador (linha que abre uma sheet explicando que o Mac sai do Wi‑Fi atual).
3. **Tablets**: DeviceRow por tablet pareado (nome amigável, meta em `mono`, Esquecer). Vazio: “Nenhum tablet pareado ainda.”
4. **Ações**: um primário que muda com o estado: **Criar display** → **Desconectar** (destrutivo). Secundário fantasma: Ajustes….
5. **Diagnóstico**: recolhido, `mono`.

**Ajustes** (janela separada, grupos): Display (resolução, HiDPI, taxa 60/120 Hz como Segmented, posição, alinhamento) · Toque e S Pen (um dedo, ⌘ no teclado do tablet, permissão de Acessibilidade) · Captura (cursor, downscale) · Energia (codificador) · Aparência (Claro / Escuro / Black espacial / Sistema) · Avançado (adb, porta, prévia de debug).

### Pareamento
Sheet presa à janela (não NSAlert solto): ícone A, “Parear com Galaxy Tab S11?”, PairingCode em dois grupos, “O tablet mostra o mesmo código? Pareie só tablets seus.”, **Não parear** / **Parear**. Ao parear: faísca, sheet fecha, cometa.

## Tablet (Android)

### Início
- **Procurando**: monograma + “Procurando seu Mac” + radar orbitando. Chips de método: Wi‑Fi · Cabo USB · Sem roteador.
- **Mac encontrado**: DeviceRow “MacBook Pro do Kelvin” com **Conectar** (primeira vez) ou **Reconectar** (pareado).
- **Pareando**: “Confirme no Mac” + PairingCode + status Aguardando o Mac.
- **Cabo USB**: o diálogo do Android (“Abrir Ginga para ‘Segunda tela para seu Mac’?” + Sempre) é o único passo.
- **Conectado/Pausado**: `display` “Conectado” ou “Pausado”, explicação curta (“Nada do Mac está nesta tela, então ele parou de enviar.”), **Mostrar tela** (primário) e **Desconectar**.

### Stream
- Antes do primeiro quadro: céu `cosmos` com o **buraco negro em dithering** (DitherSpace) centralizado, “Transmitindo de MacBook Pro do Kelvin” em `stardust` e status Conectando…. Tocar no horizonte explode as partículas (microinteração). Quando chega o primeiro quadro: warp e o stream.
- Conexão direta (sem roteador): tela própria com a **galáxia em dithering** girando, o nome da rede em `mono`/`star` (“DIRECT‑Ginga‑4F2A”), “O Mac está entrando na órbita deste tablet.” e **Encerrar**.
- Primeiro quadro: toast StatusOrbit “Conectado · 60 Hz · Wi‑Fi” por 3 s e some. Overlay de diagnóstico só se ligado em Ajustes.
- No Black espacial (tema só dos apps), a espera do stream e toda moldura são `#000` em vez de `cosmos`.

### Ajustes
Reconectar automaticamente (toggle) · Taxa preferida (Segmented: Mac decide / 60 Hz / 120 Hz) · Decodificação rápida (toggle, “usa mais bateria”) · Aparência (Claro / Escuro / Black espacial / Sistema) · Diagnóstico (toggle) · Avançado (instruções adb).

## Mapa do fluxo de conexão

| Passo | Mac | Tablet | Movimento |
|---|---|---|---|
| 1 Ligar | Toggle Wi‑Fi ou USB | Radar procurando | Faísca no toggle; órbita no status |
| 2 Encontrar | “Anunciando na rede” | DeviceRow entra subindo | `g-rise` 420ms |
| 3 Parear (1ª vez) | Sheet com código | Mesmo código | Dígitos surgem como estrelas |
| 4 Estender | Status Conectado, tablet na lista, primário vira Desconectar | Warp → área de trabalho estendida | Cometa (Wi‑Fi) ou pulso no cabo (USB), anel no tablet, tablet encaixa |
| Sem roteador | Sheet explica que o Mac sai do Wi‑Fi | Galáxia em dithering + nome da rede | Galáxia girando devagar |
| Pausado | Status Pausado | “Pausado” + Mostrar tela | Órbita para |
| Erro | Ponto `danger` + causa + ação | Mesmo texto | Sem animação |
