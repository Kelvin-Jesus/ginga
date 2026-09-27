import React from "react";
import { AbsoluteFill } from "remotion";
import { C } from "../theme";
import { F } from "../fonts";
import type { Strings } from "../i18n";
import { DitherBlackHole } from "./DitherBlackHole";
import { StatusPill } from "./StatusPill";
import { Wallpaper } from "./MacBook";
import { TAB } from "./GalaxyTab";
import { Img, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { PairingCode } from "./PairingCode";

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
export const NOTES = { w: 290, h: 200 };
export const NotesWindow: React.FC<{ s: Strings; style?: React.CSSProperties; scroll?: number; children?: React.ReactNode }> = ({ s, style, scroll = 0, children }) => (
  <div style={{ position: "absolute", width: NOTES.w, height: NOTES.h, borderRadius: 14, background: C.surfaceDark, color: C.nevoa, boxShadow: "0 24px 64px rgba(0,0,0,.55), inset 0 1px 0 rgba(255,255,255,.05)", overflow: "hidden", ...style }}>
    <div style={{ position: "absolute", top: 40, left: 18, right: 18, bottom: 0, overflow: "hidden" }}>
      <div style={{ transform: `translateY(${-scroll}px)` }}>
        {[1, 0.6, 0.85, 1, 0.5, 0.8, 0.9, 0.55, 1, 0.7, 0.8, 0.45].map((wd, i) => <div key={i} style={{ height: 8, borderRadius: 4, margin: "10px 0", width: `${wd * 100}%`, background: i % 5 === 2 ? C.cobaltSoftDark : C.surface2Dark }} />)}
      </div>
    </div>
    <div style={{ position: "absolute", top: 0, left: 0, right: 0, height: 36, background: C.surfaceDark, padding: "12px 18px 0", boxSizing: "border-box", font: `600 14px/18px ${F.sans}`, color: C.inkMuted }}>{s.notesTitle}</div>
    {children}
  </div>
);

/** Área de trabalho estendida no tablet (o primeiro quadro). */
export const TabletStream: React.FC<{ s: Strings; toast: number; children?: React.ReactNode }> = ({ s, toast, children }) => (
  <AbsoluteFill style={{ background: C.cosmos }}>
    <Wallpaper flip scale={0.75} />
    {children}
    <div style={{ position: "absolute", left: "50%", top: 16, transform: `translate(-50%, ${(1 - toast) * -16}px)`, opacity: Math.min(1, toast) }}>
      <StatusPill kind="connected" label={s.connected} glass size={0.95} />
    </div>
  </AbsoluteFill>
);

const Head: React.FC<{ title: string; sub?: string }> = ({ title, sub }) => (
  <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
    <Img src={staticFile("logos/ginga-monogram-dark.png")} style={{ width: 36, height: 36 }} />
    <div><div style={{ font: `600 20px/26px ${F.display}` }}>{title}</div>{sub && <div style={{ font: `400 14px/19px ${F.sans}`, color: C.inkMuted, marginTop: 2 }}>{sub}</div>}</div>
  </div>
);

/** Procurando: radar orbitando (dur-orbit). */
export const TabletSearching: React.FC<{ s: Strings; opacity?: number }> = ({ s, opacity = 1 }) => {
  const f = useCurrentFrame(); const { fps } = useVideoConfig();
  const a = ((f / fps) / 2.4) * 360, b = -((f / fps) / 1.7) * 360, ping = ((f / fps) % 2.2) / 2.2;
  return (
    <AbsoluteFill style={{ background: C.noite, color: C.nevoa, padding: "26px 28px", opacity }}>
      <Head title={s.searching} />
      <div style={{ position: "absolute", right: 44, top: "50%", width: 170, height: 170, marginTop: -70 }}>
        <div style={{ position: "absolute", inset: 0, borderRadius: "50%", border: `1px solid ${C.lineDark}` }} />
        <div style={{ position: "absolute", inset: 32, borderRadius: "50%", border: `1px solid ${C.lineDark}` }} />
        <div style={{ position: "absolute", inset: 62, borderRadius: "50%", background: C.cobalt }} />
        <div style={{ position: "absolute", inset: 62, borderRadius: "50%", border: `1.5px solid ${C.cobaltNight}`, transform: `scale(${1 + ping * 2.2})`, opacity: 1 - ping }} />
        <div style={{ position: "absolute", inset: 0, transform: `rotate(${a}deg)` }}><i style={{ position: "absolute", top: -5, left: "50%", width: 10, height: 10, marginLeft: -5, borderRadius: "50%", background: C.star, boxShadow: "0 0 12px rgba(255,196,61,.7)" }} /></div>
        <div style={{ position: "absolute", inset: 32, transform: `rotate(${b}deg)` }}><i style={{ position: "absolute", top: -4, left: "50%", width: 8, height: 8, marginLeft: -4, borderRadius: "50%", background: C.cobaltNight }} /></div>
      </div>
      <div style={{ position: "absolute", left: 28, bottom: 24, display: "flex", gap: 8 }}>
        {["Wi‑Fi", "USB", "Direct"].map((c, i) => <span key={c} style={{ height: 30, padding: "0 13px", borderRadius: 999, display: "inline-flex", alignItems: "center", font: `500 13px/1 ${F.sans}`, color: i ? C.inkMuted : C.nevoa, background: i ? "transparent" : C.cobaltSoftDark, boxShadow: i ? `inset 0 0 0 1px ${C.lineDark}` : "none" }}>{c}</span>)}
      </div>
    </AbsoluteFill>
  );
};

/** Mac encontrado: a linha sobe (`rise` 0–1) com Conectar (`press` 0–1). */
export const CONNECT_BTN = { x: 470, y: 132 };
export const TabletFound: React.FC<{ s: Strings; rise: number; press?: number }> = ({ s, rise, press = 0 }) => (
  <AbsoluteFill style={{ background: C.noite, color: C.nevoa, padding: "26px 28px" }}>
    <Head title={s.macNearby} sub={s.macNearbySub} />
    <div style={{ marginTop: 22, borderRadius: 16, background: C.surfaceDark, display: "flex", alignItems: "center", gap: 14, padding: "12px 16px", opacity: Math.min(1, rise * 1.5), transform: `translateY(${(1 - rise) * 22}px)` }}>
      <span style={{ width: 44, height: 30, borderRadius: 6, background: C.surface2Dark, boxShadow: `inset 0 0 0 2px ${C.lineDark}` }} />
      <span style={{ flex: 1, font: `500 16px/20px ${F.sans}` }}>{s.macName}<span style={{ display: "block", font: `400 12px/16px ${F.mono}`, color: C.inkMuted }}>Wi‑Fi · 192.168.0.12</span></span>
      <span style={{ height: 38, padding: "0 20px", borderRadius: 999, display: "grid", placeItems: "center", background: C.cobaltNight, color: C.noite, font: `600 14px/1 ${F.sans}`, transform: `scale(${1 - 0.03 * press})` }}>{s.connect}</span>
    </div>
  </AbsoluteFill>
);

/** Pareando: “Confirme no Mac” + código. */
export const TabletPairing: React.FC<{ s: Strings; codeT: number }> = ({ s, codeT }) => (
  <AbsoluteFill style={{ background: C.noite, color: C.nevoa, display: "flex", flexDirection: "column", alignItems: "center", paddingTop: 70, gap: 14 }}>
    <div style={{ font: `600 22px/28px ${F.display}` }}>{s.confirmOnMac}</div>
    <PairingCode t={codeT} size={44} />
    <StatusPill kind="pairing" label={s.waitingMac} size={0.95} />
  </AbsoluteFill>
);
