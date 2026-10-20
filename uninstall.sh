#!/usr/bin/env bash
set -euo pipefail

DEVICE_NAME='SYNA3602:00 0911:5288 Touchpad'
PRESET_NAME='Corrigir botoes fisicos'
MANAGED_BEGIN='# BEGIN positivo-vaio-vjfe-touchpad-linux-fix'
MANAGED_END='# END positivo-vaio-vjfe-touchpad-linux-fix'
REMOVE_PACKAGES=false

if [[ ${1:-} == '--remove-packages' ]]; then
    REMOVE_PACKAGES=true
elif [[ $# -gt 0 ]]; then
    echo "Uso: $0 [--remove-packages]" >&2
    exit 2
fi

if [[ $EUID -eq 0 ]]; then
    echo 'Execute como usuário normal; o script solicitará sudo quando necessário.' >&2
    exit 1
fi

user_home=$(getent passwd "$(id -u)" | cut -d: -f6)
config_dir=${XDG_CONFIG_HOME:-$user_home/.config}/input-remapper-2
if python3 -c 'from inputremapper.configs.paths import CONFIG_PATH' >/dev/null 2>&1; then
    config_dir=$(python3 - <<'PY'
from inputremapper.configs.paths import CONFIG_PATH
print(CONFIG_PATH)
PY
)
fi

state_path="$config_dir/positivo-vaio-vjfe-touchpad-linux-fix.json"
preset_dir="$config_dir/presets/SYNA3602_00 0911_5288 Touchpad"
if [[ -f $state_path ]]; then
    mapfile -t install_state < <(STATE_PATH="$state_path" python3 - <<'PY'
import json
import os

with open(os.environ['STATE_PATH'], encoding='utf-8') as stream:
    state = json.load(stream)
print(state['device_name'])
print(state['preset_dir'])
PY
    )
    if [[ ${#install_state[@]} -eq 2 ]]; then
        DEVICE_NAME=${install_state[0]}
        preset_dir=${install_state[1]}
    fi
fi

if python3 -c 'import inputremapper' >/dev/null 2>&1; then
    DEVICE_NAME="$DEVICE_NAME" python3 - <<'PY' || true
import os
from inputremapper.daemon import Daemon

service = Daemon.connect(fallback=False)
service.stop_injecting(os.environ['DEVICE_NAME'])
PY
fi

CONFIG_DIR="$config_dir" DEVICE_NAME="$DEVICE_NAME" python3 - <<'PY'
import json
import os
import tempfile

config_path = os.path.join(os.environ['CONFIG_DIR'], 'config.json')
if not os.path.exists(config_path):
    raise SystemExit

with open(config_path, encoding='utf-8') as stream:
    config = json.load(stream)
config.get('autoload', {}).pop(os.environ['DEVICE_NAME'], None)

fd, temporary = tempfile.mkstemp(dir=os.path.dirname(config_path), prefix='.config-', text=True)
with os.fdopen(fd, 'w', encoding='utf-8') as stream:
    json.dump(config, stream, indent=4)
    stream.write('\n')
os.replace(temporary, config_path)
PY

rm -f "$preset_dir/$PRESET_NAME.json" "$state_path"
rmdir "$preset_dir" 2>/dev/null || true

if sudo test -f /etc/libinput/local-overrides.quirks; then
    tmp_quirks=$(mktemp)
    trap 'rm -f "$tmp_quirks"' EXIT
    sudo awk -v begin="$MANAGED_BEGIN" -v end="$MANAGED_END" '
        $0 == begin { managed = 1; next }
        $0 == end { managed = 0; next }
        !managed { print }
    ' /etc/libinput/local-overrides.quirks > "$tmp_quirks"
    sudo install -o root -g root -m 0644 "$tmp_quirks" /etc/libinput/local-overrides.quirks
fi

gsettings set org.gnome.desktop.peripherals.touchpad left-handed 'mouse'

if [[ $REMOVE_PACKAGES == true ]]; then
    sudo apt-get remove -y input-remapper input-remapper-gtk input-remapper-daemon python3-inputremapper
fi

echo 'Correção removida. Overrides antigos desativados não foram restaurados automaticamente.'
