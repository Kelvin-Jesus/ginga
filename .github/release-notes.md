## Instalação / Installation

**Mac** (`Ginga-*-macOS.zip`, Apple Silicon e Intel, macOS 14+)

1. Descompacte e arraste o **Ginga** para **Aplicativos**.
2. O Ginga não é notarizado pela Apple, então na primeira vez o macOS bloqueia: abra **Ajustes do Sistema › Privacidade e Segurança** e clique em **Abrir Mesmo Assim** (ou, no Terminal: `xattr -dr com.apple.quarantine /Applications/Ginga.app`).
3. Conceda **Gravação de Tela** e **Acessibilidade** quando pedido (para o modo sem roteador, também Bluetooth e Localização). As permissões continuam valendo nas próximas versões.

Intel: precisa de um Mac com codificador HEVC por hardware (2017 ou mais novo); ainda não testado em hardware Intel.

**Tablet** (`Ginga-*-android.apk`, Android 12+)

Abra o APK no tablet e permita "instalar apps desconhecidos" para o navegador ou gerenciador de arquivos. Se você tinha uma versão de desenvolvimento instalada, desinstale-a antes (a assinatura é outra).

Confira os arquivos com `shasum -a 256 -c SHA256SUMS`.

---

**Mac:** unzip, move **Ginga** to Applications, then allow it once in System Settings › Privacy & Security › Open Anyway (the app is not notarized). Grant Screen Recording and Accessibility when asked. Intel Macs need a hardware HEVC encoder (2017 or newer) and are untested so far. **Tablet:** install the APK (allow unknown apps); uninstall any development build first.
