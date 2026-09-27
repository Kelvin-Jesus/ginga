# Vídeos do Ginga (Remotion)

Vídeos de demonstração do Ginga, feitos com o design system em `../design/ginga-design/` (tokens, logos, DitherSpace).

| Composição | Formato | Duração | Uso |
|---|---|---|---|
| `GingaHero-pt` / `-en` | 1920×1080, 60 fps | 30 s | site, README, YouTube |
| `GingaVertical-pt` / `-en` | 1080×1920, 60 fps | 20 s | Reels, TikTok, Shorts |
| `GingaLoop-pt` | 1600×1000, 30 fps | 8 s, loop perfeito | fundo do topo do site (sem texto; `-en` é idêntico) |
| `GingaTeaser-pt` / `-en` | 3840×2160, 60 fps | 6 s | teaser cinético (3 palavras + logo) |
| `GingaKeynote-pt` / `-en` | 3840×2160, 60 fps | 10 s | teaser 3D estilo keynote (Three.js + pós-produção) |
| `CometPreview-pt` / `-en` | 1920×1080, 60 fps | 3 s | a cena do cometa isolada |

## Renderizar

```sh
npm install
npm run studio            # pré-visualizar e ajustar no navegador
npm run render:hero       # out/ginga-hero-{pt,en}.mp4
npm run render:vertical   # out/ginga-vertical-{pt,en}.mp4
npm run render:loop       # out/ginga-loop.{webm,mp4}
npm run srt               # subtitles/ginga-hero.{pt,en}.srt
npm run render:teaser     # out/ginga-teaser-{pt,en}.mp4
npm run render:keynote:proxy  # out/ginga-keynote-pt-proxy.mp4 em 1280×720, para iterar
npm run render:keynote    # 4K H.264 CRF 16 + masters ProRes 4444 em out/
```

## GingaKeynote

`src/keynote/`: `GingaKeynote` (um único `ThreeCanvas`), `Shots.tsx` (os seis planos), `CameraRig` (chaves de posição, alvo e FOV; deriva, push-in e tremor nos hits), `Devices3D`, `PostFX` (DoF → títulos → bloom, aberração, onda de choque/lente, grão, vinheta, fade), `HeadlineReveal`, `LightSweep`, `AnamorphicFlare`, `Shockwave`, `LensingPass`, `poses.ts` e `timing.ts` (quadros de cada plano e hits).
WebGL no render usa `Config.setChromiumOpenGlRenderer("angle")` (em `remotion.config.ts`). Sons: veja `public/sfx/README.md` e renderize com `--props='{"lang":"pt","sfx":true}'`.

A URL do repositório no fechamento é a prop `repoUrl` (padrão em `src/Root.tsx`). Para trocar sem editar o código: `npx remotion render GingaHero-pt out/x.mp4 --props='{"lang":"pt","repoUrl":"github.com/…"}'`, e `node scripts/srt.ts github.com/…` para as legendas.

## Como está organizado

- `src/timeline.ts`: roteiro em segundos (eventos, câmera, cursor, legendas) e o layout de cada formato. É aqui que se ajusta o tempo.
- `src/World.tsx`: o mundo inteiro como função do tempo. Hero e Vertical são o mesmo `World` com timelines e layouts diferentes.
- `src/i18n.ts`: todo texto na tela, pt e en.
- `src/components/`: `DitherBlackHole` e `PixelSky` (portados do `bundle.js`), `MacBook`, `GalaxyTab`, `GingaWindow`, `PairingCode`, `Comet`, `Warp`, `Cursor`/`Finger`/`SPen` (`Pointers.tsx`), `StatusPill`, telas do tablet.

Regras: cada quadro se calcula sozinho a partir de `useCurrentFrame()` (RNG com semente, nada acumula entre quadros), porque o Remotion renderiza fora de ordem. Só as cores de `tokens.json`; curvas `ease-ginga`/`ease-out` e durações dos tokens em `src/theme.ts`. No loop, toda fase é `2π·k·frame/total` com `k` inteiro.
