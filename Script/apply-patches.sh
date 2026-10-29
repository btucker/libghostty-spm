#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source_dir=${1:?Usage: apply-patches.sh SOURCE}
expected=$(cat Ghostty.ref)
[[ $(git -C "$source_dir" rev-parse HEAD) == "$expected" ]] || { echo '[!] Wrong Ghostty source revision' >&2; exit 1; }
fingerprint=$(python3 - <<'HASH'
import hashlib,json
from pathlib import Path
recipe=Path('Paging/recipe.json')
hash=hashlib.sha256(recipe.read_bytes())
for name in json.loads(recipe.read_text())['rendererPatches']:
    hash.update((Path('Paging')/(name+'.patch')).read_bytes())
print(hash.hexdigest())
HASH
)
stamp="$source_dir/.libghostty-paging-inputs"
# Hash the tracked native diff as well as the recipe. The input stamp alone
# cannot prove that a reused checkout still contains exactly the patched engine.
diff_digest() { git -C "$source_dir" diff --binary HEAD | shasum -a 256 | awk '{print $1}'; }
untracked=$(git -C "$source_dir" ls-files --others --exclude-standard | sed '/^\.libghostty-paging-inputs$/d')
[[ -z "$untracked" ]] || { echo '[!] Unexpected untracked native source files' >&2; exit 1; }
if [[ -f "$stamp" ]]; then
    [[ $(sed -n '1p' "$stamp") == "$fingerprint" && $(sed -n '2p' "$stamp") == "$(diff_digest)" ]] || {
        echo '[!] Patched native source changed; use a fresh source checkout' >&2; exit 1;
    }
    exit 0
fi
[[ -z $(git -C "$source_dir" status --porcelain) ]] || { echo '[!] Use a clean pinned source checkout' >&2; exit 1; }
while IFS= read -r name; do
    patch="$PWD/Paging/$name.patch"
    git -C "$source_dir" apply --check "$patch"
    git -C "$source_dir" apply --intent-to-add "$patch"
done < <(python3 -c 'import json; print("\n".join(json.load(open("Paging/recipe.json"))["rendererPatches"]))')
printf '%s\n%s\n' "$fingerprint" "$(diff_digest)" > "$stamp"
