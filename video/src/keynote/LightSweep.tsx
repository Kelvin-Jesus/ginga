import React, { useLayoutEffect, useMemo, useRef } from "react";
import { createPortal, useThree } from "@react-three/fiber";
import { AdditiveBlending, Color, Mesh, PerspectiveCamera, Scene, ShaderMaterial, Vector3 } from "three";

/** Varredura de luz diagonal em espaço de tela (cena de sobreposição). `p` de 0 a 1 atravessa o quadro. */
export const LightSweep: React.FC<{ overlay: Scene; p: number; color?: string; width?: number; angle?: number; intensity?: number }> = ({ overlay, p, color = "#6F82FF", width = 0.06, angle = -0.6, intensity = 2.2 }) => {
  const { camera, size } = useThree();
  const ref = useRef<Mesh>(null);
  const mat = useMemo(() => new ShaderMaterial({
    transparent: true, depthTest: false, depthWrite: false, blending: AdditiveBlending, toneMapped: false,
    uniforms: { uP: { value: 0 }, uW: { value: width }, uA: { value: angle }, uC: { value: new Color(color) }, uI: { value: intensity }, uAspect: { value: 16 / 9 } },
    vertexShader: "varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }",
    fragmentShader: `varying vec2 vUv; uniform float uP, uW, uA, uI, uAspect; uniform vec3 uC;
      void main(){ vec2 q = (vUv - 0.5) * vec2(uAspect, 1.0); vec2 n = vec2(cos(uA), sin(uA));
        float s = dot(q, n) - mix(-1.3, 1.3, uP);
        float band = exp(-pow(s / uW, 2.0)) + 0.35 * exp(-pow(s / (uW * 5.0), 2.0));
        gl_FragColor = vec4(uC * band * uI, 1.0); }`,
  }), [color, width, angle, intensity]);
  mat.uniforms.uP.value = p;
  mat.uniforms.uAspect.value = size.width / size.height;
  useLayoutEffect(() => {
    const cam = camera as PerspectiveCamera, m = ref.current, d = 2;
    if (!m) return;
    const vh = 2 * d * Math.tan((cam.fov * Math.PI) / 360);
    const f = new Vector3(); camera.getWorldDirection(f);
    m.position.copy(camera.position).addScaledVector(f, d); m.quaternion.copy(camera.quaternion);
    m.scale.set(vh * cam.aspect, vh, 1); m.updateMatrixWorld();
  });
  if (p <= 0 || p >= 1) return null;
  return createPortal(<mesh ref={ref} material={mat} renderOrder={30}><planeGeometry args={[1, 1]} /></mesh>, overlay);
};
