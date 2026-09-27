# Sons do GingaKeynote (espaço reservado)

Os arquivos desta pasta são sintetizados por `npm run sfx` (sons originais, sem licença de terceiros). Para usar sons licenciados, substitua os arquivos mantendo os nomes. O som está ligado por padrão (`sfx: true`); desligue com `--props='{"lang":"pt","sfx":false}'`.


| Arquivo | Onde (quadro a 60 fps) | O que é |
|---|---|---|
| `riser.wav` | 0–90 | riser grave |
| `hit-soft.wav` | 30, 130, 200, 350, 400, 510 | hits suaves nos marcadores |
| `whoosh.wav` | 90, 196, 308 | movimentos de câmera |
| `whoosh-long.wav` | 420–500 | espiral; é cortado seco no quadro 500 |
| `chord.wav` | 502–600 | acorde resolvido sob o logo |

Silêncio total no corte do quadro 500 (nenhuma faixa atravessa esse quadro). A lista está em `src/keynote/GingaKeynote.tsx` (`SFX`).

## Camadas do Kenney (CC0)

`kenney/` tem sons do pacote [Sci-fi Sounds](https://kenney.nl/assets/sci-fi-sounds) de Kenney (www.kenney.nl), licença Creative Commons Zero (CC0, domínio público; crédito opcional). Convertidos de OGG para WAV 48 kHz. Licença original em `kenney/License.txt`.
