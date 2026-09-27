import React from "react";
import { Billboard } from "@react-three/drei";
import { AdditiveBlending, Color } from "three";
import { useCanvasTexture } from "./canvasTexture";

/** Estrela de 4 pontas em pixels (textura 7×7, filtro nearest), emissiva acima de 1 para o bloom. */
const STAR = ["...X...", "...X...", "..XXX..", "XXXXXXX", "..XXX..", "...X...", "...X..."];
export const PixelStar3D: React.FC<{ position: [number, number, number]; size: number; intensity: number; rotation?: number }> = ({ position, size, intensity, rotation = 0 }) => {
  const tex = useCanvasTexture(7, 7, (c) => {
    STAR.forEach((row, y) => row.split("").forEach((ch, x) => { if (ch === "X") { c.fillStyle = x === 3 && y === 3 ? "#FFF6DA" : "#FFC43D"; c.fillRect(x, y, 1, 1); } }));
  }, [], true);
  if (size <= 0 || intensity <= 0) return null;
  return (
    <Billboard position={position}>
      <mesh rotation={[0, 0, rotation]} renderOrder={21}>
        <planeGeometry args={[size, size]} />
        <meshBasicMaterial map={tex} color={new Color(intensity, intensity, intensity)} transparent depthWrite={false} blending={AdditiveBlending} toneMapped={false} />
      </mesh>
    </Billboard>
  );
};
