#!/bin/bash
# This file is used to correct the four lm_eval task-YAML dataset-path to namespaced paths.
# e.g. the `dataset_path: hellaswag` in 
# ... /.conda/envs/mamba3/lib/python3.10/site-packages/lm_eval/tasks/hellaswag/hellaswag.yaml
# becomes
# `dataset_path: Rowan/hellaswag`
#
# This file is also used to add the dataset_kwargs entry to piqa.yaml,
# for resolving the following error:
# `Dataset scripts are no longer supported, but found piqa.py`
#
# ARC and LAMBADA are deliberately untouched -- allenai/ai2_arc and
# EleutherAI/lambada_openai already use namespaced paths and load fine.
#
# WHY: lm_eval 0.4.2 ships bare canonical dataset names (e.g. hellaswag) that 
# no longer load under datasets 5.x
#
# `pip install --force-reinstall lm_eval` or rebuilding the conda env silently
# reverts them. Run this script afterwards to restore them.
#
# Use the following command to run this script:
#   conda activate mamba3 && export PATH="$CONDA_PREFIX/bin:$PATH" && ./patch_lm_eval_task_yamls.sh

set -euo pipefail

# TASKS_DIR=<your home directory>/.conda/envs/mamba3/lib/python3.10/site-packages/lm_eval/tasks
TASKS_DIR="$(python -c "import importlib.util as u; print(u.find_spec('lm_eval.tasks').submodule_search_locations[0])")"
echo "lm_eval tasks dir: $TASKS_DIR"
echo

rc=0

# Rewrite a bare `dataset_path:` to its namespaced equivalent.
patch_path() {
    local rel="$1" old="$2" new="$3"
    local f="$TASKS_DIR/$rel"

    if [ ! -f "$f" ]; then
        echo "MISSING   $rel  (expected at $f)"
        rc=1
        return
    fi

    # Checking for the new value first is what makes re-running harmless
    if grep -qE "^dataset_path: *${new}\$" "$f"; then
        echo "already   $rel  ->  $new"
    elif grep -qE "^dataset_path: *${old}\$" "$f"; then
        sed -i -E "s|^dataset_path: *${old}\$|dataset_path: ${new}|" "$f"
        echo "PATCHED   $rel  ->  $new"
    else
        echo "UNEXPECTED $rel -- dataset_path is neither '$old' nor '$new':"
        grep -n "^dataset_path" "$f" || echo "  (no dataset_path line at all)"
        rc=1
    fi
}

# PIQA needs the parquet-branch pin in addition to the path rewrite, because
# ybisk/piqa's main branch still ships a loading script.
#
# CAREFUL: lm_eval 0.4.3 ships its OWN `dataset_kwargs: {trust_remote_code: true}` in this
# file (0.4.2 did not). Blindly appending a second `dataset_kwargs:` block produces a
# duplicate yaml key -- the last one wins, so our revision pin gets silently overridden by
# trust_remote_code, which datasets 5.x rejects outright. The run then only works if the
# parquet data happens to be cached already. So we need to delete every existing dataset_kwargs block
# first, then insert ours. That is version-agnostic and stays idempotent.
patch_piqa_revision() {
    local f="$TASKS_DIR/piqa/piqa.yaml"

    if [ ! -f "$f" ]; then
        echo "MISSING   piqa/piqa.yaml"
        rc=1
        return
    fi

    if python - "$f" <<'PY'
import re, sys

path = sys.argv[1]
original = open(path).read()
lines = original.splitlines()
WANT = ["dataset_kwargs:", "  revision: refs/convert/parquet"]

# 1) drop every existing dataset_kwargs block (the key line plus its indented children)
kept, dropped, i = [], [], 0
while i < len(lines):
    if re.match(r"^dataset_kwargs:\s*$", lines[i]):
        i += 1
        while i < len(lines) and re.match(r"^\s+\S", lines[i]):
            dropped.append(lines[i].strip())
            i += 1
        continue
    kept.append(lines[i])
    i += 1

# 2) reinsert ours immediately after `dataset_name: null`
for j, line in enumerate(kept):
    if re.match(r"^dataset_name:\s*null\s*$", line):
        kept[j + 1 : j + 1] = WANT
        break
else:
    sys.exit("UNEXPECTED piqa/piqa.yaml -- no 'dataset_name: null' line to anchor the insert")

new = "\n".join(kept) + "\n"
if new == original:
    print("already   piqa/piqa.yaml  ->  revision: refs/convert/parquet")
else:
    open(path, "w").write(new)
    conflicting = [d for d in dropped if "refs/convert/parquet" not in d]
    note = f"  (removed conflicting: {', '.join(conflicting)})" if conflicting else ""
    print(f"PATCHED   piqa/piqa.yaml  ->  revision: refs/convert/parquet{note}")
PY
    then :; else rc=1; fi
}

patch_path "hellaswag/hellaswag.yaml"   "hellaswag"  "Rowan/hellaswag"
patch_path "openbookqa/openbookqa.yaml" "openbookqa" "allenai/openbookqa"
patch_path "winogrande/default.yaml"    "winogrande" "allenai/winogrande"
patch_path "piqa/piqa.yaml"             "piqa"       "ybisk/piqa"
patch_piqa_revision

echo
echo "=== resulting dataset settings ==="
for rel in hellaswag/hellaswag.yaml openbookqa/openbookqa.yaml \
           winogrande/default.yaml piqa/piqa.yaml; do
    echo "--- $rel"
    grep -nE "^dataset_path|^dataset_name|^dataset_kwargs|^  revision" "$TASKS_DIR/$rel" \
        | sed 's/^/    /'
done

echo
if [ "$rc" -ne 0 ]; then
    echo "FAILED: at least one file was missing or in an unexpected state (see above)."
    echo "The lm_eval version may differ from 0.4.2"
    echo "this file (i.e. patch_lm_eval_task_yamls.sh) is designed to correct the dataset-paths"
    echo "for lm_eval 0.4.2 version, other versions may represent dataset-paths or parquet-branchin of ybisk/piqa"
    echo "in different way that this script cannot capture."
    echo "Please check if the dataset-path settings are correct manually."
    exit 1
fi
echo "All five patches are in place."
