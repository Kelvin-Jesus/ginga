## Downloads

| | Arquivo | Requisitos |
|---|---|---|
| **Mac** | [Ginga-{{VERSION}}-macOS.dmg](https://github.com/Kelvin-Jesus/ginga/releases/download/{{TAG}}/Ginga-{{VERSION}}-macOS.dmg) | macOS 14 ou mais novo, Apple Silicon ou Intel |
| **Tablet** | [Ginga-{{VERSION}}-android.apk](https://github.com/Kelvin-Jesus/ginga/releases/download/{{TAG}}/Ginga-{{VERSION}}-android.apk) | Galaxy Tab com Android 12 ou mais novo |

### Instalar no Mac

1. Abra o `.dmg` e arraste o **Ginga** para **Aplicativos**.
2. Na primeira vez, o macOS avisa que não pode verificar o desenvolvedor (o Ginga ainda não é notarizado pela Apple). Abra **Ajustes do Sistema › Privacidade e Segurança** e clique em **Abrir Mesmo Assim**.
3. Permita **Gravação de Tela** e **Acessibilidade** quando o Ginga pedir. No modo sem roteador ele pede também Bluetooth e Localização. As permissões continuam valendo nas próximas versões.

### Instalar no tablet

Baixe o APK no tablet, abra e permita instalar apps desta fonte. Se você tinha uma versão de desenvolvimento do Ginga, desinstale antes.

<details>
<summary>English</summary>

**Mac:** open the `.dmg` and drag **Ginga** to Applications. The first time, macOS can't verify the developer (Ginga isn't notarized yet): allow it in System Settings › Privacy & Security › Open Anyway, then grant Screen Recording and Accessibility when asked. **Tablet:** download the APK on the tablet, open it and allow installs from that source; uninstall any development build first.

</details>

Para conferir os arquivos: `shasum -a 256 -c SHA256SUMS`.
