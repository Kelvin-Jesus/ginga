import { Img, staticFile } from "remotion";
import { C, glowStar } from "../theme";
import { F } from "../fonts";
import type { Strings } from "../i18n";
import { StatusPill, type StatusKind } from "./StatusPill";

/** Toggle do design system; `on` 0–1 já com a curva aplicada (o thumb desliza com ease-ginga). */
export const Switch: React.FC<{ on: number; s?: number }> = ({ on, s = 1 }) => (
  <span style={{ position: "relative", width: 44 * s, height: 26 * s, flex: "none", display: "inline-block" }}>
    <span style={{ position: "absolute", inset: 0, borderRadius: 999, background: C.surface2Dark, boxShadow: `inset 0 0 0 1px ${C.lineDark}` }} />
    <span style={{ position: "absolute", inset: 0, borderRadius: 999, background: C.cobaltNight, opacity: Math.min(1, Math.max(0, on)) }} />
    <span style={{ position: "absolute", top: 3 * s, left: 3 * s, width: 20 * s, height: 20 * s, borderRadius: "50%", background: C.nevoa, boxShadow: "0 1px 3px rgba(0,0,0,.35)", transform: `translateX(${18 * s * on}px)` }} />
  </span>
);

const Row: React.FC<{ icon: React.ReactNode; label: string; sub?: string; right: React.ReactNode; divider?: boolean }> = ({ icon, label, sub, right, divider }) => (
  <div style={{ position: "relative", display: "flex", alignItems: "center", gap: 12, minHeight: 50, padding: "9px 16px" }}>
    {divider && <div style={{ position: "absolute", top: 0, left: 16, right: 0, height: 1, background: C.lineDark }} />}
    <span style={{ width: 30, height: 30, borderRadius: 8, background: C.cobaltSoftDark, color: C.cobaltNight, display: "grid", placeItems: "center" }}>{icon}</span>
    <span style={{ flex: 1, font: `400 16px/21px ${F.sans}` }}>{label}{sub && <span style={{ display: "block", fontSize: 13, lineHeight: "17px", color: C.inkMuted }}>{sub}</span>}</span>
    {right}
  </div>
);

const WifiIcon = <svg width="17" height="17" viewBox="0 0 16 16"><path d="M2 6.2a8.5 8.5 0 0 1 12 0M4.3 8.6a5.2 5.2 0 0 1 7.4 0M6.6 11a2 2 0 0 1 2.8 0" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" /></svg>;
const UsbIcon = <svg width="17" height="17" viewBox="0 0 16 16"><path d="M8 1.5v9M5.5 4 8 1.5 10.5 4M4 7.5v2.5l4 2.5 4-2.5V7" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" /></svg>;

export type GingaWindowProps = {
  s: Strings; status: StatusKind; statusLabel: string;
  /** 0–1 com curva */ wifiOn: number;
  /** 0–1: linha do tablet pareado subindo (g-rise) */ tabletRow?: number;
  style?: React.CSSProperties;
};

/** Janela do Ginga no Mac (tema escuro), compacta como na demo. 420 px de largura. */
export const GingaWindow: React.FC<GingaWindowProps> = ({ s, status, statusLabel, wifiOn, tabletRow = 0, style }) => (
  <div style={{ position: "absolute", width: 420, borderRadius: 18, background: C.noite, color: C.nevoa, boxShadow: "0 24px 64px rgba(0,0,0,.55), 0 0 0 1px rgba(0,0,0,.3), inset 0 1px 0 rgba(255,255,255,.05)", overflow: "hidden", ...style }}>
    <div style={{ height: 40, display: "flex", alignItems: "center", gap: 8, padding: "0 16px" }}>
      {["#FF5F57", "#FEBC2E", "#28C840"].map((c) => <i key={c} style={{ width: 12, height: 12, borderRadius: "50%", background: c, display: "block" }} />)}
    </div>
    <div style={{ padding: "2px 18px 18px" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 14 }}>
        <Img src={staticFile("logos/ginga-monogram-dark.png")} style={{ width: 34, height: 34 }} />
        <span style={{ flex: 1, font: `600 21px/26px ${F.display}` }}>Ginga</span>
        <StatusPill kind={status} label={statusLabel} size={0.95} />
      </div>
      <div style={{ font: `600 12px/16px ${F.sans}`, letterSpacing: ".06em", textTransform: "uppercase", color: C.inkMuted, margin: "4px 0 7px 4px" }}>{s.connection}</div>
      <div style={{ borderRadius: 16, background: C.surfaceDark, boxShadow: "inset 0 1px 0 rgba(255,255,255,.04)" }}>
        <Row icon={WifiIcon} label={s.wifiToggle} right={<Switch on={wifiOn} />} />
        <Row icon={UsbIcon} label={s.usbToggle} sub={s.usbSub} right={<Switch on={0} />} divider />
      </div>
      <div style={{ font: `600 12px/16px ${F.sans}`, letterSpacing: ".06em", textTransform: "uppercase", color: C.inkMuted, margin: "16px 0 7px 4px" }}>{s.tablets}</div>
      <div style={{ position: "relative", borderRadius: 16, background: C.surfaceDark, height: 58, overflow: "hidden" }}>
        <div style={{ position: "absolute", inset: 0, padding: "0 16px", display: "flex", alignItems: "center", font: `400 14px/1 ${F.sans}`, color: C.inkMuted, opacity: 1 - tabletRow }}>{s.noTablets}</div>
        <div style={{ position: "absolute", inset: 0, padding: "0 16px", display: "flex", alignItems: "center", gap: 12, opacity: tabletRow, transform: `translateY(${(1 - tabletRow) * 14}px)` }}>
          <span style={{ width: 38, height: 27, borderRadius: 6, background: C.cobalt, boxShadow: `inset 0 0 0 2px ${C.cobaltNight}`, transform: "rotate(-6deg)" }} />
          <span style={{ flex: 1, font: `500 16px/20px ${F.sans}` }}>{s.tabletName}<span style={{ display: "block", font: `400 12px/16px ${F.mono}`, color: C.inkMuted }}>{s.tabletMeta}</span></span>
          <span style={{ width: 9, height: 9, borderRadius: "50%", background: C.success, boxShadow: `0 0 8px ${C.success}` }} />
        </div>
      </div>
    </div>
  </div>
);

/** Faísca: 7 pontinhos dourados saindo do centro (Ginga.spark); p = 0–1 em 520 ms. */
export const Spark: React.FC<{ p: number; x: number; y: number; count?: number; seed?: number }> = ({ p, x, y, count = 7, seed = 1 }) => {
  if (p <= 0 || p >= 1) return null;
  const e = 1 - Math.pow(1 - p, 3);
  return (
    <div style={{ position: "absolute", left: x, top: y, width: 0, height: 0 }}>
      {Array.from({ length: count }, (_, i) => {
        const a = (i / count) * 6.283 + ((i * 37 + seed * 11) % 10) / 20, d = 22 + ((i * 53 + seed * 7) % 13);
        return <i key={i} style={{ position: "absolute", width: 6, height: 6, margin: -3, borderRadius: "50%", background: C.star, boxShadow: glowStar, transform: `translate(${Math.cos(a) * d * e}px, ${Math.sin(a) * d * e}px) scale(${1 - 0.8 * e})`, opacity: 1 - e }} />;
      })}
    </div>
  );
};
