import { useEffect, useMemo, useRef } from "react";
import { rng } from "../lib/rng";

const COLS = ["255,196,61", "111,130,255", "242,243,248"];

/** Warp: estrelas esticando do centro para fora (port de warp() da demo), fechado em p (0–1). */
export const Warp: React.FC<{ p: number; width: number; height: number; count?: number; seed?: number }> = ({ p, width, height, count = 170, seed = 11 }) => {
  const ref = useRef<HTMLCanvasElement>(null);
  const W = Math.round(width * 1.5), H = Math.round(height * 1.5);
  const stars = useMemo(() => {
    const r = rng(seed);
    return Array.from({ length: count }, () => {
      const k = r();
      return { a: r() * 6.283, d: r() * 60, v: 0.6 + r() * 1.6, c: k < 0.15 ? COLS[0] : k < 0.4 ? COLS[1] : COLS[2] };
    });
  }, [count, seed]);
  useEffect(() => {
    const ctx = ref.current!.getContext("2d")!;
    ctx.clearRect(0, 0, W, H);
    if (p <= 0 || p >= 1) return;
    // distância percorrida = ∫ (26·p² + 1) — acelera; a janela da cauda cresce com a velocidade
    const S = 66; // quadros da demo (1100 ms a 60 fps)
    const dist = (q: number) => S * (q + (26 * q * q * q) / 3);
    const cx = W / 2, cy = H / 2, maxR = Math.hypot(cx, cy);
    ctx.fillStyle = `rgba(10,12,28,${0.35 + p * 0.55})`; ctx.fillRect(0, 0, W, H);
    ctx.lineCap = "round";
    for (const s of stars) {
      const d1 = (s.d + s.v * dist(p)) % (maxR + 40), d0 = Math.max(0, d1 - s.v * (dist(p) - dist(Math.max(0, p - 0.08))));
      ctx.strokeStyle = `rgba(${s.c},${Math.min(1, 0.3 + p)})`; ctx.lineWidth = (1 + p * 2) * 1.5;
      ctx.beginPath(); ctx.moveTo(cx + Math.cos(s.a) * d0, cy + Math.sin(s.a) * d0); ctx.lineTo(cx + Math.cos(s.a) * d1, cy + Math.sin(s.a) * d1); ctx.stroke();
    }
  }, [p, stars, W, H]);
  return <canvas ref={ref} width={W} height={H} style={{ position: "absolute", inset: 0, width, height, opacity: Math.max(0, Math.min(1, p / 0.08, (1 - p) / 0.1)) }} />;
};
