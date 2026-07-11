#!/bin/bash

# ---
# J.V. Loddo, 07/2026, GPL v2

# ---
source ../../bashbricks/bashbricks.sh
# ---
[[ $# = 2 ]] || { echo 1>&2 "Usage: ./check-inconsistencies.sh <CONFIG1> <CONFIG2>"; exit 1; }
# ---
CONFIG1=${1:-CONFIG-3.2.64}
CONFIG2=${2:-CONFIG-modern-base}
# ---
test_f $CONFIG1 $CONFIG2
# ---
Map.import -k '=' M1 <(grep '^[A-Z].*[^ ]=' $CONFIG1)
Map.import -k '=' M2 <(grep '^[A-Z].*[^ ]=' $CONFIG2)
# ---
Map.to_key_array M1 K1
Map.to_key_array M2 K2
# ---
Array.to_set K1 S1
Array.to_set K2 S2
# ---
Set.intersection COMMON_KEYS S1 S2
# ---
echo "Cardinalities: "
printf "  %-24s: %d\n" "$CONFIG1"     $(Map.card M1)
printf "  %-24s: %d\n" "$CONFIG2"     $(Map.card M2)
printf "  %-24s: %d\n" "INTERSECTION" $(Set.card COMMON_KEYS)
# ---
function helper {
  local KEY="$1"
  local V1=$(Map.get M1 "$KEY")
  local V2=$(Map.get M2 "$KEY")
  if [[ "$V1" != "$V2" ]]; then
    echo '---'
    printf "  %-24s: %s=%s\n" "$CONFIG1" "$KEY" "$V1"
    printf "  %-24s: %s=%s\n" "$CONFIG2" "$KEY" "$V2"
  fi
}
# ---
Set.iter COMMON_KEYS helper 
