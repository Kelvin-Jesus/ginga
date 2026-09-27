import { Composition } from "remotion";
import { SceneComet } from "./scenes/SceneComet";
import type { Lang } from "./i18n";
import "./fonts";

const LANGS: Lang[] = ["pt", "en"];

export const Root: React.FC = () => (
  <>
    {LANGS.map((lang) => (
      <Composition key={lang} id={`CometPreview-${lang}`} component={SceneComet} durationInFrames={180} fps={60} width={1920} height={1080} defaultProps={{ lang }} />
    ))}
  </>
);
