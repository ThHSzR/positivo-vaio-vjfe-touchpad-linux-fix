#!/usr/bin/env bash
set -euo pipefail

DEVICE_NAME='SYNA3602:00 0911:5288 Touchpad'
PRESET_NAME='Corrigir botoes fisicos'
MANAGED_BEGIN='# BEGIN positivo-vaio-vjfe-touchpad-linux-fix'
MANAGED_END='# END positivo-vaio-vjfe-touchpad-linux-fix'
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
FORCE=false

if [[ ${1:-} == '--force' ]]; then
    FORCE=true
elif [[ $# -gt 0 ]]; then
    echo "Uso: $0 [--force]" >&2
    exit 2
fi

if [[ $EUID -eq 0 ]]; then
    echo 'Execute como usuário normal; o script solicitará sudo quando necessário.' >&2
    exit 1
fi

for command in sudo python3 gsettings awk grep; do
    command -v "$command" >/dev/null || {
        echo "Comando obrigatório ausente: $command" >&2
        exit 1
    }
done

dmi_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)
dmi_product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)

if [[ $dmi_vendor != 'Positivo Bahia - VAIO' || $dmi_product != VJFE* ]]; then
    if [[ $FORCE != true ]]; then
        echo "Modelo não reconhecido: fabricante='$dmi_vendor', produto='$dmi_product'." >&2
        echo 'Use --force somente após confirmar o mesmo hardware com ./diagnose.sh.' >&2
        exit 1
    fi
    echo 'Aviso: validação de modelo ignorada por --force.' >&2
fi

if ! grep -Fq "N: Name=\"$DEVICE_NAME\"" /proc/bus/input/devices; then
    echo "Touchpad não encontrado: $DEVICE_NAME" >&2
    exit 1
fi

echo 'Instalando dependências do Ubuntu...'
if ! dpkg-query -W -f='${Status}' input-remapper 2>/dev/null | grep -Fq 'install ok installed'; then
    sudo apt-get update
    sudo apt-get install -y input-remapper
else
    echo 'input-remapper já está instalado.'
fi
sudo systemctl enable --now input-remapper-daemon.service

stamp=$(date +%Y%m%d-%H%M%S)
for invalid_file in \
    /etc/libinput/local-overrides.quirks \
    /usr/share/libinput/local-overrides.quirks; do
    if sudo test -f "$invalid_file" && sudo grep -Fq 'AttrClickPad=' "$invalid_file"; then
        disabled="${invalid_file}.disabled-${stamp}"
        echo "Desativando override incompatível: $invalid_file"
        sudo mv "$invalid_file" "$disabled"
    fi
done

sudo mkdir -p /etc/libinput
tmp_quirks=$(mktemp)
trap 'rm -f "$tmp_quirks"' EXIT

if sudo test -f /etc/libinput/local-overrides.quirks; then
    sudo awk -v begin="$MANAGED_BEGIN" -v end="$MANAGED_END" '
        $0 == begin { managed = 1; next }
        $0 == end { managed = 0; next }
        $0 == "[Positivo VAIO VJFE physical touchpad buttons]" {
            legacy = 1
            next
        }
        legacy && /^\[/ { legacy = 0 }
        !managed && !legacy { print }
    ' /etc/libinput/local-overrides.quirks > "$tmp_quirks"
fi

{
    printf '\n%s\n' "$MANAGED_BEGIN"
    cat "$SCRIPT_DIR/config/libinput-local-overrides.quirks"
    printf '%s\n' "$MANAGED_END"
} >> "$tmp_quirks"

sudo install -o root -g root -m 0644 "$tmp_quirks" /etc/libinput/local-overrides.quirks

event_node=$(awk -v name="$DEVICE_NAME" '
    BEGIN { RS = "" }
    index($0, "N: Name=\"" name "\"") {
        for (i = 1; i <= NF; i++)
            if ($i ~ /^event[0-9]+$/) event = $i
    }
    END { if (event) print "/dev/input/" event }
' /proc/bus/input/devices)

if [[ -z $event_node ]]; then
    echo 'Não foi possível localizar o event node do touchpad.' >&2
    exit 1
fi

echo 'Validando quirks do libinput...'
quirks_output=$(libinput quirks list "$event_node")
grep -Fq 'AttrInputProp=-INPUT_PROP_BUTTONPAD;' <<< "$quirks_output" || {
    echo 'A quirk INPUT_PROP_BUTTONPAD não foi aplicada.' >&2
    exit 1
}

config_dir=$(python3 - <<'PY'
from inputremapper.configs.paths import CONFIG_PATH
print(CONFIG_PATH)
PY
)
preset_dir="$config_dir/presets/SYNA3602_00 0911_5288 Touchpad"
mkdir -p "$preset_dir"
install -m 0644 "$SCRIPT_DIR/config/physical-buttons.json" "$preset_dir/$PRESET_NAME.json"

CONFIG_DIR="$config_dir" DEVICE_NAME="$DEVICE_NAME" PRESET_NAME="$PRESET_NAME" python3 - <<'PY'
import json
import os
import tempfile
from inputremapper.logger import VERSION

config_dir = os.environ['CONFIG_DIR']
device_name = os.environ['DEVICE_NAME']
preset_name = os.environ['PRESET_NAME']
config_path = os.path.join(config_dir, 'config.json')
os.makedirs(config_dir, exist_ok=True)

try:
    with open(config_path, encoding='utf-8') as stream:
        config = json.load(stream)
except FileNotFoundError:
    config = {}

config['version'] = VERSION
config.setdefault('autoload', {})[device_name] = preset_name

fd, temporary = tempfile.mkstemp(dir=config_dir, prefix='.config-', text=True)
with os.fdopen(fd, 'w', encoding='utf-8') as stream:
    json.dump(config, stream, indent=4)
    stream.write('\n')
os.replace(temporary, config_path)
PY

gsettings set org.gnome.desktop.peripherals.touchpad left-handed 'right'

CONFIG_DIR="$config_dir" DEVICE_NAME="$DEVICE_NAME" PRESET_NAME="$PRESET_NAME" python3 - <<'PY'
import os
from inputremapper.daemon import Daemon

service = Daemon.connect(fallback=False)
service.set_config_dir(os.environ['CONFIG_DIR'])
service.start_injecting(os.environ['DEVICE_NAME'], os.environ['PRESET_NAME'])
PY

sleep 2
if ! grep -Fq 'N: Name="input-remapper mouse"' /proc/bus/input/devices; then
    echo 'O dispositivo virtual não apareceu; consulte: journalctl -u input-remapper-daemon' >&2
    exit 1
fi

echo
echo 'Correção aplicada.'
echo "Quirk:  /etc/libinput/local-overrides.quirks"
echo "Preset: $preset_dir/$PRESET_NAME.json"
echo 'Teste os botões esquerdo e direito.'
