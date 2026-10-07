#!/bin/bash
# Build step, based on the instructor's 10-final-cicd-pipeline/build.sh.
# Produces build/ which the pipeline uploads as the "calculator-build" artifact
# and downloads again in a later job.
set -euo pipefail

GIT_SHA="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo local)}"

echo "================================="
echo "Starting Application Build"
echo "================================="
rm -rf build
mkdir -p build
cp -R app requirements.txt build/
find build -name '__pycache__' -type d -prune -exec rm -rf {} +

cat > build/build-info.txt <<INFO
Application: Session 16 Calculator
Version: 1.0.0
Git commit: ${GIT_SHA}
Built by: ${GITHUB_WORKFLOW:-local build} (run ${GITHUB_RUN_NUMBER:-n/a})
Python: $(python3 --version 2>&1)
Build date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)
INFO

echo ""
echo "Build files:"
find build -type f | sort
echo ""
cat build/build-info.txt
echo ""
echo "Build completed successfully."
