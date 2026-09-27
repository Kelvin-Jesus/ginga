import { AbsoluteFill } from "remotion";
import { C } from "../theme";
import { F } from "../fonts";
import type { Strings } from "../i18n";
import { DitherBlackHole } from "./DitherBlackHole";
import { StatusPill } from "./StatusPill";
import { Wallpaper } from "./MacBook";
import { TAB } from "./GalaxyTab";

const SW = TAB.w - TAB.pad * 2, SH = TAB.h - TAB.pad * 2;

/** Espera do stream no tablet: buraco negro em dithering até o primeiro quadro. */
export const TabletWaiting: React.FC<{ s: Strings; pull?: number }> = ({ s, pull = 0 }) => (
  <AbsoluteFill style={{ background: C.cosmos, color: C.nevoa }}>
    <DitherBlackHole width={SW} height={SH * 0.98} pull={pull} style={{ left: 0, top: -SH * 0.07 }} />
    <div style={{ position: "absolute", left: 26, right: 26, bottom: 22, display: "flex", alignItems: "flex-end", justifyContent: "space-between" }}>
      <div style={{ font: `600 19px/26px ${F.display}` }}>{s.streamingFrom}</div>
      <StatusPill kind="searching" label={s.connecting} glass size={0.9} />
    </div>
  </AbsoluteFill>
);

/** Janela de notas genérica (vai do Mac para o tablet). */
export const NotesWindow: React.FC<{ s: Strings; style?: React.CSSProperties; w?: number; h?: number }> = ({ s, style, w = 290, h = 200 }) => (
  <div style={{ position: "absolute", width: w, height: h, borderRadius: 14, background: C.surfaceDark, color: C.nevoa, boxShadow: "0 24px 64px rgba(0,0,0,.55), inset 0 1px 0 rgba(255,255,255,.05)", padding: "40px 18px 14px", boxSizing: "border-box", ...style }}>
    <div style={{ position: "absolute", top: 12, left: 18, font: `600 14px/18px ${F.sans}`, color: C.inkMuted }}>{s.notesTitle}</div>
    {[1, 0.6, 0.85, 1, 0.5, 0.8].map((wd, i) => <div key={i} style={{ height: 8, borderRadius: 4, margin: "10px 0", width: `${wd * 100}%`, background: i === 2 ? C.cobaltSoftDark : C.surface2Dark }} />)}
  </div>
);

/** Área de trabalho estendida no tablet (o primeiro quadro). */
export const TabletStream: React.FC<{ s: Strings; toast: number; notesX?: number }> = ({ s, toast, notesX = 150 }) => (
  <AbsoluteFill style={{ background: C.cosmos }}>
    <Wallpaper flip scale={0.75} />
    <NotesWindow s={s} style={{ left: notesX, top: 70 }} />
    <div style={{ position: "absolute", left: "50%", top: 16, transform: `translate(-50%, ${(1 - toast) * -16}px)`, opacity: Math.min(1, toast) }}>
      <StatusPill kind="connected" label={s.connected} glass size={0.95} />
    </div>
  </AbsoluteFill>
);
