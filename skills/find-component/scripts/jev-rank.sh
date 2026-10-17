#!/bin/sh
# jev-rank.sh "<what you need>" candidates.tsv - rank shortlisted items by how well each fits the description,
# using Jev (typesafe/jev-1.13 on OpenRouter, about $0.00002 per candidate). candidates.tsv: name<TAB>link<TAB>blurb
# Key: OPENROUTER_API_KEY=... in $LK_CHECK_KEY_FILE (default ~/.secrets/openrouter.env). Needs curl + jq.
need=$1; list=$2
[ -n "$need" ] && [ -f "$list" ] || { sed -n 2,4p "$0"; exit 2; }
f=${LK_CHECK_KEY_FILE:-$HOME/.secrets/openrouter.env}
key=$(sed -n 's/^OPENROUTER_API_KEY=//p' "$f" 2>/dev/null | tr -d "\"' "); [ -n "$key" ] || { echo "no OPENROUTER_API_KEY in $f" >&2; exit 1; }
q='{"fit":{"type":"score","instructions":"How well does this component or asset match what the person needs?","criteria":["wrong thing","related but a poor fit","good fit with changes","exactly what they described"]}}'
while IFS='	' read -r name link blurb; do
  [ -n "$name" ] || continue
  s=$(jq -n --arg n "$need" --arg c "$name" --arg b "$blurb" --argjson q "$q" \
      '{model:"typesafe/jev-1.13", state:{needed:$n, candidate:$c, description:$b}, questions:$q}' |
    curl -sf -m 20 https://openrouter.ai/api/alpha/decisions -H "Authorization: Bearer $key" -H 'Content-Type: application/json' -d @- |
    jq -r '.answers.fit.score // "?"')
  printf '%s\t%s\t%s\n' "$s" "$name" "$link"
done < "$list" | sort -rn
