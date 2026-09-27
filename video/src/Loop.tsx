import React from "react";
import { AbsoluteFill, useCurrentFrame, useVideoConfig } from "remotion";
import { C } from "./theme";
import { PixelSky } from "./components/PixelSky";
import { DitherBlackHole } from "./components/DitherBlackHole";

/** Buraco negro sem texto. Todo movimento é cíclico em t = frame/total: o último quadro emenda no primeiro. */
export const GingaLoop: React.FC = () => {
  const f = useCurrentFrame();
  const { durationInFrames, width, height, fps } = useVideoConfig();
  const cycle = f / durationInFrames;
  return (
    <AbsoluteFill style={{ background: C.cosmos }}>
      <PixelSky width={width} height={height} loop={durationInFrames} />
      <DitherBlackHole width={1200} height={760} cycle={cycle} loopSeconds={durationInFrames / fps} style={{ left: (width - 1200) / 2, top: (height - 760) / 2 - 20 }} />
    </AbsoluteFill>
  );
};
