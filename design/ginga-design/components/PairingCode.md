# PairingCode

Os seis dígitos de pareamento, iguais no Mac e no tablet, surgindo um a um como estrelas.

**O consumidor fornece** os dígitos: `el.innerHTML = Ginga.pairingCode("482913")`.

- Sempre dois grupos de três (“482 913”), estilo `code-digits` em `ink`.
- Entrada escalonada de 60ms por dígito com `ease-ginga`; com movimento reduzido aparecem direto.
- Leitores de tela recebem “Código 4 8 2 9 1 3” pelo `aria-label`.
- Mostre ao lado a pergunta (`headline`) e os botões “Parear” (primário) / “Não parear”.
