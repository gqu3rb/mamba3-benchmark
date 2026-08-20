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
patch_piqa_revision() {
    local f="$TASKS_DIR/piqa/piqa.yaml"

    if [ ! -f "$f" ]; then
        echo "MISSING   piqa/piqa.yaml"
        rc=1
        return
    fi

    if grep -q "refs/convert/parquet" "$f"; then
        echo "already   piqa/piqa.yaml  ->  revision: refs/convert/parquet"
    elif grep -qE "^dataset_name: *null\$" "$f"; then
        sed -i -E '/^dataset_name: *null$/a dataset_kwargs:\n  revision: refs/convert/parquet' "$f"
        echo "PATCHED   piqa/piqa.yaml  ->  revision: refs/convert/parquet"
    else
        echo "UNEXPECTED piqa/piqa.yaml -- no 'dataset_name: null' line to anchor the insert"
        rc=1
    fi
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
