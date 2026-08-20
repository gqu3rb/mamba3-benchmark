"""Pre-download the datasets used by run_mamba3_lm_eval.sh.

Run this on the LOGIN NODE (which has network). The compute node runs with
HF_HUB_OFFLINE=1, so anything not downloaded here will not be found there.

lm_eval (EleutherAI's lm-evaluation-harness): the framework that defines tasks, 
prompts, and metrics. Its task YAMLs specify which dataset to load, 
e.g. `dataset_path: Rowan/hellaswag` in
... /.conda/envs/mamba3/lib/python3.10/site-packages/lm_eval/tasks/hellaswag/hellaswag.yaml

datasets (HuggingFace): the library that actually resolves those names and 
downloads the data. lm_eval never fetches anything itself; 
it calls datasets.load_dataset(path, name, **kwargs) at lm_eval/api/task.py:871.
"""

import os
import sys
import traceback
from pathlib import Path

# set HF_HOME environment variable if it is unset.
# Setting HF_HOME before importing datasets/huggingface_hub
# because they read HF_HOME once at import time and cache the resolved paths
# derived from this file's location so it works on any account without editing.
os.environ.setdefault(
    "HF_HOME", str(Path(__file__).resolve().parent.parent / "hf_cache")
)

from datasets import load_dataset

PARQUET = {"revision": "refs/convert/parquet"}

# only ybisk/piqa still carries script-based loaders (i.e. piqa.py) 
# on its main branch, so it additionally needs the Hub's auto-generated
# parquet branch pinned via dataset_kwargs
DATASETS = [
    ("allenai/ai2_arc", "ARC-Easy", {}),
    ("allenai/ai2_arc", "ARC-Challenge", {}),
    ("Rowan/hellaswag", None, {}),
    ("EleutherAI/lambada_openai", "default", {}),
    ("allenai/openbookqa", "main", {}),
    ("ybisk/piqa", None, PARQUET),
    ("allenai/winogrande", "winogrande_xl", {}),
]


def main():
    if os.environ.get("HF_HUB_OFFLINE") == "1":
        sys.exit("HF_HUB_OFFLINE=1 is set; unset it — this script needs network.")
    
    print("HF_HOME =", os.environ["HF_HOME"], flush=True)

    failed = []
    for path, name, kwargs in DATASETS:
        label = f"{path}" + (f" [{name}]" if name else "")
        try:
            # for PIQA, kwargs is {"revision": "refs/convert/parquet"}, so the call 
            # becomes load_dataset("ybisk/piqa", None, revision="refs/convert/parquet")
            ds = load_dataset(path, name, **kwargs)
            print(f"OK    {label}: {dict((k, len(v)) for k, v in ds.items())}", flush=True)
        except Exception:
            print(f"FAIL  {label}", flush=True)
            # prints the full error details
            traceback.print_exc()
            failed.append(label)

    print()
    if failed:
        print(f"{len(failed)}/{len(DATASETS)} failed:")
        for f in failed:
            print("  -", f)
        sys.exit(1)
    print(f"All {len(DATASETS)} datasets cached.")


if __name__ == "__main__":
    main()
