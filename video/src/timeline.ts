import type { Strings } from "./i18n";

/* Linhas do tempo em segundos. Sem imports de runtime: scripts/srt.ts lê este arquivo direto com o Node. */

export type Cam = { t: number; cx: number; cy: number; z: number };
export type Key = { t: number; x: number; y: number };
export type Caption = { from: number; to: number; key: keyof Strings };

export type Timeline = {
  end: number;
  introOut: number;          // o buraco negro recua e os aparelhos aparecem
  wifiClick: number;
  found: number | null;      // null: pula a lista/pareamento (Vertical)
  tap: number; code: number; pairClick: number;
  comet: number;
  dragStart: number; dragEnd: number;
  pen: number; penEnd: number; touch: number;
  outro: number;
  cursor: Key[]; clicks: number[];
  cam: Cam[];
  captions: Caption[];
};

/** Aparelhos e direção do display estendido, em coordenadas do palco. */
export type Layout = {
  w: number; h: number;
  mac: { x: number; y: number }; tab: { x: number; y: number };
  extend: "right" | "down";
  bh: { cx: number; cy: number; w: number; h: number };
  logo: { cy: number; w: number };
  caption: { bottom: number; size: number; width: number };
};

export const HERO: Timeline = {
  end: 30, introOut: 3,
  wifiClick: 8.5,
  found: 11.3, tap: 12.2, code: 12.5, pairClick: 14.5,
  comet: 15.3,
  dragStart: 19.7, dragEnd: 21.8,
  pen: 23.3, penEnd: 24.9, touch: 25.1,
  outro: 27,
  cursor: [
    { t: 0, x: 700, y: 430 }, { t: 7.4, x: 700, y: 430 }, { t: 8.3, x: 424, y: 196 },
    { t: 13.8, x: 424, y: 196 }, { t: 14.35, x: 346, y: 344 },
    { t: 15.0, x: 346, y: 344 }, { t: 15.8, x: 640, y: 440 },
    { t: 19.0, x: 640, y: 440 }, { t: 19.5, x: 600, y: 264 },
  ],
  clicks: [8.5, 14.5, 19.55],
  cam: [
    { t: 0, cx: 960, cy: 560, z: 1.35 }, { t: 3, cx: 960, cy: 560, z: 1.35 }, { t: 4.4, cx: 960, cy: 560, z: 1 },
    { t: 7, cx: 960, cy: 560, z: 1 }, { t: 8, cx: 470, cy: 470, z: 1.85 },
    { t: 10.7, cx: 470, cy: 470, z: 1.85 }, { t: 11.5, cx: 1475, cy: 625, z: 1.6 },
    { t: 13.2, cx: 1475, cy: 625, z: 1.6 }, { t: 14.0, cx: 1000, cy: 530, z: 1.05 },
    { t: 14.9, cx: 1000, cy: 530, z: 1.05 }, { t: 15.5, cx: 960, cy: 560, z: 1 },
    { t: 22.2, cx: 960, cy: 560, z: 1 }, { t: 22.9, cx: 1480, cy: 640, z: 1.75 },
    { t: 26.6, cx: 1480, cy: 640, z: 1.75 }, { t: 27.4, cx: 960, cy: 560, z: 1 },
  ],
  captions: [
    { from: 3.6, to: 7.0, key: "tagline" },
    { from: 23.3, to: 25.0, key: "pen" },
    { from: 25.0, to: 26.1, key: "touch" },
    { from: 26.1, to: 27.0, key: "noDev" },
  ],
};

export const HERO_LAYOUT: Layout = {
  w: 1920, h: 1080,
  mac: { x: 150, y: 250 }, tab: { x: 1175, y: 430 }, extend: "right",
  bh: { cx: 960, cy: 440, w: 1040, h: 660 },
  logo: { cy: 850, w: 380 },
  caption: { bottom: 70, size: 44, width: 1600 },
};

export const VERTICAL: Timeline = {
  end: 20, introOut: 2.6,
  wifiClick: 4.9,
  found: null, tap: 0, code: 0, pairClick: 0,
  comet: 7.2,
  dragStart: 11.4, dragEnd: 13.4,
  pen: 14.6, penEnd: 16.0, touch: 16.05,
  outro: 17.0,
  cursor: [
    { t: 0, x: 620, y: 430 }, { t: 3.9, x: 620, y: 430 }, { t: 4.7, x: 424, y: 196 },
    { t: 5.6, x: 424, y: 196 }, { t: 6.3, x: 640, y: 440 },
    { t: 10.8, x: 640, y: 440 }, { t: 11.25, x: 600, y: 264 },
  ],
  clicks: [4.9, 11.3],
  cam: [
    { t: 0, cx: 540, cy: 900, z: 1.3 }, { t: 2.6, cx: 540, cy: 900, z: 1.3 }, { t: 3.8, cx: 540, cy: 900, z: 1 },
    { t: 3.9, cx: 540, cy: 900, z: 1 }, { t: 4.5, cx: 374, cy: 560, z: 1.7 },
    { t: 6.4, cx: 374, cy: 560, z: 1.7 }, { t: 7.1, cx: 540, cy: 900, z: 1 },
    { t: 13.8, cx: 540, cy: 900, z: 1 }, { t: 14.4, cx: 540, cy: 1235, z: 1.55 },
    { t: 16.7, cx: 540, cy: 1235, z: 1.55 }, { t: 17.3, cx: 540, cy: 900, z: 1 },
  ],
  captions: [
    { from: 2.9, to: 4.0, key: "tagline" },
    { from: 4.1, to: 6.6, key: "turnOn" },
    { from: 7.2, to: 10.8, key: "connected" },
    { from: 11.0, to: 14.0, key: "dragCap" },
    { from: 14.6, to: 16.0, key: "pen" },
    { from: 16.0, to: 17.0, key: "noDev" },
  ],
};

export const VERTICAL_LAYOUT: Layout = {
  w: 1080, h: 1920,
  mac: { x: 90, y: 300 }, tab: { x: 240, y: 1040 }, extend: "down",
  bh: { cx: 540, cy: 780, w: 1000, h: 640 },
  logo: { cy: 1230, w: 440 },
  caption: { bottom: 190, size: 60, width: 960 },
};
