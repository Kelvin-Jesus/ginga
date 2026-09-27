import { Easing } from "remotion";

/** Só as cores de design/ginga-design/tokens.json (+ os cinzas de moldura da demo). */
export const C = {
  cosmos: "#0A0C1C",
  noite: "#141830",
  surfaceDark: "#171A33",
  surface2Dark: "#20244A",
  lineDark: "#2A2E4D",
  cobalt: "#2E47F5",
  cobaltNight: "#6F82FF",
  cobaltSoftDark: "#252C66",
  star: "#FFC43D",
  starLight: "#F2A900",
  nevoa: "#F2F3F8",
  inkMuted: "#A4A9C8",
  success: "#4FD08E",
  warning: "#F2B24C",
  // molduras dos aparelhos (demo-conexao.html) e S Pen
  frame: "#1B1D2A",
  frameEdge: "#2C2F42",
  base: "#2A2D3E",
} as const;

export const ease = {
  ginga: Easing.bezier(0.34, 1.36, 0.64, 1),
  out: Easing.bezier(0.2, 0.8, 0.2, 1),
  inOut: (p: number) => (p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2),
};

/** Durações dos tokens, em ms. */
export const dur = { tap: 120, ui: 220, sheet: 420, orbit: 2400, warp: 1400 };
export const ms = (v: number, fps: number) => Math.round((v / 1000) * fps);

export const glowStar = "0 0 12px rgba(255,196,61,0.7)";
