Ginga transforma um Galaxy Tab em segunda tela do Mac. O nome carrega as duas leituras da marca: 銀河, *galáxia* em japonês, e a *ginga* da capoeira. A interface inteira segue essa ideia: um céu calmo e escuro, um tablet levemente inclinado fora do eixo, e movimentos que passam um pouco do ponto e voltam, como um balanço.

**Tab2Mac** continua sendo o nome interno (módulos, `t2m`, logs, bundle id). Nenhuma tela mostra “Tab2Mac”.

## Conteúdo e voz

- Português do Brasil primeiro, inglês como segunda língua. Frases curtas, voz ativa, “você” implícito: “Ligue o Ginga no Mac.”, não “O usuário deve habilitar…”.
- Botões são verbos no infinitivo: **Criar display**, **Conectar**, **Parear**, **Não parear**, **Esquecer**, **Desconectar**.
- Estados dizem o que está acontecendo, não o mecanismo: “Anunciando na rede”, “Aguardando código”, “Conectado · 60 Hz”, “Pausado: nada na tela do tablet”. Detalhe técnico (`adb reverse tcp:47800 tcp:47800`, portas, codec) fica recolhido em Avançado ou Diagnóstico.
- Números e specs sempre em `mono`: `2560×1600`, `60 Hz`, `482 913`. Use “×”, não “x”.
- “Galaxy”, “Samsung”, “Mac” e “Sidecar” são marcas de terceiros: só uso descritivo (“para Mac”, “funciona com Galaxy Tab”), nunca no nome nem no logo.
- Sem emoji na interface. A única “ilustração” é a estrela de quatro pontas.

## Fundamentos visuais

**Temas.** Os apps têm três, escolhidos pela pessoa (Claro / Escuro / Black espacial) ou seguindo o sistema. O site usa só Claro e Escuro, com as telas de marca em `cosmos`:
- **Claro**: `bg` Névoa, `surface` branco, texto `ink` Noite.
- **Escuro**: `bg` Noite, `surface` Superfície escura, primária Cobalto noturno.
- **Black espacial** (só na UI interna dos apps, Mac e Android; nunca no site): preto puro predominante para telas AMOLED e mini‑LED (pixels apagados, zonas desligadas, menos energia e contraste infinito). `bg` é `#000` e toma o lugar de `cosmos` nas telas de marca dos apps; tudo que é área (`bg`, `surface`, `surface-2`, fundo do stream) é #000000 exato; cartões e controles existem só pelo contorno `line` de 1px e pelo brilho `glow-cobalt`, sem nenhum cinza‑escuro; detalhes espaciais pequenos: poeira de estrelas no canto de cada grupo, halo no toggle ligado e no status, código de pareamento com leve brilho. Nunca fundos grandes em cinza: se não for preto, é pequeno.

**Cor.** Use `cobalt` para a única ação principal da tela, toggles ligados, links e o anel de foco; texto sobre ele em `on-cobalt`. `star` é só a estrela e faíscas, nunca texto. Estados: `success`, `warning`, `danger` aparecem como ponto ou ícone ao lado de texto em `ink` (no tema claro, success e warning ficam abaixo de 4.5:1 como texto). `cobalt-brand` é fixo e pinta a placa do ícone e o cometa. Fique longe do azul da Samsung (`#1428A0`) e de degradês à la Apple: a marca não pode parecer afiliada a nenhuma das duas.

**Tipo.** `display` e `title` em Unbounded, só SemiBold (600) ou ExtraBold (800), e só em títulos de tela, estados grandes e marca. Todo o resto em Figtree (`headline`, `body`, `label`, `caption`). Números, specs e códigos em IBM Plex Mono (`mono`, `code-digits`). No Mac, a UI nativa pode seguir com SF Pro e usar Unbounded só no título da janela e na marca.

**Espaço e forma.** Grade de 4px: `space-3`/`space-4` dentro das linhas, `space-6` entre grupos, `space-8` de margem. Cantos: `radius-md` em botões e campos, `radius-lg` em grupos, `radius-xl` em sheets e alertas, `radius-pill` em toggles, status e botões do tablet (toque de 44px).

**Profundidade.** Claro: `shadow-card` suave. Escuro: borda de luz no topo. Black espacial: sem sombra, só contorno e brilho. Alertas e sheets usam `shadow-float` sobre um véu `cosmos` a 40%.

**Foco.** Anel sólido de 2px em `cobalt`, afastado 2px, em todo controle focável. Passa de 3:1 em todas as superfícies dos três temas.

## Movimento e microinterações

O movimento é o “espacial” da marca, e é barato: só `transform` e `opacity`, um único canvas para o céu, nada animando fora da tela.

- **Balanço** (`ease-ginga`): toggles, dígitos surgindo, o tablet encaixando. Passa ~6% do ponto e volta.
- **Toque**: tudo que é clicável encolhe para 0.97 em `dur-tap`.
- **Faísca**: ao *ligar* um toggle ou confirmar uma ação principal, sete pontinhos `star` saem do centro (`Ginga.spark`). Nunca ao desligar.
- **Órbita**: status “Procurando” e o radar do tablet giram em `dur-orbit`, `ease-orbit`.
- **Cometa**: ao conectar por Wi‑Fi, uma cauda `star` atravessa de Mac para tablet em `dur-warp`, termina num anel que se expande e o tablet entra em *warp* (estrelas esticando) até o primeiro quadro.
- **Cabo**: por USB, um pulso `cobalt` corre pelo cabo no lugar do cometa.
- **Céu**: `Ginga.starfield` (suave) ou `Ginga.pixelSky` (em pixels) em telas de marca apenas.
- **Dithering espacial**: buraco negro e galáxia em pixels de 4 px, Bayer 4×4, só nas 6 cores da paleta (componente DitherSpace). Buraco negro na espera do stream e no topo do site (colapsa com o ponteiro, explode no clique); galáxia na conexão sem roteador e na faixa de download. Nunca atrás de texto corrido.
- **Movimento reduzido**: sem órbitas, cometa, warp ou faíscas; estados trocam por fade de 1ms. Toda animação precisa ter um equivalente estático que diga a mesma coisa em texto.

## Iconografia

- **A · Órbita** (contorno de tela, tablet inclinado, estrela) é o **ícone dos apps** no Mac e no Android, favicon e lojas: `ginga-app-icon.png` (placa `cobalt-brand`), `ginga-orbit.png` / `ginga-orbit-dark.png` sem placa.
- **B · Monograma “g”** (bojo em forma de tela, cauda de S Pen) é **detalhe**: cabeçalho da janela e da home do tablet, marcadores, loading, avatares. Não é ícone de app.
- **C · Logotipo** (“ginga” em Unbounded ExtraBold, o tablet como pingo do i) é **a marca no site**: header, footer, hero.
- Use as versões `-dark` em fundos mais escuros que `#6F82FF` (temas Escuro e Black espacial e todo fundo `cosmos`).
- Área de respiro: A e B, a largura da estrela de cada lado; C, a altura do pingo‑tablet. Mínimos: A 16px, B 20px, C 80px de largura.
- Não endireite o tablet, não recolora a estrela, não aplique sombra ou degradê, não escreva “ginga” em outra fonte.
- Ícones de interface: traço de 1.5px, cantos arredondados, desenhados no grid de 16px, na cor do texto ou `cobalt` dentro de `g-row__icon`. No Mac, SF Symbols equivalentes são aceitos. A barra de menus usa o mark A em modelo (template) monocromático.

## Os apps

Veja a seção **Fluxos de UI/UX** para as telas de cada app e o componente **ConnectDemo** para a demo clicável (Mac + tablet) com a animação de conexão.
