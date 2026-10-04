#!/usr/bin/env bash
set -euo pipefail
bash scripts/deploy.sh
bash scripts/gateway.sh
bash scripts/monitoring.sh
bash scripts/logging.sh
