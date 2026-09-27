import { Easing } from "remotion";
import { Euler, Matrix4, PerspectiveCamera, Quaternion, Vector3 } from "three";
import { camPose, type CamKey, type V3 } from "./CameraRig";
import { expoOut, ramp } from "./timing";
import { tabletScreenLocal } from "./Devices3D";

const deg = Math.PI / 180;
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const io = Easing.inOut(Easing.cubic);

export const CAM: CamKey[] = [
  { f: 0, pos: [0, 0, 15], target: [0, 0, 0], fov: 32 },
  { f: 90, pos: [0, 0.1, 11], target: [0, 0, 0], fov: 32 },
  { f: 125, pos: [0.3, 0.35, 6.0], target: [0, 0.05, 0], fov: 32 },
  { f: 200, pos: [-0.2, 0.3, 5.4], target: [0, 0, 0], fov: 32 },
  { f: 245, pos: [1.75, 0.3, 2.45], target: [0.15, -0.05, 0], fov: 30 },
  { f: 305, pos: [1.55, 0.2, 2.3], target: [0.2, -0.05, 0], fov: 30 },
  { f: 350, pos: [0, 0.7, 11], target: [-0.1, 0, 0], fov: 34 },
  { f: 420, pos: [0.2, 0.6, 10.2], target: [-0.1, 0, 0], fov: 34 },
  { f: 458, pos: [-1.5, 0.6, 8.6], target: [-9, 0.8, -8], fov: 36 },
  { f: 499, pos: [-3.6, 0.7, 3.2], target: [-9, 0.8, -8], fov: 38 },
  { f: 500, pos: [0, 0, 8], target: [0, 0, 0], fov: 30 },
  { f: 600, pos: [0, 0, 7.3], target: [0, 0, 0], fov: 30 },
];

export const BH_POS: V3 = [-9, 0.8, -8];

export type Pose = { pos: V3; rot: V3; scale: number; visible: boolean };

export function tabletPose(f: number): Pose {
  const rise = expoOut(ramp(f, 90, 135));
  const four = expoOut(ramp(f, 310, 350));
  let ry = lerp(-25, -8, io(ramp(f, 90, 200)));
  ry = lerp(ry, -4, ramp(f, 200, 310)); ry = lerp(ry, -16, four);
  const rx = lerp(-12, -6, four);
  const y = lerp(-4.2, 0, rise) + Math.sin(f * 0.03) * 0.025 + lerp(0, -0.05, four);
  return { pos: [lerp(0, 2.05, four), y, 0], rot: [rx * deg, ry * deg, Math.sin(f * 0.021) * 0.6 * deg], scale: lerp(1, 0.9, four), visible: f >= 88 && f < 500 };
}

export function laptopPose(f: number): Pose {
  const e = expoOut(ramp(f, 310, 352));
  return { pos: [lerp(-13, -2.35, e), -1.0 + Math.sin(f * 0.025 + 1) * 0.02, -0.4], rot: [0.1, 16 * deg, 0], scale: 0.95, visible: f >= 310 && f < 500 };
}

export function poseMatrix(p: Pose) {
  return new Matrix4().compose(new Vector3(...p.pos), new Quaternion().setFromEuler(new Euler(...p.rot)), new Vector3(p.scale, p.scale, p.scale));
}

/** Ponto da tela do tablet (u, v) no mundo. */
export function tabletScreenWorld(f: number, u: number, v: number) {
  return new Vector3(...tabletScreenLocal(u, v)).applyMatrix4(poseMatrix(tabletPose(f)));
}
/** Centro da tela do notebook no mundo (tampa inclinada ~8°). */
export function laptopScreenWorld(f: number) {
  const tilt = 1.72 - Math.PI / 2, h = 1.95 / 2 + 0.01;
  const local = new Vector3(0, Math.cos(tilt) * h, -Math.sin(tilt) * h);
  return local.applyMatrix4(poseMatrix(laptopPose(f)));
}

const tmpCam = new PerspectiveCamera();
/** Projeta um ponto do mundo em UV de tela (0–1, origem embaixo à esquerda) com a câmera do quadro f. */
export function projectUV(f: number, p: Vector3, aspect: number): [number, number] {
  const c = camPose(CAM, f);
  tmpCam.fov = c.fov; tmpCam.aspect = aspect; tmpCam.near = 0.1; tmpCam.far = 400;
  tmpCam.position.set(...c.pos); tmpCam.lookAt(...c.target); tmpCam.updateProjectionMatrix(); tmpCam.updateMatrixWorld();
  const q = p.clone().project(tmpCam);
  return [q.x * 0.5 + 0.5, q.y * 0.5 + 0.5];
}
export function camDistance(f: number, p: Vector3) {
  const c = camPose(CAM, f);
  return p.distanceTo(new Vector3(...c.pos));
}
