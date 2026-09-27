import React, { useMemo } from "react";
import { Color, DoubleSide } from "three";
import { drawBlackHole, makeGeo } from "../components/DitherBlackHole";
import { useCanvasTexture } from "./canvasTexture";

/** O buraco negro de DitherSpace como textura 3D: resolução interna baixa, ampliada com filtro nearest (pixels nítidos). */
export const DitherPlane: React.FC<{ w: number; h: number; iw?: number; ih?: number; t: number; pull?: number; opacity?: number; glow?: number } & { position?: [number, number, number]; rotation?: [number, number, number] }> = ({ w, h, iw = 480, ih = 300, t, pull = 0, opacity = 1, glow = 1.35, position, rotation }) => {
  const geo = useMemo(() => makeGeo(iw, ih, 3), [iw, ih]);
  const tex = useCanvasTexture(iw, ih, (c) => drawBlackHole(c, geo, iw, ih, { t, pull }), [t, pull, geo], true);
  return (
    <mesh position={position} rotation={rotation}>
      <planeGeometry args={[w, h]} />
      <meshBasicMaterial map={tex} color={new Color(glow, glow, glow)} transparent opacity={opacity} depthWrite={false} side={DoubleSide} toneMapped={false} />
    </mesh>
  );
};
