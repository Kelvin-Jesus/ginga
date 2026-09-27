import { evolvePath } from "@remotion/paths";
import { C } from "../theme";
import { F } from "../fonts";
import type { Strings } from "../i18n";
import { roundRect } from "./canvasTexture";

/* Interfaces desenhadas em canvas 2D para as telas dos aparelhos 3D (mesma linguagem de GingaWindow). */

export const SCREEN = { w: 1600, h: 1040 };

function wallpaper(ctx: CanvasRenderingContext2D, W: number, H: number, flip = false) {
  ctx.fillStyle = C.cosmos; ctx.fillRect(0, 0, W, H);
  ctx.save();
  if (flip) { ctx.translate(W, 0); ctx.scale(-1, 1); }
  ctx.fillStyle = C.cobalt; ctx.globalAlpha = 0.9;
  ctx.beginPath(); ctx.arc(W * 0.86, H * 1.18, H * 0.72, 0, Math.PI * 2); ctx.fill();
  ctx.globalAlpha = 1; ctx.strokeStyle = "rgba(255,196,61,.55)"; ctx.lineWidth = 4;
  ctx.beginPath(); ctx.ellipse(W * 0.8, H * 0.98, W * 0.62, H * 0.2, -0.24, 0, Math.PI * 2); ctx.stroke();
  ctx.restore();
}

function pill(ctx: CanvasRenderingContext2D, x: number, y: number, label: string, dot: string, s = 1) {
  ctx.font = `500 ${26 * s}px ${F.sans}`;
  const w = ctx.measureText(label).width + 70 * s;
  roundRect(ctx, x - w, y, w, 52 * s, 26 * s); ctx.fillStyle = C.surface2Dark; ctx.fill();
  ctx.fillStyle = dot; ctx.beginPath(); ctx.arc(x - w + 28 * s, y + 26 * s, 9 * s, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = C.nevoa; ctx.textBaseline = "middle"; ctx.fillText(label, x - w + 48 * s, y + 27 * s);
}

function toggle(ctx: CanvasRenderingContext2D, x: number, y: number, on: number) {
  roundRect(ctx, x, y, 88, 52, 26); ctx.fillStyle = on > 0.5 ? C.cobaltNight : C.surface2Dark; ctx.fill();
  ctx.fillStyle = C.nevoa; ctx.beginPath(); ctx.arc(x + 26 + 36 * on, y + 26, 20, 0, Math.PI * 2); ctx.fill();
}

/** Janela do Ginga (tema escuro). (x, y) canto superior esquerdo, largura 820. */
export function gingaWindow(ctx: CanvasRenderingContext2D, s: Strings, x: number, y: number, o: { status: string; dot: string; wifi: number; tablet: boolean }) {
  const W = 820, H = 640;
  ctx.save();
  ctx.shadowColor = "rgba(0,0,0,.55)"; ctx.shadowBlur = 60; ctx.shadowOffsetY = 24;
  roundRect(ctx, x, y, W, H, 34); ctx.fillStyle = C.noite; ctx.fill();
  ctx.restore();
  ["#FF5F57", "#FEBC2E", "#28C840"].forEach((c, i) => { ctx.fillStyle = c; ctx.beginPath(); ctx.arc(x + 40 + i * 34, y + 38, 11, 0, Math.PI * 2); ctx.fill(); });
  ctx.fillStyle = C.nevoa; ctx.textBaseline = "alphabetic"; ctx.font = `600 44px ${F.display}`; ctx.fillText("Ginga", x + 36, y + 128);
  pill(ctx, x + W - 32, y + 88, o.status, o.dot);
  ctx.font = `600 22px ${F.sans}`; ctx.fillStyle = C.inkMuted; ctx.fillText(s.connection.toUpperCase(), x + 40, y + 196);
  roundRect(ctx, x + 32, y + 214, W - 64, 196, 28); ctx.fillStyle = C.surfaceDark; ctx.fill();
  ctx.fillStyle = C.nevoa; ctx.font = `400 30px ${F.sans}`;
  ctx.fillText(s.wifiToggle, x + 64, y + 322 - 50); toggle(ctx, x + W - 160, y + 244, o.wifi);
  ctx.fillStyle = C.lineDark; ctx.fillRect(x + 64, y + 312, W - 128, 2);
  ctx.fillStyle = C.nevoa; ctx.fillText(s.usbToggle, x + 64, y + 366); toggle(ctx, x + W - 160, y + 340, 0);
  ctx.font = `600 22px ${F.sans}`; ctx.fillStyle = C.inkMuted; ctx.fillText(s.tablets.toUpperCase(), x + 40, y + 466);
  roundRect(ctx, x + 32, y + 484, W - 64, 116, 28); ctx.fillStyle = C.surfaceDark; ctx.fill();
  if (o.tablet) {
    ctx.save(); ctx.translate(x + 110, y + 542); ctx.rotate(-0.1); roundRect(ctx, -38, -26, 76, 52, 8); ctx.fillStyle = C.cobalt; ctx.fill(); ctx.restore();
    ctx.fillStyle = C.nevoa; ctx.font = `500 30px ${F.sans}`; ctx.fillText(s.tabletName, x + 176, y + 536);
    ctx.fillStyle = C.inkMuted; ctx.font = `400 22px ${F.mono}`; ctx.fillText(s.tabletMeta, x + 176, y + 572);
    ctx.fillStyle = C.success; ctx.beginPath(); ctx.arc(x + W - 80, y + 542, 10, 0, Math.PI * 2); ctx.fill();
  } else { ctx.fillStyle = C.inkMuted; ctx.font = `400 28px ${F.sans}`; ctx.fillText(s.noTablets, x + 64, y + 552); }
}

/** Janela de notas genérica. */
export function notesWindow(ctx: CanvasRenderingContext2D, s: Strings, x: number, y: number, w = 620, h = 430) {
  ctx.save();
  ctx.shadowColor = "rgba(0,0,0,.55)"; ctx.shadowBlur = 50; ctx.shadowOffsetY = 20;
  roundRect(ctx, x, y, w, h, 28); ctx.fillStyle = C.surfaceDark; ctx.fill();
  ctx.restore();
  ctx.fillStyle = C.inkMuted; ctx.font = `600 28px ${F.sans}`; ctx.textBaseline = "alphabetic"; ctx.fillText(s.notesTitle, x + 36, y + 56);
  [1, 0.6, 0.85, 1, 0.5, 0.8, 0.9].forEach((k, i) => { roundRect(ctx, x + 36, y + 96 + i * 44, (w - 72) * k, 16, 8); ctx.fillStyle = i === 2 ? C.cobaltSoftDark : C.surface2Dark; ctx.fill(); });
}

/** Curva da S Pen em coordenadas da tela do tablet (termina na borda direita e continua como sublinhado). */
export const PEN_PATH = "M 260 700 C 380 520, 470 500, 540 620 S 700 800, 820 600 S 1000 330, 1120 520 S 1320 760, 1600 560";

export type TabletState = {
  mode: "window" | "stream";
  tap?: number;         // 0–1 do toque (dedo translúcido + anel)
  pen?: number;         // 0–1 do traço
  warp?: number;        // 0–1 das linhas de warp
  winIn?: number;       // 0–1 da janela entrando pela esquerda
};

export function drawTablet(ctx: CanvasRenderingContext2D, s: Strings, st: TabletState) {
  const { w: W, h: H } = SCREEN;
  if (st.mode === "window") {
    ctx.fillStyle = C.noite; ctx.fillRect(0, 0, W, H);
    gingaWindow(ctx, s, (W - 820) / 2, 200, { status: s.connected.split(" · ")[0], dot: C.success, wifi: 1, tablet: true });
  } else {
    wallpaper(ctx, W, H, true);
    ctx.fillStyle = "rgba(10,12,28,.72)"; roundRect(ctx, W / 2 - 250, 40, 500, 60, 30); ctx.fill();
    ctx.fillStyle = C.success; ctx.beginPath(); ctx.arc(W / 2 - 214, 70, 10, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = C.nevoa; ctx.font = `500 28px ${F.sans}`; ctx.textBaseline = "middle"; ctx.fillText(s.connected.replace("60 Hz", "120 Hz"), W / 2 - 190, 71);
    if (st.winIn !== undefined && st.winIn > 0) notesWindow(ctx, s, -640 + st.winIn * 900, 300);
  }
  if (st.pen !== undefined && st.pen > 0) {
    const { strokeDasharray, strokeDashoffset } = evolvePath(st.pen, PEN_PATH);
    const p = new Path2D(PEN_PATH);
    ctx.save();
    ctx.lineCap = "round"; ctx.lineJoin = "round";
    ctx.setLineDash(String(strokeDasharray).split(" ").map(Number)); ctx.lineDashOffset = Number(strokeDashoffset);
    ctx.shadowColor = "rgba(255,196,61,.9)"; ctx.shadowBlur = 30;
    ctx.strokeStyle = C.star; ctx.lineWidth = 14; ctx.stroke(p);
    ctx.shadowBlur = 0; ctx.strokeStyle = "#FFF6DA"; ctx.lineWidth = 4; ctx.stroke(p);
    ctx.restore();
  }
  if (st.tap !== undefined && st.tap > 0 && st.tap < 1) {
    const x = W * 0.66, y = H * 0.36, e = st.tap;
    ctx.fillStyle = `rgba(242,243,248,${0.35 * (1 - Math.max(0, e - 0.6) / 0.4)})`;
    ctx.beginPath(); ctx.arc(x, y, 64 * (1 - 0.15 * Math.sin(Math.PI * Math.min(1, e * 2))), 0, Math.PI * 2); ctx.fill();
    ctx.strokeStyle = `rgba(242,243,248,${0.7 * (1 - e)})`; ctx.lineWidth = 5;
    ctx.beginPath(); ctx.arc(x, y, 64 + e * 160, 0, Math.PI * 2); ctx.stroke();
  }
  if (st.warp !== undefined && st.warp > 0 && st.warp < 1) {
    const p = st.warp, cx = W / 2, cy = H / 2;
    ctx.save(); ctx.globalAlpha = Math.sin(Math.PI * p); ctx.lineCap = "round";
    for (let i = 0; i < 160; i++) {
      const a = (i * 2.399963) % (Math.PI * 2), d0 = ((i * 97) % 400) + p * p * 1400, len = 40 + p * 520;
      ctx.strokeStyle = i % 7 === 0 ? C.star : i % 3 === 0 ? C.cobaltNight : C.nevoa; ctx.lineWidth = 3 + p * 4;
      ctx.beginPath(); ctx.moveTo(cx + Math.cos(a) * d0, cy + Math.sin(a) * d0); ctx.lineTo(cx + Math.cos(a) * (d0 + len), cy + Math.sin(a) * (d0 + len)); ctx.stroke();
    }
    ctx.restore();
  }
  // vidro: reflexo diagonal sutil
  const g = ctx.createLinearGradient(0, 0, W, H);
  g.addColorStop(0, "rgba(242,243,248,0.06)"); g.addColorStop(0.35, "rgba(242,243,248,0)"); g.addColorStop(1, "rgba(242,243,248,0)");
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
}

export function drawLaptop(ctx: CanvasRenderingContext2D, s: Strings, o: { notesOut: number }) {
  const { w: W, h: H } = SCREEN;
  wallpaper(ctx, W, H);
  ctx.fillStyle = "rgba(10,12,28,.6)"; ctx.fillRect(0, 0, W, 44);
  gingaWindow(ctx, s, 90, 150, { status: s.connected.split(" · ")[0], dot: C.success, wifi: 1, tablet: true });
  if (o.notesOut < 1) notesWindow(ctx, s, 940 + o.notesOut * 900, 420);
}
