# StatusOrbit

Pílula de estado da conexão: um “planeta” colorido com uma órbita animada, e o estado em palavras.

**O consumidor fornece** o estado (`g-status--searching|pairing|connected|paused|error`, nenhum = desligado) e o texto.

- Procurando: arco `cobalt` girando (`ease-orbit`). Aguardando código e Conectado: pulso que se expande. Pausado e Erro: parados.
- Cor nunca sozinha: o texto sempre diz o estado. O texto fica em `ink` (os tons de estado no claro não chegam a 4.5:1 como texto).
- Specs dentro da pílula em `mono` (“60 Hz”, “2560×1600”).
- Um só StatusOrbit por tela, no topo (Mac: cabeçalho da janela e barra de menus; tablet: topo da home).
