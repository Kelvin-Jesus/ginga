# SettingsGroup

Grupo de linhas em cartão: a unidade de toda tela de ajustes, no Mac e no tablet.

**O consumidor fornece** um título curto (`g-group-title`, fora do cartão), as linhas (`g-row`) e, se preciso, uma ajuda (`g-help`) abaixo.

- Cartão `surface` com `radius-lg` e `shadow-card` sobre `bg`; divisórias `line` recuadas `space-4`.
- Linha: ícone opcional (`g-row__icon`, 28px, `cobalt` sobre `cobalt-soft`), rótulo `body`, subtítulo `caption` em `ink-muted`, e à direita um valor (`g-row__value`, números em `mono`), um Switch, um Segmented ou um Button `--sm`.
- Altura mínima 48px; no tablet use linhas de 56px (toque).
- Máximo de 6 linhas por grupo; mais que isso, divida.
- Ordem das seções no Mac: Status → Tablets → Display → Captura → Energia → Diagnóstico (este recolhido).
