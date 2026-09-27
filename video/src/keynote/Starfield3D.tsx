import React, { useMemo } from "react";
import { random } from "remotion";
import { BufferAttribute, BufferGeometry, Color } from "three";

/** 6000 estrelas quadradas de 4 px (sprites sem atenuação), cores da paleta, algumas acima de 1 para o bloom. */
export const Starfield3D: React.FC<{ count?: number; px: number; opacity?: number }> = ({ count = 6000, px, opacity = 1 }) => {
  const geo = useMemo(() => {
    const g = new BufferGeometry(), pos = new Float32Array(count * 3), col = new Float32Array(count * 3);
    const pal = ["#F2F3F8", "#F2F3F8", "#6F82FF", "#2E47F5", "#FFC43D"].map((c) => new Color(c));
    for (let i = 0; i < count; i++) {
      pos[i * 3] = (random(`sx${i}`) - 0.5) * 90;
      pos[i * 3 + 1] = (random(`sy${i}`) - 0.5) * 54;
      pos[i * 3 + 2] = -90 + random(`sz${i}`) * 104;
      const k = random(`sc${i}`), c = pal[k < 0.6 ? 0 : k < 0.75 ? 1 : k < 0.9 ? 2 : k < 0.985 ? 3 : 4];
      const b = (0.08 + 0.55 * Math.pow(random(`sb${i}`), 3)) * (random(`sh${i}`) > 0.99 ? 4 : 1);
      col[i * 3] = c.r * b; col[i * 3 + 1] = c.g * b; col[i * 3 + 2] = c.b * b;
    }
    g.setAttribute("position", new BufferAttribute(pos, 3));
    g.setAttribute("color", new BufferAttribute(col, 3));
    return g;
  }, [count]);
  return (
    <points geometry={geo}>
      <pointsMaterial size={px} sizeAttenuation={false} vertexColors toneMapped={false} transparent opacity={opacity} depthWrite={false} />
    </points>
  );
};
