import React from "react";
import { useCurrentFrame, useVideoConfig } from "remotion";
import { C } from "../theme";
import { F } from "../fonts";

export type StatusKind = "off" | "searching" | "pairing" | "connected";
const color: Record<StatusKind, string> = { off: C.inkMuted, searching: C.cobaltNight, pairing: C.warning, connected: C.success };

/** StatusOrbit: ponto + arco girando (procurando) ou pulso (pareando/conectado). */
export const StatusPill: React.FC<{ kind: StatusKind; label: string; size?: number; glass?: boolean; style?: React.CSSProperties }> = ({ kind, label, size = 1, glass, style }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const c = color[kind], s = size;
  const spin = ((frame / fps) / 1.1) * 360;
  const pulseT = ((frame / fps) % (kind === "connected" ? 2.4 : 1.6)) / (kind === "connected" ? 2.4 : 1.6);
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: 7 * s, height: 30 * s, padding: `0 ${13 * s}px 0 ${8 * s}px`, borderRadius: 999, background: glass ? "rgba(10,12,28,.72)" : C.surface2Dark, color: C.nevoa, font: `500 ${13 * s}px/1 ${F.sans}`, whiteSpace: "nowrap", ...style }}>
      <span style={{ position: "relative", width: 16 * s, height: 16 * s, flex: "none" }}>
        <span style={{ position: "absolute", inset: 4.5 * s, borderRadius: "50%", background: c }} />
        {kind === "searching" && <span style={{ position: "absolute", inset: 0, borderRadius: "50%", border: `${1.6 * s}px solid transparent`, borderTopColor: c, transform: `rotate(${spin}deg)` }} />}
        {(kind === "pairing" || kind === "connected") && <span style={{ position: "absolute", inset: 0, borderRadius: "50%", border: `${1.6 * s}px solid ${c}`, transform: `scale(${0.6 + pulseT * 0.9})`, opacity: 1 - pulseT }} />}
      </span>
      {label}
    </span>
  );
};
