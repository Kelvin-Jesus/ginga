// @ts-check
import { defineConfig } from "astro/config";
import react from "@astrojs/react";
import sitemap from "@astrojs/sitemap";

// SITE_URL: o endereço final (ex.: https://ginga.app). BASE_PATH: "/" na Vercel ou num domínio próprio,
// "/ginga/" no GitHub Pages de projeto.
const site = process.env.SITE_URL || "https://ginga.example";
const base = process.env.BASE_PATH || "/";

export default defineConfig({
  site,
  base,
  trailingSlash: "ignore",
  integrations: [react(), sitemap({ i18n: { defaultLocale: "pt", locales: { pt: "pt-BR", en: "en" } } })],
  build: { format: "directory" },
});
