import { loadFont as unbounded } from "@remotion/google-fonts/Unbounded";
import { loadFont as figtree } from "@remotion/google-fonts/Figtree";
import { loadFont as plex } from "@remotion/google-fonts/IBMPlexMono";

export const F = {
  display: unbounded("normal", { weights: ["600", "800"], subsets: ["latin"] }).fontFamily,
  sans: figtree("normal", { weights: ["400", "500", "600"], subsets: ["latin"] }).fontFamily,
  mono: plex("normal", { weights: ["400", "500"], subsets: ["latin"] }).fontFamily,
};
