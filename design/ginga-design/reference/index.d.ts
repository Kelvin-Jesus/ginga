/**
 * Ginga — componentes em CSS (bundle.css, classes g-*) + utilitários em JS (window.Ginga).
 * Nenhum framework: nos apps nativos (SwiftUI / Android Views) estes arquivos são a
 * referência visual; na web (site, demo) são usados direto.
 */

/** Button — `<button class="g-btn g-btn--primary">`. */
export interface ButtonClasses {
  /** Variante: nenhuma (secundário), `g-btn--primary`, `g-btn--ghost`, `g-btn--danger`. */
  variant?: "g-btn--primary" | "g-btn--ghost" | "g-btn--danger";
  /** Tamanho: `g-btn--sm` (28px, Mac compacto) ou `g-btn--pill` (44px, tablet). */
  size?: "g-btn--sm" | "g-btn--pill";
}

/** Switch — `<label class="g-switch"><input type="checkbox" role="switch"><span class="g-switch__track"></span><span class="g-switch__thumb"></span></label>`. */
export interface SwitchMarkup { checked: boolean; disabled?: boolean; }

/** StatusOrbit — `<span class="g-status g-status--connected"><span class="g-status__orb"></span>Conectado</span>`. */
export type ConnectionState = "off" | "searching" | "pairing" | "connected" | "paused" | "error";

/** Ginga.starfield(canvas) — céu estrelado; pausa fora da tela. */
export declare function starfield(canvas: HTMLCanvasElement, opts?: { density?: number; drift?: number; colors?: string[] }): { start(): void; stop(): void; resize(): void };

/** Ginga.spark(el) — faísca de estrela no centro do elemento (ex.: toggle ligado). */
export declare function spark(el: Element, count?: number): void;

/** Ginga.segmented(root, onChange) — liga um `.g-seg` com `.g-seg__thumb` e botões `aria-pressed`. */
export declare function segmented(root: Element, onChange?: (value: string) => void): void;

/** Ginga.pairingCode("482913") — HTML do código em dois grupos com entrada animada. */
export declare function pairingCode(digits: string): string;

/** true quando o sistema pede movimento reduzido: sem órbitas, sem cometa, sem faíscas. */
export declare const reducedMotion: boolean;
