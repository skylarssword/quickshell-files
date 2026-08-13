#!/usr/bin/env bash
set -u

CACHE_DIR="$HOME/.cache/tide-island/equalizer"
STATE_FILE="$CACHE_DIR/eq_state.json"
CUSTOM_FILE="$CACHE_DIR/custom_presets.json"
PRESET_DIR="$HOME/.local/share/easyeffects/output"
PRESET_NAME="tide_island_eq"
PRESET_FILE="$PRESET_DIR/${PRESET_NAME}.json"

mkdir -p "$CACHE_DIR"
mkdir -p "$PRESET_DIR"

if [ ! -f "$STATE_FILE" ]; then
    echo '{"b1":0,"b2":0,"b3":0,"b4":0,"b5":0,"b6":0,"b7":0,"b8":0,"b9":0,"b10":0,"preset":"Flat","pending":false}' > "$STATE_FILE"
fi

if [ ! -f "$CUSTOM_FILE" ]; then
    echo '{}' > "$CUSTOM_FILE"
fi

apply_eq() {
    vals=$(cat "$STATE_FILE")
    python3 -c "
import sys, json
try:
    data = json.loads(sys.argv[1])
    slider_map = { 0:0, 1:3, 2:6, 3:9, 4:12, 5:15, 6:18, 7:21, 8:24, 9:27 }
    freqs = [32, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000, 22000, 24000, 24000]
    gains = [float(data['b1']), float(data['b2']), float(data['b3']), float(data['b4']), float(data['b5']), float(data['b6']), float(data['b7']), float(data['b8']), float(data['b9']), float(data['b10'])]
    bands = {}
    for i in range(32):
        freq = freqs[i] if i < len(freqs) else 20000.0
        gain = 0.0
        for s_idx, b_idx in slider_map.items():
            if i == b_idx:
                gain = gains[s_idx]
                break
        bands[f'band{i}'] = { 'frequency': freq, 'gain': gain, 'mode': 'Bell', 'mute': False, 'q': 1.0, 'solo': False, 'width': 1.0, 'slope': 'x1' }
    preset = { 'output': { 'blocklist': [], 'plugins_order': ['equalizer'], 'equalizer': { 'bypass': False, 'input-gain': 0.0, 'output-gain': 0.0, 'left': bands, 'right': bands, 'mode': 'IIR', 'num-bands': 32, 'split-channels': False } } }
    print(json.dumps(preset, indent=4))
except Exception:
    sys.exit(1)
" "$vals" > "$PRESET_FILE"
    easyeffects -l "$PRESET_NAME" >/dev/null 2>&1 &
}

save_preset() {
    jq -n -c --arg b1 "$1" --arg b2 "$2" --arg b3 "$3" --arg b4 "$4" --arg b5 "$5" \
          --arg b6 "$6" --arg b7 "$7" --arg b8 "$8" --arg b9 "$9" --arg b10 "${10}" --arg p "${11}" \
       '{"b1": $b1, "b2": $b2, "b3": $b3, "b4": $b4, "b5": $b5, "b6": $b6, "b7": $b7, "b8": $b8, "b9": $b9, "b10": $b10, "preset": $p, "pending": false}' > "$STATE_FILE"
}

# ── Custom slot helpers ──────────────────────────────────────────────────────
# custom_presets.json shape: { "1": {"b1":0,...,"b10":0}, "3": {...}, ... }

save_custom_slot() {
    local slot="$1"
    shift
    local b1="$1" b2="$2" b3="$3" b4="$4" b5="$5" b6="$6" b7="$7" b8="$8" b9="$9" b10="${10}"
    local tmp
    tmp=$(cat "$CUSTOM_FILE")
    local band_obj
    band_obj=$(jq -n -c --arg b1 "$b1" --arg b2 "$b2" --arg b3 "$b3" --arg b4 "$b4" --arg b5 "$b5" \
          --arg b6 "$b6" --arg b7 "$b7" --arg b8 "$b8" --arg b9 "$b9" --arg b10 "$b10" \
       '{"b1": $b1, "b2": $b2, "b3": $b3, "b4": $b4, "b5": $b5, "b6": $b6, "b7": $b7, "b8": $b8, "b9": $b9, "b10": $b10}')
    echo "$tmp" | jq -c --arg slot "$slot" --argjson bands "$band_obj" '.[$slot] = $bands' > "$CUSTOM_FILE.tmp"
    mv "$CUSTOM_FILE.tmp" "$CUSTOM_FILE"
}

get_custom_slot() {
    local slot="$1"
    local bands
    bands=$(jq -c --arg slot "$slot" '.[$slot] // empty' "$CUSTOM_FILE")
    if [ -z "$bands" ]; then
        echo '{"b1":0,"b2":0,"b3":0,"b4":0,"b5":0,"b6":0,"b7":0,"b8":0,"b9":0,"b10":0,"filled":false}'
    else
        echo "$bands" | jq -c '. + {filled: true}'
    fi
}

clear_custom_slot() {
    local slot="$1"
    jq -c --arg slot "$slot" 'del(.[$slot])' "$CUSTOM_FILE" > "$CUSTOM_FILE.tmp"
    mv "$CUSTOM_FILE.tmp" "$CUSTOM_FILE"
}

get_custom_slots() {
    cat "$CUSTOM_FILE"
}

cmd="${1:-}"
arg1="${2:-}"
arg2="${3:-}"

case "$cmd" in
    "get")
        cat "$STATE_FILE"
        ;;
    "set_band")
        tmp=$(cat "$STATE_FILE")
        updated=$(echo "$tmp" | jq -c --arg val "$arg2" ".b$arg1 = \$val | .preset = \"Custom\" | .pending = true")
        echo "$updated" > "$STATE_FILE"
        ;;
    "apply")
        tmp=$(cat "$STATE_FILE")
        updated=$(echo "$tmp" | jq -c ".pending = false")
        echo "$updated" > "$STATE_FILE"
        apply_eq
        ;;
    "preset")
        case "$arg1" in
            "Flat")    save_preset 0 0 0 0 0 0 0 0 0 0 "Flat" ;;
            "Bass")    save_preset 5 7 5 2 1 0 0 0 1 2 "Bass" ;;
            "Treble")  save_preset -2 -1 0 1 2 3 4 5 6 6 "Treble" ;;
            "Vocal")   save_preset -2 -1 1 3 5 5 4 2 1 0 "Vocal" ;;
            "Pop")     save_preset 2 4 2 0 1 2 4 2 1 2 "Pop" ;;
            "Rock")    save_preset 5 4 2 -1 -2 -1 2 4 5 6 "Rock" ;;
            "Jazz")    save_preset 3 3 1 1 1 1 2 1 2 3 "Jazz" ;;
            "Classic") save_preset 0 1 2 2 2 2 1 2 3 4 "Classic" ;;
            *) exit 1 ;;
        esac
        apply_eq
        ;;
"save_custom")
        # save_custom <slot> <b1> <b2> ... <b10>
        slot="$arg1"
        shift 2
        save_custom_slot "$slot" "$@"
        # Also apply these values live immediately, same as load_custom.
        bands=$(jq -c --arg slot "$slot" '.[$slot] // empty' "$CUSTOM_FILE")
        echo "$bands" > "$STATE_FILE.custom_tmp"
        python3 -c "
import sys, json
try:
    data = json.load(open(sys.argv[1]))
    slider_map = { 0:0, 1:3, 2:6, 3:9, 4:12, 5:15, 6:18, 7:21, 8:24, 9:27 }
    freqs = [32, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000, 22000, 24000, 24000]
    gains = [float(data.get('b1',0)), float(data.get('b2',0)), float(data.get('b3',0)), float(data.get('b4',0)), float(data.get('b5',0)), float(data.get('b6',0)), float(data.get('b7',0)), float(data.get('b8',0)), float(data.get('b9',0)), float(data.get('b10',0))]
    bands = {}
    for i in range(32):
        freq = freqs[i] if i < len(freqs) else 20000.0
        gain = 0.0
        for s_idx, b_idx in slider_map.items():
            if i == b_idx:
                gain = gains[s_idx]
                break
        bands[f'band{i}'] = { 'frequency': freq, 'gain': gain, 'mode': 'Bell', 'mute': False, 'q': 1.0, 'solo': False, 'width': 1.0, 'slope': 'x1' }
    preset = { 'output': { 'blocklist': [], 'plugins_order': ['equalizer'], 'equalizer': { 'bypass': False, 'input-gain': 0.0, 'output-gain': 0.0, 'left': bands, 'right': bands, 'mode': 'IIR', 'num-bands': 32, 'split-channels': False } } }
    print(json.dumps(preset, indent=4))
except Exception:
    sys.exit(1)
" "$STATE_FILE.custom_tmp" > "$PRESET_FILE"
        rm -f "$STATE_FILE.custom_tmp"
        easyeffects -l "$PRESET_NAME" >/dev/null 2>&1 &
        ;;
"get_custom_slot")
        get_custom_slot "$arg1"
        ;;
    "load_custom")
        # Load a custom slot's values into the main state file AND apply them live.
        bands=$(jq -c --arg slot "$arg1" '.[$slot] // empty' "$CUSTOM_FILE")
        if [ -z "$bands" ]; then
            echo '{"b1":0,"b2":0,"b3":0,"b4":0,"b5":0,"b6":0,"b7":0,"b8":0,"b9":0,"b10":0}' > "$STATE_FILE.custom_tmp"
        else
            echo "$bands" > "$STATE_FILE.custom_tmp"
        fi
        # Build the EasyEffects preset JSON directly from this slot's values
        # without disturbing the main STATE_FILE (Page 1's own state stays separate).
        python3 -c "
import sys, json
try:
    data = json.load(open(sys.argv[1]))
    slider_map = { 0:0, 1:3, 2:6, 3:9, 4:12, 5:15, 6:18, 7:21, 8:24, 9:27 }
    freqs = [32, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000, 22000, 24000, 24000]
    gains = [float(data.get('b1',0)), float(data.get('b2',0)), float(data.get('b3',0)), float(data.get('b4',0)), float(data.get('b5',0)), float(data.get('b6',0)), float(data.get('b7',0)), float(data.get('b8',0)), float(data.get('b9',0)), float(data.get('b10',0))]
    bands = {}
    for i in range(32):
        freq = freqs[i] if i < len(freqs) else 20000.0
        gain = 0.0
        for s_idx, b_idx in slider_map.items():
            if i == b_idx:
                gain = gains[s_idx]
                break
        bands[f'band{i}'] = { 'frequency': freq, 'gain': gain, 'mode': 'Bell', 'mute': False, 'q': 1.0, 'solo': False, 'width': 1.0, 'slope': 'x1' }
    preset = { 'output': { 'blocklist': [], 'plugins_order': ['equalizer'], 'equalizer': { 'bypass': False, 'input-gain': 0.0, 'output-gain': 0.0, 'left': bands, 'right': bands, 'mode': 'IIR', 'num-bands': 32, 'split-channels': False } } }
    print(json.dumps(preset, indent=4))
except Exception:
    sys.exit(1)
" "$STATE_FILE.custom_tmp" > "$PRESET_FILE"
        rm -f "$STATE_FILE.custom_tmp"
        easyeffects -l "$PRESET_NAME" >/dev/null 2>&1 &
        ;;
    "clear_custom")
        clear_custom_slot "$arg1"
        ;;
    "get_custom_slots")
        get_custom_slots
        ;;
    *)
        echo "Usage: equalizer.sh {get|set_band <1-10> <gain>|apply|preset <name>|save_custom <slot> <b1..b10>|get_custom_slot <slot>|clear_custom <slot>|get_custom_slots}" >&2
        exit 1
        ;;
esac
