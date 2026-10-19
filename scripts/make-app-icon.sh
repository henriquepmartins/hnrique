#!/bin/bash
# Tira o quadrado arredondado e a borda que vinham desenhados dentro da arte do
# ícone. O iOS aplica a própria máscara, então a arte precisa de fundo até a
# borda. O glifo cresce na mesma razão do quadrado antigo para o quadro, e o
# tamanho dele em relação ao ícone visível fica igual ao da arte original.
#
#     ./scripts/make-app-icon.sh entrada.png App/Assets.xcassets/AppIcon.appiconset/AppIcon.png
#
# Precisa do ImageMagick 7 (`magick`).
set -euo pipefail

in="$1"
out="$2"
size=$(magick "$in" -format "%w" info:)
mid=$((size / 2))

bg=$(magick "$in" -format "%[pixel:p{10,10}]" info:)

# A linha do meio, aparada pela cor do canto, vai do traço esquerdo ao direito.
read -r ring_w ring_x < <(magick "$in" -crop "${size}x1+0+${mid}" +repage -fuzz 5% -trim \
  -format "%w %X\n" info: | tr -d '+')
if [ "$ring_x" -le 0 ] || [ "$ring_x" -ge $((size / 8)) ]; then
  echo "não achei o quadrado desenhado (borda em x=$ring_x); a arte já está em sangria?" >&2
  exit 1
fi

# O glifo é o que sobra dentro do quadrado, longe do traço.
inset=$((ring_x + 50))
inner=$((size - 2 * inset))
read -r gw gh gx gy < <(magick "$in" -crop "${inner}x${inner}+${inset}+${inset}" +repage \
  -fuzz 12% -trim -format "%w %h %X %Y\n" info: | tr -d '+')
gx=$((gx + inset))
gy=$((gy + inset))

scale=$(echo "$size / $ring_w" | bc -l)
read -r nw nh nx ny < <(awk -v s="$scale" -v m="$mid" -v gw="$gw" -v gh="$gh" -v gx="$gx" -v gy="$gy" \
  'BEGIN {
    cx = m + (gx + gw / 2 - m) * s; cy = m + (gy + gh / 2 - m) * s
    nw = int(gw * s + 0.5); nh = int(gh * s + 0.5)
    printf "%d %d %d %d\n", nw, nh, int(cx - nw / 2 + 0.5), int(cy - nh / 2 + 0.5)
  }')

pad=12
magick "$in" -crop "$((gw + 2 * pad))x$((gh + 2 * pad))+$((gx - pad))+$((gy - pad))" +repage \
  -fuzz 4% -fill "$bg" -opaque "$bg" \
  -filter Lanczos -resize "$(echo "$scale * 100" | bc -l)%" \
  \( -size "${size}x${size}" "xc:$bg" \) +swap \
  -geometry "+$((nx - pad * nw / gw))+$((ny - pad * nh / gh))" -composite \
  -alpha off "$out"

echo "fundo $bg, quadrado de ${ring_w}px em x=$ring_x, glifo ${gw}x${gh} -> ${nw}x${nh} em +$nx+$ny"
