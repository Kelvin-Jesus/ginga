import React from "react";
import { useEffect, useMemo, useRef } from "react";
import { useCurrentFrame, useVideoConfig } from "remotion";
import { rng } from "../lib/rng";

/* Port de Ginga.blackHole() + Ginga.ditherLoop() (design/ginga-design/reference/bundle.js).
   Diferença: nada acumula entre quadros. A órbita de cada partícula é a0 + w·t, então qualquer
   quadro pode ser renderizado isolado (Remotion renderiza em paralelo e fora de ordem). */

const PAL = [[10, 12, 28], [20, 24, 48], [46, 71, 245], [111, 130, 255], [242, 243, 248], [255, 196, 61]];
const N = PAL.length - 1;
const BAYER = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5];
const R = 0.28, K = 0.2, rIn = 0.42, rOut = 1.6;
const hash = (a: number, b: number) => { const x = Math.sin(a * 127.1 + b * 311.7) * 43758.5453; return x - Math.floor(x); };

export type Geo = ReturnType<typeof makeGeo>;
function makeGeo(W: number, H: number, seed: number) {
  const n = W * H, cx = W * 0.5, cy = H * 0.52;
  const g = { x: new Float32Array(n), y: new Float32Array(n), rd: new Float32Array(n), lrd: new Float32Array(n), ang: new Float32Array(n), rs: new Float32Array(n), st: new Float32Array(n), cx, cy, P: [] as { r: number; a: number; w: number; b: number; z: number }[] };
  for (let yy = 0, i = 0; yy < H; yy++) for (let xx = 0; xx < W; xx++, i++) {
    const x = (xx - cx) / (H / 2), y = (yy - cy) / (H / 2), v = y / K, rs = Math.sqrt(x * x + y * y);
    g.x[i] = x; g.y[i] = y; g.rd[i] = Math.sqrt(x * x + v * v); g.lrd[i] = Math.log(g.rd[i] + 0.001); g.ang[i] = Math.atan2(v, x); g.rs[i] = rs;
    const k = rs > R ? 1 + 0.09 / (rs * rs) : 0, h = hash(Math.floor(x * k * 60), Math.floor(y * k * 60));
    g.st[i] = rs > R * 1.1 && rs < 1.05 && h > 0.985 ? 0.28 + (h - 0.985) * 40 : 0;
  }
  const r = rng(seed), NP = Math.min(700, Math.round(W * H * 0.03));
  for (let p = 0; p < NP; p++) {
    const r0 = rIn * 0.9 + Math.pow(r(), 0.8) * (rOut * 1.25 - rIn);
    g.P.push({ r: r0, a: r() * 6.2832, w: 0.9 / Math.pow(r0, 1.5), b: 0.35 + r() * 0.55, z: (r() - 0.5) * 0.05 });
  }
  return g;
}

type Ph = { a: number; b: number; c: number; d: number; e: number };
function shadeAt(g: Geo, i: number, ph: Ph, pull: number) {
  const x = g.x[i], y = g.y[i], rd = g.rd[i], a = g.ang[i], rs = g.rs[i];
  const dop = 0.5 - 0.5 * Math.cos(a);
  let D = 0;
  if (rd > rIn && rd < rOut) {
    const f = 1 - (rd - rIn) / (rOut - rIn);
    const sw = 0.5 + 0.5 * Math.sin(a * 3 + g.lrd[i] * 7 + ph.a);
    const sw2 = 0.5 + 0.5 * Math.sin(a * 7 - g.lrd[i] * 11 + ph.b);
    D = Math.pow(f, 1.05) * (0.35 + 0.75 * dop) * (0.45 + 0.4 * sw + 0.2 * sw2) * Math.min(1, (rd - rIn) / 0.06);
  }
  let L = 0; const dr = Math.abs(rs - 0.47);
  if (dr < 0.17 && y < 0.05) {
    const la = Math.atan2(y, x);
    L = Math.pow(1 - dr / 0.17, 1.4) * (0.55 + 0.45 * (0.5 - 0.5 * Math.cos(la))) * (0.7 + 0.3 * Math.sin(la * 5 + ph.e + rs * 20));
  }
  const Pr = Math.max(0, 1 - Math.abs(rs - R * 1.04) / 0.02);
  if (rs < R) return y > 0 && D > 0 ? D : 0;
  const halo = 0.18 * Math.exp(-(rs - R) / 0.14) * (1 + 0.6 * pull);
  let back = Math.min(1, Math.max(0, (rs - 0.5) / 0.3)); back = back * back * (3 - 2 * back);
  let v = Math.max(y > 0 ? D : Math.max(D * back, L), Pr * (0.85 + 0.15 * Math.sin(ph.c)), halo);
  v += g.st[i] * (0.65 + 0.35 * Math.sin(ph.d + i));
  return v > 1 ? 1 : v;
}

/** Desenha um quadro do buraco negro num contexto 2D de W×H (1 px = 1 pixel de dithering).
 *  Usado pelo componente DOM e como textura 3D (keynote). */
export function drawBlackHole(ctx: CanvasRenderingContext2D, geo: Geo, W: number, H: number, o: { t: number; cycle?: number; loopSeconds?: number; pull?: number; burst?: number }) {
  const { t, cycle, loopSeconds = 8, pull = 0, burst = 0 } = o;
  const TAU = Math.PI * 2, looping = cycle !== undefined;
  const k = (rate: number) => Math.max(1, Math.round((rate * loopSeconds) / TAU));
  const ph: Ph = looping
    ? { a: TAU * k(2.2) * cycle!, b: TAU * k(3.1) * cycle!, c: TAU * k(3) * cycle!, d: TAU * k(1.7) * cycle!, e: TAU * k(2.4) * cycle! }
    : { a: t * 2.2, b: t * 3.1, c: t * 3, d: t * 1.7, e: t * 2.4 };
  const img = ctx.createImageData(W, H), d = img.data;
  const buf = new Float32Array(W * H);
  for (let j = 0; j < buf.length; j++) buf[j] = shadeAt(geo, j, ph, pull);
  const S = H / 2;
  for (const q of geo.P) {
    const a0 = q.a + (looping ? TAU * k(q.w) * cycle! : q.w * t) * (1 + 1.4 * pull);
    const r = q.r * (1 - 0.38 * pull) * (1 + 1.6 * burst * (0.6 + q.b));
    for (let kk = 0; kk < 3; kk++) {
      const aa = a0 - kk * 0.05 * (1 + pull), x = r * Math.cos(aa), y = r * Math.sin(aa) * K + q.z;
      if (Math.sqrt(x * x + y * y) < R && Math.sin(aa) < 0) continue;
      const px_ = Math.round(geo.cx + x * S), py = Math.round(geo.cy + y * S);
      if (px_ < 0 || py < 0 || px_ >= W || py >= H) continue;
      const o2 = py * W + px_;
      buf[o2] = Math.min(1, buf[o2] + q.b * (kk === 0 ? 0.75 : 0.32 / kk) * (0.6 + 0.6 * (0.5 - 0.5 * Math.cos(aa))));
    }
  }
  for (let y = 0, i = 0; y < H; y++) for (let x = 0; x < W; x++, i++) {
    const th = (BAYER[(y & 3) * 4 + (x & 3)] + 0.5) / 16;
    let lv = Math.floor(buf[i] * N + th); lv = lv < 0 ? 0 : lv > N ? N : lv;
    const c = PAL[lv], o3 = i * 4; d[o3] = c[0]; d[o3 + 1] = c[1]; d[o3 + 2] = c[2]; d[o3 + 3] = lv === 0 ? 0 : 255;
  }
  ctx.putImageData(img, 0, 0);
}
export { makeGeo };

export type DitherBlackHoleProps = {
  /** tamanho na tela; a resolução interna é 1/px disso */
  width: number; height: number; px?: number;
  /** tempo do shader em segundos; por padrão frame/fps. Para loop perfeito passe um t cíclico. */
  time?: number;
  /** loop perfeito: fração 0–1 do ciclo e a duração do ciclo em segundos */
  cycle?: number; loopSeconds?: number;
  /** 0–1: colapso das órbitas */ pull?: number;
  /** 0–1: explosão das partículas */ burst?: number;
  seed?: number; style?: React.CSSProperties;
};

export const DitherBlackHole: React.FC<DitherBlackHoleProps> = ({ width, height, px = 4, time, cycle, loopSeconds = 8, pull = 0, burst = 0, seed = 3, style }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const W = Math.round(width / px), H = Math.round(height / px);
  const ref = useRef<HTMLCanvasElement>(null);
  const geo = useMemo(() => makeGeo(W, H, seed), [W, H, seed]);
  const t = time ?? frame / fps;

  useEffect(() => {
    drawBlackHole(ref.current!.getContext("2d")!, geo, W, H, { t, cycle, loopSeconds, pull, burst });
  }, [geo, t, cycle, loopSeconds, pull, burst, W, H]);

  return <canvas ref={ref} width={W} height={H} style={{ position: "absolute", width, height, imageRendering: "pixelated", ...style }} />;
};
