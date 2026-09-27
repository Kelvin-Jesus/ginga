# Starfield

O céu da marca: fundo `cosmos` com estrelas `stardust`, algumas `cobalt` e `star`, cintilando e derivando devagar.

**O consumidor fornece** um contêiner `.g-sky` com um `<canvas>` e chama `Ginga.starfield(canvas)`.

- Só em telas de marca: onboarding, espera do stream no tablet, conexão direta, site. Nunca atrás de formulários.
- Performance: uma camada, DPR até 1.5, ~0.22 estrela por 1000 px²; pausa com a aba oculta ou fora da tela; movimento reduzido desenha um quadro parado.
- Texto por cima em `stardust` (17.5:1 em `cosmos`).
