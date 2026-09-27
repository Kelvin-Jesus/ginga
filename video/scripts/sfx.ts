// Sintetiza os efeitos sonoros do GingaKeynote em public/sfx/*.wav (48 kHz, 16 bits, estéreo).
// Sons originais gerados por matemática: sem download, sem licença de terceiros. Substitua pelos arquivos licenciados quando tiver.
// node scripts/sfx.ts
import { writeFileSync } from "node:fs";

const SR = 48000;
let seed = 1;
const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296) * 2 - 1;

function wav(name: string, L: Float32Array, R: Float32Array = L) {
  let peak = 1e-9; for (let i = 0; i < L.length; i++) peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
  const g = 0.89 / peak, n = L.length, buf = Buffer.alloc(44 + n * 4);
  buf.write("RIFF", 0); buf.writeUInt32LE(36 + n * 4, 4); buf.write("WAVE", 8); buf.write("fmt ", 12);
  buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22); buf.writeUInt32LE(SR, 24);
  buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34); buf.write("data", 36); buf.writeUInt32LE(n * 4, 40);
  for (let i = 0; i < n; i++) { buf.writeInt16LE(Math.round(L[i] * g * 32767), 44 + i * 4); buf.writeInt16LE(Math.round(R[i] * g * 32767), 46 + i * 4); }
  writeFileSync(`public/sfx/${name}`, buf); console.log(`public/sfx/${name}  ${(n / SR).toFixed(2)} s`);
}

/** Passa-banda (biquad) com centro variável. */
function bandpass(x: Float32Array, fc: (t: number) => number, q: number) {
  const y = new Float32Array(x.length); let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  for (let i = 0; i < x.length; i++) {
    const w = (2 * Math.PI * fc(i / SR)) / SR, a = Math.sin(w) / (2 * q), a0 = 1 + a;
    const b0 = a / a0, b2 = -a / a0, a1 = (-2 * Math.cos(w)) / a0, a2 = (1 - a) / a0;
    const v = b0 * x[i] + b2 * x2 - a1 * y1 - a2 * y2; x2 = x1; x1 = x[i]; y2 = y1; y1 = v; y[i] = v;
  }
  return y;
}
const noise = (n: number) => { const a = new Float32Array(n); for (let i = 0; i < n; i++) a[i] = rnd(); return a; };
const pan = (x: Float32Array, p: (t: number) => number): [Float32Array, Float32Array] => {
  const L = new Float32Array(x.length), R = new Float32Array(x.length);
  for (let i = 0; i < x.length; i++) { const a = (p(i / SR) + 1) * Math.PI / 4; L[i] = x[i] * Math.cos(a); R[i] = x[i] * Math.sin(a); }
  return [L, R];
};

// riser grave (1.5 s): senoide subindo 45→180 Hz + ruído filtrado subindo, crescendo até o fim
{
  const d = 1.5, n = d * SR, x = new Float32Array(n), nz = bandpass(noise(n), (t) => 300 + 2400 * (t / d) ** 2, 1.4);
  let ph = 0;
  for (let i = 0; i < n; i++) { const t = i / SR, k = t / d; ph += (2 * Math.PI * (45 + 135 * k * k)) / SR; x[i] = (Math.sin(ph) * 0.7 + nz[i] * 0.5 * k) * Math.pow(k, 1.6); }
  wav("riser.wav", ...pan(x, () => 0));
}
// hit suave (1 s): bumbo grave com queda de altura + transiente curto de ruído, cauda longa
{
  const d = 1.0, n = d * SR, x = new Float32Array(n), nz = bandpass(noise(n), () => 2200, 0.8);
  let ph = 0;
  for (let i = 0; i < n; i++) { const t = i / SR; ph += (2 * Math.PI * (48 + 70 * Math.exp(-t * 28))) / SR; x[i] = Math.sin(ph) * Math.exp(-t * 4.2) + nz[i] * 0.35 * Math.exp(-t * 60) + Math.sin(ph * 2.01) * 0.12 * Math.exp(-t * 7); }
  wav("hit-soft.wav", ...pan(x, () => 0));
}
// whoosh (0.75 s) e whoosh longo (1.33 s): ruído com passa-banda varrendo, passando da esquerda para a direita
for (const [name, d, lo, hi] of [["whoosh.wav", 0.75, 350, 2600], ["whoosh-long.wav", 1.33, 250, 3400]] as const) {
  const n = Math.round(d * SR), env = (t: number) => Math.sin(Math.PI * Math.min(1, t / d)) ** 2;
  const bp = bandpass(noise(n), (t) => lo + (hi - lo) * Math.sin((Math.PI / 2) * (t / d)), 2.2);
  const x = new Float32Array(n); for (let i = 0; i < n; i++) x[i] = bp[i] * env(i / SR);
  wav(name, ...pan(x, (t) => -0.7 + 1.4 * (t / d)));
}
// acorde resolvido (1.7 s): Ré maior com nona, parciais levemente desafinados, ataque lento
{
  const d = 1.7, n = Math.round(d * SR), L = new Float32Array(n), R = new Float32Array(n);
  const notes = [73.42, 146.83, 220.0, 293.66, 369.99, 440.0, 659.25];
  for (let i = 0; i < n; i++) {
    const t = i / SR, env = Math.min(1, t / 0.35) * Math.min(1, (d - t) / 0.5);
    let l = 0, r = 0;
    notes.forEach((f, k) => { const a = 1 / (1 + k * 0.6); l += a * Math.sin(2 * Math.PI * f * 0.998 * t + k); r += a * Math.sin(2 * Math.PI * f * 1.002 * t + k * 1.7); l += a * 0.2 * Math.sin(4 * Math.PI * f * t); });
    L[i] = l * env; R[i] = r * env;
  }
  wav("chord.wav", L, R);
}
