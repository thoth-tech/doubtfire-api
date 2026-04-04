#!/bin/bash
torch-model-archiver \
  --model-name effort-predictor \
  --version 1.0 \
  --model-file models/effort_model.py \
  --serialized-file effort_model.pth \
  --handler handlers/effort_regression_handler.py \
  --export-path model_store \
  --force
