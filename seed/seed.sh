#!/usr/bin/env bash
set -euo pipefail

FHIR_BASE="${FHIR_BASE_URL:-http://hapi:8080/fhir}"
BUNDLES_DIR="/bundles"
SEED_FAILED=0

# Validate bundles directory exists
if [[ ! -d "$BUNDLES_DIR" ]]; then
  echo "ERROR: Bundles directory does not exist: ${BUNDLES_DIR}"
  exit 1
fi

# Use nullglob so empty glob expands to nothing instead of the literal pattern
shopt -s nullglob
bundles=("${BUNDLES_DIR}"/*.json)
if [[ ${#bundles[@]} -eq 0 ]]; then
  echo "ERROR: No bundle files found in ${BUNDLES_DIR}"
  exit 1
fi

# Create secure temporary directory with automatic cleanup
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

echo "==> HAPI FHIR is ready. Starting seed against ${FHIR_BASE} ..."

# POST each bundle in filename order
for bundle in "${bundles[@]}"; do
  name=$(basename "$bundle")
  echo ""
  echo "==> Seeding: ${name}"
  HTTP_STATUS=$(curl -s --max-time 30 --connect-timeout 10 -o "$WORK_DIR/seed_response.json" -w "%{http_code}" \
    -X POST "${FHIR_BASE}" \
    -H "Content-Type: application/fhir+json" \
    -H "Accept: application/fhir+json" \
    --data-binary "@${bundle}")

  if [[ "$HTTP_STATUS" =~ ^2 ]]; then
    echo "    OK (HTTP ${HTTP_STATUS})"
  else
    echo "    ERROR: HTTP ${HTTP_STATUS} for ${name}"
    cat "$WORK_DIR/seed_response.json"
    SEED_FAILED=1
  fi
done

if [ "$SEED_FAILED" -ne 0 ]; then
  echo ""
  echo "ERROR: One or more bundles failed to seed. Check output above."
  exit 1
fi

echo ""
echo "========================================"
echo " Seeding complete!"
echo " FHIR base  : ${FHIR_BASE}"
echo " Tester UI  : http://localhost:8080/"
echo "========================================"
