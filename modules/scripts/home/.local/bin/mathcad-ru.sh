#!/bin/bash
export WINEPREFIX=${WINEPREFIX:-$HOME/Projects/Mathcad/prefix}
export FREETYPE_PROPERTIES="truetype:interpreter-version=40"
EXE='C:\Program Files\PTC\Mathcad Prime 12.0.0.1\MathcadPrime.exe'

args=(/culture:ru)
if [ -n "$1" ]; then
    args+=("$(winepath -w "$1")")
fi

exec wine "$EXE" "${args[@]}"
