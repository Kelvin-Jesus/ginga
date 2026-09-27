import React from "react";
import { interpolate } from "remotion";
import { C, ease, glowStar } from "../theme";
import { F } from "../fonts";

/** Código em dois grupos de três. Cada dígito surge como estrela: um brilho `star` que vira o número.
 *  `t` = segundos desde o início da animação. */
export const PairingCode: React.FC<{ code?: string; t: number; size?: number; color?: string }> = ({ code = "482913", t, size = 36, color = C.nevoa }) => {
  const d = code.split("");
  const digit = (c: string, i: number) => {
    const t0 = i * 0.07 + (i >= 3 ? 0.05 : 0);
    const p = interpolate(t - t0, [0, 0.42], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
    const e = ease.ginga(p);
    const flare = interpolate(t - t0, [0, 0.12, 0.4], [0, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
    return (
      <span key={i} style={{ position: "relative", display: "inline-block" }}>
        <span style={{ display: "inline-block", transform: `scale(${0.4 + 0.6 * e}) translateY(${(1 - e) * 6}px)`, opacity: Math.min(1, p * 2.5) }}>{c}</span>
        <span style={{ position: "absolute", left: "50%", top: "50%", width: size * 0.5, height: size * 0.5, margin: -size * 0.25, background: C.star, boxShadow: glowStar, clipPath: "polygon(50% 0,62% 38%,100% 50%,62% 62%,50% 100%,38% 62%,0 50%,38% 38%)", opacity: flare, transform: `scale(${0.4 + flare}) rotate(${flare * 45}deg)` }} />
      </span>
    );
  };
  return (
    <span style={{ display: "inline-flex", gap: size * 0.45, font: `500 ${size}px/${size * 1.12}px ${F.mono}`, letterSpacing: ".08em", color }}>
      <span style={{ display: "inline-flex", gap: 2 }}>{d.slice(0, 3).map((c, i) => digit(c, i))}</span>
      <span style={{ display: "inline-flex", gap: 2 }}>{d.slice(3).map((c, i) => digit(c, i + 3))}</span>
    </span>
  );
};
