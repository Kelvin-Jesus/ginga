import React from "react";
import { useCurrentFrame, useVideoConfig } from "remotion";
import { C } from "../theme";

/** Galaxy Tab genérico em CSS. Flutua 6 px (float) e fica levemente inclinado, como na marca. */
export const TAB = { w: 600, h: 390, pad: 13 };
export const GalaxyTab: React.FC<{ children?: React.ReactNode; style?: React.CSSProperties; float?: boolean; tilt?: number; screenBg?: string }> = ({
  children, style, float = true, tilt = -3, screenBg = C.noite,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const y = float ? Math.sin((frame / fps) * ((Math.PI * 2) / 3.5)) * 6 : 0;
  return (
    <div style={{ position: "absolute", width: TAB.w, height: TAB.h, transform: `translateY(${y}px) rotate(${tilt}deg)`, transformOrigin: "50% 90%", ...style }}>
      <div style={{ position: "absolute", inset: 0, padding: TAB.pad, borderRadius: 32, background: C.frame, boxShadow: "inset 0 0 0 2px #30344A, 0 40px 90px rgba(0,0,0,.6)" }}>
        <div style={{ position: "absolute", top: "50%", right: 4, width: 6, height: 6, marginTop: -3, borderRadius: "50%", background: "#3A3E55" }} />
        <div style={{ position: "relative", height: "100%", borderRadius: 20, overflow: "hidden", background: screenBg }}>{children}</div>
      </div>
    </div>
  );
};
