import { Easing, interpolate } from "remotion";

/* GingaKeynote: 600 quadros a 60 fps. Tudo aqui é função pura do quadro. */

export const SHOT = {
  ignition: [0, 90], touch: [90, 200], pen: [200, 310], fps: [310, 420], horizon: [420, 500], logo: [500, 600],
} as const;

/** Marcadores de hit (também os pontos de som). */
export const HITS = [30, 130, 200, 350, 400, 500, 510];
export const CUT = 500;

export const expoOut = Easing.bezier(0.16, 1, 0.3, 1);
export const ginga = Easing.bezier(0.34, 1.36, 0.64, 1);
export const inCubic = Easing.in(Easing.cubic);

const C = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
export const ramp = (f: number, a: number, b: number, e: (t: number) => number = (t) => t) => interpolate(f, [a, b], [0, 1], { ...C, easing: e });
export const between = (f: number, a: number, b: number) => f >= a && f < b;

/** Envelope de hit: sobe em 10 quadros (push-in de 3%) e volta devagar. */
export function hitPush(f: number) {
  let v = 0;
  for (const h of HITS) {
    if (h >= CUT) continue;
    const d = f - h;
    if (d < 0 || d > 60) continue;
    v = Math.max(v, d < 10 ? expoOut(d / 10) : 1 - ramp(d, 10, 60, Easing.inOut(Easing.quad)));
  }
  return v;
}
/** Decaimento do tremor: 12 quadros depois de cada hit. */
export function hitShake(f: number) {
  let v = 0;
  for (const h of HITS) { const d = f - h; if (d >= 0 && d < 12 && h < CUT) v = Math.max(v, 1 - d / 12); }
  return v;
}
/** Pulso da aberração cromática: 0.0008 de base, até 0.004 nos hits. */
export function caAmount(f: number) {
  let p = 0;
  for (const h of HITS) { const d = f - h; if (d >= 0 && d < 16 && h < CUT) p = Math.max(p, Math.exp(-d / 4)); }
  return 0.0008 + (0.004 - 0.0008) * p;
}
