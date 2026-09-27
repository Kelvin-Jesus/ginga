import { useLayoutEffect } from "react";
import { useThree } from "@react-three/fiber";
import { useCurrentFrame } from "remotion";
import { noise2D } from "@remotion/noise";
import { PerspectiveCamera } from "three";
import { expoOut, hitPush, hitShake } from "./timing";

export type V3 = [number, number, number];
export type CamKey = { f: number; pos: V3; target: V3; fov: number };

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const lerp3 = (a: V3, b: V3, t: number): V3 => [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];

/** Pose da câmera no quadro f: expo-out entre chaves, deriva lenta sempre ligada, push-in e tremor nos hits. */
export function camPose(keys: CamKey[], f: number) {
  let a = keys[0], b = keys[0];
  for (let i = 0; i < keys.length - 1; i++) if (f >= keys[i].f) { a = keys[i]; b = keys[i + 1]; }
  if (f >= keys[keys.length - 1].f) { a = b = keys[keys.length - 1]; }
  const t = a === b ? 1 : expoOut(Math.min(1, Math.max(0, (f - a.f) / (b.f - a.f))));
  const pos = lerp3(a.pos, b.pos, t), target = lerp3(a.target, b.target, t);
  // a câmera nunca para: deriva orgânica de alguns centímetros
  pos[0] += noise2D("drift-x", f / 240, 0) * 0.08;
  pos[1] += noise2D("drift-y", f / 260, 3) * 0.05;
  const fov = lerp(a.fov, b.fov, t) * (1 - 0.03 * hitPush(f));
  const sh = hitShake(f);
  return { pos, target, fov, shake: [noise2D("shake-x", f * 0.45, 1) * sh, noise2D("shake-y", f * 0.45, 7) * sh] as [number, number] };
}

/** Dirige a câmera padrão a partir do quadro (nada de relógio do three.js). */
export const CameraRig: React.FC<{ keys: CamKey[] }> = ({ keys }) => {
  const f = useCurrentFrame();
  const { camera, size } = useThree();
  useLayoutEffect(() => {
    const cam = camera as PerspectiveCamera;
    const p = camPose(keys, f);
    cam.position.set(...p.pos);
    cam.fov = p.fov;
    cam.aspect = size.width / size.height;
    cam.lookAt(...p.target);
    // tremor de 2–3 px: ~0.0012 rad num quadro 4K com fov 35°
    cam.rotateX(p.shake[1] * 0.0011);
    cam.rotateY(p.shake[0] * 0.0011);
    cam.updateProjectionMatrix();
    cam.updateMatrixWorld();
  }, [f, keys, camera, size]);
  return null;
};
