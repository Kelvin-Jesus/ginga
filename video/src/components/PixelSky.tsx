import React from "react";
import { useEffect, useMemo, useRef } from "react";
import { useCurrentFrame, useVideoConfig } from "remotion";
import { rng } from "../lib/rng";

const COL = ["#252C66", "#2E47F5", "#6F82FF", "#A4A9C8", "#F2F3F8", "#FFC43D"];

/** Céu em pixels de 4 px (port de Ginga.pixelSky), determinístico por quadro.
 *  `loop` = duração em quadros para tornar a cintilação cíclica. */
export const PixelSky: React.FC<{ width: number; height: number; seed?: number; density?: number; loop?: number; px?: number; style?: React.CSSProperties }> = ({
  width, height, seed = 7, density = 0.0048, loop, px = 4, style,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const W = Math.ceil(width / px), H = Math.ceil(height / px);
  const ref = useRef<HTMLCanvasElement>(null);
  const stars = useMemo(() => {
    const r = rng(seed), n = Math.round(W * H * density), out = [];
    for (let i = 0; i < n; i++) {
      const k = r(), c = k < 0.5 ? 0 : k < 0.74 ? 1 : k < 0.88 ? 2 : k < 0.95 ? 3 : k < 0.99 ? 4 : 5;
      // velocidade inteira quando em loop, para a fase fechar o ciclo
      out.push({ x: (r() * W) | 0, y: (r() * H) | 0, c, p: r() * 6.28, s: loop ? 1 + Math.floor(r() * 3) : 0.5 + r() * 2, big: c >= 4 && r() < 0.25 });
    }
    return out;
  }, [W, H, seed, density, loop]);

  useEffect(() => {
    const ctx = ref.current!.getContext("2d")!;
    ctx.clearRect(0, 0, W, H);
    const t = loop ? (frame / loop) * Math.PI * 2 : frame / fps;
    for (const st of stars) {
      const tw = Math.sin(st.p + t * st.s);
      let c = st.c + (tw > 0.75 ? 1 : tw < -0.6 ? -1 : 0);
      if (c < 0) continue; if (c > 5) c = 5;
      ctx.fillStyle = COL[c]; ctx.fillRect(st.x, st.y, 1, 1);
      if (st.big && tw > 0.2) {
        ctx.fillStyle = COL[Math.max(0, c - 2)];
        ctx.fillRect(st.x - 1, st.y, 1, 1); ctx.fillRect(st.x + 1, st.y, 1, 1);
        ctx.fillRect(st.x, st.y - 1, 1, 1); ctx.fillRect(st.x, st.y + 1, 1, 1);
      }
    }
  }, [frame, stars, W, H, fps, loop]);

  return <canvas ref={ref} width={W} height={H} style={{ position: "absolute", width, height, imageRendering: "pixelated", ...style }} />;
};
