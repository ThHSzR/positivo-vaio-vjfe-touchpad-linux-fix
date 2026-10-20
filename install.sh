#!/usr/bin/env bash
set -euo pipefail

DEFAULT_DEVICE_NAME='SYNA3602:00 0911:5288 Touchpad'
DEVICE_NAME=$DEFAULT_DEVICE_NAME
PRESET_NAME='Corrigir botoes fisicos'
MANAGED_BEGIN='# BEGIN positivo-vaio-vjfe-touchpad-linux-fix'
MANAGED_END='# END positivo-vaio-vjfe-touchpad-linux-fix'
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
INPUT_DEVICES_FILE=${INPUT_DEVICES_FILE:-/proc/bus/input/devices}
FORCE=false
DEVICE_NAME_EXPLICIT=false

usage() {
    cat <<EOF
Uso: $0 [--force] [--device-name NOME]

  --force              ignora a validação do modelo e, se necessário,
                       tenta detectar outro touchpad pelo nome
  --device-name NOME   usa exatamente este dispositivo (implica --force)
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --device-name)
            if [[ $# -lt 2 || -z ${2:-} ]]; then
                echo 'Informe um nome depois de --device-name.' >&2
                usage >&2
                exit 2
            fi
            DEVICE_NAME=$2
            DEVICE_NAME_EXPLICIT=true
            FORCE=true
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Opção desconhecida: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ $EUID -eq 0 ]]; then
    echo 'Execute como usuário normal; o script solicitará sudo quando necessário.' >&2
    exit 1
fi

for command in sudo python3 gsettings awk grep sort libinput systemctl; do
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

device_exists() {
    grep -Fq "N: Name=\"$1\"" "$INPUT_DEVICES_FILE"
}

list_input_names() {
    awk -F'"' '/^N: Name="/ { print "  - " $2 }' "$INPUT_DEVICES_FILE"
}

if ! device_exists "$DEVICE_NAME"; then
    if [[ $DEVICE_NAME_EXPLICIT == true ]]; then
        echo "Dispositivo informado não encontrado: $DEVICE_NAME" >&2
        echo 'Dispositivos de entrada disponíveis:' >&2
        list_input_names >&2
        exit 1
    fi

    if [[ $FORCE != true ]]; then
        echo "Touchpad esperado não encontrado: $DEVICE_NAME" >&2
        echo 'Use --force para detectar outro touchpad ou --device-name para informar o nome.' >&2
        exit 1
    fi

    mapfile -t touchpad_candidates < <(
        awk -F'"' '
            /^N: Name="/ {
                name = $2
                lower = tolower(name)
                if (lower ~ /touchpad/ && lower !~ /^input-remapper /)
                    print name
            }
        ' "$INPUT_DEVICES_FILE" | sort -u
    )

    if [[ ${#touchpad_candidates[@]} -eq 1 ]]; then
        DEVICE_NAME=${touchpad_candidates[0]}
        echo "Aviso: usando o touchpad detectado por --force: $DEVICE_NAME" >&2
    elif [[ ${#touchpad_candidates[@]} -eq 0 ]]; then
        echo 'Nenhum dispositivo com "touchpad" no nome foi encontrado.' >&2
        echo 'Execute novamente informando um dos nomes abaixo:' >&2
        echo "  $0 --force --device-name 'NOME EXATO'" >&2
        list_input_names >&2
        exit 1
    else
        echo 'Mais de um touchpad foi encontrado; escolha explicitamente:' >&2
        printf '  - %s\n' "${touchpad_candidates[@]}" >&2
        echo "Exemplo: $0 --force --device-name '${touchpad_candidates[0]}'" >&2
        exit 1
    fi
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
    awk -v name="$DEVICE_NAME" -v force="$FORCE" '
        /^MatchName=/ {
            print "MatchName=" name
            next
        }
        force == "true" && /^MatchDMIModalias=/ { next }
        { print }
    ' "$SCRIPT_DIR/config/libinput-local-overrides.quirks"
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
' "$INPUT_DEVICES_FILE")

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
preset_dir=$(DEVICE_NAME="$DEVICE_NAME" python3 - <<'PY'
import os
from inputremapper.configs.paths import get_preset_path

print(get_preset_path(os.environ['DEVICE_NAME']))
PY
)
mkdir -p "$preset_dir"
install -m 0644 "$SCRIPT_DIR/config/physical-buttons.json" "$preset_dir/$PRESET_NAME.json"

CONFIG_DIR="$config_dir" DEVICE_NAME="$DEVICE_NAME" PRESET_NAME="$PRESET_NAME" PRESET_DIR="$preset_dir" python3 - <<'PY'
import json
import os
import tempfile
from inputremapper.logger import VERSION

config_dir = os.environ['CONFIG_DIR']
device_name = os.environ['DEVICE_NAME']
preset_name = os.environ['PRESET_NAME']
preset_dir = os.environ['PRESET_DIR']
config_path = os.path.join(config_dir, 'config.json')
state_path = os.path.join(config_dir, 'positivo-vaio-vjfe-touchpad-linux-fix.json')
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

fd, temporary = tempfile.mkstemp(dir=config_dir, prefix='.touchpad-fix-', text=True)
with os.fdopen(fd, 'w', encoding='utf-8') as stream:
    json.dump({'device_name': device_name, 'preset_dir': preset_dir}, stream, indent=4)
    stream.write('\n')
os.replace(temporary, state_path)
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
if ! grep -Fq 'N: Name="input-remapper mouse"' "$INPUT_DEVICES_FILE"; then
    echo 'O dispositivo virtual não apareceu; consulte: journalctl -u input-remapper-daemon' >&2
    exit 1
fi

echo
echo 'Correção aplicada.'
echo "Quirk:  /etc/libinput/local-overrides.quirks"
echo "Preset: $preset_dir/$PRESET_NAME.json"
echo 'Teste os botões esquerdo e direito.'
