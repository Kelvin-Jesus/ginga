import { Config } from "@remotion/cli/config";
Config.setEntryPoint("src/index.ts");
Config.setVideoImageFormat("jpeg");
// WebGL (Three.js, pós-produção) no render sem interface
Config.setChromiumOpenGlRenderer("angle");
