# DitherSpace

Espaço em dithering pixelizado: um buraco negro com disco de acreção e uma galáxia espiral, desenhados em baixa resolução com matriz de Bayer 4×4 sobre a paleta da marca e ampliados sem suavização.

**O consumidor fornece** um `<canvas>` com resolução interna baixa (1 pixel de canvas = 4 px de tela, por exemplo `width="190" height="122"` para 760×486) e CSS `image-rendering: pixelated`, e chama:

- `Ginga.ditherLoop(canvas, Ginga.blackHole())`: gás espiralando para dentro com Doppler (lado esquerdo dourado), anel de fótons, arco lenteado, estrelas deformadas pela lente e ~700 partículas em órbita. O retorno expõe `shade.pullT` (0–1, colapso das órbitas: ligue à distância do ponteiro ou do dedo) e `shade.tb = loop.now()` (explosão das partículas: ligue a um `<button>` sobre o horizonte).
- `Ginga.ditherLoop(canvas, Ginga.galaxy({ cx, cy, s, spin }))`: espiral inclinada, núcleo `star`, braços `cobalt-brand`/`cobalt`.
- `Ginga.pixelSky(canvas)`: céu inteiro em pixels de 4 px, com cintilação e estrela cadente. Redimensiona sozinho.

Paleta (do escuro ao quente): `cosmos` (transparente), Noite, `cobalt-brand`, Cobalto noturno, `stardust`, `star`. Não use outras cores.

**Onde usar**
- Site: topo (buraco negro + céu em pixels), faixa de download (galáxia), 404.
- Apps: espera do stream no tablet (buraco negro, até o primeiro quadro), conexão sem roteador (galáxia), fundo de pareamento. No Black espacial o fundo é `#000` e o nível mais escuro fica transparente, então os pixels apagados continuam apagados.
- Nunca atrás de texto corrido ou formulários.

**Desempenho**: ~24 fps, só `putImageData` numa imagem de ~20 mil pixels; pausa fora da tela, com a aba oculta e com movimento reduzido (desenha um quadro parado). No Android: um `Bitmap` pequeno + `drawBitmap` com `isFilterBitmap = false`; no SwiftUI: `CGImage` num `Image(...).interpolation(.none)` atualizado por `TimelineView(.animation(minimumInterval: 1/24))`.
