import { ramp } from "./timing";

/** Lente gravitacional no horizonte de eventos (efeito DistortEffect em PostFX): puxão radial crescente + espiral. */
export function lensAt(f: number, start: number, end: number, uv: [number, number]) {
  const p = ramp(f, start, end, (t) => t * t);
  if (f < start || f >= end) return undefined;
  return { uv, strength: p * 1.6, spin: p * p * 5.5, radius: 0.18 + p * 0.3 };
}
