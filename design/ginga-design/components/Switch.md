# Switch

Toggle liga/desliga para opções que valem na hora (sem “Aplicar”).

**O consumidor fornece** um `<input type="checkbox" role="switch">` dentro de `label.g-switch`, seguido de `g-switch__track` e `g-switch__thumb`; o rótulo fica na linha (`g-row__label`), não no switch.

- Ligado: trilho `cobalt`, polegar branco desliza com `ease-ginga` (passa um pouco e volta).
- Ao ligar, chame `Ginga.spark(switchEl)`: sete pontinhos `star` saem do centro. Só ao ligar, nunca ao desligar.
- Pressionar alarga o polegar (feedback de toque).
- Foco: anel `cobalt` de 2px. Com movimento reduzido não há faísca.
- Não use para ações que demoram (criar display): isso é botão, com status.
