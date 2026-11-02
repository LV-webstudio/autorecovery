#!/bin/bash
# buscar-mac-en-logs.sh · Shania Autorecovery
# Rescata la MAC de un equipo a partir de las tablas ARP (arp -an) ya registradas en los
# logs de las sesiones de Claude. Útil cuando el equipo está APAGADO (no se puede escanear)
# pero su IP salió alguna vez en un volcado ARP del Mac.
#
# OJO: en macOS `arp` imprime las MAC SIN ceros a la izquierda (aa:b:cc:dd:ee:01). Este script
# tolera ese formato y RELLENA cada octeto a 2 dígitos para dar una MAC válida para WoL.
#
# Método FIABLE: no se fía del conteo bruto (una misma conversación puede repetir una MAC y
# sesgarlo). Busca una TABLA ARP COHERENTE: aquella donde el router (.1), el Mac (.38) y el
# portátil (.37) salen con sus MAC conocidas (se pasan por variables de entorno); en esa tabla, la MAC de la IP pedida es la buena.
#
# Uso:  ROUTER_MAC=aa:bb:cc:dd:ee:00 MAC_MAC=aa:bb:cc:dd:ee:01 PORT_MAC=aa:bb:cc:dd:ee:02 \
#         ./buscar-mac-en-logs.sh 192.168.1.33
# Variables (al menos dos de las tres deben coincidir en una misma tabla ARP para darla por buena):
#   ROUTER_MAC  MAC del router (puerta de enlace)
#   MAC_MAC     MAC del equipo que hace de despertador
#   PORT_MAC    MAC de otro equipo conocido de la red
set -euo pipefail
IP="${1:?Uso: buscar-mac-en-logs.sh <IP>}"
LOGS="${HOME}/.claude/projects"
ESTA_SESION="${CLAUDE_SESSION_FILE:-}"   # exporta esta ruta para excluir el log actual del conteo

# MAC conocidas para validar una tabla (se leen del entorno; si no, quedan los marcadores de ejemplo):
ROUTER_MAC="${ROUTER_MAC:-aa:bb:cc:dd:ee:00}"   # puerta de enlace (marcador de ejemplo)
MAC_MAC="${MAC_MAC:-aa:bb:cc:dd:ee:01}"         # equipo despertador (marcador de ejemplo)
PORT_MAC="${PORT_MAC:-aa:bb:cc:dd:ee:02}"       # otro equipo conocido (marcador de ejemplo)

ipre="${IP//./\\.}"
OCT='[0-9a-f]{1,2}'               # octeto de 1 o 2 dígitos (formato arp de macOS)
MACRE="(${OCT}:){5}${OCT}"

pad() {  # rellena cada octeto a 2 dígitos: aa:b:cc:dd:ee:1 -> aa:0b:cc:dd:ee:01
  echo "$1" | awk -F: '{for(i=1;i<=NF;i++)printf("%s%s",(i>1?":":""),substr("0" $i,length($i)+1));print""}'
}

echo "== candidatas por conteo (orientativo, puede estar sesgado) =="
grep -rhoE "${ipre}\) at ${MACRE}" "$LOGS" --include='*.jsonl' 2>/dev/null \
  | sed -E 's/.*at //' | while read -r m; do pad "$m"; done | sort | uniq -c | sort -rn || true

echo
echo "== validación por TABLA COHERENTE =="
best=""
while IFS= read -r f; do
  [ "$f" = "$ESTA_SESION" ] && continue
  tabla=$(grep -oE "192\.168\.1\.[0-9]+\) at ${MACRE}" "$f" 2>/dev/null | sort -u || true)
  ok=0
  echo "$tabla" | grep -qi "$ROUTER_MAC" && ok=$((ok+1)) || true
  echo "$tabla" | grep -qi "$MAC_MAC"    && ok=$((ok+1)) || true
  echo "$tabla" | grep -qi "$PORT_MAC"   && ok=$((ok+1)) || true
  if [ "$ok" -ge 2 ]; then
    raw=$(echo "$tabla" | grep -E "${ipre}\) at" | sed -E 's/.*at //' | head -1 || true)
    if [ -n "$raw" ]; then
      cand=$(pad "$raw")
      echo "Tabla coherente ($ok/3 conocidas) en $(basename "$f"): $IP -> $cand"
      [ -z "$best" ] && best="$cand"
    fi
  fi
done < <(grep -rloE "${ipre}\) at ${MACRE}" "$LOGS" --include='*.jsonl' 2>/dev/null \
          | xargs -I{} stat -f '%m {}' {} 2>/dev/null | sort -rn | awk '{print $2}')

echo
if [ -n "$best" ]; then
  echo "MAC MÁS FIABLE para $IP: $best"
else
  echo "No hallé una tabla coherente; usa la candidata de mayor conteo con cautela."
fi
