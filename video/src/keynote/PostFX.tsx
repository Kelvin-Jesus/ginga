import React, { useLayoutEffect, useMemo } from "react";
import { useFrame, useThree } from "@react-three/fiber";
import { BlendFunction, BloomEffect, ChromaticAberrationEffect, DepthOfFieldEffect, Effect, EffectAttribute, EffectComposer, EffectPass, RenderPass, VignetteEffect } from "postprocessing";
import { Color, HalfFloatType, Scene, Uniform, Vector2 } from "three";

/* Cadeia de pós-produção, toda dirigida pelo quadro:
   1. cena principal → profundidade de campo
   2. cena de sobreposição (títulos) por cima, sem DoF
   3. bloom · aberração cromática · onda de choque + lente gravitacional · grão · vinheta · fade */

/** Onda de choque (refração em anel) e lente gravitacional (puxão radial + giro com desfoque rotacional). */
class DistortEffect extends Effect {
  constructor() {
    super("Distort", /* glsl */ `
      uniform vec2 swC; uniform float swR; uniform float swA; uniform float aspect;
      uniform vec2 lC; uniform float lS; uniform float lSpin; uniform float lR; uniform float lH;
      vec2 lens(vec2 uv, float spin) {
        vec2 e = uv - lC; e.x *= aspect; float r = length(e);
        float pull = lS * lR * lR / (r * r + lR * lR * 0.35);
        float a = spin * exp(-r * 1.6);
        e = mat2(cos(a), -sin(a), sin(a), cos(a)) * e * (1.0 + pull);
        e.x /= aspect; return lC + e;
      }
      void mainImage(const in vec4 inputColor, const in vec2 uv, out vec4 outputColor) {
        vec2 u = uv;
        // onda de choque: desloca o UV num anel fino
        vec2 d = u - swC; d.x *= aspect; float r = length(d);
        float ring = swA * (1.0 - smoothstep(0.0, 0.045, abs(r - swR)));
        vec2 dir = normalize(d + 1e-5); dir.x /= aspect;
        vec2 uS = u - dir * ring;
        vec3 c;
        if (lS > 0.0001) {
          // desfoque rotacional: amostras ao longo do giro
          c = vec3(0.0);
          for (int i = 0; i < 8; i++) { float k = float(i) / 7.0; vec2 q = lens(uS, lSpin * (0.82 + 0.18 * k)); q = 1.0 - abs(1.0 - mod(q, 2.0)); c += texture2D(inputBuffer, q).rgb; }
          c /= 8.0;
          vec2 e = uv - lC; e.x *= aspect; float hr = length(e);
          // horizonte de eventos; no fim (lH) ele cresce até engolir o quadro, com o anel de fótons na borda
          float hz = max(lR * 0.31 * lS, lH);
          c = mix(vec3(0.0030, 0.0037, 0.0116), c, smoothstep(hz - 0.012 - 0.03 * step(0.0001, lH), hz + 0.002, hr));   // fecha em cosmos, igual à cena seguinte
          c += vec3(0.43, 0.51, 1.0) * 1.4 * exp(-pow((hr - hz - 0.004) / 0.006, 2.0)) * step(0.0001, lH);
        } else {
          // pulso de aberração dentro do anel
          c.r = texture2D(inputBuffer, uS + dir * ring * 0.6).r;
          c.g = texture2D(inputBuffer, uS).g;
          c.b = texture2D(inputBuffer, uS - dir * ring * 0.6).b;
        }
        outputColor = vec4(c, inputColor.a);
      }`, {
      attributes: EffectAttribute.CONVOLUTION,
      uniforms: new Map<string, Uniform>([
        ["swC", new Uniform(new Vector2(0.5, 0.5))], ["swR", new Uniform(0)], ["swA", new Uniform(0)], ["aspect", new Uniform(16 / 9)],
        ["lC", new Uniform(new Vector2(0.5, 0.5))], ["lS", new Uniform(0)], ["lSpin", new Uniform(0)], ["lR", new Uniform(0.3)], ["lH", new Uniform(0)],
      ]),
    });
  }
}

/** Grão animado (semente = quadro) e fade para cosmos. */
class GrainFadeEffect extends Effect {
  constructor() {
    super("GrainFade", /* glsl */ `
      uniform float seed; uniform float amount; uniform float fade; uniform vec3 cosmos; uniform vec2 res; uniform float iris;
      float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233)) + seed) * 43758.5453); }
      void mainImage(const in vec4 inputColor, const in vec2 uv, out vec4 outputColor) {
        float n = h(floor(uv * res / 2.0)) - 0.5;
        vec3 c = inputColor.rgb + n * amount * (0.35 + inputColor.rgb);
        c = mix(cosmos, c, fade);
        if (iris >= 0.0) {
          // saída do buraco: a cena nova abre do centro, com o mesmo anel de fótons na borda
          vec2 q = (uv - 0.5) * vec2(res.x / res.y, 1.0); float d = length(q);
          c = mix(c, cosmos, smoothstep(iris - 0.05, iris, d));
          c += vec3(0.43, 0.51, 1.0) * 1.2 * exp(-pow((d - iris) / 0.006, 2.0)) * (1.0 - smoothstep(0.9, 1.15, iris));
        }
        outputColor = vec4(c, inputColor.a);
      }`, {
      blendFunction: BlendFunction.NORMAL,
      uniforms: new Map<string, Uniform>([["seed", new Uniform(0)], ["amount", new Uniform(0.06)], ["fade", new Uniform(1)], ["cosmos", new Uniform(new Color("#0A0C1C"))], ["res", new Uniform(new Vector2(3840, 2160))], ["iris", new Uniform(-1)]]),
    });
  }
}

export type FxState = {
  focus: number;            // distância de foco em metros
  range?: number;           // faixa nítida (0 = automática)
  bokeh: number;
  ca: number;
  shock?: { uv: [number, number]; r: number; amp: number };
  lens?: { uv: [number, number]; strength: number; spin: number; radius: number; hole?: number };
  iris?: number;            // abertura circular a partir do centro (0 = fechado, ≥1.1 = aberto); undefined = sem íris
  fade: number;             // 1 = imagem, 0 = cosmos
  frame: number;
};

export const PostFX: React.FC<{ overlay: Scene; w: number; h: number; fx: FxState }> = ({ overlay, w, h, fx }) => {
  const { gl, scene, camera } = useThree();
  const chain = useMemo(() => {
    const composer = new EffectComposer(gl, { frameBufferType: HalfFloatType });
    composer.addPass(new RenderPass(scene, camera));
    const dof = new DepthOfFieldEffect(camera, { worldFocusDistance: 8, worldFocusRange: 3, bokehScale: 3 });
    composer.addPass(new EffectPass(camera, dof));
    const over = new RenderPass(overlay, camera); over.clear = false; over.clearPass.enabled = false;
    composer.addPass(over);
    const bloom = new BloomEffect({ mipmapBlur: true, luminanceThreshold: 0.6, luminanceSmoothing: 0.2, intensity: 1.2 });
    const ca = new ChromaticAberrationEffect({ offset: new Vector2(0.0008, 0.0008), radialModulation: true, modulationOffset: 0.15 });
    composer.addPass(new EffectPass(camera, bloom, ca));
    const distort = new DistortEffect();
    composer.addPass(new EffectPass(camera, distort));
    const grain = new GrainFadeEffect(), vig = new VignetteEffect({ darkness: 0.55, offset: 0.3 });
    composer.addPass(new EffectPass(camera, vig, grain));
    return { composer, dof, ca, distort, grain };
  }, [gl, scene, camera, overlay]);

  useLayoutEffect(() => { chain.composer.setSize(w, h); }, [chain, w, h]);
  useLayoutEffect(() => {
    const { dof, ca, distort, grain } = chain;
    dof.cocMaterial.worldFocusDistance = fx.focus;
    dof.cocMaterial.worldFocusRange = fx.range || Math.max(1.2, fx.focus * 0.35);
    dof.bokehScale = fx.bokeh;
    ca.offset.set(fx.ca, fx.ca * 0.6);
    const u = distort.uniforms;
    u.get("aspect")!.value = w / h;
    if (fx.shock) { (u.get("swC")!.value as Vector2).set(...fx.shock.uv); u.get("swR")!.value = fx.shock.r; u.get("swA")!.value = fx.shock.amp; } else u.get("swA")!.value = 0;
    if (fx.lens) { (u.get("lC")!.value as Vector2).set(...fx.lens.uv); u.get("lS")!.value = fx.lens.strength; u.get("lSpin")!.value = fx.lens.spin; u.get("lR")!.value = fx.lens.radius; u.get("lH")!.value = fx.lens.hole ?? 0; } else u.get("lS")!.value = 0;
    grain.uniforms.get("seed")!.value = (fx.frame * 7.31) % 1000;
    grain.uniforms.get("fade")!.value = fx.fade;
    grain.uniforms.get("iris")!.value = fx.iris ?? -1;
    (grain.uniforms.get("res")!.value as Vector2).set(w, h);
  }, [chain, fx, w, h]);
  useFrame(() => chain.composer.render(1 / 60), 1);
  return null;
};
