# Ginga: handoff do design system para implementação

Este pasta é a fonte de verdade da nova UI do Ginga (nome interno Tab2Mac). Leia nesta ordem antes de mudar qualquer código:

1. `brand-book.md`: voz, cores, tipo, temas, movimento, iconografia. Regras obrigatórias.
2. `flows.md`: a nova estrutura de telas do Mac e do Android, estado por estado.
3. `components/*.md`: cada componente (o que é, quando usar, estados, microinteração).
4. `tokens.json`: valores exatos. Não invente cor, raio, espaçamento ou duração fora dele.
5. `reference/demo-conexao.html`: abra no navegador. É a referência viva de layout, estados e animações (cometa, warp, faíscas, órbitas). `reference/bundle.css` e `bundle.js` mostram cada microinteração em código.

## Arquivos prontos para copiar

| Arquivo | Destino sugerido |
|---|---|
| `platform/apple/GingaTheme.swift` | `mac/Sources/Tab2MacApp/Design/` |
| `platform/android/values/ginga_colors.xml`, `ginga_dimens.xml` | `android/app/src/main/res/values/` |
| `logos/ginga-app-icon.png` e demais | ícone do app já existe via `brand/`; use `ginga-monogram*.png` no cabeçalho das telas (ou os SVGs de `brand/`, preferíveis) |

## Temas

Três aparências nos **apps** (Mac e Android): Claro, Escuro, **Black espacial**, mais “Sistema”. O site usa só Claro e Escuro.

**Black espacial é preto puro `#000000`** em tudo que é área: fundo, cartões, trilhos, fundo do stream, janelas e sheets. Nenhum cinza‑escuro. Cartões e controles aparecem só por contorno de 1px na cor `line` e pelo brilho `glow-cobalt`. O único tom não preto permitido em área é `cobalt-soft`, e só em elementos pequenos (segmento ativo, chip). É para AMOLED e mini‑LED: pixel preto = pixel apagado.

- Mac: `@AppStorage("appearance")` com `GingaAppearance`; `.system` segue `colorScheme`; `.space` força `.preferredColorScheme(.dark)` e usa `GingaPalette.space`. Injete a paleta via `EnvironmentValues`.
- Android: `Theme.Ginga.Light`, `Theme.Ginga.Dark`, `Theme.Ginga.Space` (parent Material3 DayNight NoActionBar), atributos de cor apontando para `ginga_*_light|dark|space`. Troca em runtime com `recreate()`. Em Space, `android:windowBackground`, `statusBarColor` e `navigationBarColor` = `#000000`.

## Tipografia

Unbounded (600/800) só em títulos e marca; Figtree no texto; IBM Plex Mono em números, specs e o código de pareamento. Android: fontes em `res/font/` (todas SIL OFL, baixe do Google Fonts). Mac: SF Pro na UI nativa é aceito; Unbounded só no título “Ginga” e na marca.

## Movimento (obrigatório respeitar)

- `ease-ginga` = cubic‑bezier(0.34, 1.36, 0.64, 1) para toggles, dígitos, encaixes. Pressionar = escala 0.97 em 120 ms.
- Faísca de 7 pontos `star` ao **ligar** um toggle ou confirmar ação principal.
- Status “Procurando”: arco girando; Conectado: pulso. Pausado/Erro: parado.
- Conexão Wi‑Fi: cometa Mac → tablet (1.4 s) e warp no tablet até o primeiro quadro. USB: pulso pelo cabo.
- Só `transform`/`opacity` (Android: `ViewPropertyAnimator`/`animate()`, Canvas em uma View para o céu; Mac: `withAnimation`, `TimelineView` só enquanto visível). Pare tudo fora da tela.
- Movimento reduzido (Mac: `accessibilityReduceMotion`; Android: `Settings.Global.ANIMATOR_DURATION_SCALE == 0`) desliga cometa, warp, faíscas e órbitas.

## Ordem de trabalho sugerida

1. Tokens e temas nos dois apps (incluindo seletor de Aparência nos Ajustes), sem mudar layout. Verificar os três temas.
2. Mac: nova janela principal (Status, Conexão, Tablets, Ações, Diagnóstico recolhido) + janela de Ajustes + sheet de pareamento, conforme `flows.md`. Menu da barra por estado.
3. Android: nova tela inicial por estados (Procurando, Mac encontrado, Pareando, USB, Conectado/Pausado), Ajustes com Segmented, tela de stream com céu e toast.
4. Microinterações e animações de conexão.
5. Textos em pt‑BR (strings em recursos, com inglês como segunda língua).

Não altere protocolo, pareamento TLS, captura, codificação ou nomes internos (`t2m`, bundle id): isto é só a camada de UI. Mostre o plano antes de mudanças grandes e faça em commits pequenos por etapa.
