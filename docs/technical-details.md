# Detalhes técnicos

## Causa observada

O dispositivo `SYNA3602:00 0911:5288 Touchpad` anuncia estas capacidades ao
kernel:

```text
BTN_LEFT    (272): ausente
BTN_RIGHT   (273): presente
BTN_MIDDLE  (274): presente
```

Nos notebooks afetados, os dois botões físicos correspondem aos códigos 273 e
274. Portanto, o segundo botão é interpretado como botão do meio.

O dispositivo também anuncia `INPUT_PROP_BUTTONPAD`, apesar de possuir botões
físicos separados. A quirk incluída remove essa propriedade para o modelo DMI
afetado e mantém `BTN_RIGHT` habilitado.

## Por que `AttrClickPad=0` não funciona

`AttrClickPad` não é uma chave válida no libinput 1.25. Um erro de sintaxe em
qualquer arquivo de quirks faz o libinput abandonar todas as quirks, o que pode
piorar o comportamento do touchpad.

A propriedade suportada para corrigir a classificação é:

```ini
AttrInputProp=-INPUT_PROP_BUTTONPAD
```

## Por que ainda é necessário remapear

As quirks do libinput podem habilitar ou desabilitar códigos anunciados, mas não
traduzem um evento recebido em outro código. O `input-remapper` captura somente
este dispositivo, preserva os eventos não mapeados e emite os dois cliques com
os códigos corretos por `uinput`.

## Persistência

O preset é registrado em `~/.config/input-remapper-2/config.json`. O serviço do
`input-remapper` é iniciado pelo systemd, e o autoload da sessão aplica o preset
quando o usuário entra no ambiente gráfico.

## Referências

- [libinput: Device quirks](https://wayland.freedesktop.org/libinput/doc/1.25.0/device-quirks.html)
- [libinput: Clickpads with a fake right button](https://wayland.freedesktop.org/libinput/doc/1.25.0/clickpad-with-right-button.html)
- [Linux kernel input event codes](https://www.kernel.org/doc/html/latest/input/event-codes.html)
- [input-remapper](https://github.com/sezanzeb/input-remapper)
