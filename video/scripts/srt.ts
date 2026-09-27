// Gera subtitles/ginga-hero.{pt,en}.srt a partir das legendas do GingaHero.
// Roda direto no Node (type stripping): node scripts/srt.ts
import { writeFileSync } from "node:fs";
import { dict, type Lang } from "../src/i18n.ts";
import { HERO } from "../src/timeline.ts";

const REPO = process.argv[2] ?? "github.com/Kelvin-Jesus/ginga";
const ts = (s: number) => {
  const ms = Math.round(s * 1000), h = Math.floor(ms / 3600000), m = Math.floor(ms / 60000) % 60, sec = Math.floor(ms / 1000) % 60;
  const p = (n: number, w = 2) => String(n).padStart(w, "0");
  return `${p(h)}:${p(m)}:${p(sec)},${p(ms % 1000, 3)}`;
};
for (const lang of ["pt", "en"] as Lang[]) {
  const s = dict[lang];
  const cues = [
    ...HERO.captions.map((c) => ({ from: c.from, to: c.to, text: s[c.key] })),
    { from: HERO.outro + 1.6, to: HERO.end, text: `${s.openSource}\n${REPO}` },
  ];
  const body = cues.map((c, i) => `${i + 1}\n${ts(c.from)} --> ${ts(c.to)}\n${c.text}\n`).join("\n");
  writeFileSync(`subtitles/ginga-hero.${lang}.srt`, body);
  console.log(`subtitles/ginga-hero.${lang}.srt: ${cues.length} legendas`);
}
