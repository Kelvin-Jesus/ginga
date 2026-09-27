import { ramp } from "./timing";
import { Easing } from "remotion";

/** Lente gravitacional no horizonte de eventos (efeito DistortEffect em PostFX): puxão radial crescente + espiral. */
export function lensAt(f: number, start: number, end: number, uv: [number, number]) {
  const p = ramp(f, start, end, (t) => t * t);
  if (f < start || f >= end) return undefined;
  // últimos 14 quadros: o horizonte cresce até cobrir o quadro (meia diagonal de 16:9 ≈ 1.02)
  const hole = f >= end - 16 ? 1.12 * ramp(f, end - 16, end - 3, Easing.in(Easing.cubic)) : 0;
  return { uv, strength: p * 1.6, spin: p * p * 5.5, radius: 0.18 + p * 0.3, hole };
}
