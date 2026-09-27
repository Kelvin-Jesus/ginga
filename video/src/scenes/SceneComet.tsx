import { AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { C, dur, ease, ms } from "../theme";
import { t as tr, type Lang } from "../i18n";
import { PixelSky } from "../components/PixelSky";
import { MacBook, MACBOOK, Wallpaper } from "../components/MacBook";
import { GalaxyTab, TAB } from "../components/GalaxyTab";
import { GingaWindow } from "../components/GingaWindow";
import { Comet } from "../components/Comet";
import { Warp } from "../components/Warp";
import { TabletStream, TabletWaiting } from "../components/TabletScreens";

/* Cena 5 · O cometa (15–19 s do GingaHero). Palco 1920×1080.
   A câmera abre para os dois aparelhos; cometa Mac → tablet em dur-warp; anel; warp até o primeiro quadro. */
export const MAC_AT = { x: 150, y: 250 };
export const TAB_AT = { x: 1175, y: 430 };

export const SceneComet: React.FC<{ lang: Lang }> = ({ lang }) => {
  const s = tr(lang);
  const f = useCurrentFrame();
  const { fps, width, height } = useVideoConfig();

  const cometStart = ms(300, fps), cometLen = ms(dur.warp, fps);
  const cometEnd = cometStart + cometLen;
  const ringLen = ms(700, fps), warpStart = cometEnd - ms(60, fps), warpLen = ms(1100, fps);
  const firstFrame = warpStart + warpLen - ms(80, fps);

  const cam = interpolate(f, [0, ms(700, fps)], [1.07, 1], { easing: ease.out, extrapolateRight: "clamp" });
  const p = (f - cometStart) / cometLen;
  const ring = (f - cometEnd) / ringLen;
  const warp = (f - warpStart) / warpLen;
  const connected = f >= cometEnd;
  const row = interpolate(f, [cometEnd + ms(100, fps), cometEnd + ms(100 + dur.sheet, fps)], [0, 1], { easing: ease.ginga, extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const toast = interpolate(f, [firstFrame + ms(80, fps), firstFrame + ms(80 + dur.sheet, fps)], [0, 1], { easing: ease.ginga, extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  // o buraco negro puxa as órbitas enquanto o cometa chega
  const pull = interpolate(f, [cometEnd - ms(500, fps), cometEnd], [0, 0.8], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

  const macScreen = { x: MAC_AT.x + MACBOOK.pad, y: MAC_AT.y + MACBOOK.pad };
  const from = { x: macScreen.x + 520, y: macScreen.y + 92 }; // status do Ginga na janela
  const to = { x: TAB_AT.x + TAB.w * 0.47, y: TAB_AT.y + TAB.h * 0.42 };

  return (
    <AbsoluteFill style={{ background: C.cosmos, overflow: "hidden" }}>
      <PixelSky width={width} height={height} />
      <AbsoluteFill style={{ transform: `scale(${cam})` }}>
        <MacBook style={{ left: MAC_AT.x, top: MAC_AT.y }}>
          <Wallpaper />
          <GingaWindow s={s} status={connected ? "connected" : "searching"} statusLabel={connected ? s.connected.split(" · ")[0] : s.connecting} wifiOn={1} tabletRow={row} style={{ left: 60, top: 54 }} />
        </MacBook>
        <GalaxyTab style={{ left: TAB_AT.x, top: TAB_AT.y }} screenBg={C.cosmos}>
          {f < firstFrame ? <TabletWaiting s={s} pull={pull} /> : <TabletStream s={s} toast={toast} />}
          <Warp p={warp} width={TAB.w - TAB.pad * 2} height={TAB.h - TAB.pad * 2} />
        </GalaxyTab>
        <Comet from={from} to={to} p={p} ring={ring} width={width} height={height} />
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
