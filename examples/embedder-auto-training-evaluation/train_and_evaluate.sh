#!/usr/bin/env bash
set -e

BASE_MODEL='intfloat/e5-base-v2'

OUTPUT_DIR="$1"
DOCUMENTS="$2"
TRAIN_QUERIES="$3"
TRAIN_QRELS="$4"
TEST_QUERIES="$5"
TEST_QRELS="$6"
MODEL_DIR="${OUTPUT_DIR}/models/"

echo 'Ensuring directories exist'
mkdir -p "${OUTPUT_DIR}"
mkdir -p "${MODEL_DIR}"
mkdir -p application-package/model/

echo 'Generating hard negatives'
python3 scripts/positives-negatives.py \
      --endpoint "${VESPA_ENDPOINT}" \
      --certificate "${VESPA_CERTIFICATE}" \
      --key "${VESPA_KEY}" \
      --ranking ann \
      --hits 100 \
      --queries "${TRAIN_QUERIES}" \
      --qrels "${TRAIN_QRELS}" \
      --output_file "${OUTPUT_DIR}/queries.jsonl"

echo 'Training model'
python3 scripts/sentence-transformers.py \
  --model "${BASE_MODEL}" \
  --documents "${DOCUMENTS}" \
  --queries "${OUTPUT_DIR}/queries.jsonl" \
  --epochs 10 \
  --output_dir "${MODEL_DIR}"

echo 'Exporting finetuned model to .onnx'
python3 scripts/export_hf_model_from_hf.py \
  --hf_model "${MODEL_DIR}" \
  --output_dir "${OUTPUT_DIR}"

echo 'Moving finetuned model to application package'
mv "${OUTPUT_DIR}/model.onnx" application-package/model/tuned.onnx
mv "${OUTPUT_DIR}/tokenizer.json" application-package/model/tokenizer-tuned.json

echo 'Deploying finetuned model'
vespa deploy --wait 1800 application-package/

echo 'Evaluating'
python3 scripts/evaluate.py \
                  --endpoint "${VESPA_ENDPOINT}" \
                  --certificate "${VESPA_CERTIFICATE}" \
                  --key "${VESPA_KEY}" \
                  --ranking ann \
                  --queries "${TEST_QUERIES}"
trec_eval -mndcg_cut.10 "${TEST_QRELS}" ann.run
