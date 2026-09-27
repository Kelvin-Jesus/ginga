// RMS e pico de um WAV PCM 16 bits, por trechos (o ffmpeg do Remotion não tem volumedetect).
// node scripts/loudness.mjs out/keynote-audio.wav 0:10 3.6:4.3 8.4:9.9
import { readFileSync } from "node:fs";

const [file, ...ranges] = process.argv.slice(2);
const b = readFileSync(file);
let o = 12;
while (b.toString("ascii", o, o + 4) !== "data") o += 8 + b.readUInt32LE(o + 4);
const ch = b.readUInt16LE(22), sr = b.readUInt32LE(24), d = o + 8, n = b.readUInt32LE(o + 4) / (2 * ch);
for (const r of ranges.length ? ranges : [`0:${n / sr}`]) {
  const [a, z] = r.split(":").map(Number);
  let s = 0, c = 0, p = 0;
  for (let i = Math.floor(a * sr); i < Math.min(n, z * sr); i++) for (let k = 0; k < ch; k++) {
    const v = b.readInt16LE(d + (i * ch + k) * 2) / 32768; s += v * v; c++; p = Math.max(p, Math.abs(v));
  }
  const db = (x) => (20 * Math.log10(x + 1e-9)).toFixed(1);
  console.log(`${r.padEnd(10)} ${db(Math.sqrt(s / c))} dB RMS, pico ${db(p)} dB`);
}
