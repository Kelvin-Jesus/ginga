import React from "react";
/* Gerado de GingaSite.dc.html (protótipo do editor de design) por tools/dc2jsx.py. */

export default class GingaSite extends React.Component {
  constructor(props) {
    super(props);
    this.state = { lang: props.lang || "pt", theme: "dark", phase: "off", via: null, paired: false, wifi: false, usb: false,
      screen: "search", sheet: false, docked: false, live: false, macNotesAway: false, tabNotesIn: false, toast: false,
      route: false, story: "s1", rail: 1, hint: { k: "wifi", t: "hWifi", up: false }, scale: 1, left: 0, px: 0, py: 0, wrapW: 1200, mobile: false };
    this.r = {}; this.refFns = {}; this.timers = [];
  }
  dict() {
    if (!this._T) this._T = {
  pt: {
    vidEy: "Veja funcionando", vidH: "O Ginga em 30 segundos", vidAlt: "Vídeo de 30 segundos: o Mac aceita tablets por Wi‑Fi, o Galaxy Tab pareia com um código de 6 dígitos, o sinal chega como um cometa, uma janela passa para o tablet e a S Pen escreve nela.", vidTag: "demo · 30 s",
    docTitle: "Ginga — seu Galaxy Tab vira tela do Mac", metaDesc: "Ginga transforma um Galaxy Tab em display estendido do Mac com toque e S Pen. USB direto a 120 fps, Wi‑Fi ou sem roteador. Grátis e de código aberto.", navSec: "Segurança",
    hDrag: "Arraste a janela para o tablet", hPen: "Toque para desenhar com a S Pen",
    secEy: "Segurança e privacidade", secH: "Seu Mac, seu tablet, e mais ninguém no meio", secP: "O Ginga pede permissões sensíveis no Mac, então aqui está exatamente o que ele faz com elas.",
    sec1h: "Fica na sua rede", sec1: "Mac e tablet falam direto: pelo cabo, pelo Wi‑Fi da sua casa ou pela rede do próprio tablet. Sem servidor no meio e sem conta.",
    sec2h: "Criptografado", sec2: "O Wi‑Fi usa TLS 1.3 com o certificado de cada lado fixado. Pelo USB direto, só tablets que você aprovou abrem uma sessão.",
    sec3h: "Pareamento por código", sec3: "Na primeira vez, as duas telas mostram os mesmos 6 dígitos. Só pareie tablets seus; “Esquecer” remove o acesso na hora.",
    sec4h: "Código aberto", sec4: "Todo o código do Mac e do Android está no GitHub. Qualquer pessoa pode ler, auditar e compilar.",
    perm1h: "Gravação de Tela", perm1: "O macOS pede essa permissão para o Ginga capturar o display virtual que ele cria para o tablet. É o que vai para a tela do tablet.",
    perm2h: "Acessibilidade", perm2: "Necessária para que o toque e a S Pen no tablet movam o cursor e cliquem no Mac. Sem ela, o tablet só mostra a imagem.",
    cpEy: "Compatibilidade", cpH: "Funciona com o que você tem?", cpTab: "Tablets", cpTested: "testado", cpCheck: "a confirmar", cpReq: "requisito", cpConn: "conexão",
    cpOtherTabs: "Galaxy Tab S9 FE+, Galaxy S25 Ultra e outros Android", cpOtherTabsP: "Já têm perfil de tela e o app se ajusta ao painel informado pelo aparelho, mas ainda não foram testados neles.",
    cpAndroidP: "O app do tablet é um APK no GitHub. Pelo USB direto não precisa de modo desenvolvedor.",
    cpMacP: "Testado no macOS 26.6.2. O Ginga confere a cada versão se o display virtual continua disponível e avisa em vez de travar.",
    cpChipP: "Macs com Intel não são suportados: a codificação em hardware e o display virtual usados dependem do Apple Silicon.",
    cpConnH: "USB‑C, Wi‑Fi ou sem roteador", cpConnP: "Cabo USB com dados, a mesma rede Wi‑Fi, ou a rede Wi‑Fi criada pelo próprio tablet.",
    faqH: "Perguntas frequentes",
    faq: [
      ["Funciona com qualquer tablet Android?", "O Ginga foi feito e testado no Galaxy Tab S11 (2560×1600, até 120 Hz). O app se ajusta ao painel de outros aparelhos com Android 12 ou mais novo, e o Tab S9 FE+ e o S25 Ultra já têm perfil, mas ainda não foram testados neles."],
      ["Preciso ativar o modo desenvolvedor?", "Não. Pelo USB direto, o Android só pergunta uma vez se pode abrir o Ginga; marque “Sempre”. O caminho com adb continua disponível em Avançado para quem prefere."],
      ["Funciona sem internet?", "Sim. Pelo cabo, pela rede Wi‑Fi local, ou pela conexão direta, em que o tablet cria a própria rede e o Mac entra nela. Enquanto isso o Mac fica fora do Wi‑Fi de antes, a menos que tenha cabo de rede."],
      ["O toque e a S Pen funcionam?", "Sim. O toque clica, arrasta e rola com dois dedos. A S Pen vira uma mesa digitalizadora para o macOS, com pressão, inclinação, borracha e proximidade, como a Apple Pencil no Sidecar. O macOS pede a permissão de Acessibilidade para isso."],
      ["Gasta muita bateria?", "Pouco. Medido no Mac: um display de 60 Hz com animação contínua acrescenta cerca de 230 mW, e uma área de trabalho parada acrescenta quase zero, porque nada é capturado nem enviado quando a tela não muda."],
      ["Qual o melhor jeito de conectar?", "O USB direto: 120 fps a 120 Hz, sem quadros perdidos e cerca de 13 ms de ponta a ponta. O Wi‑Fi (60 fps) dá liberdade de levar o tablet pela casa. A conexão direta é para hotel, trem ou lugares sem roteador."],
      ["Por que o Mac pede Gravação de Tela?", "Porque o Ginga cria um display virtual e captura só ele para enviar ao tablet. A partir do macOS 15, o sistema pede para reconfirmar essa permissão todo mês. Conteúdo com DRM aparece preto, e nada é capturado na tela de bloqueio."],
      ["Quanto custa?", "Nada. O Ginga é software livre (AGPL‑3.0) e o download é pelo GitHub. Ele usa uma API privada do macOS para criar o display, então não pode estar na Mac App Store."],
      ["E Linux e Windows?", "Linux está nos próximos passos. Para Windows, a própria Samsung já oferece o Second Screen, então o foco do Ginga é quem usa Mac e, em breve, Linux."]
    ],
    ossEy: "Código aberto", ossH: "Aberto de ponta a ponta", ossBoxH: "100% do código no GitHub", ossBoxP: "Os apps do Mac (Swift 6) e do Android (Kotlin) e o protocolo estão no mesmo repositório, sob a licença AGPL‑3.0. Leia, compile, abra uma issue ou mande um pull request.",
    ossCode: "Ver o código", ossContrib: "Contribuir",
    roadH: "Próximos passos", roadP: "O que vem por aí. Dá para acompanhar tudo pelas issues.", soon: "em breve",
    roadLinux: "Um host para Linux com o mesmo protocolo e o mesmo app no tablet: X11 primeiro, depois Wayland.",
    roadMultiH: "Vários tablets", roadMulti: "Mais de um tablet ao mesmo tempo, um display para cada.", roadSignH: "App assinado e notarizado", roadSign: "Distribuição com Developer ID, para abrir sem avisos do macOS.",
    roadIdeaH: "Sua ideia", roadIdea: "Falta algo?", roadIdeaLink: "Abra uma issue",
    auEy: "Quem fez", auH: "Feito por um estudante de Engenharia de Software",
    auP: "O Ginga é um projeto independente do Kelvin Jesus, estudante de Engenharia de Software. Nasceu de uma vontade simples: usar o Galaxy Tab como segunda tela do MacBook, sem assinatura e sem modo desenvolvedor. Cada linha do código está aberta para quem quiser aprender com ela ou melhorá-la.",
    auSig: "Kelvin Jesus · Engenharia de Software",
    navLabel: "Principal", navHow: "Como conectar", navFeat: "Recursos", navDl: "Baixar", navCmp: "Comparar", langLabel: "Idioma", themeLabel: "Tema", light: "Tema claro", dark: "Tema escuro",
    kicker: "Segunda tela para Mac", bhCap: "passe o mouse · clique no horizonte", blast: "Disparar o buraco negro",
    h1: "Seu Galaxy Tab vira tela do Mac.",
    lead: "Arraste janelas, toque na tela e desenhe com a S Pen: o Ginga transforma o tablet num display estendido de verdade. Por cabo USB sem modo desenvolvedor, por Wi‑Fi ou sem roteador.",
    ctaMac: "Baixar para Mac", ctaAnd: "Baixar para Android",
    tryA: "Experimente aqui embaixo:", tryB: "toque ou clique na tela do Mac e conecte o tablet.",
    reset: "Recomeçar", r1: "Ligar no Mac", r2: "Encontrar", r3: "Parear", r4: "Estender",
    mFile: "Arquivo", mEdit: "Editar", mView: "Ver", clock: "sáb. 20:20", notes: "Notas — Cálculo II",
    gConn: "Conexão", rWifi: "Aceitar tablets por Wi‑Fi", rUsb: "Aceitar tablet por USB", rUsbSub: "Sem modo desenvolvedor",
    gTabs: "Tablets", noTabs: "Nenhum tablet pareado ainda.", forget: "Esquecer", settings: "Ajustes…", create: "Criar display", disconnect: "Desconectar",
    metaWifi: "Wi‑Fi · TLS · 2560×1600", metaUsb: "USB direto · 2560×1600", metaAway: "pareado · fora de alcance",
    pairQ: "Parear com Galaxy Tab S11?", pairP: "O tablet mostra o mesmo código? Pareie só tablets seus.", noPair: "Não parear", doPair: "Parear",
    stOff: "Desligado", stAdv: "Anunciando na rede", stPair: "Aguardando código", stConn: "Conectando…", stOk: "Conectado · 60 Hz", stCable: "Esperando o cabo", stApprove: "Tablet aprovando",
    tSearch: "Procurando seu Mac", tSearchP: "Ligue o Ginga no Mac. Ele aparece aqui.", chipUsb: "Cabo USB", chipDirect: "Sem roteador",
    tFound: "Mac por perto", tFoundP: "Toque para usar este tablet como segunda tela.", fNew: "não pareado · Wi‑Fi", fPaired: "pareado · Wi‑Fi", connect: "Conectar", reconnect: "Reconectar",
    tConfirm: "Confirme no Mac", tWaitMac: "Aguardando o Mac",
    tCable: "Cabo conectado", tCableP: "O Mac pediu para virar display.", dlgQ: "Abrir Ginga para “Segunda tela para seu Mac”?", dlgP: "Nenhuma depuração USB necessária.", dlgAlways: "Sempre, para este acessório", cancel: "Cancelar", open: "Abrir",
    hWifi: "Ligue o Wi‑Fi", hConnect: "Toque em Conectar", hRe: "Reconectar", hPair: "Os códigos batem? Parear", hOpen: "Toque em Abrir", hDisc: "Desconectar e tentar de novo",
    altUsb: "Prefiro o cabo USB",
    story: {
      s1: { k: "Passo 1 de 4 · Mac", h: "Ligue o Ginga no Mac", p: "Ative “Aceitar tablets por Wi‑Fi”. O Mac começa a se anunciar na rede e o tablet, que já está procurando, o encontra sozinho." },
      s2: { k: "Passo 2 de 4 · Tablet", h: "O tablet encontra o Mac", p: "Em segundos o Mac aparece na lista do tablet. Nada de IP, porta ou adb." },
      s3: { k: "Passo 3 de 4 · Os dois", h: "Os mesmos 6 dígitos nas duas telas", p: "Na primeira vez os dois mostram o mesmo código. Se bater, é o seu tablet. A conexão é criptografada com TLS e o par fica salvo." },
      s4w: { k: "Passo 4 de 4 · Conexão", h: "Mac e tablet entram em órbita", p: "O Mac cria o display virtual e o sinal atravessa a rede como um cometa até o tablet." },
      s4u: { k: "Passo 4 de 4 · Conexão", h: "Mac e tablet entram em órbita", p: "Pelo cabo o sinal viaja direto: o Android abre o Ginga como acessório, sem modo desenvolvedor." },
      s5: { k: "Conectado", h: "Seu tablet agora é tela do Mac", p: "Arraste janelas para a direita e elas continuam no tablet. Quando nada aparece nele, o Mac para de enviar quadros e poupa bateria." },
      s7: { k: "Estender", h: "Arraste uma janela para a direita", p: "O tablet agora é um monitor à direita do Mac. Arraste a janela de Notas até a borda e ela continua na tela do tablet." },
      s8: { k: "Toque e S Pen", h: "Desenhe direto no tablet", p: "O toque e a S Pen controlam o Mac. Toque na janela no tablet para desenhar com a caneta." },
      s6: { k: "Pareado", h: "Da próxima vez, sem código", p: "O tablet já é conhecido. Toque em Reconectar: o cometa sai direto, sem pedir os 6 dígitos de novo." },
      su: { k: "Cabo USB", h: "Plugue o cabo", p: "Com o USB direto, o Android pergunta uma vez se abre o Ginga. Marque “Sempre” e da próxima vez a tela abre sozinha." }
    },
    howEy: "Como conectar", howH: "Três jeitos de entrar em órbita", howP: "Use o que tiver à mão. O Ginga escolhe sozinho da próxima vez.",
    w1: "Pareie uma vez comparando um código de 6 dígitos nas duas telas. Depois o tablet reconecta sozinho, com tudo criptografado.", w1t: "TLS · pareamento por código",
    w2h: "Cabo USB", w2: "Plugue e pronto: o Android abre o Ginga como acessório. Sem depuração USB, sem adb, sem modo desenvolvedor.", w2t: "120 fps · ~13 ms",
    w3h: "Sem roteador", w3: "No hotel, no trem ou sem internet: o tablet cria a própria rede Wi‑Fi e o Mac entra nela. Ao terminar, o Mac volta para a sua rede.", w3t: "conexão direta",
    featEy: "Recursos", featH: "Feito para parecer que sempre esteve ali",
    f1: "Escolha fluidez ou bateria. 60 Hz gasta cerca de um terço da energia de 120 Hz para o mesmo stream de 60 fps.",
    f2h: "Toque e S Pen", f2: "O toque clica, arrasta e rola. A S Pen vira mesa digitalizadora para o macOS, com pressão, inclinação e borracha.",
    f3: "Pixel exato no painel do tablet, com HiDPI: parece 1280 × 800, nítido como uma tela Retina.",
    f4h: "Poupa energia", f4: "Área de trabalho parada: quase zero de consumo extra. Nada é capturado ou enviado quando a tela não muda.",
    f5h: "Teclado do tablet", f5: "Escolha qual tecla vira ⌘: a tecla Samsung ou Ctrl. Atalhos do Mac funcionam no teclado da capa.",
    f6h: "Como um monitor de verdade", f6: "Posicione o tablet à esquerda, à direita, acima ou abaixo nos Ajustes de Telas do macOS, em paisagem ou retrato.",
    cmpEy: "Comparar", cmpH: "Galaxy Tab + Mac: quem faz o quê", cmpP: "A maioria das opções de “tablet como segunda tela” foi feita para Windows ou para iPad. Veja o que funciona quando o computador é um Mac e o tablet é um Galaxy.",
    cmpCol: "Mac + tablet Galaxy", cmpByUs: "este app", cmpOpen: "código aberto", cmpSwipe: "Arraste a tabela para o lado →", yes: "Sim", no: "Não", part: "Em parte",
    cmp: [
      ["Estende um Mac atual", ["y", "macOS com display virtual"], ["y", "macOS 10.14 ou mais novo"], ["y"], ["n", "só Windows 10 ou mais novo"], ["y"], ["n", "só Windows"]],
      ["Funciona com tablet Galaxy / Android", ["y", "feito para Galaxy Tab"], ["y", "Android 7 ou mais novo"], ["y", "pelo navegador"], ["y", "Galaxy Tab S7 ou mais novo"], ["n", "só iPad"], ["y"]],
      ["Tela estendida sem acessório extra", ["y"], ["y"], ["p", "estender pede um adaptador de display virtual"], ["y"], ["y"], ["y"]],
      ["Por cabo USB", ["y", "sem modo desenvolvedor"], ["y"], ["n", "só Wi‑Fi local"], ["n", "só Wi‑Fi"], ["y"], ["y"]],
      ["Custo", ["t", "Grátis · AGPL‑3.0"], ["t", "Pago, compras no app"], ["t", "Grátis"], ["t", "Incluso no Galaxy Tab"], ["t", "Incluso no macOS"], ["t", "Grátis para uso pessoal"]]
    ],
    cmpFoot: "Informações das páginas oficiais e das lojas de apps em setembro de 2026; podem mudar. Duet Display, Deskreen, Second Screen, Sidecar e spacedesk são marcas de seus donos e aparecem aqui só para comparação.",
    stEy: "Começar", stH: "Em órbita em três passos",
    s1h: "Baixe os dois apps", s1: "O app do Mac e o APK do Android estão na página de releases do GitHub.",
    s2h: "Ligue no Mac", s2: "Abra o Ginga e ative Wi‑Fi ou USB no painel.",
    s3h: "Conecte no tablet", s3: "Toque em Conectar e confira o código. Pronto.",
    dlH: "Pronto para decolar?", dlP: "Baixe o Ginga para o Mac e para o tablet no GitHub.", req: "Mac com Apple Silicon e macOS 14+ · Android 12+ · grátis, AGPL‑3.0",
    iconAlt: "Ícone do Ginga",
    legal: "Galaxy e Samsung são marcas da Samsung Electronics. Mac, macOS e Sidecar são marcas da Apple Inc. O Ginga funciona com esses produtos e não é afiliado a nenhuma das duas empresas."
  },
  en: {
    vidEy: "See it work", vidH: "Ginga in 30 seconds", vidAlt: "30-second video: the Mac accepts tablets over Wi‑Fi, the Galaxy Tab pairs with a 6-digit code, the signal arrives as a comet, a window moves onto the tablet and the S Pen writes on it.", vidTag: "demo · 30 s",
    docTitle: "Ginga — your Galaxy Tab becomes a Mac display", metaDesc: "Ginga turns a Galaxy Tab into an extended Mac display with touch and S Pen. Direct USB at 120 fps, Wi‑Fi or no router. Free and open source.", navSec: "Security",
    hDrag: "Drag the window to the tablet", hPen: "Tap to draw with the S Pen",
    secEy: "Security and privacy", secH: "Your Mac, your tablet, and nobody in between", secP: "Ginga asks for sensitive permissions on the Mac, so here is exactly what it does with them.",
    sec1h: "Stays on your network", sec1: "Mac and tablet talk directly: over the cable, your home Wi‑Fi or the tablet’s own network. No server in the middle and no account.",
    sec2h: "Encrypted", sec2: "Wi‑Fi uses TLS 1.3 with each side’s certificate pinned. Over direct USB, only tablets you approved get a session.",
    sec3h: "Code pairing", sec3: "The first time, both screens show the same 6 digits. Only pair tablets you own; “Forget” revokes access instantly.",
    sec4h: "Open source", sec4: "All the Mac and Android code is on GitHub. Anyone can read, audit and build it.",
    perm1h: "Screen Recording", perm1: "macOS asks for this so Ginga can capture the virtual display it creates for the tablet. That is what goes to the tablet’s screen.",
    perm2h: "Accessibility", perm2: "Needed so touch and the S Pen on the tablet can move the cursor and click on the Mac. Without it, the tablet only shows the picture.",
    cpEy: "Compatibility", cpH: "Does it work with what you have?", cpTab: "Tablets", cpTested: "tested", cpCheck: "to confirm", cpReq: "required", cpConn: "connection",
    cpOtherTabs: "Galaxy Tab S9 FE+, Galaxy S25 Ultra and other Androids", cpOtherTabsP: "They already have display profiles and the app adapts to the panel the device reports, but they haven’t been tested yet.",
    cpAndroidP: "The tablet app is an APK on GitHub. Over direct USB, no developer mode needed.",
    cpMacP: "Tested on macOS 26.6.2. Ginga checks on every version that the virtual display is still available and tells you instead of crashing.",
    cpChipP: "Intel Macs are not supported: the hardware encoding and virtual display Ginga uses depend on Apple Silicon.",
    cpConnH: "USB‑C, Wi‑Fi or no router", cpConnP: "A USB data cable, the same Wi‑Fi network, or the Wi‑Fi network the tablet creates itself.",
    faqH: "Frequently asked questions",
    faq: [
      ["Does it work with any Android tablet?", "Ginga was built and tested on the Galaxy Tab S11 (2560×1600, up to 120 Hz). The app adapts to the panel of other devices with Android 12 or later, and the Tab S9 FE+ and S25 Ultra already have profiles, but they haven’t been tested yet."],
      ["Do I need developer mode?", "No. Over direct USB, Android asks once whether to open Ginga; tick “Always”. The adb path is still available under Advanced if you prefer it."],
      ["Does it work without internet?", "Yes. Over the cable, the local Wi‑Fi, or the direct connection, where the tablet creates its own network and the Mac joins it. Meanwhile the Mac is off its previous Wi‑Fi unless it also has Ethernet."],
      ["Do touch and the S Pen work?", "Yes. Touch clicks, drags and scrolls with two fingers. The S Pen becomes a pen tablet for macOS, with pressure, tilt, eraser and hover, like the Apple Pencil with Sidecar. macOS asks for the Accessibility permission for this."],
      ["Does it drain the battery?", "Barely. Measured on the Mac: a 60 Hz display with continuous animation adds about 230 mW, and a still desktop adds close to zero, because nothing is captured or sent while the screen doesn’t change."],
      ["What’s the best way to connect?", "Direct USB: 120 fps at 120 Hz, no dropped frames and about 13 ms end to end. Wi‑Fi (60 fps) lets you carry the tablet around. The direct connection is for hotels, trains or places with no router."],
      ["Why does the Mac ask for Screen Recording?", "Because Ginga creates a virtual display and captures only that one to send it to the tablet. Since macOS 15 the system asks you to reconfirm this permission monthly. DRM content shows black, and nothing is captured at the lock screen."],
      ["How much does it cost?", "Nothing. Ginga is free software (AGPL‑3.0), downloaded from GitHub. It uses a private macOS API to create the display, so it can’t be on the Mac App Store."],
      ["What about Linux and Windows?", "Linux is next on the roadmap. For Windows, Samsung already offers Second Screen, so Ginga focuses on Mac users and, soon, Linux."]
    ],
    ossEy: "Open source", ossH: "Open from end to end", ossBoxH: "100% of the code on GitHub", ossBoxP: "The Mac (Swift 6) and Android (Kotlin) apps and the protocol live in one repository under the AGPL‑3.0. Read it, build it, open an issue or send a pull request.",
    ossCode: "See the code", ossContrib: "Contribute",
    roadH: "What’s next", roadP: "What’s coming. You can follow everything in the issues.", soon: "soon",
    roadLinux: "A Linux host with the same protocol and the same tablet app: X11 first, then Wayland.",
    roadMultiH: "Several tablets", roadMulti: "More than one tablet at once, one display each.", roadSignH: "Signed and notarized app", roadSign: "Developer ID distribution, so it opens without macOS warnings.",
    roadIdeaH: "Your idea", roadIdea: "Something missing?", roadIdeaLink: "Open an issue",
    auEy: "Who made it", auH: "Made by a software engineering student",
    auP: "Ginga is an independent project by Kelvin Jesus, a software engineering student. It started from a simple wish: use a Galaxy Tab as a second screen for a MacBook, with no subscription and no developer mode. Every line of code is open for anyone who wants to learn from it or improve it.",
    auSig: "Kelvin Jesus · Software Engineering",
    navLabel: "Main", navHow: "How to connect", navFeat: "Features", navDl: "Download", navCmp: "Compare", langLabel: "Language", themeLabel: "Theme", light: "Light theme", dark: "Dark theme",
    kicker: "Second display for Mac", bhCap: "hover · click the horizon", blast: "Fire the black hole",
    h1: "Your Galaxy Tab becomes a Mac display.",
    lead: "Drag windows, touch the screen and draw with the S Pen: Ginga turns the tablet into a true extended display. Over USB with no developer mode, over Wi‑Fi, or with no router at all.",
    ctaMac: "Download for Mac", ctaAnd: "Download for Android",
    tryA: "Try it right below:", tryB: "tap or click the Mac’s screen and connect the tablet.",
    reset: "Start over", r1: "Turn on the Mac", r2: "Discover", r3: "Pair", r4: "Extend",
    mFile: "File", mEdit: "Edit", mView: "View", clock: "Sat 8:20 PM", notes: "Notes — Calculus II",
    gConn: "Connection", rWifi: "Accept tablets over Wi‑Fi", rUsb: "Accept a tablet over USB", rUsbSub: "No developer mode",
    gTabs: "Tablets", noTabs: "No paired tablets yet.", forget: "Forget", settings: "Settings…", create: "Create display", disconnect: "Disconnect",
    metaWifi: "Wi‑Fi · TLS · 2560×1600", metaUsb: "Direct USB · 2560×1600", metaAway: "paired · out of range",
    pairQ: "Pair with Galaxy Tab S11?", pairP: "Does the tablet show the same code? Only pair tablets you own.", noPair: "Don’t pair", doPair: "Pair",
    stOff: "Off", stAdv: "Advertising on the network", stPair: "Waiting for code", stConn: "Connecting…", stOk: "Connected · 60 Hz", stCable: "Waiting for the cable", stApprove: "Tablet approving",
    tSearch: "Looking for your Mac", tSearchP: "Turn on Ginga on the Mac. It shows up here.", chipUsb: "USB cable", chipDirect: "No router",
    tFound: "Mac nearby", tFoundP: "Tap to use this tablet as a second screen.", fNew: "not paired · Wi‑Fi", fPaired: "paired · Wi‑Fi", connect: "Connect", reconnect: "Reconnect",
    tConfirm: "Confirm on the Mac", tWaitMac: "Waiting for the Mac",
    tCable: "Cable connected", tCableP: "The Mac asked to become a display.", dlgQ: "Open Ginga for “Second display for your Mac”?", dlgP: "No USB debugging needed.", dlgAlways: "Always, for this accessory", cancel: "Cancel", open: "Open",
    hWifi: "Turn on Wi‑Fi", hConnect: "Tap Connect", hRe: "Reconnect", hPair: "Codes match? Pair", hOpen: "Tap Open", hDisc: "Disconnect and try again",
    altUsb: "I’d rather use USB",
    story: {
      s1: { k: "Step 1 of 4 · Mac", h: "Turn Ginga on", p: "Switch on “Accept tablets over Wi‑Fi”. The Mac starts advertising on the network and the tablet, already looking, finds it by itself." },
      s2: { k: "Step 2 of 4 · Tablet", h: "The tablet finds the Mac", p: "In seconds the Mac shows up on the tablet. No IP, port or adb." },
      s3: { k: "Step 3 of 4 · Both", h: "The same 6 digits on both screens", p: "The first time, both show the same code. If it matches, it’s your tablet. The connection is TLS‑encrypted and the pair is remembered." },
      s4w: { k: "Step 4 of 4 · Connection", h: "Mac and tablet enter orbit", p: "The Mac creates the virtual display and the signal crosses the network like a comet to the tablet." },
      s4u: { k: "Step 4 of 4 · Connection", h: "Mac and tablet enter orbit", p: "Over the cable the signal goes straight through: Android opens Ginga as an accessory, no developer mode." },
      s5: { k: "Connected", h: "Your tablet is now a Mac screen", p: "Drag windows to the right and they carry on onto the tablet. When nothing is on it, the Mac stops sending frames and saves battery." },
      s7: { k: "Extend", h: "Drag a window to the right", p: "The tablet is now a monitor to the right of the Mac. Drag the Notes window past the edge and it carries on onto the tablet." },
      s8: { k: "Touch and S Pen", h: "Draw right on the tablet", p: "Touch and the S Pen control the Mac. Tap the window on the tablet to draw with the pen." },
      s6: { k: "Paired", h: "Next time, no code", p: "The tablet is already known. Tap Reconnect: the comet flies straight away, no digits needed." },
      su: { k: "USB cable", h: "Plug in the cable", p: "With direct USB, Android asks once whether to open Ginga. Tick “Always” and next time the display opens by itself." }
    },
    howEy: "How to connect", howH: "Three ways into orbit", howP: "Use whatever you have. Ginga remembers next time.",
    w1: "Pair once by comparing a 6‑digit code on both screens. After that the tablet reconnects on its own, fully encrypted.", w1t: "TLS · code pairing",
    w2h: "USB cable", w2: "Plug it in: Android opens Ginga as an accessory. No USB debugging, no adb, no developer mode.", w2t: "120 fps · ~13 ms",
    w3h: "No router", w3: "Hotel, train or no internet: the tablet creates its own Wi‑Fi network and the Mac joins it. When you finish, the Mac goes back to your network.", w3t: "direct connection",
    featEy: "Features", featH: "Built to feel like it was always there",
    f1: "Pick smoothness or battery. 60 Hz uses about a third of the power of 120 Hz for the same 60 fps stream.",
    f2h: "Touch and S Pen", f2: "Touch clicks, drags and scrolls. The S Pen becomes a pen tablet for macOS, with pressure, tilt and eraser.",
    f3: "Pixel‑exact on the tablet’s panel, with HiDPI: looks like 1280 × 800, sharp like a Retina screen.",
    f4h: "Saves power", f4: "A still desktop costs close to nothing extra. Nothing is captured or sent while the screen doesn’t change.",
    f5h: "Tablet keyboard", f5: "Choose which key becomes ⌘: the Samsung key or Ctrl. Mac shortcuts work on the cover keyboard.",
    f6h: "Like a real monitor", f6: "Place the tablet left, right, above or below in macOS Displays settings, in landscape or portrait.",
    cmpEy: "Compare", cmpH: "Galaxy Tab + Mac: who does what", cmpP: "Most “tablet as a second screen” options were built for Windows or for iPad. Here is what works when the computer is a Mac and the tablet is a Galaxy.",
    cmpCol: "Mac + Galaxy tablet", cmpByUs: "this app", cmpOpen: "open source", cmpSwipe: "Swipe the table sideways →", yes: "Yes", no: "No", part: "Partly",
    cmp: [
      ["Extends a current Mac", ["y", "macOS virtual display"], ["y", "macOS 10.14 or later"], ["y"], ["n", "Windows 10 or later only"], ["y"], ["n", "Windows only"]],
      ["Works with a Galaxy / Android tablet", ["y", "built for Galaxy Tab"], ["y", "Android 7 or later"], ["y", "in the browser"], ["y", "Galaxy Tab S7 or later"], ["n", "iPad only"], ["y"]],
      ["Extended display, no extra hardware", ["y"], ["y"], ["p", "extending needs a virtual display adapter"], ["y"], ["y"], ["y"]],
      ["Over a USB cable", ["y", "no developer mode"], ["y"], ["n", "local Wi‑Fi only"], ["n", "Wi‑Fi only"], ["y"], ["y"]],
      ["Cost", ["t", "Free · AGPL‑3.0"], ["t", "Paid, in‑app purchases"], ["t", "Free"], ["t", "Included with Galaxy Tab"], ["t", "Included in macOS"], ["t", "Free for personal use"]]
    ],
    cmpFoot: "Based on official pages and app store listings as of September 2026; details may change. Duet Display, Deskreen, Second Screen, Sidecar and spacedesk are trademarks of their owners, named here for comparison only.",
    stEy: "Get started", stH: "In orbit in three steps",
    s1h: "Download both apps", s1: "The Mac app and the Android APK are on the GitHub releases page.",
    s2h: "Turn it on on the Mac", s2: "Open Ginga and switch on Wi‑Fi or USB.",
    s3h: "Connect the tablet", s3: "Tap Connect and check the code. Done.",
    dlH: "Ready for liftoff?", dlP: "Get Ginga for your Mac and your tablet on GitHub.", req: "Apple Silicon Mac with macOS 14+ · Android 12+ · free, AGPL‑3.0",
    iconAlt: "Ginga icon",
    legal: "Galaxy and Samsung are trademarks of Samsung Electronics. Mac, macOS and Sidecar are trademarks of Apple Inc. Ginga works with these products and is not affiliated with either company."
  }
};
    return this._T;
  }
  ref(name) { var self = this; if (!this.refFns[name]) this.refFns[name] = function (el) { self.r[name] = el; }; return this.refFns[name]; }
  later(fn, ms) { var rm = window.Ginga && (window.Ginga && window.Ginga.reducedMotion); this.timers.push(setTimeout(fn, rm ? Math.min(ms, 60) : ms)); }
  clearTimers() { this.timers.forEach(clearTimeout); this.timers = []; }

  componentDidMount() {
    var self = this;
    try {
      var qs = new URLSearchParams(location.search).get("lang") || (location.hash.match(/lang=(pt|en)/) || [])[1];
      if (qs === "pt" || qs === "en") this._langFromUrl = qs;
    } catch (e) {}
    this.setupAstro();
    try {
      var v = this.r.vid, rmv = !!(window.Ginga && window.Ginga.reducedMotion);
      if (v) {
        v.muted = true;
        var playV = function () { if (self._vidVis && !rmv && !self._vidUserPaused) { var pr = v.play(); if (pr && pr.catch) pr.catch(function () {}); } };
        this._playVid = playV;
        v.addEventListener("pause", function () { if (self._vidVis && !v.seeking && v.readyState >= 2 && document.visibilityState === "visible") self._vidUserPaused = true; });
        v.addEventListener("play", function () { self._vidUserPaused = false; });
        v.addEventListener("loadeddata", playV);
        if (window.IntersectionObserver) {
          this._vidIO = new IntersectionObserver(function (en) {
            self._vidVis = en[0].isIntersecting;
            if (self._vidVis) { if (v.preload !== "auto") { v.preload = "auto"; v.load(); } playV(); } else if (!v.paused) { v.pause(); self._vidUserPaused = false; }
          }, { rootMargin: "200px 0px" });
          this._vidIO.observe(v);
        } else { v.preload = "metadata"; }
      }
    } catch (e) {}
    try { if (window.matchMedia("(prefers-color-scheme: light)").matches) this.setState({ theme: "light" }); } catch (e) {}
    if (!this.props.lang) {
      if (this._langFromUrl) this.setState({ lang: this._langFromUrl });
      else { try { if ((navigator.language || "").toLowerCase().indexOf("pt") !== 0) this.setState({ lang: "en" }); } catch (e) {} }
    }
    this.arrive();
    if (this.r.sky) this.sky = this.pixelSky(this.r.sky);
    var fit = function () {
      var w = self.r.wrap ? self.r.wrap.clientWidth : 1200; if (w < 200) return; var s = Math.min(1, w / 1200);
      self.setState({ scale: +s.toFixed(4), left: Math.max(0, (w - 1200 * s) / 2), wrapW: w, mobile: w < 760 });
    };
    fit();
    if (window.ResizeObserver && this.r.wrap) { this.ro = new ResizeObserver(fit); this.ro.observe(this.r.wrap); }
    this.hintTimer = setInterval(function () { self.placeHint(); }, 220);
    if (this.r.bh) this.bhLoop = this.ditherLoop(this.r.bh, this.blackHole());
    if (this.r.gal) this.galLoop = this.ditherLoop(this.r.gal, this.galaxy());
    if (this.r.macWall) this.macWallLoop = this.ditherLoop(this.r.macWall, this.galaxy({ cx: 0.68, cy: 0.62, s: 1.15, spin: 0.15 }));
    if (this.r.tabWall) this.tabWallLoop = this.ditherLoop(this.r.tabWall, this.galaxy({ cx: 0.2, cy: 0.7, s: 1.2, spin: 0.15 }));
  }

  /* ---------- céu em pixels: estrelas cintilando em toda a seção inicial + estrelas cadentes ---------- */
  pixelSky(cv) {
    var PX = 4, ctx = cv.getContext("2d"), W = 0, H = 0, stars = [], shoot = null, raf = 0, last = 0, visible = true;
    var COL = ["#252C66", "#2E47F5", "#6F82FF", "#A4A9C8", "#F2F3F8", "#FFC43D"];
    var rm = !!(window.Ginga && window.Ginga.reducedMotion);
    var seed = function () {
      var r = cv.getBoundingClientRect(); W = Math.max(1, Math.ceil(r.width / PX)); H = Math.max(1, Math.ceil(r.height / PX));
      cv.width = W; cv.height = H; stars = [];
      var n = Math.round(W * H * 0.0048);
      for (var i = 0; i < n; i++) {
        var k = Math.random(), c = k < 0.5 ? 0 : k < 0.74 ? 1 : k < 0.88 ? 2 : k < 0.95 ? 3 : k < 0.99 ? 4 : 5;
        stars.push({ x: (Math.random() * W) | 0, y: (Math.random() * H) | 0, c: c, p: Math.random() * 6.28, s: 0.5 + Math.random() * 2, big: c >= 4 && Math.random() < 0.25 });
      }
      draw(0);
    };
    var draw = function (t) {
      ctx.clearRect(0, 0, W, H);
      for (var i = 0; i < stars.length; i++) {
        var st = stars[i], tw = Math.sin(st.p + t * st.s), c = st.c + (tw > 0.75 ? 1 : tw < -0.6 ? -1 : 0);
        if (c < 0) continue; if (c > 5) c = 5;
        ctx.fillStyle = COL[c]; ctx.fillRect(st.x, st.y, 1, 1);
        if (st.big && tw > 0.2) { ctx.fillStyle = COL[Math.max(0, c - 2)]; ctx.fillRect(st.x - 1, st.y, 1, 1); ctx.fillRect(st.x + 1, st.y, 1, 1); ctx.fillRect(st.x, st.y - 1, 1, 1); ctx.fillRect(st.x, st.y + 1, 1, 1); }
      }
      if (shoot) {
        var e = t - shoot.t0, len = 14;
        if (e > 1.1) shoot = null; else {
          var hx = shoot.x + e * shoot.vx, hy = shoot.y + e * shoot.vy;
          for (var j = 0; j < len; j++) { ctx.fillStyle = COL[j < 2 ? 5 : j < 5 ? 4 : j < 9 ? 2 : 1]; ctx.fillRect(Math.round(hx - j * shoot.vx / 60), Math.round(hy - j * shoot.vy / 60), 1, 1); }
        }
      } else if (Math.random() < 0.004) {
        shoot = { t0: t, x: Math.random() * W * 0.7, y: Math.random() * H * 0.35, vx: 90 + Math.random() * 60, vy: 30 + Math.random() * 30 };
      }
    };
    var t0 = performance.now();
    var loop = function (now) { raf = 0; if (!visible || document.hidden) return; if (now - last > 90) { last = now; draw((now - t0) / 1000); } raf = requestAnimationFrame(loop); };
    seed();
    var ro = window.ResizeObserver ? new ResizeObserver(seed) : null; if (ro) ro.observe(cv);
    if (!rm) {
      raf = requestAnimationFrame(loop);
      if (window.IntersectionObserver) new IntersectionObserver(function (en) { visible = en[0].isIntersecting; if (visible && !raf) raf = requestAnimationFrame(loop); }).observe(cv);
      document.addEventListener("visibilitychange", function () { if (!document.hidden && !raf) raf = requestAnimationFrame(loop); });
    }
    return { stop: function () { if (raf) cancelAnimationFrame(raf); raf = 0; visible = false; if (ro) ro.disconnect(); } };
  }

  /* ---------- dithering pixelizado (Bayer 4×4) sobre a paleta da marca ---------- */
  ditherLoop(cv, shade) {
    var ctx = cv.getContext("2d"), W = cv.width, H = cv.height, img = ctx.createImageData(W, H), d = img.data;
    var PAL = [[10,12,28],[20,24,48],[46,71,245],[111,130,255],[242,243,248],[255,196,61]], N = PAL.length - 1;
    var B = [0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5];
    var geo = shade.init(W, H), buf = new Float32Array(W * H), raf = 0, visible = true, last = 0, t0 = performance.now();
    var rm = window.Ginga && (window.Ginga && window.Ginga.reducedMotion);
    var draw = function (t) {
      for (var j = 0; j < buf.length; j++) buf[j] = shade.at(geo, j, t);
      if (shade.splat) shade.splat(buf, W, H, t);
      for (var y = 0, i = 0; y < H; y++) for (var x = 0; x < W; x++, i++) {
        var v = buf[i], th = (B[(y & 3) * 4 + (x & 3)] + 0.5) / 16;
        var lv = Math.floor(v * N + th); lv = lv < 0 ? 0 : lv > N ? N : lv;
        var c = PAL[lv], o = i * 4; d[o] = c[0]; d[o + 1] = c[1]; d[o + 2] = c[2]; d[o + 3] = lv === 0 ? 0 : 255;
      }
      ctx.putImageData(img, 0, 0);
    };
    var loop = function (now) {
      raf = 0; if (!visible || document.hidden) return;
      if (now - last > 42) { last = now; draw((now - t0) / 1000); }
      raf = requestAnimationFrame(loop);
    };
    draw(0);
    if (!rm) {
      raf = requestAnimationFrame(loop);
      if (window.IntersectionObserver) new IntersectionObserver(function (e) { visible = e[0].isIntersecting; if (visible && !raf) raf = requestAnimationFrame(loop); }).observe(cv);
      document.addEventListener("visibilitychange", function () { if (!document.hidden && !raf) raf = requestAnimationFrame(loop); });
    }
    return { shade: shade, now: function () { return (performance.now() - t0) / 1000; }, stop: function () { if (raf) cancelAnimationFrame(raf); raf = 0; visible = false; } };
  }
  blackHole() {
    /* Buraco negro em dithering: gás espiralando para dentro (disco inclinado com efeito Doppler),
       anel de fótons, arco lenteado por cima, estrelas de fundo deformadas pela lente
       e ~700 partículas em órbita kepleriana que colapsam com o mouse e explodem no clique. */
    var R = 0.28, K = 0.2, rIn = 0.42, rOut = 1.6;
    var hash = function (a, b) { var x = Math.sin(a * 127.1 + b * 311.7) * 43758.5453; return x - Math.floor(x); };
    var shade = {
      pull: 0, pullT: 0, tb: -99, cx: 0, cy: 0, W: 0, H: 0,
      init: function (W, H) {
        var n = W * H, g = { x: new Float32Array(n), y: new Float32Array(n), rd: new Float32Array(n), lrd: new Float32Array(n), ang: new Float32Array(n), rs: new Float32Array(n), st: new Float32Array(n) };
        shade.W = W; shade.H = H; shade.cx = W * 0.5; shade.cy = H * 0.52;
        for (var yy = 0, i = 0; yy < H; yy++) for (var xx = 0; xx < W; xx++, i++) {
          var x = (xx - shade.cx) / (H / 2), y = (yy - shade.cy) / (H / 2), v = y / K, rs = Math.sqrt(x * x + y * y);
          g.x[i] = x; g.y[i] = y; g.rd[i] = Math.sqrt(x * x + v * v); g.lrd[i] = Math.log(g.rd[i] + 0.001); g.ang[i] = Math.atan2(v, x); g.rs[i] = rs;
          /* lente: a estrela vista aqui vem de um ponto empurrado para fora (Einstein) */
          var k = rs > R ? 1 + 0.09 / (rs * rs) : 0, sx = x * k, sy = y * k;
          var h = hash(Math.floor(sx * 60), Math.floor(sy * 60));
          g.st[i] = rs > R * 1.1 && rs < 1.05 && h > 0.985 ? 0.28 + (h - 0.985) * 40 : 0;
        }
        var P = [], NP = Math.min(700, Math.round(W * H * 0.03));
        for (var p = 0; p < NP; p++) {
          var r0 = rIn * 0.9 + Math.pow(Math.random(), 0.8) * (rOut * 1.25 - rIn);
          P.push({ r: r0, a: Math.random() * 6.2832, w: 0.9 / Math.pow(r0, 1.5), b: 0.35 + Math.random() * 0.55, z: (Math.random() - 0.5) * 0.05 });
        }
        g.P = P;
        return g;
      },
      at: function (g, i, t) {
        var x = g.x[i], y = g.y[i], rd = g.rd[i], a = g.ang[i], rs = g.rs[i];
        var dop = 0.5 - 0.5 * Math.cos(a);
        var D = 0;
        if (rd > rIn && rd < rOut) {
          var f = 1 - (rd - rIn) / (rOut - rIn);
          /* espirais que puxam o gás para dentro */
          var sw = 0.5 + 0.5 * Math.sin(a * 3 + g.lrd[i] * 7 + t * 2.2);
          var sw2 = 0.5 + 0.5 * Math.sin(a * 7 - g.lrd[i] * 11 + t * 3.1);
          D = Math.pow(f, 1.05) * (0.35 + 0.75 * dop) * (0.45 + 0.4 * sw + 0.2 * sw2) * Math.min(1, (rd - rIn) / 0.06);
        }
        var L = 0, dr = Math.abs(rs - 0.47);
        if (dr < 0.17 && y < 0.05) {
          var la = Math.atan2(y, x);
          L = Math.pow(1 - dr / 0.17, 1.4) * (0.55 + 0.45 * (0.5 - 0.5 * Math.cos(la))) * (0.7 + 0.3 * Math.sin(la * 5 + t * 2.4 + rs * 20));
        }
        var Pr = Math.max(0, 1 - Math.abs(rs - R * 1.04) / 0.02);
        if (rs < R) return (y > 0 && D > 0) ? D : 0;
        var halo = 0.18 * Math.exp(-(rs - R) / 0.14) * (1 + 0.6 * shade.pull);
        var back = Math.min(1, Math.max(0, (rs - 0.5) / 0.3)); back = back * back * (3 - 2 * back);
        var v = Math.max(y > 0 ? D : Math.max(D * back, L), Pr * (0.85 + 0.15 * Math.sin(t * 3)), halo);
        v += g.st[i] * (0.65 + 0.35 * Math.sin(t * 1.7 + i));
        return v > 1 ? 1 : v;
      },
      splat: function (buf, W, H, t) {
        var g = shade.g; if (!g) return;
        shade.pull += (shade.pullT - shade.pull) * 0.08;
        var e = t - shade.tb, burst = e > 0 && e < 2.2 ? Math.sin(Math.PI * Math.min(1, e / 2.2)) * Math.exp(-e * 0.6) : 0;
        var S = H / 2, dt = 0.042;
        for (var p = 0; p < g.P.length; p++) {
          var q = g.P[p];
          q.a += q.w * dt * (1 + 1.4 * shade.pull);
          var r = q.r * (1 - 0.38 * shade.pull) * (1 + 1.6 * burst * (0.6 + q.b));
          for (var k = 0; k < 3; k++) {
            var aa = q.a - k * 0.05 * (1 + shade.pull), x = r * Math.cos(aa), y = r * Math.sin(aa) * K + q.z;
            var rs = Math.sqrt(x * x + y * y);
            if (rs < R && Math.sin(aa) < 0) continue;
            var px = Math.round(shade.cx + x * S), py = Math.round(shade.cy + y * S);
            if (px < 0 || py < 0 || px >= W || py >= H) continue;
            var o = py * W + px, add = q.b * (k === 0 ? 0.75 : 0.32 / k) * (0.6 + 0.6 * (0.5 - 0.5 * Math.cos(aa)));
            buf[o] = Math.min(1, buf[o] + add);
          }
        }
      }
    };
    var init = shade.init;
    shade.init = function (W, H) { var g = init(W, H); shade.g = g; return g; };
    return shade;
  }
  galaxy(o) {
    o = o || {}; var CX = o.cx == null ? 0.5 : o.cx, CY = o.cy == null ? 0.5 : o.cy, SC = o.s || 1, SPIN = o.spin == null ? 0.35 : o.spin;
    return {
      init: function (W, H) {
        var n = W * H, g = { r: new Float32Array(n), th: new Float32Array(n) }, U = Math.min(W, H) / 2 * SC;
        for (var yy = 0, i = 0; yy < H; yy++) for (var xx = 0; xx < W; xx++, i++) {
          var x = (xx - W * CX) / U, y = (yy - H * CY) / U;
          var c = Math.cos(-0.5), s = Math.sin(-0.5), u = x * c - y * s, w = (x * s + y * c) / 0.62;
          g.r[i] = Math.sqrt(u * u + w * w); g.th[i] = Math.atan2(w, u);
        }
        return g;
      },
      at: function (g, i, t) {
        var r = g.r[i]; if (r > 1.05) return 0;
        var arms = Math.pow(0.5 + 0.5 * Math.cos(2 * g.th[i] - 5.2 * Math.log(r + 0.06) - t * SPIN), 3);
        var edge = Math.min(1, (1.05 - r) / 0.35);
        var v = (Math.exp(-r * 2.4) * (0.25 + 1.1 * arms)) * edge + 1.15 * Math.exp(-r * r * 60);
        return v > 1 ? 1 : v;
      }
    };
  }
  componentDidUpdate(pp, ps) {
    if (ps && ps.lang !== this.state.lang) this.syncLang();
  }
  arrive() {
    var from = false;
    try { from = sessionStorage.getItem("ginga-from-404") === "1"; sessionStorage.removeItem("ginga-from-404"); } catch (e) {}
    if (!from) return;
    var self = this, rm = !!(window.Ginga && window.Ginga.reducedMotion);
    if (rm) return;
    this.setState({ arriving: true });
    setTimeout(function () { if (self.bhLoop) self.bhLoop.shade.tb = self.bhLoop.now(); }, 60);
    setTimeout(function () { self.setState({ arriving: false }); }, 1500);
  }
  syncLang() {
    var L = this.state.lang, t = this.dict()[L];
    try { document.documentElement.lang = L === "pt" ? "pt-BR" : "en"; document.title = t.docTitle; } catch (e) {}
    try { history.replaceState(null, "", (this.props.base || "/") + L + "/" + location.hash); } catch (e) {}
    try { var md = document.querySelector('meta[name="description"]'); if (md) md.setAttribute("content", t.metaDesc); } catch (e) {}
  }
  /* Cursor astronauta: ele É o ponteiro (a mão levantada é o ponto do clique). Uma cordinha solta presa às
     costas balança com física Verlet. Com o mouse parado, a gravidade do buraco negro puxa o astronauta numa
     espiral até o horizonte; mexer o mouse o traz de volta na hora. */
  setupAstro() {
    var self = this, fine = false, rm = !!(window.Ginga && window.Ginga.reducedMotion);
    try { fine = window.matchMedia("(pointer: fine)").matches; } catch (e) {}
    this.astroOk = fine && !rm && this.props.astronaut !== false;
    if (!this.astroOk) return;
    this.setState({ astroOn: true });
    var gen = this._astroGen = (this._astroGen || 0) + 1;
    var N = 9, SEG = 6, DAMP = 0.9, ITER = 8, IDLE = 900, VMAX = 4;
    var A = { tx: -200, ty: -200, x: -200, y: -200, vx: 0, vy: 0, rot: 0, sc: 1, stretch: 1, radial: 0, behind: false, orb: null, hot: false, seen: false, mode: "follow", lastMove: 0 };
    var rope = []; for (var i = 0; i < N; i++) rope.push({ x: -200, y: -200, px: -200, py: -200 });
    var parts = [], k = 0, lastSpark = 0, W = 0, H = 0, prev = performance.now();
    for (var q = 0; q < 6; q++) parts.push({ x: -50, y: -50, life: 0, vx: 0, vy: 0 });
    this.astroState = A;
    var sizeCanvas = function () { var c = self.r.tether; if (!c) return; W = window.innerWidth; H = window.innerHeight; c.width = W; c.height = H; };
    sizeCanvas(); window.addEventListener("resize", sizeCanvas); this._astroResize = sizeCanvas;
    var anchor = function () { /* ponto da corda nas costas (mochila), girando junto com o astronauta */
      var a = A.rot * Math.PI / 180, ox = 20 * A.sc, oy = 26 * A.sc;
      return { x: A.x + ox * Math.cos(a) - oy * Math.sin(a), y: A.y + ox * Math.sin(a) + oy * Math.cos(a) };
    };
    var resetRope = function () { var an = anchor(); for (var i = 0; i < N; i++) { rope[i].x = rope[i].px = an.x - i * 2; rope[i].y = rope[i].py = an.y + i * SEG; } };
    var burst = function (x, y, n) { for (var i = 0; i < (n || 6); i++) { var p = parts[k++ % parts.length], ang = Math.random() * 6.283, v = 1.5 + Math.random() * 2.5; p.x = x; p.y = y; p.vx = Math.cos(ang) * v; p.vy = Math.sin(ang) * v; p.life = 1; } };
    var hole = function () {
      var c = self.r.bh; if (!c) return null;
      if (document.visibilityState !== "visible") return null;
      var r = c.getBoundingClientRect(); if (r.width < 10) return null;
      /* só puxa com o buraco negro de fato na tela: o horizonte inteiro visível e pelo menos 60% do disco à vista */
      var hx = r.left + r.width * 0.5, hy = r.top + r.height * 0.52, R = 0.28 * r.height / 2, vw = window.innerWidth, vh = window.innerHeight;
      if (hx - R < 0 || hx + R > vw || hy - R < 0 || hy + R > vh) return null;
      var visH = Math.max(0, Math.min(r.bottom, vh) - Math.max(r.top, 0)), visW = Math.max(0, Math.min(r.right, vw) - Math.max(r.left, 0));
      if (visH * visW < 0.6 * r.width * r.height) return null;
      return { x: hx, y: hy, R: R };
    };
    this._astroMoved = function () {
      A.lastMove = performance.now();
      if (A.mode === "eaten") { A.x = A.tx; A.y = A.ty; A.vx = A.vy = 0; A.rot = 0; A.sc = 1; A.stretch = 1; resetRope(); burst(A.x + 10, A.y + 10, 6); }
      if (A.mode === "pulled") { A.orb = null; A.behind = false; }
      A.mode = "follow";
      if (self.bhLoop) self.bhLoop.shade.pullT = 0;
    };
    var loop = function (now) {
      if (gen !== self._astroGen) return;
      self.astroRaf = requestAnimationFrame(loop);
      var dt = Math.min(2, (now - prev) / 16.67); prev = now;
      var el = self.r.astro, star = self.r.cstar, cv = self.r.tether; if (!el || !cv) return;
      var ctx = cv.getContext("2d"); ctx.clearRect(0, 0, W, H);
      if (star) star.classList.remove("on");
      if (!A.seen) { el.classList.remove("on"); return; }
      var h = hole();
      if (A.mode === "follow") {
        var nx = A.x + (A.tx - A.x) * 0.55, ny = A.y + (A.ty - A.y) * 0.55;
        A.vx = nx - A.x; A.vy = ny - A.y; A.x = nx; A.y = ny;
        A.rot += ((Math.max(-10, Math.min(10, A.vx * 0.6))) - A.rot) * 0.15;
        A.sc += (1 - A.sc) * 0.2; A.stretch = 1 + ((A.stretch || 1) - 1) * 0.8; A.behind = false; A.orb = null;
        if (h && now - A.lastMove > IDLE && Math.hypot(h.x - A.x, h.y - A.y) < Math.max(900, window.innerWidth * 0.8)) { A.mode = "pulled"; A.vx = A.vy = 0; }
      } else if (A.mode === "pulled") {
        if (!h) { A.mode = "follow"; A.orb = null; A.behind = false; if (self.bhLoop) self.bhLoop.shade.pullT = 0; }
        else {
          /* órbita no plano do disco (achatado) que se fecha em espiral: lei de Kepler, ω ∝ r^-1.5 */
          var F = 0.42, secs = dt / 60;
          if (!A.orb) {
            var ox = A.x - h.x, oy = (A.y - h.y) / F;
            A.orb = { r: Math.min(520, Math.max(h.R * 2.4, Math.hypot(ox, oy))), th: Math.atan2(oy, ox), blend: 0, sx: A.x, sy: A.y };
          }
          var O = A.orb;
          O.th += Math.min(7, 1.5 * Math.pow(220 / O.r, 1.5)) * secs;
          O.r *= Math.exp(-0.3 * secs * (O.r < h.R * 2 ? 2.2 : 1));
          O.blend = Math.min(1, O.blend + secs * 1.4);
          var bx = h.x + O.r * Math.cos(O.th), by = h.y + O.r * Math.sin(O.th) * F, e2 = O.blend * O.blend * (3 - 2 * O.blend);
          var nx2 = O.sx + (bx - O.sx) * e2, ny2 = O.sy + (by - O.sy) * e2;
          if (O.blend >= 1) { O.sx = bx; O.sy = by; }
          A.vx = nx2 - A.x; A.vy = ny2 - A.y; A.x = nx2; A.y = ny2;
          /* espaguetificação: estica na direção do buraco e afina conforme se aproxima */
          var rr = O.blend < 1 ? Math.hypot(A.x - h.x, (A.y - h.y) / F) : O.r;
          A.stretch = 1 + Math.min(2.4, Math.pow(h.R * 2 / Math.max(rr, h.R), 3) * 1.2);
          A.radial = Math.atan2(h.y - A.y, h.x - A.x) * 57.2958;
          A.rot += (1.2 + Math.hypot(A.vx, A.vy) * 0.8) * dt;
          A.sc = Math.max(0.35, Math.min(1, rr / (h.R * 3)));
          /* atrás do buraco (metade de cima da órbita) ele some atrás da sombra */
          A.behind = Math.sin(O.th) < 0 && Math.abs(A.x - h.x) < h.R * 1.05 && Math.abs(A.y - h.y) < h.R;
          if (self.bhLoop) self.bhLoop.shade.pullT = 1;
          if (O.r < h.R * 1.02) {
            A.mode = "eaten"; A.orb = null; burst(A.x, A.y, 6);
            if (self.bhLoop) { self.bhLoop.shade.tb = self.bhLoop.now(); self.bhLoop.shade.pullT = 0; }
          }
        }
      }
      /* corda: ponto 0 preso na mochila; o resto solto, com inércia e um pouco de gravidade do buraco negro */
      var an = anchor(); rope[0].x = rope[0].px = an.x; rope[0].y = rope[0].py = an.y;
      for (var i = 1; i < N; i++) {
        var p = rope[i], vx = (p.x - p.px) * DAMP, vy = (p.y - p.py) * DAMP, gx = 0, gy = 0.12, vm = Math.hypot(vx, vy);
        if (vm > VMAX) { vx *= VMAX / vm; vy *= VMAX / vm; }
        if (h && A.mode === "pulled") { var ddx = h.x - p.x, ddy = h.y - p.y, dd = Math.max(30, Math.hypot(ddx, ddy)); gx = ddx / dd * 0.12; gy = ddy / dd * 0.12; }
        p.px = p.x; p.py = p.y; p.x += vx + gx * dt; p.y += vy + gy * dt;
      }
      for (var it = 0; it < ITER; it++) for (var j = 0; j < N - 1; j++) {
        var a1 = rope[j], b1 = rope[j + 1], ex = b1.x - a1.x, ey = b1.y - a1.y, e = Math.hypot(ex, ey) || 0.001, df = (e - SEG * A.sc) / e;
        if (j === 0) { b1.x -= ex * df; b1.y -= ey * df; } else { a1.x += ex * df * 0.5; a1.y += ey * df * 0.5; b1.x -= ex * df * 0.5; b1.y -= ey * df * 0.5; }
      }
      if (A.mode !== "eaten" && !A.behind) {
        for (var s2 = 0; s2 < N - 1; s2++) {
          var P = rope[s2], Q = rope[s2 + 1];
          for (var u = 0; u < 3; u++) {
            var x = P.x + (Q.x - P.x) * u / 3, y = P.y + (Q.y - P.y) * u / 3;
            ctx.fillStyle = (s2 * 3 + u) % 4 < 2 ? "#F2F3F8" : "#6F82FF";
            ctx.fillRect(Math.round(x / 2) * 2, Math.round(y / 2) * 2, 2, 2);
          }
        }
        /* a ponta solta da corda: um mosquetão dourado */
        var T = rope[N - 1]; ctx.fillStyle = "#FFC43D"; ctx.fillRect(Math.round(T.x / 2) * 2 - 1, Math.round(T.y / 2) * 2 - 1, 4, 4);
      }
      var st = A.stretch || 1, sc0 = A.sc * (A.hot && A.mode === "follow" ? 1.15 : 1), rad = A.radial || 0;
      el.style.transform = "translate(" + (A.x - 4).toFixed(1) + "px, " + (A.y - 5).toFixed(1) + "px)" +
        (st > 1.01 ? " rotate(" + rad.toFixed(1) + "deg) scale(" + st.toFixed(3) + ", " + (1 / Math.sqrt(st)).toFixed(3) + ") rotate(" + (-rad).toFixed(1) + "deg)" : "") +
        " rotate(" + A.rot.toFixed(1) + "deg) scale(" + sc0.toFixed(3) + ")";
      el.classList.toggle("on", A.mode !== "eaten" && !A.behind);
      /* faíscas de propulsão ao mover rápido */
      var sp = Math.hypot(A.vx, A.vy);
      if (A.mode === "follow" && sp > 4 && now - lastSpark > 45) { lastSpark = now; var pp = parts[k++ % parts.length]; pp.x = an.x; pp.y = an.y; pp.vx = -A.vx * 0.25 + (Math.random() - 0.5); pp.vy = -A.vy * 0.25 + (Math.random() - 0.5); pp.life = 1; }
      for (var m = 0; m < parts.length; m++) {
        var z = parts[m], spn = self.r["tr" + m]; if (!spn) continue;
        if (z.life > 0) { z.life -= 0.045 * dt; z.x += z.vx * dt; z.y += z.vy * dt; }
        spn.style.opacity = Math.max(0, z.life).toFixed(2);
        spn.style.transform = "translate(" + Math.round(z.x / 4) * 4 + "px, " + Math.round(z.y / 4) * 4 + "px)";
      }
    };
    this._astroReset = function () { A.x = A.tx; A.y = A.ty; resetRope(); };
    this.astroRaf = requestAnimationFrame(loop);
  }
  componentWillUnmount() {
    if (this._vidIO) this._vidIO.disconnect();
    if (this.astroRaf) cancelAnimationFrame(this.astroRaf); if (this._astroResize) window.removeEventListener("resize", this._astroResize); [this.bhLoop, this.galLoop, this.macWallLoop, this.tabWallLoop, this.sky].forEach(function (l) { if (l) l.stop(); }); this.clearTimers(); clearInterval(this.hintTimer); if (this.ro) this.ro.disconnect();  }

  /* geometria em coordenadas do stage (ele pode estar escalado) */
  box(el) {
    var st = this.r.stage, s = st.getBoundingClientRect(), r = el.getBoundingClientRect(), k = st.offsetWidth / s.width;
    return { x: (r.left - s.left) * k, y: (r.top - s.top) * k, w: r.width * k, h: r.height * k };
  }
  placeHint() {
    var h = this.state.hint, el = h && this.r[h.k], hint = this.r.hint;
    if (!hint || !el || !this.r.stage) return;
    var b = this.box(el), p = 6;
    hint.style.borderRadius = b.h > 60 ? "20px" : "999px";
    hint.style.left = (b.x - p) + "px"; hint.style.top = (b.y - p) + "px";
    hint.style.width = (b.w + p * 2) + "px"; hint.style.height = (b.h + p * 2) + "px";
  }
  spark(name) { if (window.Ginga && this.r[name]) window.Ginga.spark(this.r[name]); }

  /* ---------- efeitos ---------- */
  routePath() {
    var m = this.box(this.r.macScreen), t = this.box(this.r.tabScreen);
    var x1 = m.x + m.w - 40, y1 = m.y + 60, x2 = t.x + t.w * 0.45, y2 = t.y + t.h * 0.4;
    return "M" + x1 + " " + y1 + " C " + (x1 + 90) + " " + (y1 - 150) + ", " + (x2 - 40) + " " + (y2 - 190) + ", " + x2 + " " + y2;
  }
  burst(pt) {
    var b = this.r.burst; if (!b) return;
    b.setAttribute("cx", pt.x); b.setAttribute("cy", pt.y);
    if (b.animate) b.animate([{ r: 6, opacity: 1, strokeWidth: 3 }, { r: 70, opacity: 0, strokeWidth: 0.5 }], { duration: 700, easing: "cubic-bezier(0.2,0.8,0.2,1)" });
  }
  comet(done) {
    var self = this, tail = this.r.tail, head = this.r.head, route = this.r.route, d = this.routePath();
    route.setAttribute("d", d); tail.setAttribute("d", d); this.setState({ route: true });
    if ((window.Ginga && window.Ginga.reducedMotion)) { done(); return; }
    var L = tail.getTotalLength(), T = 1400, t0 = performance.now(), TL = 90;
    tail.style.strokeDasharray = TL + " " + (L + TL); tail.style.opacity = 1; head.style.opacity = 1;
    var step = function (now) {
      var p = Math.min(1, (now - t0) / T), e = p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2;
      var at = e * L, pt = tail.getPointAtLength(at);
      head.setAttribute("cx", pt.x); head.setAttribute("cy", pt.y); tail.style.strokeDashoffset = (TL - at);
      if (p < 1) requestAnimationFrame(step); else { tail.style.opacity = 0; head.style.opacity = 0; self.burst(pt); done(); }
    };
    requestAnimationFrame(step);
  }
  cablePath() {
    var m = this.box(this.r.mac), t = this.box(this.r.tab);
    var x1 = m.x + m.w - 18, y1 = m.y + m.h - 8, x2 = t.x + t.w * 0.5, y2 = t.y + t.h + 6;
    return "M" + x1 + " " + y1 + " C " + (x1 + 30) + " " + (y1 + 110) + ", " + (x2 - 20) + " " + (y2 + 150) + ", " + x2 + " " + y2;
  }
  drawCable(done) {
    var c = this.r.cable, d = this.cablePath(); c.setAttribute("d", d); this.r.cableGlow.setAttribute("d", d);
    var L = c.getTotalLength(); c.style.strokeDasharray = L; c.style.strokeDashoffset = L; c.style.opacity = 1;
    var a = c.animate([{ strokeDashoffset: L }, { strokeDashoffset: 0 }], { duration: (window.Ginga && window.Ginga.reducedMotion) ? 1 : 900, easing: "cubic-bezier(0.2,0.8,0.2,1)", fill: "forwards" });
    a.onfinish = done;
  }
  cablePulse(done) {
    var self = this, g = this.r.cableGlow, L = g.getTotalLength();
    g.style.opacity = 1; g.style.strokeDasharray = "40 " + L;
    var a = g.animate([{ strokeDashoffset: 40 }, { strokeDashoffset: -L }], { duration: (window.Ginga && window.Ginga.reducedMotion) ? 1 : 1000, easing: "cubic-bezier(0.4,0,0.2,1)" });
    a.onfinish = function () { g.style.opacity = 0; self.burst(g.getPointAtLength(L)); done(); };
  }
  removeCable() { var c = this.r.cable; if (!c) return; c.getAnimations().forEach(function (a) { a.cancel(); }); c.style.opacity = 0; }
  warp(done) {
    var cv = this.r.warp;
    if (!cv || (window.Ginga && window.Ginga.reducedMotion)) { done(); return; }
    var ctx = cv.getContext("2d"), w = cv.width = Math.round(cv.offsetWidth * 1.5), h = cv.height = Math.round(cv.offsetHeight * 1.5), stars = [];
    for (var i = 0; i < 140; i++) stars.push({ a: Math.random() * 6.283, d: Math.random() * 40, v: 0.6 + Math.random() * 1.6, c: Math.random() < 0.15 ? "255,196,61" : Math.random() < 0.3 ? "111,130,255" : "242,243,248" });
    cv.classList.add("on"); var t0 = performance.now(), T = 1100;
    var step = function (now) {
      var p = Math.min(1, (now - t0) / T), sp = Math.pow(p, 2) * 26 + 1, cx = w / 2, cy = h / 2;
      ctx.fillStyle = "rgba(0,0,0," + (0.35 + p * 0.3) + ")"; ctx.fillRect(0, 0, w, h);
      stars.forEach(function (s) {
        var d0 = s.d; s.d += s.v * sp;
        ctx.strokeStyle = "rgba(" + s.c + "," + Math.min(1, 0.3 + p) + ")"; ctx.lineWidth = 1 + p * 1.5;
        ctx.beginPath(); ctx.moveTo(cx + Math.cos(s.a) * d0, cy + Math.sin(s.a) * d0); ctx.lineTo(cx + Math.cos(s.a) * s.d, cy + Math.sin(s.a) * s.d); ctx.stroke();
        if (s.d > w) s.d = Math.random() * 20;
      });
      if (p < 1) requestAnimationFrame(step); else { done(); setTimeout(function () { cv.classList.remove("on"); ctx.clearRect(0, 0, w, h); }, 120); }
    };
    requestAnimationFrame(step);
  }

  /* ---------- fluxo ---------- */
  resetInk() { if (this.r.ink) { this.r.ink.style.strokeDasharray = ""; this.r.ink.style.strokeDashoffset = ""; } if (this.r.notes) this.r.notes.style.transform = ""; }
  toOff(keepPaired) {
    this.resetInk();
    this.clearTimers(); this.removeCable();
    this.setState({ phase: "off", via: null, wifi: false, usb: false, screen: "search", sheet: false, docked: false, live: false,
      macNotesAway: false, tabNotesIn: false, toast: false, route: false, story: "s1", rail: 1, penDone: false, sending: false, paired: keepPaired ? this.state.paired : false,
      hint: { k: "wifi", t: "hWifi", up: false } });
  }
  wifiOn() {
    var self = this;
    this.setState({ phase: "adv", via: "wifi", wifi: true, rail: 2, story: "s2", hint: null });
    this.later(function () {
      self.setState({ phase: "found", screen: "found" });
      self.later(function () { self.setState({ hint: { k: "tabConnect", t: self.state.paired ? "hRe" : "hConnect", up: false } }); }, 380);
    }, 1100);
  }
  tabConnect() {
    var self = this;
    if (this.state.paired) { this.connect("wifi"); return; }
    this.setState({ phase: "pairing", rail: 3, hint: null, screen: "pair", story: "s3" });
    this.later(function () {
      self.setState({ sheet: true });
      self.later(function () { self.setState({ hint: { k: "doPair", t: "hPair", up: false } }); }, 420);
    }, 500);
  }
  connect(via) {
    var self = this;
    this.setState({ phase: "connecting", via: via, rail: 4, hint: null, sheet: false, docked: true, story: via === "usb" ? "s4u" : "s4w" });
    var go = function () { self.warp(function () { self.connected(); }); };
    this.later(function () { via === "usb" ? self.cablePulse(go) : self.comet(go); }, 250);
  }
  connected() {
    var self = this;
    this.setState({ phase: "connected", screen: "stream", paired: this.state.paired || this.state.via === "wifi", live: true, rail: 5, story: "s5" });
    this.later(function () { self.setState({ toast: true }); }, 150);
    this.later(function () { self.setState({ toast: false }); }, 3200);
    this.later(function () { self.setState({ hint: { k: "notes", t: "hDrag", up: false }, story: "s7" }); }, 900);
  }
  sendNotes() {
    var self = this;
    if (this.state.macNotesAway || this.state.phase !== "connected") return;
    if (this.r.notes) { this.r.notes.style.transform = ""; }
    this.setState({ macNotesAway: true, hint: null, sending: true });
    this.later(function () { self.setState({ tabNotesIn: true, sending: false }); }, 420);
    this.later(function () { self.setState({ hint: { k: "tabNotes", t: "hPen", up: true }, story: "s8" }); }, 1100);
  }
  drawPen() {
    var self = this, path = this.r.ink, pen = this.r.pen;
    if (!path || this.state.penDone || !this.state.tabNotesIn) return;
    this.setState({ hint: null, penDone: true });
    var L = path.getTotalLength(), rm = !!(window.Ginga && window.Ginga.reducedMotion), T = rm ? 1 : 1600, t0 = performance.now();
    path.style.strokeDasharray = L; path.style.strokeDashoffset = L;
    if (pen) pen.classList.add("on");
    var step = function (now) {
      var p = Math.min(1, (now - t0) / T), at = p * L, pt = path.getPointAtLength(at);
      path.style.strokeDashoffset = L - at;
      if (pen) pen.style.transform = "translate(" + (pt.x + 10) + "px, " + (pt.y + 24) + "px) rotate(-38deg)";
      if (p < 1) requestAnimationFrame(step);
      else {
        if (pen) setTimeout(function () { pen.classList.remove("on"); }, 400);
        if (window.Ginga && self.r.tabNotes) window.Ginga.spark(self.r.tabNotes, 9);
        self.setState({ story: "s5" });
        self.later(function () { self.setState({ hint: { k: "main", t: "hDisc", up: true } }); }, 1600);
      }
    };
    requestAnimationFrame(step);
  }
  disconnect() {
    this.clearTimers();
    this.setState({ hint: null, docked: false, route: false, live: false, macNotesAway: false, tabNotesIn: false, toast: false, penDone: false, sending: false });
    this.resetInk();
    if (this.state.via === "usb") {
      this.removeCable(); this.setState({ usb: false });
      if (this.state.wifi) { this.setState({ screen: "search" }); this.wifiOn(); } else this.toOff(true);
      return;
    }
    this.setState({ screen: "search" }); this.wifiOn(); this.setState({ story: "s6" });
  }
  usbStart() {
    var self = this;
    this.clearTimers();
    this.setState({ usb: true, via: "usb", rail: 2, sheet: false, hint: null, phase: "usbWait", story: "su" });
    this.later(function () { self.spark("usb"); }, 30);
    this.later(function () {
      self.drawCable(function () {
        self.setState({ screen: "usb", rail: 3, phase: "usbDialog" });
        self.later(function () { self.setState({ hint: { k: "usbOk", t: "hOpen", up: false } }); }, 400);
      });
    }, 60);
  }

  renderVals() {
    var self = this, s = this.state, L = s.lang, t = this.dict()[L];
    var status = { off: ["", t.stOff], adv: ["searching", t.stAdv], found: ["searching", t.stAdv], pairing: ["pairing", t.stPair],
      connecting: ["searching", t.stConn], connected: ["connected", t.stOk], usbWait: ["searching", t.stCable], usbDialog: ["pairing", t.stApprove] }[s.phase] || ["", t.stOff];
    var railLabels = [t.r1, t.r2, t.r3, t.r4];
    var scr = function (n) { return s.screen === n ? "show" : ""; };
    var conn = s.phase === "connected";
    var hasDev = conn || s.paired;
    return {
      t: t, theme: s.theme, isLight: s.theme === "light", isDark: s.theme !== "light",
      github: this.props.githubUrl || "https://github.com/[OWNER]/[REPO]/releases/latest",
      mono: s.theme === "light" ? (this.props.base + "assets/ginga-monogram.svg") : (this.props.base + "assets/ginga-monogram-dark.svg"),
      langPt: L === "pt" ? "on" : "", langEn: L === "en" ? "on" : "", isPt: L === "pt", isEn: L === "en",
      thLight: s.theme === "light" ? "on" : "", thDark: s.theme === "dark" ? "on" : "",
      setPt: function () { self.setState({ lang: "pt" }); }, setEn: function () { self.setState({ lang: "en" }); },
      githubRepo: this.props.repoUrl || "https://github.com/[OWNER]/[REPO]",
      githubIssues: (this.props.repoUrl || "https://github.com/[OWNER]/[REPO]") + "/issues",
      faq: t.faq.map(function (x) { return { q: x[0], a: x[1] }; }),
      vidSrc: (this.props.base || "/") + "assets/ginga-demo-" + L + ".mp4", vidPoster: (this.props.base || "/") + "assets/ginga-demo-poster.jpg",
      astroCls: s.astroOn ? "astro-on" : "", arriveCls: s.arriving ? "arrive" : "",
      onRootMove: function (e) { var A = self.astroState; if (!A || e.pointerType === "touch") return; A.tx = e.clientX; A.ty = e.clientY; if (!A.seen) { if (self._astroReset) self._astroReset(); A.seen = true; } if (self._astroMoved) self._astroMoved(); },
      onRootLeave: function () { if (self.astroState) self.astroState.seen = false; },
      onRootOver: function (e) { var A = self.astroState; if (!A) return; var el = e.target; A.hot = !!(el && el.closest && el.closest("a, button, summary, label, .notes, .blast")); },
      notesDown: function (e) { if (self.state.phase !== "connected" || self.state.macNotesAway) return; self._drag = { x: e.clientX, moved: 0 }; try { e.currentTarget.setPointerCapture(e.pointerId); } catch (er) {} },
      notesMove: function (e) { var d = self._drag; if (!d || !self.r.notes) return; var k = self.r.stage ? self.r.stage.offsetWidth / self.r.stage.getBoundingClientRect().width : 1; d.moved = (e.clientX - d.x) * k; self.r.notes.style.transform = "translateX(" + Math.max(0, d.moved) + "px)"; },
      notesUp: function () { var d = self._drag; self._drag = null; if (!d) return; if (d.moved > 60 || Math.abs(d.moved) < 4) self.sendNotes(); else if (self.r.notes) self.r.notes.style.transform = ""; },
      penDraw: function () { self.drawPen(); },
      setLight: function () { self.setState({ theme: "light" }); }, setDark: function () { self.setState({ theme: "dark" }); },
      mobile: s.mobile, mCls: s.mobile ? "m" : "",
      cmpCols: [
        { name: "Ginga", by: t.cmpByUs, cls: "me" }, { name: "Duet Display", by: "Kairos", cls: "" }, { name: "Deskreen", by: t.cmpOpen, cls: "" },
        { name: "Second Screen", by: "Samsung", cls: "" }, { name: "Sidecar", by: "Apple", cls: "" }, { name: "spacedesk", by: "datronicsoft", cls: "" }
      ],
      cmpRows: t.cmp.map(function (row) {
        return { label: row[0], cells: row.slice(1).map(function (c, i) {
          var k = c[0], cls = (k === "y" ? "yes" : k === "n" ? "no" : k === "t" ? "txt" : "part") + (i === 0 ? " me" : "");
          if (k === "t") return { cls: cls, isYes: false, word: c[1], note: "" };
          return { cls: cls, isYes: k === "y", word: k === "y" ? t.yes : k === "n" ? t.no : t.part, note: c[1] || "" };
        }) };
      }),
      stageH: s.mobile ? 460 : Math.round(860 * s.scale), stageLeft: s.mobile ? 0 : Math.round(s.left),
      stageTransform: (function () {
        if (!s.mobile) return "scale(" + s.scale + ")";
        /* no celular, uma "câmera" acompanha a ação: janela do Mac ↔ tablet, e abre para mostrar o cometa */
        var REG = { mac2: { x: 380, y: 100, w: 360, h: 360 }, mac: { x: 70, y: 100, w: 360, h: 360 }, tab: { x: 740, y: 226, w: 432, h: 300 }, all: { x: 30, y: 90, w: 1150, h: 640 } };
        var hk = s.hint && s.hint.k, key;
        if (s.phase === "connecting" || s.phase === "usbWait") key = "all";
        else if (s.sending) key = "all";
        else if (hk) key = { wifi: "mac", usb: "mac", main: "mac", doPair: "mac", notes: "mac2", tabConnect: "tab", usbOk: "tab", tabNotes: "tab" }[hk] || "mac";
        else if (s.screen === "stream" || s.phase === "adv" || s.phase === "found" || s.phase === "pairing") key = s.sheet ? "mac" : "tab";
        else key = "mac";
        var r = REG[key], W = s.wrapW, H = 460, k = Math.min(W / r.w, H / r.h);
        var tx = W / 2 - (r.x + r.w / 2) * k, ty = H / 2 - (r.y + r.h / 2) * k;
        return "translate(" + tx.toFixed(1) + "px, " + ty.toFixed(1) + "px) scale(" + k.toFixed(4) + ")";
      })(),
      rail: railLabels.map(function (l, i) { return { n: i + 1, label: l, cls: i + 1 === s.rail ? "on" : (i + 1 < s.rail ? "done" : "") }; }),
      statusCls: "g-status" + (status[0] ? " g-status--" + status[0] : ""), statusTxt: status[1],
      wifi: s.wifi, usb: s.usb,
      onWifi: function (e) {
        if (e.target.checked) { self.spark("wifi"); if (s.phase === "off" || s.phase === "adv" || (s.phase === "usbWait" || s.phase === "usbDialog")) { self.clearTimers(); self.removeCable(); self.setState({ usb: false }); self.wifiOn(); } else self.setState({ wifi: true }); }
        else if (s.via !== "usb" || s.phase === "off") self.toOff(true); else self.setState({ wifi: false });
      },
      onUsb: function (e) {
        if (e.target.checked) self.usbStart();
        else if (s.via === "usb") { if (s.phase === "connected") self.disconnect(); else self.toOff(true); }
      },
      noDevice: !hasDev, hasDevice: hasDev,
      deviceMeta: conn ? (s.via === "usb" ? t.metaUsb : t.metaWifi) : t.metaAway,
      mainCls: conn ? "g-btn g-btn--danger" : "g-btn g-btn--primary", mainDisabled: !conn, mainLabel: conn ? t.disconnect : t.create,
      onMain: function () { if (self.state.phase === "connected") self.disconnect(); },
      sheetCls: s.sheet ? "show" : "", sheetOpen: s.sheet,
      noPair: function () { self.setState({ sheet: false, screen: "search" }); self.wifiOn(); },
      doPair: function () { self.spark("doPair"); self.connect("wifi"); },
      tabCls: s.docked ? "docked" : "",
      scrSearch: scr("search"), scrFound: scr("found"), scrPair: scr("pair"), scrUsb: scr("usb"), scrStream: scr("stream"),
      showTabCode: s.screen === "pair",
      foundMeta: s.paired ? t.fPaired : t.fNew, tabConnectLabel: s.paired ? t.reconnect : t.connect,
      tabConnect: function () { self.tabConnect(); },
      usbOk: function () { self.spark("usbOk"); self.connect("usb"); },
      macNotesCls: s.macNotesAway ? "away" : "", tabNotesCls: s.tabNotesIn ? "" : "pre",
      toastCls: s.toast ? "" : "hide", toastTxt: t.stOk + " · " + (s.via === "usb" ? "USB" : "Wi‑Fi"),
      menuLive: s.live ? "live" : "", routeCls: s.route ? "on" : "",
      hintCls: s.hint ? (s.hint.up ? "up" : "") : "off", hintTxt: s.hint ? t[s.hint.t] : "",
      story: t.story[s.story],
      altUsb: function () { if (!self.state.usb) self.usbStart(); },
      doReset: function () { self.toOff(false); },
      refSky: this.ref("sky"), refWrap: this.ref("wrap"), refStage: this.ref("stage"), refMac: this.ref("mac"), refMacScreen: this.ref("macScreen"),
      refTab: this.ref("tab"), refTabScreen: this.ref("tabScreen"), refWifi: this.ref("wifi"), refUsb: this.ref("usb"), refMain: this.ref("main"),
      refDoPair: this.ref("doPair"), refTabConnect: this.ref("tabConnect"), refUsbOk: this.ref("usbOk"), refWarp: this.ref("warp"),
      refCable: this.ref("cable"), refCableGlow: this.ref("cableGlow"), refRoute: this.ref("route"), refTail: this.ref("tail"),
      refBh: this.ref("bh"), refGal: this.ref("gal"), refMacWall: this.ref("macWall"), refTabWall: this.ref("tabWall"),
      bhTransform: "translate(" + (s.px * 18).toFixed(1) + "px, " + (s.py * 12).toFixed(1) + "px) rotate(" + (s.px * -1.5).toFixed(2) + "deg)",
      onHeroMove: function (e) {
        var r = e.currentTarget.getBoundingClientRect(); var nx = (e.clientX - r.left) / r.width - 0.5, ny = (e.clientY - r.top) / r.height - 0.5;
        if (Math.abs(nx - self.state.px) + Math.abs(ny - self.state.py) > 0.04) self.setState({ px: nx, py: ny });
        if (self.bhLoop && self.r.bh) { var b = self.r.bh.getBoundingClientRect(), dx = e.clientX - (b.left + b.width / 2), dy = e.clientY - (b.top + b.height * 0.52), d = Math.sqrt(dx * dx + dy * dy) / (b.width * 0.5); if (!self.astroState || self.astroState.mode === "follow") self.bhLoop.shade.pullT = Math.max(0, Math.min(1, 1.25 - d)); }
      },
      onHeroLeave: function () { if (self.bhLoop) self.bhLoop.shade.pullT = 0; },
      onBlast: function () { if (self.bhLoop) { self.bhLoop.shade.tb = self.bhLoop.now(); } if (window.Ginga && self.r.blast) window.Ginga.spark(self.r.blast, 11); },
      refBlast: this.ref("blast"),
      refHead: this.ref("head"), refNotes: this.ref("notes"), refTabNotes: this.ref("tabNotes"), refInk: this.ref("ink"), refPen: this.ref("pen"), refAstro: this.ref("astro"), refVid: this.ref("vid"), refTether: this.ref("tether"), refCstar: this.ref("cstar"), refTr0: this.ref("tr0"), refTr1: this.ref("tr1"), refTr2: this.ref("tr2"), refTr3: this.ref("tr3"), refTr4: this.ref("tr4"), refTr5: this.ref("tr5"), refBurst: this.ref("burst"), refHint: this.ref("hint")
    };
  }

  render() {
    const v = this.renderVals();
    const A = this.props.base + "assets/";
    return (<>{" "}<div className={`site g-root ${v.astroCls} ${v.arriveCls}`} data-theme={v.theme} style={{"width": "100%", "minHeight": "4700px", "background": "var(--bg)", "color": "var(--ink)"}} onPointerMove={v.onRootMove} onPointerLeave={v.onRootLeave} onPointerOver={v.onRootOver}>{" "}<canvas className={"tether"} ref={v.refTether} aria-hidden={"true"}></canvas>{" "}<span className={"cstar"} ref={v.refCstar} aria-hidden={"true"}></span>{" "}<img className={"astro"} ref={v.refAstro} src={A + "ginga-astronaut.svg"} alt={""} aria-hidden={"true"} />{" "}<span className={"trail t0"} ref={v.refTr0}></span><span className={"trail t1"} ref={v.refTr1}></span><span className={"trail t2"} ref={v.refTr2}></span><span className={"trail t3"} ref={v.refTr3}></span><span className={"trail t4"} ref={v.refTr4}></span><span className={"trail t5"} ref={v.refTr5}></span>{" "}<section className={"hero"} style={{"background": "var(--cosmos)", "paddingBottom": "40px"}} onPointerMove={v.onHeroMove} onPointerLeave={v.onHeroLeave}>{" "}<canvas className={"sky dither"} ref={v.refSky} aria-hidden={"true"}></canvas>{" "}<canvas className={"dither bh"} ref={v.refBh} width={"190"} height={"122"} aria-hidden={"true"} style={{"transform": v.bhTransform}}></canvas>{" "}<button className={"blast"} ref={v.refBlast} onClick={v.onBlast} aria-label={v.t.blast} style={{"transform": v.bhTransform}}></button>{" "}<div className={"bhcap"}>{v.t.bhCap}</div>{" "}<div className={"wrap"}>{" "}<nav className={"nav"} aria-label={v.t.navLabel}>{" "}<a href={"#top"} aria-label={"Ginga"}><img src={A + "ginga-wordmark-dark.svg"} alt={"ginga"} /></a>{" "}<div className={"links"}>{" "}<a href={"#recursos"}>{v.t.navFeat}</a>{" "}<a href={"#seguranca"}>{v.t.navSec}</a>{" "}<a href={"#comparar"}>{v.t.navCmp}</a>{" "}<a href={"#faq"}>{"FAQ"}</a>{" "}<a href={"#baixar"}>{v.t.navDl}</a>{" "}</div>{" "}<div className={"seg-dark"} role={"group"} aria-label={v.t.langLabel}>{" "}<button className={v.langPt} onClick={v.setPt} aria-pressed={v.isPt}>{"PT"}</button>{" "}<button className={v.langEn} onClick={v.setEn} aria-pressed={v.isEn}>{"EN"}</button>{" "}</div>{" "}<div className={"seg-dark"} role={"group"} aria-label={v.t.themeLabel}>{" "}<button className={v.thLight} onClick={v.setLight} aria-label={v.t.light}><svg width={"16"} height={"16"} viewBox={"0 0 16 16"} aria-hidden={"true"}><circle cx={"8"} cy={"8"} r={"3"} fill={"none"} stroke={"currentColor"} strokeWidth={"1.5"}></circle><path d={"M8 1.5v1.6M8 12.9v1.6M1.5 8h1.6M12.9 8h1.6M3.4 3.4l1.1 1.1M11.5 11.5l1.1 1.1M3.4 12.6l1.1-1.1M11.5 4.5l1.1-1.1"} stroke={"currentColor"} strokeWidth={"1.5"} strokeLinecap={"round"}></path></svg></button>{" "}<button className={v.thDark} onClick={v.setDark} aria-label={v.t.dark}><svg width={"16"} height={"16"} viewBox={"0 0 16 16"} aria-hidden={"true"}><path d={"M13.5 9.6A5.8 5.8 0 0 1 6.4 2.5a5.8 5.8 0 1 0 7.1 7.1z"} fill={"none"} stroke={"currentColor"} strokeWidth={"1.5"} strokeLinejoin={"round"}></path></svg></button>{" "}</div>{" "}<a className={"gh"} href={v.github} aria-label={"GitHub"}><svg width={"16"} height={"16"} viewBox={"0 0 16 16"} aria-hidden={"true"}><path fill={"currentColor"} d={"M8 0a8 8 0 0 0-2.53 15.59c.4.07.55-.17.55-.38v-1.33c-2.23.48-2.7-1.07-2.7-1.07-.36-.92-.89-1.17-.89-1.17-.73-.5.06-.49.06-.49.8.06 1.23.83 1.23.83.72 1.22 1.87.87 2.33.67.07-.52.28-.87.5-1.07-1.78-.2-3.65-.89-3.65-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.6 7.6 0 0 1 4 0c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.28.82 2.15 0 3.07-1.87 3.75-3.66 3.95.29.25.54.73.54 1.48v2.2c0 .21.15.46.55.38A8 8 0 0 0 8 0z"}></path></svg><span className={"ghl"}>{"GitHub"}</span></a>{" "}</nav>{" "}<div className={"herotext"} id={"top"}>{" "}<div className={"kicker"}><span className={"star4"}></span>{v.t.kicker}</div>{" "}<h1 className={"h1"}>{v.t.h1}</h1>{" "}<p className={"lead"}>{v.t.lead}</p>{" "}<div className={"ctas"}>{" "}<a className={"cta primary"} href={v.github}><svg width={"18"} height={"18"} viewBox={"0 0 16 16"} aria-hidden={"true"}><path d={"M8 2v8.5M4.5 7 8 10.5 11.5 7M3 13.5h10"} fill={"none"} stroke={"currentColor"} strokeWidth={"1.6"} strokeLinecap={"round"} strokeLinejoin={"round"}></path></svg>{v.t.ctaMac}<small>{"GitHub"}</small></a>{" "}<a className={"cta ghost"} href={v.github}><svg width={"18"} height={"18"} viewBox={"0 0 16 16"} aria-hidden={"true"}><path d={"M8 2v8.5M4.5 7 8 10.5 11.5 7M3 13.5h10"} fill={"none"} stroke={"currentColor"} strokeWidth={"1.6"} strokeLinecap={"round"} strokeLinejoin={"round"}></path></svg>{v.t.ctaAnd}<small>{"APK \u00b7 GitHub"}</small></a>{" "}</div>{" "}<p className={"trynote"}><b>{v.t.tryA}</b>{" "}{v.t.tryB}</p>{" "}</div>{" "}</div>{" "}<div className={`stagewrap ${v.mCls}`} ref={v.refWrap} style={{"height": `${v.stageH}px`}}>{" "}<div className={`stage ${v.mCls}`} ref={v.refStage} style={{"transform": v.stageTransform, "left": `${v.stageLeft}px`}}>{" "}<svg className={"orbits"} viewBox={"0 0 1200 860"} aria-hidden={"true"}>{" "}<ellipse className={"o"} cx={"600"} cy={"400"} rx={"560"} ry={"250"}></ellipse>{" "}<ellipse className={"o dash"} cx={"600"} cy={"400"} rx={"470"} ry={"190"} transform={"rotate(-6 600 400)"}></ellipse>{" "}<ellipse className={"o"} cx={"960"} cy={"380"} rx={"260"} ry={"120"} transform={"rotate(-10 960 380)"}></ellipse>{" "}</svg>{" "}<div className={"dtop"}>{" "}<div className={"rail"} aria-live={"polite"}>{" "}{(v.rail || []).map((it, $index) => (<React.Fragment key={$index}>{" "}<span className={it.cls}><b>{it.n}</b>{it.label}</span>{" "}</React.Fragment>))}{" "}</div>{" "}<button className={"reset"} onClick={v.doReset}>{v.t.reset}</button>{" "}</div>{" "}<div className={"mac"} ref={v.refMac} data-theme={v.theme}>{" "}<div className={"mac__lid"}>{" "}<div className={"mac__notch"}></div>{" "}<div className={"mac__screen"} ref={v.refMacScreen}>{" "}<canvas className={"dither wallgal"} ref={v.refMacWall} width={"158"} height={"98"} aria-hidden={"true"}></canvas>{" "}<div className={"menubar"}><span>{"Finder"}</span><span className={"mi"}>{v.t.mFile}</span><span className={"mi"}>{v.t.mEdit}</span><span className={"mi"}>{v.t.mView}</span><span className={"sp"}></span><span className={`gwrap ${v.menuLive}`}><img className={"gicon"} src={A + "ginga-app-icon.png"} alt={""} /></span><span className={"mi"}>{v.t.clock}</span></div>{" "}<div className={`notes ${v.macNotesCls}`} ref={v.refNotes} onPointerDown={v.notesDown} onPointerMove={v.notesMove} onPointerUp={v.notesUp} onPointerCancel={v.notesUp} style={{"touchAction": "none"}}><span className={"nt"}>{v.t.notes}</span><div className={"l"}></div><div className={"l s"}></div><div className={"l c"}></div><div className={"l"}></div><div className={"l s"}></div></div>{" "}<div className={"win"}>{" "}<div className={"win__bar"}><i className={"r"}></i><i className={"y"}></i><i className={"g"}></i></div>{" "}<div className={"win__body"}>{" "}<div className={"win__head"}>{" "}<img src={v.mono} alt={""} />{" "}<span className={"t"}>{"Ginga"}</span>{" "}<span className={v.statusCls}><span className={"g-status__orb"}></span>{v.statusTxt}</span>{" "}</div>{" "}<h3 className={"g-group-title"}>{v.t.gConn}</h3>{" "}<div className={"g-group"}>{" "}<label className={"g-row"}><span className={"g-row__icon"}><svg viewBox={"0 0 16 16"}><path d={"M2 6.2a8.5 8.5 0 0 1 12 0M4.3 8.6a5.2 5.2 0 0 1 7.4 0M6.6 11a2 2 0 0 1 2.8 0"} fill={"none"} stroke={"currentColor"} strokeWidth={"1.5"} strokeLinecap={"round"}></path></svg></span><span className={"g-row__label"}>{v.t.rWifi}</span><span className={"g-switch"} ref={v.refWifi}><input type={"checkbox"} role={"switch"} checked={v.wifi} onChange={v.onWifi} /><span className={"g-switch__track"}></span><span className={"g-switch__thumb"}></span></span></label>{" "}<label className={"g-row"}><span className={"g-row__icon"}><svg viewBox={"0 0 16 16"}><path d={"M8 1.5v9M5.5 4 8 1.5 10.5 4M4 7.5v2.5l4 2.5 4-2.5V7"} fill={"none"} stroke={"currentColor"} strokeWidth={"1.5"} strokeLinecap={"round"} strokeLinejoin={"round"}></path></svg></span><span className={"g-row__label"}>{v.t.rUsb}<span className={"g-row__sub"}>{v.t.rUsbSub}</span></span><span className={"g-switch"} ref={v.refUsb}><input type={"checkbox"} role={"switch"} checked={v.usb} onChange={v.onUsb} /><span className={"g-switch__track"}></span><span className={"g-switch__thumb"}></span></span></label>{" "}</div>{" "}<h3 className={"g-group-title"}>{v.t.gTabs}</h3>{" "}<div className={"g-group"}>{" "}{v.noDevice ? (<><div className={"empty"}>{v.t.noTabs}</div></>) : null}{" "}{v.hasDevice ? (<><div className={"g-device"}><span className={"g-device__art"}></span><span className={"g-device__name"}>{"Galaxy Tab S11"}<span className={"g-device__meta"}>{v.deviceMeta}</span></span><button className={"g-btn g-btn--sm g-btn--danger"}>{v.t.forget}</button></div></>) : null}{" "}</div>{" "}<div className={"actions"}><button className={v.mainCls} ref={v.refMain} disabled={v.mainDisabled} onClick={v.onMain}>{v.mainLabel}</button><button className={"g-btn g-btn--ghost"}>{v.t.settings}</button></div>{" "}</div>{" "}<div className={`sheet ${v.sheetCls}`}>{" "}<div className={"sheet__card"}>{" "}<img src={A + "ginga-app-icon.png"} alt={""} />{" "}<h4>{v.t.pairQ}</h4>{" "}<p>{v.t.pairP}</p>{" "}{v.sheetOpen ? (<><span className={"g-code"} aria-label={"4 8 2 9 1 3"}><span className={"g-code__group"}><span className={"g-code__d"}>{"4"}</span><span className={"g-code__d"}>{"8"}</span><span className={"g-code__d"}>{"2"}</span></span><span className={"g-code__group"}><span className={"g-code__d"}>{"9"}</span><span className={"g-code__d"}>{"1"}</span><span className={"g-code__d"}>{"3"}</span></span></span></>) : null}{" "}<div className={"row"}><button className={"g-btn"} onClick={v.noPair}>{v.t.noPair}</button><button className={"g-btn g-btn--primary"} ref={v.refDoPair} onClick={v.doPair}>{v.t.doPair}</button></div>{" "}</div>{" "}</div>{" "}</div>{" "}</div>{" "}</div>{" "}<div className={"mac__base"}></div>{" "}</div>{" "}<div className={`tab ${v.tabCls}`} ref={v.refTab} data-theme={v.theme}>{" "}<div className={"tab__body"}>{" "}<div className={"tab__cam"}></div>{" "}<div className={"tab__screen"} ref={v.refTabScreen}>{" "}<div className={`scr ${v.scrSearch}`}>{" "}<div className={"tabhead"}><img src={v.mono} alt={""} /><div><h5>{v.t.tSearch}</h5><p className={"sub2"}>{v.t.tSearchP}</p></div></div>{" "}<div className={"radar"}><div className={"c"}></div><div className={"c c2"}></div><div className={"c c3"}></div><div className={"ping"}></div><div className={"sat"}></div><div className={"sat b"}></div></div>{" "}<div className={"chips"}><span className={"chip on"}>{"Wi\u2011Fi"}</span><span className={"chip"}>{v.t.chipUsb}</span><span className={"chip"}>{v.t.chipDirect}</span></div>{" "}</div>{" "}<div className={`scr ${v.scrFound}`}>{" "}<div className={"tabhead"}><img src={v.mono} alt={""} /><div><h5>{v.t.tFound}</h5><p className={"sub2"}>{v.t.tFoundP}</p></div></div>{" "}<div className={"list g-group"}><div className={"g-device"}><span className={"g-device__art"}></span><span className={"g-device__name"}>{"MacBook Pro"}<span className={"g-device__meta"}>{v.foundMeta}</span></span><button className={"g-btn g-btn--sm g-btn--primary"} ref={v.refTabConnect} onClick={v.tabConnect}>{v.tabConnectLabel}</button></div></div>{" "}<div className={"chips"}><span className={"chip on"}>{"Wi\u2011Fi"}</span><span className={"chip"}>{v.t.chipUsb}</span><span className={"chip"}>{v.t.chipDirect}</span></div>{" "}</div>{" "}<div className={`scr pair ${v.scrPair}`}>{" "}<h5>{v.t.tConfirm}</h5>{" "}{v.showTabCode ? (<><span className={"g-code"} aria-label={"4 8 2 9 1 3"}><span className={"g-code__group"}><span className={"g-code__d"}>{"4"}</span><span className={"g-code__d"}>{"8"}</span><span className={"g-code__d"}>{"2"}</span></span><span className={"g-code__group"}><span className={"g-code__d"}>{"9"}</span><span className={"g-code__d"}>{"1"}</span><span className={"g-code__d"}>{"3"}</span></span></span></>) : null}{" "}<div><span className={"g-status g-status--pairing"}><span className={"g-status__orb"}></span>{v.t.tWaitMac}</span></div>{" "}</div>{" "}<div className={`scr ${v.scrUsb}`}>{" "}<div className={"tabhead"}><img src={v.mono} alt={""} /><div><h5>{v.t.tCable}</h5><p className={"sub2"}>{v.t.tCableP}</p></div></div>{" "}<div className={"dialog"}><div className={"dialog__card"}><b>{v.t.dlgQ}</b>{v.t.dlgP}<span className={"al"}><i></i>{v.t.dlgAlways}</span><div className={"row"}><button className={"g-btn g-btn--ghost"}>{v.t.cancel}</button><button className={"g-btn g-btn--primary"} ref={v.refUsbOk} onClick={v.usbOk}>{v.t.open}</button></div></div></div>{" "}</div>{" "}<div className={`scr stream ${v.scrStream}`}>{" "}<canvas className={"dither wallgal"} ref={v.refTabWall} width={"96"} height={"60"} aria-hidden={"true"}></canvas>{" "}<div className={`notes ${v.tabNotesCls}`} ref={v.refTabNotes} onClick={v.penDraw}><span className={"nt"}>{v.t.notes}</span><div className={"l"}></div><div className={"l s"}></div><div className={"l c"}></div><div className={"l"}></div><div className={"l s"}></div><svg className={"ink"} viewBox={"0 0 200 116"} aria-hidden={"true"}><path ref={v.refInk} d={"M14 92 C 30 60, 44 58, 52 78 S 70 100, 84 70 S 104 30, 118 62 S 140 96, 156 58 C 164 40, 176 36, 186 48"}></path></svg><span className={"pen"} ref={v.refPen}></span></div>{" "}<div className={`toast ${v.toastCls}`}><span className={"g-status g-status--connected"}><span className={"g-status__orb"}></span>{v.toastTxt}</span></div>{" "}</div>{" "}<canvas className={"warp"} ref={v.refWarp}></canvas>{" "}</div>{" "}</div>{" "}</div>{" "}<svg className={"fx"} viewBox={"0 0 1200 860"} aria-hidden={"true"}>{" "}<path className={"cable"} ref={v.refCable} d={"M0 0"}></path>{" "}<path className={"cable-glow"} ref={v.refCableGlow} d={"M0 0"}></path>{" "}<path className={`route ${v.routeCls}`} ref={v.refRoute} d={"M0 0"}></path>{" "}<path className={"tail"} ref={v.refTail} d={"M0 0"}></path>{" "}<circle className={"head"} ref={v.refHead} r={"5"}></circle>{" "}<circle className={"burst"} ref={v.refBurst} r={"10"}></circle>{" "}</svg>{" "}<div className={`hint ${v.hintCls}`} ref={v.refHint}><span>{v.hintTxt}</span></div>{" "}<div className={"story"}>{" "}<div className={"story__txt"}>{" "}<div className={"story__k"}>{v.story.k}</div>{" "}<div className={"story__h"}>{v.story.h}</div>{" "}<p className={"story__p"}>{v.story.p}</p>{" "}</div>{" "}<button className={"altbtn"} onClick={v.altUsb}>{v.t.altUsb}</button>{" "}</div>{" "}</div>{" "}</div>{" "}{v.mobile ? (<>{" "}<div className={"mstory"}>{" "}<div className={"rail"} aria-live={"polite"}>{" "}{(v.rail || []).map((it, $index) => (<React.Fragment key={$index}>{" "}<span className={it.cls}><b>{it.n}</b>{it.label}</span>{" "}</React.Fragment>))}{" "}</div>{" "}<div className={"story__k"}>{v.story.k}</div>{" "}<div className={"story__h"}>{v.story.h}</div>{" "}<p className={"story__p"}>{v.story.p}</p>{" "}<div className={"row"}><button className={"altbtn"} onClick={v.altUsb}>{v.t.altUsb}</button><button className={"reset"} onClick={v.doReset}>{v.t.reset}</button></div>{" "}</div>{" "}</>) : null}{" "}</section>{" "}<section className={"vidsec"} id={"video"}>{" "}<div className={"wrap"}>{" "}<div className={"eyebrow"}><span className={"star4"}></span>{v.t.vidEy}</div>{" "}<h2 className={"h2"}>{v.t.vidH}</h2>{" "}<div className={"vid"}>{" "}<video ref={v.refVid} src={v.vidSrc} poster={v.vidPoster} muted={true} loop={true} playsInline={true} controls={true} preload={"none"} aria-label={v.t.vidAlt} suppressHydrationWarning={true}></video>{" "}<span className={"tag"}>{v.t.vidTag}</span>{" "}</div>{" "}</div>{" "}</section>{" "}<section className={"sec"} id={"como"}>{" "}<div className={"wrap"}>{" "}<div className={"eyebrow"}><span className={"star4"}></span>{v.t.howEy}</div>{" "}<h2 className={"h2"}>{v.t.howH}</h2>{" "}<p className={"sub"}>{v.t.howP}</p>{" "}<div className={"grid3"}>{" "}<div className={"card"}><span className={"orbitline"}></span>{" "}<div className={"ico"}><svg viewBox={"0 0 24 24"}><path d={"M3 9.3a12.7 12.7 0 0 1 18 0M6.4 12.9a7.8 7.8 0 0 1 11.2 0M9.9 16.5a3 3 0 0 1 4.2 0"} fill={"none"} stroke={"currentColor"} strokeWidth={"2"} strokeLinecap={"round"}></path></svg></div>{" "}<h3>{"Wi\u2011Fi"}</h3><p>{v.t.w1}</p><span className={"tag"}>{v.t.w1t}</span>{" "}</div>{" "}<div className={"card"}><span className={"orbitline"}></span>{" "}<div className={"ico"}><svg viewBox={"0 0 24 24"}><path d={"M12 2.5v13M8.5 6 12 2.5 15.5 6M6 11v3.5l6 3.5 6-3.5V10M12 18v3.5"} fill={"none"} stroke={"currentColor"} strokeWidth={"2"} strokeLinecap={"round"} strokeLinejoin={"round"}></path></svg></div>{" "}<h3>{v.t.w2h}</h3><p>{v.t.w2}</p><span className={"tag"}>{v.t.w2t}</span>{" "}</div>{" "}<div className={"card"}><span className={"orbitline"}></span>{" "}<div className={"ico"}><svg viewBox={"0 0 24 24"}><rect x={"4"} y={"6"} width={"11"} height={"8"} rx={"2"} fill={"none"} stroke={"currentColor"} strokeWidth={"2"}></rect><path d={"M15 17.5a4 4 0 0 0 5-5M17 15.5a1.2 1.2 0 0 0 1.4-1.4"} fill={"none"} stroke={"currentColor"} strokeWidth={"2"} strokeLinecap={"round"}></path></svg></div>{" "}<h3>{v.t.w3h}</h3><p>{v.t.w3}</p><span className={"tag"}>{v.t.w3t}</span>{" "}</div>{" "}</div>{" "}</div>{" "}</section>{" "}<section className={"sec"} id={"recursos"} style={{"paddingTop": "0"}}>{" "}<div className={"wrap"}>{" "}<div className={"eyebrow"}><span className={"star4"}></span>{v.t.featEy}</div>{" "}<h2 className={"h2"}>{v.t.featH}</h2>{" "}<div className={"grid3"}>{" "}<div className={"card feat"}><div className={"ico"}><svg viewBox={"0 0 24 24"}><path d={"M3 12h3l2-6 4 12 2-6h7"} fill={"none"} stroke={"currentColor"} strokeWidth={"2"} strokeLinecap={"round"} strokeLinejoin={"round"}></path></svg></div><h3><span className={"hl"}>{"60 \u00b7 "}<span className={"st"}>{"120"}</span>{" Hz"}</span></h3><p>{v.t.f1}</p></div>{" "}<div className={"card feat"}><div className={"ico"}><svg viewBox={"0 0 24 24"}><path d={"M4 20l3.5-1 11-11a2.1 2.1 0 0 0-3-3l-11 11L4 20z"} fill={"none"} stroke={"currentColor"} strokeWidth={"2"} strokeLinejoin={"round"}></path><path d={"M13.5 7.5l3 3"} stroke={"currentColor"} strokeWidth={"2"}></path></svg></div><h3>{v.t.f2h}</h3><p>{v.t.f2}</p></div>{" "}<div className={"card feat"}><div className={"ico"}><svg viewBox={"0 0 24 24"}><rect x={"3"} y={"5"} width={"18"} height={"12"} rx={"2.5"} fill={"none"} stroke={"currentColor"} strokeWidth={"2"}></rect><path d={"M8 20h8"} stroke={"currentColor"} strokeWidth={"2"} strokeLinecap={"round"}></path></svg></div><h3><span className={"hl"}>{"2560\u00d71600"}</span></h3><p>{v.t.f3}</p></div>{" "}<div className={"card feat"}><div className={"ico"}><svg viewBox={"0 0 24 24"}><path d={"M12 3a9 9 0 1 0 9 9"} fill={"none"} stroke={"currentColor"} strokeWidth={"2"} strokeLinecap={"round"}></path><path d={"M12 7v5l3 2"} fill={"none"} stroke={"currentColor"} strokeWidth={"2"} strokeLinecap={"round"}></path><path d={"M19 2.5c.4 1.7.8 2.1 2.5 2.5-1.7.4-2.1.8-2.5 2.5-.4-1.7-.8-2.1-2.5-2.5 1.7-.4 2.1-.8 2.5-2.5z"} fill={"currentColor"}></path></svg></div><h3>{v.t.f4h}</h3><p>{v.t.f4}</p></div>{" "}<div className={"card feat"}><div className={"ico"}><svg viewBox={"0 0 24 24"}><rect x={"2.5"} y={"6"} width={"19"} height={"12"} rx={"2.5"} fill={"none"} stroke={"currentColor"} strokeWidth={"2"}></rect><path d={"M6 10h1M10 10h1M14 10h1M18 10h0M7 14h10"} stroke={"currentColor"} strokeWidth={"2"} strokeLinecap={"round"}></path></svg></div><h3>{v.t.f5h}</h3><p>{v.t.f5}</p></div>{" "}<div className={"card feat"}><div className={"ico"}><svg viewBox={"0 0 24 24"}><path d={"M20 12a8 8 0 1 1-2.3-5.6M20 4v4h-4"} fill={"none"} stroke={"currentColor"} strokeWidth={"2"} strokeLinecap={"round"} strokeLinejoin={"round"}></path></svg></div><h3>{v.t.f6h}</h3><p>{v.t.f6}</p></div>{" "}</div>{" "}</div>{" "}</section>{" "}<section className={"sec"} id={"seguranca"} style={{"paddingTop": "0"}}>{" "}<div className={"wrap"}>{" "}<div className={"eyebrow"}><span className={"star4"}></span>{v.t.secEy}</div>{" "}<h2 className={"h2"}>{v.t.secH}</h2>{" "}<p className={"sub"}>{v.t.secP}</p>{" "}<div className={"grid4"}>{" "}<div className={"sbox"}><div className={"ico"}><svg viewBox={"0 0 24 24"}><path d={"M3 11.5 12 4l9 7.5M5.5 9.5V20h13V9.5"} fill={"none"} stroke={"currentColor"} strokeWidth={"2"} strokeLinecap={"round"} strokeLinejoin={"round"}></path></svg></div><h3>{v.t.sec1h}</h3><p>{v.t.sec1}</p></div>{" "}<div className={"sbox"}><div className={"ico"}><svg viewBox={"0 0 24 24"}><rect x={"5"} y={"10.5"} width={"14"} height={"10"} rx={"2.5"} fill={"none"} stroke={"currentColor"} strokeWidth={"2"}></rect><path d={"M8.5 10.5V7.5a3.5 3.5 0 0 1 7 0v3"} fill={"none"} stroke={"currentColor"} strokeWidth={"2"} strokeLinecap={"round"}></path></svg></div><h3>{v.t.sec2h}</h3><p>{v.t.sec2}</p></div>{" "}<div className={"sbox"}><div className={"ico"}><svg viewBox={"0 0 24 24"}><rect x={"2.5"} y={"7"} width={"8"} height={"10"} rx={"2"} fill={"none"} stroke={"currentColor"} strokeWidth={"2"}></rect><rect x={"13.5"} y={"7"} width={"8"} height={"10"} rx={"2"} fill={"none"} stroke={"currentColor"} strokeWidth={"2"}></rect><path d={"M5 12h3M16 12h3"} stroke={"currentColor"} strokeWidth={"2"} strokeLinecap={"round"}></path></svg></div><h3>{v.t.sec3h}</h3><p>{v.t.sec3}</p></div>{" "}<div className={"sbox"}><div className={"ico"}><svg viewBox={"0 0 24 24"}><path d={"M8 7 3 12l5 5M16 7l5 5-5 5M13.5 4.5l-3 15"} fill={"none"} stroke={"currentColor"} strokeWidth={"2"} strokeLinecap={"round"} strokeLinejoin={"round"}></path></svg></div><h3>{v.t.sec4h}</h3><p>{v.t.sec4}</p></div>{" "}</div>{" "}<dl className={"secpanel"}>{" "}<dt>{v.t.perm1h}</dt><dd>{v.t.perm1}</dd>{" "}<dt>{v.t.perm2h}</dt><dd>{v.t.perm2}</dd>{" "}</dl>{" "}</div>{" "}</section>{" "}<section className={"sec"} id={"compativeis"} style={{"paddingTop": "0"}}>{" "}<div className={"wrap"}>{" "}<div className={"eyebrow"}><span className={"star4"}></span>{v.t.cpEy}</div>{" "}<h2 className={"h2"}>{v.t.cpH}</h2>{" "}<div className={"grid2"}>{" "}<div className={"compat"}>{" "}<h3>{v.t.cpTab}</h3>{" "}<div className={"it"}><span className={"chipok"}>{v.t.cpTested}</span><div><b>{"Galaxy Tab S11"}</b><span className={"spec"}>{"SM\u2011X730 \u00b7 2560\u00d71600 \u00b7 120 Hz"}</span></div></div>{" "}<div className={"it"}><span className={"chipok wait"}>{v.t.cpCheck}</span><div><b>{v.t.cpOtherTabs}</b><span>{v.t.cpOtherTabsP}</span></div></div>{" "}<div className={"it"}><span className={"chipok"}>{v.t.cpReq}</span><div><b>{"Android 12+"}</b><span>{v.t.cpAndroidP}</span></div></div>{" "}</div>{" "}<div className={"compat"}>{" "}<h3>{"Mac"}</h3>{" "}<div className={"it"}><span className={"chipok"}>{v.t.cpReq}</span><div><b>{"macOS 14 Sonoma+"}</b><span>{v.t.cpMacP}</span></div></div>{" "}<div className={"it"}><span className={"chipok"}>{v.t.cpReq}</span><div><b>{"Apple Silicon (M1+)"}</b><span>{v.t.cpChipP}</span></div></div>{" "}<div className={"it"}><span className={"chipok"}>{v.t.cpConn}</span><div><b>{v.t.cpConnH}</b><span>{v.t.cpConnP}</span></div></div>{" "}</div>{" "}</div>{" "}</div>{" "}</section>{" "}<section className={"sec"} id={"comparar"} style={{"paddingTop": "0"}}>{" "}<div className={"wrap"}>{" "}<div className={"eyebrow"}><span className={"star4"}></span>{v.t.cmpEy}</div>{" "}<h2 className={"h2"}>{v.t.cmpH}</h2>{" "}<p className={"sub"}>{v.t.cmpP}</p>{" "}<div className={"cmphint"}>{v.t.cmpSwipe}</div>{" "}<div className={"cmpwrap"}>{" "}<div className={"cmp"} role={"table"} aria-label={v.t.cmpH}>{" "}<div className={"hc corner"} role={"columnheader"}><small>{v.t.cmpCol}</small></div>{" "}{(v.cmpCols || []).map((col, $index) => (<React.Fragment key={$index}>{" "}<div className={`hc ${col.cls}`} role={"columnheader"}><span className={"nm"}>{col.name}</span><small>{col.by}</small></div>{" "}</React.Fragment>))}{" "}{(v.cmpRows || []).map((row, $index) => (<React.Fragment key={$index}>{" "}<div className={"rh"} role={"rowheader"}>{row.label}</div>{" "}{(row.cells || []).map((c, $index) => (<React.Fragment key={$index}>{" "}<div className={`cell ${c.cls}`} role={"cell"}><span className={"mk"}>{c.isYes ? (<><svg viewBox={"0 0 10 10"} aria-hidden={"true"}><path d={"M5 0 6 4 10 5 6 6 5 10 4 6 0 5 4 4Z"}></path></svg></>) : null}{c.word}</span><span className={"note"}>{c.note}</span></div>{" "}</React.Fragment>))}{" "}</React.Fragment>))}{" "}</div>{" "}</div>{" "}<p className={"cmpfoot"}>{v.t.cmpFoot}</p>{" "}</div>{" "}</section>{" "}<section className={"sec"} id={"faq"} style={{"paddingTop": "0"}}>{" "}<div className={"wrap"}>{" "}<div className={"eyebrow"}><span className={"star4"}></span>{"FAQ"}</div>{" "}<h2 className={"h2"}>{v.t.faqH}</h2>{" "}<div className={"faq"}>{" "}{(v.faq || []).map((q, $index) => (<React.Fragment key={$index}>{" "}<details><summary>{q.q}</summary><div className={"ans"}>{q.a}</div></details>{" "}</React.Fragment>))}{" "}</div>{" "}</div>{" "}</section>{" "}<section className={"sec"} id={"aberto"} style={{"paddingTop": "0"}}>{" "}<div className={"wrap"}>{" "}<div className={"eyebrow"}><span className={"star4"}></span>{v.t.ossEy}</div>{" "}<h2 className={"h2"}>{v.t.ossH}</h2>{" "}<div className={"oss"}>{" "}<div className={"ossbox"}>{" "}<h3>{v.t.ossBoxH}</h3>{" "}<p>{v.t.ossBoxP}</p>{" "}<div className={"code"}><i>{"$"}</i>{" git clone "}<b>{v.githubRepo}</b>{"\n"}<i>{"$"}</i>{" open mac/        "}<i>{"# SwiftUI"}</i>{"\n"}<i>{"$"}</i>{" open android/    "}<i>{"# Kotlin"}</i></div>{" "}<div className={"ctas"}>{" "}<a className={"cta primary"} href={v.githubRepo}>{v.t.ossCode}</a>{" "}<a className={"cta ghost"} href={v.githubIssues}>{v.t.ossContrib}</a>{" "}</div>{" "}</div>{" "}<div className={"road"}>{" "}<h3>{v.t.roadH}</h3>{" "}<p>{v.t.roadP}</p>{" "}<div className={"ritem soon"}><span className={"dot"}></span><div><b data-tag={v.t.soon}>{"Linux"}</b><span>{v.t.roadLinux}</span></div></div>{" "}<div className={"ritem"}><span className={"dot"}></span><div><b>{v.t.roadMultiH}</b><span>{v.t.roadMulti}</span></div></div>{" "}<div className={"ritem"}><span className={"dot"}></span><div><b>{v.t.roadSignH}</b><span>{v.t.roadSign}</span></div></div>{" "}<div className={"ritem"}><span className={"dot"}></span><div><b>{v.t.roadIdeaH}</b><span>{v.t.roadIdea}{" "}<a href={v.githubIssues}>{v.t.roadIdeaLink}</a></span></div></div>{" "}</div>{" "}</div>{" "}</div>{" "}</section>{" "}<section className={"sec"} id={"autor"} style={{"paddingTop": "0"}}>{" "}<div className={"wrap"}>{" "}<div className={"author"}>{" "}<div className={"av"}><img src={A + "ginga-monogram-dark.svg"} alt={""} /></div>{" "}<div>{" "}<div className={"eyebrow"}><span className={"star4"}></span>{v.t.auEy}</div>{" "}<h3 style={{"marginTop": "10px"}}>{v.t.auH}</h3>{" "}<p>{v.t.auP}</p>{" "}<div className={"sig"}>{v.t.auSig}</div>{" "}</div>{" "}</div>{" "}</div>{" "}</section>{" "}<section className={"sec"} id={"baixar"} style={{"paddingTop": "0"}}>{" "}<div className={"wrap"}>{" "}<div className={"band"}>{" "}<canvas className={"dither gal"} ref={v.refGal} width={"120"} height={"120"} aria-hidden={"true"}></canvas>{" "}<div className={"bt"}>{" "}<h2>{v.t.dlH}</h2>{" "}<p>{v.t.dlP}</p>{" "}<div className={"ctas"}>{" "}<a className={"cta primary"} href={v.github}>{v.t.ctaMac}<small>{"GitHub"}</small></a>{" "}<a className={"cta ghost"} href={v.github}>{v.t.ctaAnd}<small>{"APK"}</small></a>{" "}</div>{" "}<div className={"mini"}><span><b>{"1"}</b>{v.t.s1h}</span><span><b>{"2"}</b>{v.t.s2h}</span><span><b>{"3"}</b>{v.t.s3h}</span></div>{" "}<div className={"req"}>{v.t.req}</div>{" "}</div>{" "}</div>{" "}</div>{" "}</section>{" "}<footer className={"wrap"}>{" "}<div className={"foot"}>{" "}{v.isLight ? (<><img src={A + "ginga-wordmark.svg"} alt={"ginga"} /></>) : null}{" "}{v.isDark ? (<><img src={A + "ginga-wordmark-dark.svg"} alt={"ginga"} /></>) : null}{" "}<p className={"legal"} style={{"margin": "0"}}>{v.t.legal}</p>{" "}<div className={"fl"}><a href={v.githubRepo}>{"GitHub"}</a><a href={"#faq"}>{"FAQ"}</a><a href={"#seguranca"}>{v.t.navSec}</a><a href={"#baixar"}>{v.t.navDl}</a></div>{" "}</div>{" "}</footer>{" "}</div>{" "}</>);
  }
}

