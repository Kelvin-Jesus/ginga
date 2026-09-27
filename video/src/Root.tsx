import React from "react";
import { Composition } from "remotion";
import { World, type WorldProps } from "./World";
import { GingaLoop } from "./Loop";
import { GingaTeaser } from "./Teaser";
import { GingaKeynote, KeynoteSound } from "./keynote/GingaKeynote";
import { HERO, HERO_LAYOUT, VERTICAL, VERTICAL_LAYOUT } from "./timeline";
import type { Lang } from "./i18n";
import "./fonts";

const LANGS: Lang[] = ["pt", "en"];
export const REPO_URL = "github.com/Kelvin-Jesus/ginga";

type P = { lang: Lang; repoUrl: string };
const Hero: React.FC<P> = (p) => <World {...p} tl={HERO} L={HERO_LAYOUT} />;
const Vertical: React.FC<P> = (p) => <World {...p} tl={VERTICAL} L={VERTICAL_LAYOUT} />;
const Loop: React.FC<P> = () => <GingaLoop />;
export type { WorldProps };

export const Root: React.FC = () => (
  <>
    <Composition id="GingaKeynoteAudio" component={KeynoteSound} durationInFrames={600} fps={60} width={320} height={180} />
    {LANGS.map((lang) => (
      <React.Fragment key={lang}>
        <Composition id={`GingaHero-${lang}`} component={Hero} durationInFrames={30 * 60} fps={60} width={1920} height={1080} defaultProps={{ lang, repoUrl: REPO_URL }} />
        <Composition id={`GingaVertical-${lang}`} component={Vertical} durationInFrames={20 * 60} fps={60} width={1080} height={1920} defaultProps={{ lang, repoUrl: REPO_URL }} />
        <Composition id={`GingaLoop-${lang}`} component={Loop} durationInFrames={8 * 30} fps={30} width={1600} height={1000} defaultProps={{ lang, repoUrl: REPO_URL }} />
        <Composition id={`GingaTeaser-${lang}`} component={GingaTeaser} durationInFrames={360} fps={60} width={3840} height={2160} defaultProps={{ lang }} />
        <Composition id={`GingaKeynote-${lang}`} component={GingaKeynote} durationInFrames={600} fps={60} width={3840} height={2160} defaultProps={{ lang, sfx: true }} />
      </React.Fragment>
    ))}
  </>
);
