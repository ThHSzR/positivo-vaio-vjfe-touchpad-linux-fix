# Positivo VAIO VJFE touchpad fix for Linux

Correção reproduzível para os botões físicos do touchpad `SYNA3602:00 0911:5288`
em notebooks Positivo VAIO da família VJFE, testada no Ubuntu 24.04 com GNOME
Wayland.

## Sintomas

- O cursor, gestos e toque funcionam, mas os botões físicos não.
- O kernel detecta os botões, porém anuncia `BTN_RIGHT` e `BTN_MIDDLE` no lugar
  de `BTN_LEFT` e `BTN_RIGHT`.
- Depois de uma correção parcial, o botão esquerdo funciona e o direito executa
  a ação do botão do meio/rolagem.
- O `libinput` pode exibir `clickpad advertising right button`.
- Overrides antigos com `AttrClickPad=0` fazem o `libinput` rejeitar todo o
  banco de quirks.

## Hardware identificado

```text
Fabricante DMI: Positivo Bahia - VAIO
Produto DMI:    VJFE...
Touchpad:       SYNA3602:00 0911:5288 Touchpad
Barramento:     I2C HID
```

## Instalação

```bash
git clone https://github.com/ThHSzR/positivo-vaio-vjfe-touchpad-linux-fix.git
cd positivo-vaio-vjfe-touchpad-linux-fix
./install.sh
```

O instalador verifica o modelo antes de alterar o sistema. Para testar em outro
notebook que use exatamente o mesmo touchpad:

```bash
./install.sh --force
```

## O que a correção faz

1. Instala o `input-remapper` fornecido pelo Ubuntu.
2. Remove a classificação incorreta de clickpad com uma quirk específica por
   nome e DMI.
3. Remapeia somente este touchpad:
   - código 273 (`BTN_RIGHT`) → `BTN_LEFT`;
   - código 274 (`BTN_MIDDLE`) → `BTN_RIGHT`.
4. Mantém movimento, toque, rolagem com dois dedos e gestos.
5. Não altera mouses USB/Bluetooth.
6. Ativa o preset automaticamente nas próximas sessões.

Arquivos existentes são preservados sempre que possível. Overrides inválidos
com `AttrClickPad` são renomeados com data e sufixo `.disabled-*`.

## Diagnóstico

```bash
./diagnose.sh
```

O relatório não modifica o sistema e não coleta dados fora da máquina.

## Desinstalação

```bash
./uninstall.sh
```

Para também remover os pacotes instalados:

```bash
./uninstall.sh --remove-packages
```

## Detalhes técnicos

Consulte [docs/technical-details.md](docs/technical-details.md).

## Escopo

Esta correção é intencionalmente restrita ao `SYNA3602:00 0911:5288` em
modelos Positivo VAIO VJFE. Outros computadores podem usar o mesmo ID com um
descritor HID diferente; use `--force` apenas se o diagnóstico mostrar os
mesmos códigos deslocados.

## Licença

MIT — veja [LICENSE](LICENSE).
