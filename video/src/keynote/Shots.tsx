import React, { useMemo } from "react";
import { useThree } from "@react-three/fiber";
import { Line, useTexture } from "@react-three/drei";
import { random, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { getLength, getPointAtLength } from "@remotion/paths";
import { AdditiveBlending, BufferAttribute, BufferGeometry, Color, Euler, Quaternion, Scene, Vector3 } from "three";
import { C } from "../theme";
import { F } from "../fonts";
import type { Strings } from "../i18n";
import { AnamorphicFlare } from "./AnamorphicFlare";
import { LightSweep } from "./LightSweep";
import { PixelStar3D } from "./PixelStar";
import { drawHeadline, ScreenPlane } from "./HeadlineReveal";
import { useCanvasTexture } from "./canvasTexture";
import { DitherPlane } from "./DitherPlane";
import { PEN_PATH, SCREEN } from "./screens";
import { BH_POS, laptopScreenWorld, tabletPose, tabletScreenWorld, poseMatrix } from "./poses";
import { expoOut, ginga, ramp } from "./timing";

type ShotProps = { overlay: Scene; s: Strings };
const HW = 3072, HH = 760;

/* ---------------- 1 · Ignição (0–90) ---------------- */
export const ShotIgnition: React.FC<ShotProps> = ({ overlay }) => {
  const f = useCurrentFrame();
  if (f >= 110) return null;
  const ign = ramp(f, 30, 38, expoOut), decay = 1 - 0.55 * ramp(f, 38, 90);
  const len = 2 + 42 * ramp(f, 30, 48, expoOut);
  const fadeOut = 1 - ramp(f, 90, 110);
  return (
    <>
      <PixelStar3D position={[0, 0, 0]} size={0.22 * (0.6 + 0.4 * ginga(ramp(f, 30, 42)))} intensity={f < 30 ? 0 : 3.2 * ign * decay * fadeOut} />
      <AnamorphicFlare position={[0, 0, 0.01]} intensity={f < 30 ? 0 : (1.8 * ign * decay + 1.4 * Math.exp(-(f - 30) / 5)) * fadeOut} length={len} />
      <LightSweep overlay={overlay} p={ramp(f, 60, 84)} />
    </>
  );
};

/* ---------------- 2 · Toque (90–200) ---------------- */
export const ShotTouch: React.FC<ShotProps> = ({ overlay, s }) => {
  const f = useCurrentFrame(); const { fps } = useVideoConfig();
  const tex = useCanvasTexture(HW, HH, (c) => drawHeadline(c, HW, HH, [{ text: s.kTouch, font: `800 300px ${F.display}`, size: 300 }], { lf: f - 140, fps, exit: (f - 188) / 12 }), [f, s]);
  if (f < 134 || f >= 202) return null;
  return <ScreenPlane overlay={overlay} map={tex} w={HW} h={HH} y={40} />;
};

/* ---------------- 3 · S Pen (200–310) ---------------- */
const PEN_LEN = getLength(PEN_PATH);
export const penProgress = (f: number) => ramp(f, 212, 262, (t) => t * t * (3 - 2 * t));
export const ShotPen: React.FC<ShotProps> = ({ overlay, s }) => {
  const f = useCurrentFrame(); const { fps, height } = useVideoConfig();
  const p = penProgress(f);
  const pt = getPointAtLength(PEN_PATH, PEN_LEN * Math.min(0.999, p));
  const u = Math.min(1, pt!.x / SCREEN.w), v = pt!.y / SCREEN.h;
  const tip = tabletScreenWorld(f, u, v);
  // caneta: inclinada em relação à tela, entra antes e sai depois do traço
  const lift = 0.35 * (1 - ramp(f, 204, 214, expoOut)) + 0.5 * ramp(f, 262, 278);
  const q = new Quaternion().setFromEuler(new Euler(...tabletPose(f).rot));
  const axis = new Vector3(0.45, 0.35, 1).normalize().applyQuaternion(q);
  const penPos = tip.clone().addScaledVector(axis, lift);
  const penQ = new Quaternion().setFromUnitVectors(new Vector3(0, 1, 0), axis);
  // faíscas a cada 8 quadros
  const sparks = useMemo(() => { const g = new BufferGeometry(); g.setAttribute("position", new BufferAttribute(new Float32Array(20 * 6 * 3), 3)); g.setAttribute("color", new BufferAttribute(new Float32Array(20 * 6 * 3), 3)); return g; }, []);
  const pos = sparks.getAttribute("position") as BufferAttribute, col = sparks.getAttribute("color") as BufferAttribute;
  let n = 0;
  for (let k = 0; k < 20; k++) {
    const sf = 214 + k * 8, age = f - sf;
    if (sf > 262 || age < 0 || age > 18) continue;
    const sp = getPointAtLength(PEN_PATH, PEN_LEN * penProgress(sf)), o = tabletScreenWorld(sf, Math.min(1, sp!.x / SCREEN.w), sp!.y / SCREEN.h);
    for (let j = 0; j < 6; j++) {
      const a = random(`sa${k}-${j}`) * Math.PI * 2, sp2 = 0.012 + random(`sv${k}-${j}`) * 0.02;
      pos.setXYZ(n, o.x + Math.cos(a) * sp2 * age, o.y + Math.sin(a) * sp2 * age - 0.0006 * age * age, o.z + 0.02 + 0.004 * age);
      const b = 3 * (1 - age / 18); col.setXYZ(n, b, b * 0.77, b * 0.24); n++;
    }
  }
  for (let i = n; i < 120; i++) { pos.setXYZ(i, 0, 0, -999); col.setXYZ(i, 0, 0, 0); }
  pos.needsUpdate = true; col.needsUpdate = true;

  const tex = useCanvasTexture(HW, HH, (c) => drawHeadline(c, HW, HH, [{ text: s.kPen, font: `800 300px ${F.display}`, size: 300 }], {
    lf: f - 272, fps, exit: (f - 298) / 12,
    extra: (cx, L) => {
      // o traço sai da tela e vira o sublinhado
      const g = ramp(f, 258, 278, expoOut);
      if (g <= 0) return;
      const y = L.base + 300 * 0.36, xe = -40 + (L.x1 + 20 + 40) * g;
      cx.save(); cx.lineCap = "round"; cx.shadowColor = "rgba(255,196,61,.9)"; cx.shadowBlur = 36;
      cx.strokeStyle = C.star; cx.lineWidth = 16; cx.beginPath(); cx.moveTo(-40, y - 60 * (1 - g)); cx.quadraticCurveTo(L.x0 * 0.6, y, xe, y); cx.stroke();
      cx.shadowBlur = 0; cx.strokeStyle = "#FFF6DA"; cx.lineWidth = 5; cx.stroke(); cx.restore();
      if (g < 1) { cx.fillStyle = "#FFF6DA"; cx.shadowColor = C.star; cx.shadowBlur = 60; cx.beginPath(); cx.arc(xe, y, 16, 0, Math.PI * 2); cx.fill(); }
    },
  }), [f, s]);
  if (f < 200 || f >= 312) return null;
  const drawing = f >= 212 && f < 264;
  return (
    <>
      <group position={penPos} quaternion={penQ} visible={f >= 204 && f < 280}>
        <mesh position={[0, 0.72, 0]}><cylinderGeometry args={[0.018, 0.018, 1.36, 24]} /><meshPhysicalMaterial color="#2A2D3E" roughness={0.3} metalness={0.4} clearcoat={1} /></mesh>
        <mesh position={[0, 0.02, 0]}><coneGeometry args={[0.018, 0.05, 24]} /><meshStandardMaterial color={C.cobaltNight} emissive={C.cobaltNight} emissiveIntensity={0.6} /></mesh>
        <mesh position={[0, 0.34, 0]}><cylinderGeometry args={[0.0195, 0.0195, 0.07, 24]} /><meshPhysicalMaterial color="#3A3E55" roughness={0.2} /></mesh>
      </group>
      {drawing && <PixelStar3D position={[tip.x, tip.y, tip.z + 0.01]} size={0.07} intensity={2.4} />}
      {drawing && <AnamorphicFlare position={[tip.x, tip.y, tip.z + 0.02]} intensity={0.35} length={4} />}
      <points geometry={sparks}><pointsMaterial size={Math.max(2, (5 * height) / 2160)} sizeAttenuation={false} vertexColors transparent blending={AdditiveBlending} depthWrite={false} toneMapped={false} /></points>
      {f >= 266 && <ScreenPlane overlay={overlay} map={tex} w={HW} h={HH} y={60} />}
    </>
  );
};

/* ---------------- 4 · 120 fps (310–420) ---------------- */
const bez = (a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: number) => {
  const u = 1 - t;
  return a.clone().multiplyScalar(u * u * u).add(b.clone().multiplyScalar(3 * u * u * t)).add(c.clone().multiplyScalar(3 * u * t * t)).add(d.clone().multiplyScalar(t * t * t));
};
export const COMET = [326, 350] as const;
export const ShotFps: React.FC<ShotProps> = ({ overlay, s }) => {
  const f = useCurrentFrame(); const { fps } = useVideoConfig();
  const a = laptopScreenWorld(COMET[0]), d = tabletScreenWorld(COMET[1], 0.5, 0.45);
  const b = a.clone().add(new Vector3(1.2, 2.6, 1.2)), c = d.clone().add(new Vector3(-1.4, 2.4, 1.4));
  const p = ramp(f, COMET[0], COMET[1], (t) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2));
  const head = bez(a, b, c, d, p);
  const trail: Vector3[] = [], colors: [number, number, number][] = [];
  for (let i = 0; i <= 40; i++) { const tt = Math.max(0, p - i * 0.006); trail.push(bez(a, b, c, d, tt)); const k = Math.pow(1 - i / 40, 1.6) * 4; colors.push([k, k * 0.77, k * 0.24]); }
  const flying = f >= COMET[0] && f < COMET[1];
  const ring = ramp(f, COMET[1], COMET[1] + 34, expoOut);

  const count = Math.round(120 * ramp(f, 352, 398, (t) => 1 - Math.pow(1 - t, 3)));
  const tex = useCanvasTexture(HW, HH, (cx) => {
    const T = document.createElement("canvas"); T.width = HW; T.height = HH; const t = T.getContext("2d")!;
    const base = HH * 0.62, xR = HW * 0.5 + 60, e = (f - 408) / 12;
    // linhas de velocidade atrás do número
    const sl = ramp(f, 350, 360) * (1 - ramp(f, 396, 410));
    if (sl > 0) for (let i = 0; i < 26; i++) {
      const y = base - 280 + random(`ly${i}`) * 300, spd = 90 + random(`lv${i}`) * 140, len = 200 + random(`ll${i}`) * 700;
      const x = ((random(`lx${i}`) * HW * 2 + (f - 350) * spd) % (HW + len)) - len;
      const g = t.createLinearGradient(x, 0, x + len, 0); g.addColorStop(0, "rgba(111,130,255,0)"); g.addColorStop(1, `rgba(111,130,255,${0.55 * sl})`);
      t.fillStyle = g; t.fillRect(x, y, len, 3 + (i % 3));
    }
    if (f >= 352) {
      t.font = `500 300px ${F.mono}`; t.textAlign = "right"; t.textBaseline = "alphabetic"; t.fillStyle = C.nevoa;
      const pop = f >= 398 ? 1 + 0.04 * Math.sin(Math.PI * ramp(f, 398, 408)) : 1;
      t.save(); t.translate(xR, base); t.scale(pop, pop); t.fillText(String(count), 0, 0); t.restore();
    }
    t.font = `800 300px ${F.display}`;
    const wF = t.measureText(s.kFps).width;
    t.save(); t.translate(xR + 90 + wF / 2 - HW / 2, 0);
    drawHeadline(t, HW, HH, [{ text: s.kFps, font: `800 300px ${F.display}`, size: 300 }], { lf: f - 392, fps, exit: 0, baseline: base, slit: true, sheen: true });
    t.restore();
    // saída do bloco inteiro
    const ee = Math.min(1, Math.max(0, e)), k = ee * ee * ee;
    cx.globalAlpha = 1 - k; if (k > 0) cx.filter = `blur(${30 * k}px)`;
    cx.translate(HW / 2, base); cx.scale(1 - 0.04 * k, 1 - 0.04 * k); cx.translate(-HW / 2, -base);
    cx.drawImage(T, 0, 0);
  }, [f, s, count]);

  if (f < 310 || f >= 422) return null;
  return (
    <>
      {flying && <>
        <Line points={trail} vertexColors={colors} lineWidth={10} transparent toneMapped={false} />
        <mesh position={head}><sphereGeometry args={[0.07, 24, 24]} /><meshBasicMaterial color={new Color(6, 5, 3)} toneMapped={false} /></mesh>
        <AnamorphicFlare position={[head.x, head.y, head.z + 0.05]} intensity={1.1} length={16} />
      </>}
      {ring > 0 && ring < 1 && (
        <mesh position={d} quaternion={new Quaternion().setFromEuler(new Euler(...tabletPose(f).rot))}>
          <ringGeometry args={[0.2 + ring * 2.2, 0.24 + ring * 2.2 + 0.05 * (1 - ring), 96]} />
          <meshBasicMaterial color={new Color(4 * (1 - ring), 3 * (1 - ring), 0.9 * (1 - ring))} transparent depthWrite={false} blending={AdditiveBlending} toneMapped={false} />
        </mesh>
      )}
      {f >= 350 && f < 356 && <AnamorphicFlare position={[d.x, d.y, d.z + 0.05]} intensity={2 * (1 - (f - 350) / 6)} length={40} />}
      {f >= 350 && <ScreenPlane overlay={overlay} map={tex} w={HW} h={HH} y={-40} />}
    </>
  );
};

/* ---------------- 5 · Horizonte de eventos (420–500) ---------------- */
export const ShotHorizon: React.FC<{ camPos: Vector3 }> = ({ camPos }) => {
  const f = useCurrentFrame();
  if (f < 420 || f >= 500) return null;
  const pos = new Vector3(...BH_POS), look = new Vector3().subVectors(camPos, pos).normalize();
  const q = new Quaternion().setFromUnitVectors(new Vector3(0, 0, 1), look);
  return (
    <group position={pos} quaternion={q}>
      <DitherPlane w={44} h={27.5} iw={1280} ih={800} t={f / 60} pull={ramp(f, 460, 500)} opacity={ramp(f, 420, 446)} />
    </group>
  );
};

/* ---------------- 6 · Logo (500–600) ---------------- */
export const ShotLogo: React.FC<ShotProps> = ({ overlay, s }) => {
  const f = useCurrentFrame();
  const logoTex = useTexture(staticFile("logos/ginga-wordmark-dark.png"));
  const img = logoTex.image as HTMLImageElement;
  const LW = 1500, LH = Math.round((1500 * 423) / 1200);
  const inL = ramp(f, 502, 530, expoOut);
  const logo = useCanvasTexture(LW, LH, (c) => {
    
    c.drawImage(img, 0, 0, LW, LH);
    const p = ramp(f, 520, 556);
    if (p > 0 && p < 1) {
      c.globalCompositeOperation = "source-atop";
      const x = -300 + (LW + 600) * p, g = c.createLinearGradient(x - 180, 0, x + 180, 0);
      g.addColorStop(0, "rgba(255,255,255,0)"); g.addColorStop(0.5, "rgba(255,255,255,0.9)"); g.addColorStop(1, "rgba(255,255,255,0)");
      c.setTransform(1, 0, -0.4, 1, 0, 0); c.fillStyle = g; c.fillRect(-LW, 0, LW * 3, LH);
    }
  }, [f, img]);
  const tag = useCanvasTexture(2400, 200, (c) => {
    c.font = `600 76px ${F.sans}`; c.textAlign = "center"; c.textBaseline = "middle"; c.fillStyle = "rgba(242,243,248,0.78)"; c.fillText(s.tagline, 1200, 100);
  }, [s]);
  const oss = useCanvasTexture(2000, 140, (c) => {
    c.font = `400 52px ${F.mono}`; c.textAlign = "center"; c.textBaseline = "middle"; c.fillStyle = C.star; c.fillText(s.freeOss, 1000, 70);
  }, [s]);
  if (f < 502) return null;
  const tagIn = ramp(f, 540, 566, expoOut), ossIn = ramp(f, 552, 578, expoOut);
  const glint = ramp(f, 528, 540, ginga) * (1 - ramp(f, 548, 575));
  const lscale = 0.94 + 0.06 * inL;
  return (
    <>
      <DitherPlane w={9} h={5.6} iw={960} ih={600} t={f / 60} opacity={0.1} glow={0.9} position={[0, 1.1, -5]} rotation={[0, 0, (f - 500) * 0.0025]} />
      <ScreenPlane overlay={overlay} map={logo} w={LW * lscale} h={LH * lscale} y={-170} opacity={inL} />
      <ScreenPlane overlay={overlay} map={tag} w={2400} h={200} y={330 - 16 * tagIn} opacity={tagIn} />
      <ScreenPlane overlay={overlay} map={oss} w={2000} h={140} y={450 - 16 * ossIn} opacity={ossIn} />
      {glint > 0 && <LogoGlint overlay={overlay} f={f} amount={glint} x={-LW * lscale / 2 + LW * lscale * 0.316} y={-170 - LH * lscale / 2 + LH * lscale * 0.12} />}
    </>
  );
};

const LogoGlint: React.FC<{ overlay: Scene; f: number; amount: number; x: number; y: number }> = ({ overlay, f, amount, x, y }) => {
  const tex = useCanvasTexture(512, 512, (c) => {
    const g = c.createRadialGradient(256, 256, 0, 256, 256, 256);
    g.addColorStop(0, "rgba(255,246,218,1)"); g.addColorStop(0.08, "rgba(255,196,61,0.9)"); g.addColorStop(0.3, "rgba(255,196,61,0)");
    c.fillStyle = g; c.fillRect(0, 0, 512, 512);
    c.fillStyle = "rgba(255,220,130,0.95)";
    c.beginPath(); c.moveTo(256, 0); c.lineTo(270, 242); c.lineTo(512, 256); c.lineTo(270, 270); c.lineTo(256, 512); c.lineTo(242, 270); c.lineTo(0, 256); c.lineTo(242, 242); c.closePath(); c.fill();
  }, []);
  const sz = 520 * amount;
  return <ScreenPlane overlay={overlay} map={tex} w={sz} h={sz} x={x} y={y} additive opacity={Math.min(1, amount * 1.2)} />;
};
