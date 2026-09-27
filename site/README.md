# Site do Ginga

Site estático em **Astro** + **React** (uma ilha hidratada por página), em português (`/pt/`) e inglês (`/en/`), com a 404 do buraco negro.

```sh
cd site
npm install
npm run dev        # http://localhost:4321/pt/
npm run build      # gera dist/
npm run preview    # serve dist/ (a 404 funciona aqui)
```

## Configurar antes de publicar

| O quê | Onde |
|---|---|
| Endereço do repositório (botões de download, “Ver o código”, issues) | `PUBLIC_REPO_URL` (o workflow do Pages preenche sozinho) ou `src/config.ts` |
| Domínio final (canonical, hreflang, sitemap, imagem de compartilhamento) | `SITE_URL` (o workflow usa `https://<usuário>.github.io`) |
| Pasta base | `BASE_PATH`: `/` na Vercel ou num domínio próprio; `/ginga/` no GitHub Pages de projeto |

```sh
SITE_URL=https://ginga.app PUBLIC_REPO_URL=https://github.com/Kelvin-Jesus/ginga npm run build
```

## Publicar no GitHub Pages

O workflow `.github/workflows/site.yml` já faz tudo: compila `site/` e publica a cada push em `main` que mexa no site (ou manualmente em Actions › site › Run workflow). Ele define sozinho:

- `SITE_URL` = `https://<seu-usuário>.github.io`
- `BASE_PATH` = `/<nome-do-repositório>/` (o site fica em `https://<seu-usuário>.github.io/ginga/`)
- `PUBLIC_REPO_URL` = o próprio repositório (botões de download apontam para os Releases)

Uma vez só:

1. Crie o repositório no GitHub e faça o push (`git remote add origin …` e `git push -u origin main`).
2. Em **Settings › Pages › Build and deployment**, escolha **Source: GitHub Actions**.
3. Rode o workflow **site** (ou faça um push mexendo em `site/`). O endereço aparece na execução e em Settings › Pages.

Observações:

- Repositório **privado** só publica Pages em planos pagos do GitHub; em conta grátis, deixe o repositório público.
- A `404.html` é usada pelo GitHub Pages para qualquer endereço inexistente dentro de `/ginga/`.
- **Domínio próprio** (ex.: `ginga.app`): configure em Settings › Pages › Custom domain, adicione `site/public/CNAME` com o domínio e, no workflow, troque `SITE_URL` para `https://ginga.app` e `BASE_PATH` para `/`.
- Os downloads apontam para `…/releases/latest`: publique os binários (Ginga.app zipado e o APK) como assets de um Release.

Para testar localmente com o mesmo caminho do Pages:

```sh
BASE_PATH=/ginga/ SITE_URL=https://<seu-usuário>.github.io npm run build && npm run preview
# abra http://localhost:4321/ginga/pt/
```

## Como o site é feito

- `design/*.dc.html` são os protótipos do editor de design (a fonte da verdade visual e dos textos PT/EN).
- `npm run regen` transforma os protótipos em componentes React: `tools/prod_patch.py` aplica as diferenças de produção (rotas de idioma, transição 404 → home) e `tools/dc2jsx.py` converte o template em JSX (`src/components/*.jsx`, `src/styles/*.css`). Não edite os `.jsx` à mão: edite o protótipo e rode o regen.
- `src/styles/ds-*.css` e `public/ds/bundle.js` vêm do design system Ginga (`design/ginga-design/` na raiz do repositório).
- Fontes da marca servidas pelo próprio site (WOFF2, subconjunto latino; licença SIL OFL em `public/fonts/`). Nenhum script ou fonte de terceiros, nenhum rastreamento.

## Transição 404 → home

Na 404, a página “caída” é sugada pelo buraco negro. “Voltar para a órbita” faz o caminho inverso: os pedaços saem do horizonte em espiral e se encaixam; o navegador troca para a home (com View Transition em Chrome, Edge e Safari 18.2+), e a home chega “cuspida” pelo buraco negro, com a explosão de partículas. Com movimento reduzido tudo vira troca direta.

## Som da 404

O som do buraco negro é sintetizado na hora pela Web Audio e guiado pela própria animação, sem nenhum arquivo:

- um ronco grave cresce enquanto a página treme e racha;
- cada ladrilho que se solta dá um estalo curto, no lado da tela onde está;
- um vento em espiral sobe de tom com a velocidade da órbita dos pedaços e gira entre os canais junto com eles;
- um tom grave desce conforme a página some, e cada pedaço que cruza o horizonte dá uma batidinha;
- quando o último pedaço cai, as camadas são cortadas seco e vem o “gole”.

Como tudo sai do mesmo estado da animação, o som fica em sincronia em qualquer tamanho de tela e entra no ponto certo mesmo se o áudio for liberado no meio.

- Só toca quando o navegador libera o áudio: ao clicar em “Ver de novo”, ou já na primeira vez se a pessoa interagiu com o site antes. Firefox e Zen bloqueiam para sempre um contexto de áudio criado sem gesto, por isso ele é recriado dentro do clique.
- Não toca com movimento reduzido nem com a aba em segundo plano. Sem notícias da animação por 250 ms (por exemplo, ao clicar em “Voltar para a órbita” no meio), o som para.
- Ao terminar, o contexto de áudio é suspenso, para não manter o áudio do sistema acordado.
- O código fica em `design/404.dc.html` (`sfx*`).
