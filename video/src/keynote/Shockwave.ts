import { ramp, expoOut } from "./timing";

/** Onda de choque de um toque no quadro `at`: raio (fração da altura) e amplitude do deslocamento. */
export function shockAt(f: number, at: number, uv: [number, number]) {
  const p = ramp(f, at, at + 40, expoOut);
  if (f < at || p >= 1) return undefined;
  return { uv, r: 0.02 + p * 0.7, amp: 0.018 * (1 - p) };
}
