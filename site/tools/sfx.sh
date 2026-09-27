#!/bin/bash
# Mixes the 404's swallow sounds from the demo video's effects (video/public/sfx: sounds synthesized by
# video/scripts/sfx.ts, plus Kenney's Sci-fi Sounds, CC0) into public/assets/*.mp3.
#   ginga-404-swallow.mp3  spiral under the tiles (8 s, longer than the swallow on a 5K screen; the page cuts it dry when the last tile is gone)
#   ginga-404-gulp.mp3     the swallow itself (hit + low tail), right after the cut
# Uses $FFMPEG, else ffmpeg on PATH, else the one Remotion installs in video/node_modules.
# Only basic filters (Remotion's build has no afade/alimiter): fades are volume expressions.
set -euo pipefail
cd "$(dirname "$0")/.."
S=../video/public/sfx
remotion=../video/node_modules/@remotion/compositor-darwin-arm64
ff="${FFMPEG:-}"
if [[ -z "$ff" ]] && sh -c "ffmpeg -version >/dev/null 2>&1 && echo ok" 2>/dev/null | grep -q ok; then ff=ffmpeg; fi   # a broken install aborts
if [[ -z "$ff" && -x "$remotion/ffmpeg" ]]; then ff="$remotion/ffmpeg"; export DYLD_LIBRARY_PATH="$remotion"; fi
[[ -n "$ff" ]] || { echo "no working ffmpeg (set FFMPEG, or npm install in video/)" >&2; exit 1; }
mp3=(-c:a libmp3lame -b:a 96k -ar 44100)
slow() { echo "asetrate=48000*$1,aresample=48000"; }   # slower and lower, like falling in

"$ff" -loglevel error -y -i "$S/kenney/spaceEngineLow_000.wav" -i "$S/kenney/lowFrequency_explosion_000.wav" \
  -i "$S/whoosh-long.wav" -i "$S/whoosh-long.wav" -i "$S/whoosh-long.wav" -filter_complex "
  [0]$(slow 0.62),volume=0.5[a];
  [1]volume=0.35[b];
  [2]$(slow 0.6),volume=0.8,adelay=500|500[c];
  [3]$(slow 0.55),volume=0.9,adelay=2300|2300[d];
  [4]$(slow 0.5),volume=0.8,adelay=4200|4200[e];
  [a][b][c][d][e]amix=inputs=5:normalize=0,atrim=0:8,volume='0.85*min(1,t/0.6)*min(1,(8-t)/0.6)':eval=frame" \
  "${mp3[@]}" public/assets/ginga-404-swallow.mp3

"$ff" -loglevel error -y -i "$S/hit-soft.wav" -i "$S/kenney/lowFrequency_explosion_001.wav" -filter_complex "
  [0]volume=1[a]; [1]volume=0.6[b];
  [a][b]amix=inputs=2:normalize=0,atrim=0:1,volume='min(1,(1-t)/0.3)':eval=frame" \
  "${mp3[@]}" public/assets/ginga-404-gulp.mp3

ls -l public/assets/ginga-404-*.mp3
