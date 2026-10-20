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

O instalador verifica o modelo e o nome do touchpad antes de alterar o sistema.
Para testar em outro notebook, use o modo forçado:

```bash
./install.sh --force
```

Se o touchpad original não existir, esse modo procura outro dispositivo físico
com `touchpad` no nome. Quando houver mais de um candidato, ou o dispositivo
usar outro tipo de nome, informe o nome exato:

```bash
grep '^N: Name=' /proc/bus/input/devices
./install.sh --force --device-name 'NOME EXATO DO TOUCHPAD'
```

O modo forçado gera a quirk e o preset para o nome detectado. Use-o somente se
o diagnóstico confirmar que os botões enviam os mesmos códigos deslocados.

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

Por padrão, esta correção é restrita ao `SYNA3602:00 0911:5288` em modelos
Positivo VAIO VJFE. O modo `--force` amplia esse escopo de forma intencional;
outros touchpads podem emitir códigos diferentes, portanto confirme antes que
os botões físicos enviam 273 e 274.

## Licença

MIT — veja [LICENSE](LICENSE).
