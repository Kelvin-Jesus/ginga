import React from "react";
import { AbsoluteFill, Easing, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { C, ease } from "./theme";
import { F } from "./fonts";
import { t as tr, type Lang } from "./i18n";
import { PixelSky } from "./components/PixelSky";
import { DitherBlackHole } from "./components/DitherBlackHole";

/* GingaTeaser: 6 s, 3840×2160, 60 fps. Três palavras cinéticas e o logotipo sobre o buraco negro. */

const STARTS = [24, 78, 132];
const OUT_AT = 46, OUT_LEN = 12; // a saída (s+46…s+58) cruza a entrada da próxima palavra (s+54)
const BH = { w: 3000, h: 1500 };
const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** Estrela de 4 pontas em pixels (grade 7×7), no lugar do ponto final. */
const STAR = ["...X...", "...X...", "..XXX..", "XXXXXXX", "..XXX..", "...X...", "...X..."];
const PixelStar: React.FC<{ u: number; scale: number }> = ({ u, scale }) => (
  <svg width={u * 7} height={u * 7} viewBox="0 0 7 7" shapeRendering="crispEdges" style={{ display: "inline-block", marginLeft: u * 1.2, transform: `scale(${scale})`, transformOrigin: "50% 50%", verticalAlign: "baseline" }}>
    {STAR.flatMap((row, y) => row.split("").map((c, x) => (c === "X" ? <rect key={`${x}-${y}`} x={x} y={y} width={1} height={1} fill={x === 3 && y === 3 ? "#FFF6DA" : C.star} /> : null)))}
  </svg>
);

const Word: React.FC<{ text: string; start: number }> = ({ text, start }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const l = f - start;
  if (l < 0 || l > OUT_AT + OUT_LEN) return null;
  const inS = spring({ frame: l, fps, config: { damping: 20, stiffness: 190 } });
  const out = interpolate(l, [OUT_AT, OUT_AT + OUT_LEN], [0, 1], { ...clamp, easing: Easing.in(Easing.cubic) });
  const star = spring({ frame: l - 4, fps, config: { damping: 11, stiffness: 220 } });
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <div style={{
        font: `800 300px/1 ${F.display}`, letterSpacing: "-0.02em", color: C.nevoa, whiteSpace: "nowrap",
        opacity: interpolate(l, [0, 8], [0, 1], clamp) * (1 - out),
        transform: `scale(${(1.15 - 0.15 * inS) * (1 - 0.04 * out)})`,
        filter: out > 0 ? `blur(${28 * out}px)` : undefined,
      }}>
        {text}<PixelStar u={11} scale={l < 4 ? 0 : star} />
      </div>
    </AbsoluteFill>
  );
};

export const GingaTeaser: React.FC<{ lang: Lang }> = ({ lang }) => {
  const s = tr(lang);
  const f = useCurrentFrame();
  const { width, height, durationInFrames } = useVideoConfig();
  const intro = interpolate(f, [0, 24], [0, 1], clamp);
  const fadeAll = interpolate(f, [340, 360], [1, 0], clamp);
  const breathe = interpolate(f, [0, durationInFrames], [1, 1.04]);
  const bhIn = interpolate(f, [186, 246], [0, 1], { ...clamp, easing: ease.ginga });
  const logo = interpolate(f, [230, 256], [0, 1], { ...clamp, easing: ease.ginga });
  const tag = interpolate(f, [260, 285], [0, 1], { ...clamp, easing: ease.out });
  const oss = interpolate(f, [290, 315], [0, 1], { ...clamp, easing: ease.out });
  const G = width * 0.55;
  return (
    <AbsoluteFill style={{ background: C.cosmos, overflow: "hidden" }}>
      <AbsoluteFill style={{ opacity: fadeAll }}>
        <PixelSky width={width} height={height} density={0.003} style={{ opacity: 0.35 * intro }} />
        <div style={{ position: "absolute", left: (width - G) / 2, top: (height - G) / 2, width: G, height: G, borderRadius: "50%", opacity: intro, transform: `scale(${breathe})`,
          background: "radial-gradient(circle, rgba(242,243,248,0.14) 0%, rgba(111,130,255,0.06) 45%, rgba(111,130,255,0) 70%)" }} />
        {STARTS.map((st, i) => <Word key={i} text={s.teaserWords.split("|")[i]} start={st} />)}
        {f >= 186 && <>
          {/* 3000×1500 com pixels de 4 px: as partículas em órbita não descem até o texto (nunca atrás de texto) */}
          <div style={{ position: "absolute", left: (width - BH.w) / 2, top: 700 - BH.h * 0.52, width: BH.w, height: BH.h, opacity: interpolate(f, [186, 206], [0, 1], clamp), transform: `scale(${0.6 + 0.4 * bhIn})` }}>
            <DitherBlackHole width={BH.w} height={BH.h} px={4} />
          </div>
          <div style={{ position: "absolute", left: 0, right: 0, top: 1330, display: "flex", flexDirection: "column", alignItems: "center" }}>
            <Img src={staticFile("logos/ginga-wordmark-dark.png")} style={{ width: 880, opacity: Math.min(1, logo * 1.5), transform: `scale(${0.9 + 0.1 * logo})` }} />
            <div style={{ marginTop: 56, font: `600 64px/1.2 ${F.sans}`, color: C.nevoa, opacity: 0.7 * tag, transform: `translateY(${(1 - tag) * 16}px)` }}>{s.tagline}</div>
            <div style={{ marginTop: 28, font: `400 40px/1.2 ${F.mono}`, color: C.star, opacity: oss, transform: `translateY(${(1 - oss) * 16}px)` }}>{s.freeOss}</div>
          </div>
        </>}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};
