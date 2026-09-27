import React, { useMemo } from "react";
import { Billboard } from "@react-three/drei";
import { AdditiveBlending, Color, ShaderMaterial } from "three";

/** Faixa anamórfica horizontal (cobalto) + núcleo, sempre de frente para a câmera. Intensidade > 1 alimenta o bloom. */
export const AnamorphicFlare: React.FC<{ position: [number, number, number]; intensity: number; length?: number; core?: string }> = ({ position, intensity, length = 30, core = "#FFC43D" }) => {
  const mat = useMemo(() => new ShaderMaterial({
    transparent: true, depthWrite: false, depthTest: false, blending: AdditiveBlending, toneMapped: false,
    uniforms: { uI: { value: 0 }, uStreak: { value: new Color("#6F82FF") }, uCore: { value: new Color(core) } },
    vertexShader: "varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }",
    fragmentShader: `varying vec2 vUv; uniform float uI; uniform vec3 uStreak; uniform vec3 uCore;
      void main(){ vec2 p = vUv - 0.5; float ax = abs(p.x);
        float streak = exp(-pow(p.y * 90.0, 2.0)) * pow(1.0 - clamp(ax * 2.0, 0.0, 1.0), 2.2);
        float halo = exp(-pow(p.y * 22.0, 2.0)) * pow(1.0 - clamp(ax * 2.0, 0.0, 1.0), 6.0) * 0.25;
        float core = exp(-dot(p * vec2(length(vec2(${length.toFixed(1)}, 1.0)) , 1.0), p * vec2(length(vec2(${length.toFixed(1)}, 1.0)), 1.0)) * 900.0);
        vec3 c = uStreak * (streak + halo) + uCore * core * 1.5;
        gl_FragColor = vec4(c * uI, 1.0); }`,
  }), [length, core]);
  mat.uniforms.uI.value = intensity;
  if (intensity <= 0.001) return null;
  return (
    <Billboard position={position}>
      <mesh material={mat} renderOrder={20}><planeGeometry args={[length, 1.2]} /></mesh>
    </Billboard>
  );
};
