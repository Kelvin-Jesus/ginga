# Button

Botão de ação: uma ação primária por tela, o resto secundário ou fantasma.

**O consumidor fornece** o rótulo (verbo no infinitivo: “Criar display”, “Conectar”) e, se quiser, a estrela `g-btn__star` só no primário.

- `g-btn--primary`: fundo `cobalt`, texto `on-cobalt`, halo `glow-cobalt` no hover. Uma por tela (Mac: “Criar display”/“Remover display”; tablet: “Conectar”).
- sem modificador: secundário em `surface-2`.
- `g-btn--ghost`: links de ação (“Mostrar prévia”, “Ajustes de Telas…”).
- `g-btn--danger`: “Esquecer”, “Desconectar” quando encerra uma sessão ativa. Texto `danger`, contorno `line`.
- `g-btn--pill` (44px) no tablet, para toque; `g-btn--sm` (28px) em linhas do Mac.
- Pressionar encolhe para 0.97 em `dur-tap`. Desativado: 45% de opacidade, sem hover.
- Não use mais de um primário por tela; não pinte botões de `star`.
