import React from "react";
import { AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { C, dur, ease } from "./theme";
import { F } from "./fonts";
import { t as tr, type Lang } from "./i18n";
import type { Cam, Key, Layout, Timeline } from "./timeline";
import { PixelSky } from "./components/PixelSky";
import { DitherBlackHole } from "./components/DitherBlackHole";
import { MacBook, MACBOOK, Wallpaper } from "./components/MacBook";
import { GalaxyTab, TAB } from "./components/GalaxyTab";
import { GingaWindow, PAIR_BTN, Spark } from "./components/GingaWindow";
import { Comet } from "./components/Comet";
import { Warp } from "./components/Warp";
import { CONNECT_BTN, NOTES, NotesWindow, TabletFound, TabletPairing, TabletSearching, TabletStream, TabletWaiting } from "./components/TabletScreens";
import { Cursor, Finger, SPen } from "./components/Pointers";

/* O mundo inteiro é função do tempo t (segundos): cada quadro se calcula sozinho.
   Coordenadas: palco (layout), tela do Mac (MW×MH) e tela do tablet (TW×TH). */

const MW = MACBOOK.w - MACBOOK.pad * 2, MH = MACBOOK.h - MACBOOK.pad - 20;
const TW = TAB.w - TAB.pad * 2, TH = TAB.h - TAB.pad * 2;
const WIN = { x: 60, y: 54 };
const TOGGLE = { x: WIN.x + 364, y: WIN.y + 142 };
const NOTES_MAC = { x: 520, y: 250 };
const GRAB = { x: 80, y: 14 };

const cl = (v: number) => (v < 0 ? 0 : v > 1 ? 1 : v);
const ramp = (t: number, a: number, len: number, e: (p: number) => number = ease.out) => e(cl((t - a) / len));
const lerp = (a: number, b: number, p: number) => a + (b - a) * p;

function camAt(keys: Cam[], t: number) {
  if (t <= keys[0].t) return keys[0];
  for (let i = 0; i < keys.length - 1; i++) {
    const a = keys[i], b = keys[i + 1];
    if (t <= b.t) { const p = ease.inOut(cl((t - a.t) / (b.t - a.t))); return { t, cx: lerp(a.cx, b.cx, p), cy: lerp(a.cy, b.cy, p), z: lerp(a.z, b.z, p) }; }
  }
  return keys[keys.length - 1];
}
function keyAt(keys: Key[], t: number) {
  if (t <= keys[0].t) return keys[0];
  for (let i = 0; i < keys.length - 1; i++) {
    const a = keys[i], b = keys[i + 1];
    if (t <= b.t) { const p = ease.inOut(cl((t - a.t) / (b.t - a.t))); return { t, x: lerp(a.x, b.x, p), y: lerp(a.y, b.y, p) }; }
  }
  return keys[keys.length - 1];
}
/** Curva suave (Catmull-Rom) pelos pontos da tinta da S Pen, amostrada. */
const INK = [[14, 92], [30, 66], [46, 64], [54, 80], [70, 98], [86, 70], [104, 36], [120, 62], [138, 94], [156, 58], [172, 38], [186, 48]];
const inkPts = (() => {
  const out: [number, number][] = [];
  for (let i = 0; i < INK.length - 1; i++) {
    const p0 = INK[Math.max(0, i - 1)], p1 = INK[i], p2 = INK[i + 1], p3 = INK[Math.min(INK.length - 1, i + 2)];
    for (let k = 0; k < 16; k++) {
      const u = k / 16, u2 = u * u, u3 = u2 * u;
      const f = (a: number, b: number, c: number, d: number) => 0.5 * (2 * b + (-a + c) * u + (2 * a - 5 * b + 4 * c - d) * u2 + (-a + 3 * b - 3 * c + d) * u3);
      // viewBox 200×116 → área das linhas da nota
      out.push([18 + (f(p0[0], p1[0], p2[0], p3[0]) / 200) * 254, 44 + (f(p0[1], p1[1], p2[1], p3[1]) / 116) * 140]);
    }
  }
  out.push([18 + (186 / 200) * 254, 44 + (48 / 116) * 140]);
  return out;
})();

export const Caption: React.FC<{ text: string; t: number; from: number; to: number; L: Layout }> = ({ text, t, from, to, L }) => {
  const i = ramp(t, from, dur.sheet / 1000), o = ramp(t, to - dur.ui / 1000, dur.ui / 1000);
  if (t < from || t > to) return null;
  return (
    <div style={{ position: "absolute", left: (L.w - L.caption.width) / 2, width: L.caption.width, bottom: L.caption.bottom, textAlign: "center", font: `600 ${L.caption.size}px/1.2 ${F.display}`, letterSpacing: "-0.01em", color: C.nevoa, opacity: i * (1 - o), transform: `translateY(${(1 - i) * 14}px)`, textShadow: "0 2px 24px rgba(10,12,28,.9)" }}>{text}</div>
  );
};

export type WorldProps = { lang: Lang; repoUrl: string; tl: Timeline; L: Layout };

export const World: React.FC<WorldProps> = ({ lang, repoUrl, tl, L }) => {
  const s = tr(lang);
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const t = frame / fps;

  // ---- intro / outro: buraco negro + logotipo ----
  const introIn = ramp(t, 0, 0.9), introAway = ramp(t, tl.introOut, 1.2, ease.inOut);
  const outroSwallow = ramp(t, tl.outro, 1.2, (p) => p * p * p);
  const outroBh = ramp(t, tl.outro + 0.1, 1.1, ease.out);
  const bhOpacity = t < tl.outro ? introIn * (1 - introAway) : outroBh;
  const bhScale = t < tl.outro ? lerp(0.85, 1, introIn) * lerp(1, 0.3, introAway) : lerp(0.35, 1, outroBh);
  const bhPull = t < tl.outro ? 0 : 1 - ramp(t, tl.outro + 0.6, 1.4);
  const logoIn = t < tl.outro ? ramp(t, 0.7, dur.sheet / 1000 * 1.6, ease.ginga) : ramp(t, tl.outro + 1.25, dur.sheet / 1000 * 1.6, ease.ginga);
  const logoOp = t < tl.outro ? cl((t - 0.7) / 0.3) * (1 - introAway) : cl((t - tl.outro - 1.25) / 0.3);
  const endText = ramp(t, tl.outro + 1.6, 0.5), endUrl = ramp(t, tl.outro + 1.85, 0.5);
  const worldOp = cl((t - tl.introOut) / 1.0) * (1 - outroSwallow);
  const swallow = lerp(1, 0.12, outroSwallow);

  // ---- câmera ----
  const cam = camAt(tl.cam, t);
  const camT = `translate(${L.w / 2}px, ${L.h / 2}px) scale(${cam.z}) translate(${-cam.cx}px, ${-cam.cy}px)`;

  // ---- Mac ----
  const wifiOn = ramp(t, tl.wifiClick + 0.05, dur.ui / 1000, ease.ginga);
  const pairing = tl.found !== null;
  const cometLen = dur.warp / 1000, cometEnd = tl.comet + cometLen;
  const warpStart = cometEnd - 0.06, warpLen = 1.1, firstFrame = warpStart + warpLen - 0.08;
  const sheet = pairing ? ramp(t, tl.code, dur.sheet / 1000, ease.ginga) * (1 - ramp(t, tl.pairClick + 0.25, dur.ui / 1000)) : 0;
  const status =
    t < tl.wifiClick + 0.1 ? { k: "off" as const, l: s.off }
    : pairing && t < tl.code ? { k: "searching" as const, l: s.advertising }
    : pairing && t < tl.pairClick + 0.1 ? { k: "pairing" as const, l: s.awaitingCode }
    : !pairing && t < tl.comet ? { k: "searching" as const, l: s.advertising }
    : t < cometEnd ? { k: "searching" as const, l: s.connecting }
    : { k: "connected" as const, l: s.connected.split(" · ")[0] };
  const row = ramp(t, cometEnd + 0.1, dur.sheet / 1000, ease.ginga);

  // janela de notas no desktop virtual (Mac + tablet)
  const O = L.extend === "right" ? { x: MW, y: 160 } : { x: 380, y: MH };
  const notesEnd = L.extend === "right" ? { x: MW + 140, y: NOTES_MAC.y } : { x: NOTES_MAC.x, y: MH + 70 };
  const dp = ease.inOut(cl((t - tl.dragStart) / (tl.dragEnd - tl.dragStart)));
  const notes = { x: lerp(NOTES_MAC.x, notesEnd.x, dp), y: lerp(NOTES_MAC.y, notesEnd.y, dp) };
  const notesTab = { x: notes.x - O.x, y: notes.y - O.y };

  // cursor: keyframes, e durante o arraste preso à barra da janela
  const dragging = t >= tl.dragStart - 0.15;
  const cur = dragging ? { x: notes.x + GRAB.x, y: notes.y + GRAB.y } : keyAt(tl.cursor, t);
  const press = Math.max(0, ...tl.clicks.map((c) => (t >= c - 0.06 && t < c + 0.14 ? Math.sin(Math.PI * cl((t - c + 0.06) / 0.2)) : 0)), t >= tl.dragStart - 0.1 && t < tl.dragEnd ? 1 : 0);
  const curOp = cl((t - tl.introOut - 0.6) / 0.4) * (1 - ramp(t, tl.dragEnd + 0.4, 0.4));
  const onMac = cur.x <= MW && cur.y <= MH;

  // ---- tablet ----
  const pen = cl((t - tl.pen) / (tl.penEnd - tl.pen));
  const penN = Math.max(1, Math.round(ease.inOut(pen) * (inkPts.length - 1)));
  const penTip = inkPts[penN];
  const penOp = cl((t - tl.pen + 0.35) / 0.3) * (1 - cl((t - tl.penEnd - 0.1) / 0.3));
  const tapP = cl((t - tl.touch - 0.2) / 0.4);
  const scroll = 70 * ramp(t, tl.touch + 0.7, 0.8);
  const fingerOp = cl((t - tl.touch + 0.2) / 0.2) * (1 - cl((t - tl.touch - 1.6) / 0.3));
  const fingerY = 130 - scroll;

  let tabletScreen: React.ReactNode;
  if (pairing && tl.found !== null && t >= tl.found && t < tl.code) {
    const tapT = cl((t - tl.tap) / 0.4);
    const fx = interpolate(t, [tl.found + 0.4, tl.tap - 0.05], [TW * 0.6, CONNECT_BTN.x], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease.out });
    const fy = interpolate(t, [tl.found + 0.4, tl.tap - 0.05], [TH * 0.9, CONNECT_BTN.y], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: ease.out });
    tabletScreen = <>
      <TabletFound s={s} rise={ramp(t, tl.found, dur.sheet / 1000, ease.ginga)} press={Math.sin(Math.PI * tapT)} />
      <Finger x={fx} y={fy} tap={tapT} opacity={cl((t - tl.found - 0.3) / 0.2)} />
    </>;
  } else if (pairing && t >= tl.code && t < tl.comet) tabletScreen = <TabletPairing s={s} codeT={t - tl.code} />;
  else if (t < tl.comet - (pairing ? 0 : 0.4)) tabletScreen = <TabletSearching s={s} />;
  else if (t < firstFrame) tabletScreen = <TabletWaiting s={s} pull={interpolate(t, [cometEnd - 0.5, cometEnd], [0, 0.8], { extrapolateLeft: "clamp", extrapolateRight: "clamp" })} />;
  else tabletScreen = (
    <TabletStream s={s} toast={ramp(t, firstFrame + 0.08, dur.sheet / 1000, ease.ginga) * (1 - ramp(t, firstFrame + 3.2, 0.4))}>
      {t >= tl.dragStart && (
        <NotesWindow s={s} scroll={scroll} style={{ left: notesTab.x, top: notesTab.y }}>
          <svg width={NOTES.w} height={NOTES.h} style={{ position: "absolute", left: 0, top: 0, transform: `translateY(${-scroll}px)` }}>
            <polyline points={inkPts.slice(0, t >= tl.pen ? penN + 1 : 0).map((p) => p.join(",")).join(" ")} fill="none" stroke={C.star} strokeWidth={3.5} strokeLinecap="round" strokeLinejoin="round" style={{ filter: "drop-shadow(0 0 4px rgba(255,196,61,.6))" }} />
          </svg>
        </NotesWindow>
      )}
      {penOp > 0 && <SPen x={notesTab.x + penTip[0]} y={notesTab.y + penTip[1]} opacity={penOp} />}
      {fingerOp > 0 && <Finger x={notesTab.x + 150} y={notesTab.y + fingerY} tap={tapP} opacity={fingerOp} />}
      {!onMac && curOp > 0 && <Cursor x={cur.x - O.x} y={cur.y - O.y} press={press} opacity={curOp} />}
    </TabletStream>
  );

  // ---- cometa (palco) ----
  const macScreen = { x: L.mac.x + MACBOOK.pad, y: L.mac.y + MACBOOK.pad };
  const from = { x: macScreen.x + WIN.x + 460, y: macScreen.y + WIN.y + 38 };
  const to = { x: L.tab.x + TAB.w * 0.47, y: L.tab.y + TAB.h * 0.42 };

  const caption = tl.captions.find((c) => t >= c.from && t <= c.to);

  return (
    <AbsoluteFill style={{ background: C.cosmos, overflow: "hidden" }}>
      <PixelSky width={L.w} height={L.h} />

      {worldOp > 0 && (
        <AbsoluteFill style={{ opacity: worldOp, transform: `translate(${L.bh.cx}px, ${L.bh.cy}px) scale(${swallow}) translate(${-L.bh.cx}px, ${-L.bh.cy}px)` }}>
          <div style={{ position: "absolute", left: 0, top: 0, width: L.w, height: L.h, transformOrigin: "0 0", transform: camT }}>
            <MacBook style={{ left: L.mac.x, top: L.mac.y }}>
              <Wallpaper />
              {t < tl.dragStart + 0.1 || notes.x < MW ? <NotesWindow s={s} style={{ left: notes.x, top: notes.y }} /> : null}
              <GingaWindow s={s} status={status.k} statusLabel={status.l} wifiOn={wifiOn} tabletRow={row} sheet={sheet} codeT={t - tl.code} pairPress={pairing ? Math.sin(Math.PI * cl((t - tl.pairClick + 0.06) / 0.2)) : 0} style={{ left: WIN.x, top: WIN.y }} />
              <Spark p={(t - tl.wifiClick) / 0.52} x={TOGGLE.x} y={TOGGLE.y} />
              {pairing && <Spark p={(t - tl.pairClick) / 0.52} x={WIN.x + PAIR_BTN.x} y={WIN.y + PAIR_BTN.y} seed={2} />}
              {onMac && curOp > 0 && <Cursor x={cur.x} y={cur.y} press={press} opacity={curOp} />}
            </MacBook>
            <GalaxyTab style={{ left: L.tab.x, top: L.tab.y }} screenBg={C.cosmos}>
              {tabletScreen}
              <Warp p={(t - warpStart) / warpLen} width={TW} height={TH} />
            </GalaxyTab>
            <Comet from={from} to={to} p={(t - tl.comet) / cometLen} ring={(t - cometEnd) / 0.7} width={L.w} height={L.h} />
          </div>
        </AbsoluteFill>
      )}

      {bhOpacity > 0 && (
        <div style={{ position: "absolute", left: L.bh.cx - L.bh.w / 2, top: L.bh.cy - L.bh.h / 2, width: L.bh.w, height: L.bh.h, opacity: bhOpacity, transform: `scale(${bhScale})` }}>
          <DitherBlackHole width={L.bh.w} height={L.bh.h} pull={bhPull} />
        </div>
      )}
      {logoOp > 0 && (
        <div style={{ position: "absolute", left: 0, right: 0, top: L.logo.cy - (L.logo.w * 423) / 1200 / 2, display: "flex", flexDirection: "column", alignItems: "center", opacity: logoOp, transform: t < tl.outro ? `scale(${lerp(1, 0.6, introAway)})` : undefined }}>
          <Img src={staticFile("logos/ginga-wordmark-dark.png")} style={{ width: L.logo.w, transform: `scale(${lerp(0.9, 1, logoIn)})` }} />
          {t >= tl.outro && <>
            <div style={{ marginTop: 22, font: `500 ${L.caption.size * 0.72}px/1.3 ${F.sans}`, color: C.nevoa, opacity: endText, transform: `translateY(${(1 - endText) * 10}px)` }}>{s.openSource}</div>
            <div style={{ marginTop: 10, font: `400 ${L.caption.size * 0.56}px/1.3 ${F.mono}`, color: C.star, opacity: endUrl, transform: `translateY(${(1 - endUrl) * 10}px)` }}>{repoUrl}</div>
          </>}
        </div>
      )}

      {caption && <Caption text={s[caption.key]} t={t} from={caption.from} to={caption.to} L={L} />}
    </AbsoluteFill>
  );
};
