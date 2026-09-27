import React, { useMemo } from "react";
import { ThreeCanvas } from "@remotion/three";
import { AbsoluteFill, Audio, Sequence, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Environment, Lightformer } from "@react-three/drei";
import { Scene, Vector3 } from "three";
import { C } from "../theme";
import { t as tr, type Lang } from "../i18n";
import { CameraRig, camPose } from "./CameraRig";
import { PostFX, type FxState } from "./PostFX";
import { Starfield3D } from "./Starfield3D";
import { Laptop3D, Tablet3D } from "./Devices3D";
import { useCanvasTexture } from "./canvasTexture";
import { drawLaptop, drawTablet, SCREEN } from "./screens";
import { BH_POS, CAM, camDistance, laptopPose, projectUV, tabletPose, tabletScreenWorld } from "./poses";
import { shockAt } from "./Shockwave";
import { lensAt } from "./LensingPass";
import { caAmount, CUT, expoOut, ramp } from "./timing";
import { CameraMotionBlur } from "@remotion/motion-blur";
import { ShotFps, ShotHorizon, ShotIgnition, ShotLogo, ShotPen, ShotTouch } from "./Shots";

/* GingaKeynote: 10 s, 3840×2160, 60 fps. Um único ThreeCanvas; cada plano entra e sai pelo quadro. */

export type KeynoteProps = { lang: Lang; sfx?: boolean };

/** Faixas de som (arquivos licenciados em public/sfx/, fornecidos à parte). Silêncio total no corte do quadro 500. */
export const SFX: { file: string; from: number; dur: number; vol?: number; note: string }[] = [
  { file: "riser.wav", from: 0, dur: 90, vol: 0.75, note: "riser grave 0–90 (sintetizado)" },
  { file: "kenney/spaceEngineLow_000.wav", from: 0, dur: 90, vol: 0.35, note: "cama do riser" },
  { file: "hit-soft.wav", from: 30, dur: 60, note: "ignição" },
  { file: "kenney/lowFrequency_explosion_001.wav", from: 30, dur: 60, vol: 0.5, note: "ignição, grave" },
  { file: "kenney/forceField_001.wav", from: 60, dur: 57, vol: 0.45, note: "varredura de luz" },
  { file: "whoosh.wav", from: 90, dur: 45, note: "tablet sobe" },
  { file: "hit-soft.wav", from: 130, dur: 60, note: "toque" },
  { file: "whoosh.wav", from: 196, dur: 50, note: "órbita" },
  { file: "hit-soft.wav", from: 200, dur: 60, note: "S Pen" },
  { file: "kenney/forceField_003.wav", from: 214, dur: 57, vol: 0.18, note: "brilho do traço da S Pen" },
  { file: "pen-scratch.wav", from: 212, dur: 57, vol: 0.7, note: "caneta riscando papel (quadros 212–262)" },
  { file: "whoosh.wav", from: 308, dur: 50, note: "recuo" },
  { file: "kenney/thrusterFire_002.wav", from: 324, dur: 30, vol: 0.4, note: "voo do cometa" },
  { file: "hit-soft.wav", from: 350, dur: 60, note: "impacto do cometa" },
  { file: "kenney/lowFrequency_explosion_000.wav", from: 350, dur: 70, vol: 0.6, note: "impacto, grave" },
  { file: "hit-soft.wav", from: 400, dur: 60, note: "fps" },
  { file: "kenney/forceField_001.wav", from: 400, dur: 57, vol: 0.35, note: "brilho do fps" },
  { file: "whoosh-long.wav", from: 420, dur: 80, note: "espiral (termina seco no corte)" },
  { file: "kenney/spaceEngineLow_000.wav", from: 440, dur: 60, vol: 0.45, note: "espiral, grave" },
  { file: "hit-soft.wav", from: 510, dur: 60, note: "logo" },
  { file: "kenney/lowFrequency_explosion_001.wav", from: 510, dur: 60, vol: 0.35, note: "logo, grave" },
  { file: "chord.wav", from: 502, dur: 98, vol: 0.75, note: "acorde resolvido sob o logo" },
];

const Screens: React.FC<{ lang: Lang }> = ({ lang }) => {
  const f = useCurrentFrame();
  const s = tr(lang);
  const tabTex = useCanvasTexture(SCREEN.w, SCREEN.h, (c) => drawTablet(c, s, {
    mode: f >= 350 ? "stream" : "window",
    tap: ramp(f, 130, 156),
    pen: f >= 200 && f < 350 ? ramp(f, 212, 262, (t) => t * t * (3 - 2 * t)) : 0,
    warp: ramp(f, 350, 374),
    winIn: ramp(f, 368, 400, (t) => 1 - Math.pow(1 - t, 4)),
  }), [f, s]);
  const lapTex = useCanvasTexture(SCREEN.w, SCREEN.h, (c) => drawLaptop(c, s, { notesOut: ramp(f, 360, 392, (t) => t * t) }), [f >= 355 ? f : 0, s]);
  const tp = tabletPose(f), lp = laptopPose(f);
  return (
    <>
      <Tablet3D screen={tabTex} position={tp.pos} rotation={tp.rot} scale={tp.scale} visible={tp.visible} glow={1.05} />
      <Laptop3D screen={lapTex} position={lp.pos} rotation={lp.rot} scale={lp.scale} visible={lp.visible} glow={1.05} />
    </>
  );
};

function fxAt(f: number, aspect: number): FxState {
  const tab = tabletScreenWorld(Math.min(Math.max(f, 90), 499), 0.5, 0.5);
  const dTab = camDistance(f, tab);
  let focus = 8, range = 0;
  if (f < 90) { focus = 22; range = 30; }  // só as estrelas próximas viram bokeh
  if (f >= 90 && f < 200) focus = f < 136 ? dTab : f < 150 ? dTab + (2.5 - dTab) * ramp(f, 136, 150) : f < 188 ? 2.5 : 2.5 + (dTab - 2.5) * ramp(f, 188, 200);
  else if (f >= 200 && f < 310) focus = f < 266 ? dTab : dTab + (1.4 - dTab) * ramp(f, 266, 285) * (1 - ramp(f, 300, 312));
  else if (f >= 310 && f < 420) { const d0 = camDistance(f, new Vector3(0, 0, 0)); focus = d0 + (3 - d0) * ramp(f, 356, 370) * (1 - ramp(f, 405, 420)); }
  else if (f >= 420 && f < 500) focus = camDistance(f, new Vector3(...BH_POS));
  const shock = shockAt(f, 130, projectUV(f, tabletScreenWorld(130, 0.66, 0.36), aspect)) ?? shockAt(f, 350, projectUV(f, tabletScreenWorld(350, 0.5, 0.45), aspect));
  const lens = lensAt(f, 440, CUT, projectUV(f, new Vector3(...BH_POS), aspect));
  let fade = ramp(f, 0, 20) * (0.8 + 0.2 * ramp(f, 60, 76));
  // sem corte seco: a cena do logo abre do centro (íris) logo depois de o horizonte engolir tudo
  const iris = f >= CUT ? 1.15 * ramp(f, CUT, CUT + 30, expoOut) : undefined;
  if (f >= CUT) fade = 1 - ramp(f, 580, 600);
  return { focus, range, bokeh: 5, ca: caAmount(f), shock, lens, fade, iris, frame: f };
}

/** Planos rápidos com desfoque de movimento de câmera (180°, 6 amostras): o voo do cometa e a espiral final. */
export const FAST: [number, number][] = [[324, 356], [470, 492]];

export const GingaKeynote: React.FC<KeynoteProps> = ({ lang, sfx = false }) => {
  const f = useCurrentFrame();
  const fast = FAST.some(([a, b]) => f >= a && f < b);
  return (
    <AbsoluteFill style={{ background: C.cosmos }}>
      {fast ? <CameraMotionBlur shutterAngle={180} samples={6}><KeynoteScene lang={lang} /></CameraMotionBlur> : <KeynoteScene lang={lang} />}
      {sfx && <KeynoteSound />}
    </AbsoluteFill>
  );
};

const KeynoteScene: React.FC<{ lang: Lang }> = ({ lang }) => {
  const f = useCurrentFrame();
  const { width, height } = useVideoConfig();
  const overlay = useMemo(() => new Scene(), []);
  const s = tr(lang);
  const fx = fxAt(f, width / height);
  const cam = camPose(CAM, f);
  const stars = f < CUT ? 1 : 0.45;
  const px = Math.max(1, (4 * height) / 2160);
  return (
    <AbsoluteFill style={{ background: C.cosmos }}>
      <ThreeCanvas width={width} height={height} gl={{ preserveDrawingBuffer: true, antialias: true }} camera={{ fov: 32, near: 0.05, far: 400, position: [0, 0, 15] }}>
        <color attach="background" args={[C.cosmos]} />
        <CameraRig keys={CAM} />
        <Environment resolution={512} frames={1}>
          <Lightformer form="rect" color={C.cobalt} intensity={5} scale={[14, 0.35, 1]} position={[0, 3.5, -5]} />
          <Lightformer form="rect" color={C.cobaltNight} intensity={4} scale={[14, 0.3, 1]} position={[-2, -2.5, -4]} rotation={[0, 0, 0.2]} />
          <Lightformer form="rect" color={C.star} intensity={9} scale={[1.6, 1.2, 1]} position={[1.5, 5, 3]} rotation={[Math.PI / 2, 0, 0]} />
          <Lightformer form="ring" color={C.cobaltNight} intensity={2} scale={3} position={[6, 0, 4]} />
        </Environment>
        <ambientLight intensity={0.05} />
        <directionalLight position={[0, 6, 2.5]} color={C.star} intensity={1.6} />
        <directionalLight position={[-3, 1.5, -5]} color={C.cobalt} intensity={4} />
        <directionalLight position={[4, -1, -4]} color={C.cobaltNight} intensity={2.5} />
        {f < CUT && <Starfield3D px={px} opacity={stars} />}
        {f >= CUT && <Starfield3D px={px} opacity={0.35} count={2500} />}
        <Screens lang={lang} />
        <ShotIgnition overlay={overlay} s={s} />
        <ShotTouch overlay={overlay} s={s} />
        <ShotPen overlay={overlay} s={s} />
        <ShotFps overlay={overlay} s={s} />
        <ShotHorizon camPos={new Vector3(...cam.pos)} />
        <ShotLogo overlay={overlay} s={s} />
        <PostFX overlay={overlay} w={width} h={height} fx={fx} />
      </ThreeCanvas>
    </AbsoluteFill>
  );
};

/** Ganho geral da mixagem (−3 dB): a soma das camadas estourava no riser e no logo. */
const MASTER = 0.7;

/** Só a trilha de efeitos (também registrada como composição leve, para trocar o áudio sem renderizar o 3D). */
export const KeynoteSound: React.FC = () => (
  <>
    {SFX.map((x, i) => {
      const len = Math.min(x.dur, x.from < CUT ? CUT - x.from : 600 - x.from);
      return (
        <Sequence key={i} from={x.from} durationInFrames={len}>
          <Audio src={staticFile(`sfx/${x.file}`)} volume={(fr) => MASTER * (x.vol ?? 1) * Math.min(1, fr / 3, (len - fr) / 4)} />
        </Sequence>
      );
    })}
  </>
);
