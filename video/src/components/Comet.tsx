import { interpolate } from "remotion";
import { C, ease } from "../theme";

export type Pt = { x: number; y: number };
const bez = (p0: Pt, p1: Pt, p2: Pt, p3: Pt, t: number): Pt => {
  const u = 1 - t;
  return { x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x, y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y };
};

/** Cometa dourado numa curva de Mac para tablet, em coordenadas do palco.
 *  `p` 0–1 é o voo (dur-warp, easeInOut); `ring` 0–1 é o anel que se expande no fim (700 ms). */
export const Comet: React.FC<{ from: Pt; to: Pt; p: number; ring: number; width: number; height: number; lift?: number }> = ({ from, to, p, ring, width, height, lift = 260 }) => {
  const c1 = { x: from.x + 140, y: from.y - lift }, c2 = { x: to.x - 60, y: to.y - lift * 1.25 };
  const route = `M${from.x} ${from.y} C ${c1.x} ${c1.y}, ${c2.x} ${c2.y}, ${to.x} ${to.y}`;
  const e = ease.inOut(Math.min(1, Math.max(0, p)));
  const flying = p > 0 && p < 1;
  // cauda: amostras atrás da cabeça, afinando e apagando
  const TAIL = 28, span = 0.2, segs = [] as React.ReactNode[];
  if (flying) for (let i = 0; i < TAIL; i++) {
    const a = Math.max(0, e - (span * i) / TAIL), b = Math.max(0, e - (span * (i + 1)) / TAIL);
    if (a === b) break;
    const A = bez(from, c1, c2, to, a), B = bez(from, c1, c2, to, b), k = 1 - i / TAIL;
    segs.push(<line key={i} x1={A.x} y1={A.y} x2={B.x} y2={B.y} stroke={C.star} strokeWidth={1 + 6 * k} strokeLinecap="round" opacity={0.15 + 0.85 * k * k} />);
  }
  const head = bez(from, c1, c2, to, e);
  const routeOp = interpolate(p, [-0.15, 0, 1, 1.4], [0, 0.55, 0.55, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const r = ease.out(Math.min(1, Math.max(0, ring)));
  return (
    <svg width={width} height={height} style={{ position: "absolute", left: 0, top: 0, overflow: "visible", pointerEvents: "none" }}>
      <defs>
        <filter id="cometGlow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="6" result="b" /><feMerge><feMergeNode in="b" /><feMergeNode in="SourceGraphic" /></feMerge></filter>
        <radialGradient id="cometHead"><stop offset="0" stopColor="#FFFFFF" /><stop offset=".35" stopColor="#FFF6DA" /><stop offset="1" stopColor={C.star} stopOpacity="0" /></radialGradient>
      </defs>
      <path d={route} fill="none" stroke={C.cobaltNight} strokeWidth={1.6} strokeDasharray="2 9" strokeLinecap="round" opacity={routeOp} />
      <g filter="url(#cometGlow)">{segs}</g>
      {flying && <circle cx={head.x} cy={head.y} r={16} fill="url(#cometHead)" />}
      {flying && <circle cx={head.x} cy={head.y} r={4.5} fill="#FFFFFF" />}
      {ring > 0 && ring < 1 && <>
        <circle cx={to.x} cy={to.y} r={8 + 110 * r} fill="none" stroke={C.star} strokeWidth={3.5 - 3 * r} opacity={1 - r} />
        <circle cx={to.x} cy={to.y} r={4 + 60 * r} fill="none" stroke={C.cobaltNight} strokeWidth={2 - 1.5 * r} opacity={(1 - r) * 0.7} />
      </>}
    </svg>
  );
};
