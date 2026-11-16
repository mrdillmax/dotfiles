#!/usr/bin/env bash
CACHE="$HOME/.cache/clockwall"
mkdir -p "$CACHE"

FONT=$(fc-match -f '%{file}' 'JetBrains Mono:bold')
SIZE_RATIO=3   # висота тексту = висота екрана / це число

render() {
    # кольори перечитуються щоразу, тож зміна matugen підхопиться сама
    BG="#101010"; FG="#ffffff"
    # shellcheck source=/dev/null
    [ -f "$CACHE/colors.env" ] && source "$CACHE/colors.env"

    hyprctl monitors -j | jq -r '.[] | "\(.name) \(.width) \(.height)"' |
    while read -r name w h; do
        out="$CACHE/$name.png"
        magick -size "${w}x${h}" "xc:$BG" \
            -font "$FONT" -fill "$FG" -pointsize $((h / SIZE_RATIO)) \
            -gravity center -annotate +0+0 "$(date +%H:%M)" "$out"
        awww img -o "$name" --transition-type none "$out"
    done
}

while true; do
    render
    sleep $((60 - 10#$(date +%S)))   # чекаємо початку наступної хвилини
done
