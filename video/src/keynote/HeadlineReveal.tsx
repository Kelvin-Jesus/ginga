import React, { useLayoutEffect, useRef } from "react";
import { createPortal, useThree } from "@react-three/fiber";
import { spring } from "remotion";
import type { Mesh, PerspectiveCamera, Scene, Texture } from "three";
import { Vector3 } from "three";
import { C } from "../theme";
import { inCubic, ramp } from "./timing";

/* Títulos: desenhados em canvas 2D e colocados num plano preso à câmera (cena de sobreposição).
   O canvas mapeia 1:1 em pixels de um quadro 4K. */

export type Seg = { text: string; font: string; size: number; color?: string };

const layer = new Map<string, HTMLCanvasElement>();
const offscreen = (w: number, h: number) => {
  const k = `${w}x${h}`;
  if (!layer.has(k)) { const c = document.createElement("canvas"); c.width = w; c.height = h; layer.set(k, c); }
  return layer.get(k)!;
};

const SPRING = { damping: 20, stiffness: 190 };

/** Revelação: fenda de luz horizontal + máscara, letras com 2 quadros de atraso, rastro de movimento,
 *  brilho especular 10 quadros depois de pousar; saída com blur 0→30 px, escala 0.96, opacidade 0 em 12 quadros. */
export function drawHeadline(ctx: CanvasRenderingContext2D, W: number, H: number, segs: Seg[], o: {
  lf: number; fps: number; exit: number; baseline?: number; slit?: boolean; sheen?: boolean;
  extra?: (c: CanvasRenderingContext2D, layout: { x0: number; x1: number; base: number }) => void;
}) {
  const L = offscreen(W, H), c = L.getContext("2d")!;
  c.reset();
  const base = o.baseline ?? H * 0.62;
  // layout por caractere
  const chars: { ch: string; x: number; seg: Seg }[] = [];
  let x = 0;
  for (const s of segs) {
    c.font = `${s.font}`; c.letterSpacing = "0px";
    for (const ch of s.text) { chars.push({ ch, x, seg: s }); x += c.measureText(ch).width - s.size * 0.02; }
    x += s.size * 0.18;
  }
  x -= segs[segs.length - 1].size * 0.18;
  const x0 = (W - x) / 2, x1 = x0 + x;
  const maxSize = Math.max(...segs.map((s) => s.size));
  const slitY = base + maxSize * 0.3;

  c.save();
  c.beginPath(); c.rect(0, 0, W, slitY); c.clip();
  c.textBaseline = "alphabetic";
  chars.forEach((k, i) => {
    const tt = o.lf - 2 * i;
    if (tt < 0) return;
    const sp = (f: number) => spring({ frame: f, fps: o.fps, config: SPRING });
    const y = (f: number) => base + (1 - sp(f)) * maxSize * 1.15;
    c.font = k.seg.font; c.fillStyle = k.seg.color ?? C.nevoa;
    // rastro (desfoque de movimento na entrada): subamostras do próprio spring
    const v = Math.abs(y(tt) - y(tt - 1));
    if (v > 2) for (let s = 1; s <= 4; s++) { c.globalAlpha = 0.22; c.fillText(k.ch, x0 + k.x, y(tt - s * 0.25)); }
    c.globalAlpha = 1; c.fillText(k.ch, x0 + k.x, y(tt));
  });
  c.restore();

  o.extra?.(c, { x0, x1, base });

  // fenda de luz
  if (o.slit !== false) {
    const grow = ramp(o.lf, -6, 8), fadeS = 1 - ramp(o.lf, 2 * chars.length + 10, 2 * chars.length + 30);
    if (grow * fadeS > 0) {
      const cx = W / 2, hw = (x1 - x0) * 0.62 * grow;
      c.save(); c.globalAlpha = fadeS;
      c.shadowColor = C.cobaltNight; c.shadowBlur = 40;
      const g = c.createLinearGradient(cx - hw, 0, cx + hw, 0);
      g.addColorStop(0, "rgba(242,243,248,0)"); g.addColorStop(0.5, "rgba(242,243,248,1)"); g.addColorStop(1, "rgba(242,243,248,0)");
      c.fillStyle = g; c.fillRect(cx - hw, slitY - 2, hw * 2, 4);
      c.restore();
    }
  }
  // brilho especular: faixa em gradiente varrendo as letras 10 quadros depois de pousarem
  if (o.sheen !== false) {
    const land = 2 * (chars.length - 1) + 18, p = ramp(o.lf, land + 10, land + 40);
    if (p > 0 && p < 1) {
      const sx = x0 - 400 + (x1 - x0 + 800) * p;
      c.save(); c.globalCompositeOperation = "source-atop";
      const g = c.createLinearGradient(sx - 220, 0, sx + 220, 0);
      g.addColorStop(0, "rgba(255,255,255,0)"); g.addColorStop(0.5, "rgba(255,246,218,0.85)"); g.addColorStop(1, "rgba(255,255,255,0)");
      c.setTransform(1, 0, -0.35, 1, 0, 0); c.fillStyle = g; c.fillRect(-W, 0, W * 3, H);
      c.restore();
    }
  }
  // saída
  const e = inCubic(Math.min(1, Math.max(0, o.exit)));
  ctx.save();
  ctx.globalAlpha = 1 - e;
  if (e > 0) ctx.filter = `blur(${30 * e}px)`;
  const s = 1 - 0.04 * e;
  ctx.translate(W / 2, base); ctx.scale(s, s); ctx.translate(-W / 2, -base);
  ctx.drawImage(L, 0, 0);
  ctx.restore();
}

const fwd = new Vector3();

/** Plano preso à câmera, na cena de sobreposição. Tamanho e posição em pixels de um quadro 4K (centro = 0). */
export const ScreenPlane: React.FC<{ overlay: Scene; map: Texture; w: number; h: number; x?: number; y?: number; d?: number; opacity?: number; additive?: boolean }> = ({ overlay, map, w, h, x = 0, y = 0, d = 3, opacity = 1, additive }) => {
  const { camera } = useThree();
  const ref = useRef<Mesh>(null);
  useLayoutEffect(() => {
    const cam = camera as PerspectiveCamera, m = ref.current!;
    const vh = 2 * d * Math.tan((cam.fov * Math.PI) / 360), px = vh / 2160;
    camera.getWorldDirection(fwd);
    m.position.copy(camera.position).addScaledVector(fwd, d);
    m.quaternion.copy(camera.quaternion);
    m.translateX(x * px); m.translateY(-y * px);
    m.scale.set(w * px, h * px, 1);
    m.updateMatrixWorld();
  });
  return createPortal(
    <mesh ref={ref} renderOrder={10}>
      <planeGeometry args={[1, 1]} />
      <meshBasicMaterial map={map} transparent opacity={opacity} depthTest={false} depthWrite={false} toneMapped={false} blending={additive ? 2 : 1} />
    </mesh>,
    overlay,
  );
};
