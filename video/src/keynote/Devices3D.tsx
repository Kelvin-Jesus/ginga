import React, { forwardRef } from "react";
import { RoundedBox } from "@react-three/drei";
import type { Group, Texture } from "three";
import type { ThreeElements } from "@react-three/fiber";
import { C } from "../theme";

/* Aparelhos genéricos (sem logos nem formas de marca): caixas arredondadas de alumínio + tela de vidro. */

export const TAB3 = { w: 2.6, h: 1.7, d: 0.07, sw: 2.46, sh: 1.6 };
export const LAP3 = { w: 3.0, h: 1.95, d: 0.05, sw: 2.86, sh: 1.86, open: 1.72 /* rad (~98°) */ };

const Aluminium: React.FC = () => <meshPhysicalMaterial color={C.nevoa} metalness={1} roughness={0.35} clearcoat={0.3} envMapIntensity={1.4} />;

/** Vidro: clearcoat 1 sobre a interface emissiva, para o reflexo passar por cima. */
const Glass: React.FC<{ map: Texture; glow?: number }> = ({ map, glow = 1 }) => (
  <meshPhysicalMaterial map={map} emissiveMap={map} emissive="#ffffff" emissiveIntensity={glow} color="#000000" roughness={0.08} metalness={0} clearcoat={1} clearcoatRoughness={0.04} envMapIntensity={0.9} />
);

/** Ponto na tela do tablet em coordenadas locais do grupo (u, v de 0 a 1, v de cima para baixo). */
export const tabletScreenLocal = (u: number, v: number): [number, number, number] => [(u - 0.5) * TAB3.sw, (0.5 - v) * TAB3.sh, TAB3.d / 2 + 0.002];

export const Tablet3D = forwardRef<Group, { screen: Texture; glow?: number } & ThreeElements["group"]>(({ screen, glow, children, ...g }, ref) => (
  <group ref={ref} {...g}>
    <RoundedBox args={[TAB3.w, TAB3.h, TAB3.d]} radius={0.1} smoothness={6}><Aluminium /></RoundedBox>
    {/* moldura preta sob o vidro */}
    <mesh position={[0, 0, TAB3.d / 2 + 0.0005]}><planeGeometry args={[TAB3.w - 0.06, TAB3.h - 0.06]} /><meshStandardMaterial color="#05060d" roughness={0.3} /></mesh>
    <mesh position={[0, 0, TAB3.d / 2 + 0.001]}><planeGeometry args={[TAB3.sw, TAB3.sh]} /><Glass map={screen} glow={glow} /></mesh>
    {children}
  </group>
));

export const Laptop3D = forwardRef<Group, { screen: Texture; glow?: number } & ThreeElements["group"]>(({ screen, glow, ...g }, ref) => (
  <group ref={ref} {...g}>
    {/* base */}
    <RoundedBox args={[LAP3.w + 0.12, 0.07, 2.05]} radius={0.03} smoothness={4} position={[0, -0.035, 1.02]}><Aluminium /></RoundedBox>
    {/* tampa, articulada na borda de trás da base */}
    <group rotation={[-(LAP3.open - Math.PI / 2), 0, 0]}>
      <RoundedBox args={[LAP3.w, LAP3.h, LAP3.d]} radius={0.06} smoothness={5} position={[0, LAP3.h / 2, -LAP3.d / 2]}><Aluminium /></RoundedBox>
      <mesh position={[0, LAP3.h / 2, 0.0006]}><planeGeometry args={[LAP3.w - 0.04, LAP3.h - 0.04]} /><meshStandardMaterial color="#05060d" roughness={0.3} /></mesh>
      <mesh position={[0, LAP3.h / 2 + 0.01, 0.0012]}><planeGeometry args={[LAP3.sw, LAP3.sh]} /><Glass map={screen} glow={glow} /></mesh>
    </group>
  </group>
));
