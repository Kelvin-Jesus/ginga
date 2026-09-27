import { useLayoutEffect, useMemo } from "react";
import { CanvasTexture, LinearFilter, NearestFilter, SRGBColorSpace } from "three";

/** Canvas 2D → textura, redesenhada a cada quadro por `draw` (dependências explícitas). */
export function useCanvasTexture(w: number, h: number, draw: (ctx: CanvasRenderingContext2D) => void, deps: unknown[], nearest = false) {
  const { canvas, tex } = useMemo(() => {
    const canvas = document.createElement("canvas");
    canvas.width = w; canvas.height = h;
    const tex = new CanvasTexture(canvas);
    tex.colorSpace = SRGBColorSpace;
    tex.anisotropy = 8;
    if (nearest) { tex.magFilter = NearestFilter; tex.minFilter = NearestFilter; tex.generateMipmaps = false; }
    else { tex.minFilter = LinearFilter; tex.generateMipmaps = false; }
    return { canvas, tex };
  }, [w, h, nearest]);
  useLayoutEffect(() => {
    const ctx = canvas.getContext("2d")!;
    ctx.reset();
    draw(ctx);
    tex.needsUpdate = true;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [canvas, tex, ...deps]);
  return tex;
}

export function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath(); ctx.roundRect(x, y, w, h, r);
}
