import React from "react";
import { C } from "../theme";

/** Ponteiro macOS genérico em SVG. (x, y) é a ponta; `press` 0–1 encolhe no clique. */
export const Cursor: React.FC<{ x: number; y: number; press?: number; size?: number; opacity?: number }> = ({ x, y, press = 0, size = 1, opacity = 1 }) => (
  <svg width={26 * size} height={38 * size} viewBox="0 0 26 38" style={{ position: "absolute", left: x - 3 * size, top: y - 2 * size, transform: `scale(${1 - 0.12 * press})`, transformOrigin: "3px 2px", opacity, overflow: "visible", zIndex: 50, filter: "drop-shadow(0 2px 3px rgba(0,0,0,.45))" }}>
    <path d="M3 2 L3 30 L10 23.5 L14.5 34 L19 32 L14.6 21.8 L23.5 21.8 Z" fill="#FFFFFF" stroke="#000000" strokeWidth="1.6" strokeLinejoin="round" />
  </svg>
);

/** Dedo: círculo translúcido Névoa a 35%, com anel no toque (`tap` 0–1). */
export const Finger: React.FC<{ x: number; y: number; opacity?: number; tap?: number; size?: number }> = ({ x, y, opacity = 1, tap = 0, size = 46 }) => (
  <div style={{ position: "absolute", left: x, top: y, width: 0, height: 0, opacity, zIndex: 50 }}>
    <div style={{ position: "absolute", width: size, height: size, margin: -size / 2, borderRadius: "50%", background: "rgba(242,243,248,.35)", boxShadow: "0 0 0 1.5px rgba(242,243,248,.25)", transform: `scale(${1 - 0.14 * Math.sin(Math.PI * Math.min(1, tap))})` }} />
    {tap > 0 && tap < 1 && <div style={{ position: "absolute", width: size, height: size, margin: -size / 2, borderRadius: "50%", border: "2px solid rgba(242,243,248,.6)", transform: `scale(${1 + tap * 0.9})`, opacity: 1 - tap }} />}
  </div>
);

/** S Pen: barra fina #2A2D3E com ponta Cobalto noturno. (x, y) é a ponta. */
export const SPen: React.FC<{ x: number; y: number; opacity?: number; angle?: number; len?: number }> = ({ x, y, opacity = 1, angle = -38, len = 230 }) => (
  <div style={{ position: "absolute", left: x, top: y, width: 0, height: 0, opacity, zIndex: 50, transform: `rotate(${angle}deg)` }}>
    <div style={{ position: "absolute", left: 0, top: -4, width: 16, height: 8, background: C.cobaltNight, clipPath: "polygon(0 50%, 100% 0, 100% 100%)" }} />
    <div style={{ position: "absolute", left: 14, top: -5, width: len, height: 10, borderRadius: "2px 5px 5px 2px", background: "#2A2D3E", boxShadow: "inset 0 1px 0 #3A3E55, 0 10px 18px rgba(0,0,0,.45)" }} />
    <div style={{ position: "absolute", left: 60, top: -5.5, width: 22, height: 11, borderRadius: 3, background: "#3A3E55" }} />
  </div>
);
