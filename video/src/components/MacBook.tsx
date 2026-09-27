import React from "react";
import { C } from "../theme";

/** MacBook genérico em CSS (como em demo-conexao.html). Sem logos. */
export const MACBOOK = { w: 900, h: 580, pad: 14 };
export const MacBook: React.FC<{ children?: React.ReactNode; style?: React.CSSProperties }> = ({ children, style }) => (
  <div style={{ position: "absolute", width: MACBOOK.w, ...style }}>
    <div style={{ position: "relative", height: MACBOOK.h, padding: `${MACBOOK.pad}px ${MACBOOK.pad}px 20px`, boxSizing: "border-box", borderRadius: "30px 30px 10px 10px", background: C.frame, boxShadow: `inset 0 0 0 2px ${C.frameEdge}, 0 40px 100px rgba(0,0,0,.55)` }}>
      <div style={{ position: "absolute", top: MACBOOK.pad, left: "50%", width: 150, height: 22, marginLeft: -75, background: C.frame, borderRadius: "0 0 10px 10px", zIndex: 10 }} />
      <div style={{ position: "relative", height: "100%", borderRadius: 12, overflow: "hidden", background: C.cosmos }}>{children}</div>
    </div>
    <div style={{ position: "relative", height: 22, margin: "0 -46px", borderRadius: "0 0 22px 22px", background: C.base, boxShadow: "inset 0 3px 0 #3A3E55" }}>
      <div style={{ position: "absolute", left: "50%", top: 0, width: 160, marginLeft: -80, height: 8, borderRadius: "0 0 10px 10px", background: "#1E2030" }} />
    </div>
  </div>
);

/** Papel de parede espacial da demo: planeta cobalto + anel dourado. */
export const Wallpaper: React.FC<{ flip?: boolean; scale?: number }> = ({ flip, scale = 1 }) => (
  <div style={{ position: "absolute", inset: 0, overflow: "hidden", transform: flip ? "scaleX(-1)" : undefined }}>
    <div style={{ position: "absolute", right: -160 * scale, bottom: -340 * scale, width: 680 * scale, height: 680 * scale, borderRadius: "50%", background: C.cobalt, opacity: 0.9 }} />
    <div style={{ position: "absolute", right: -260 * scale, bottom: -150 * scale, width: 920 * scale, height: 290 * scale, borderRadius: "50%", border: `${2.5 * scale}px solid rgba(255,196,61,.55)`, transform: "rotate(-14deg)" }} />
  </div>
);
