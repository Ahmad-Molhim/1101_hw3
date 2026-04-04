#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if ! command -v ncverilog >/dev/null 2>&1; then
  echo "Error: ncverilog not found in PATH. Please load your Cadence environment and try again."
  exit 1
fi

declare -a results=()

echo "Running all testbenches tb0..tb3 in $SCRIPT_DIR"

touch /tmp/$$.dummy >/dev/null 2>&1 || true

for tb in 0 1 2 3; do
  define="tb${tb}"
  log_file="tb${tb}.log"

  echo
  echo "================================================================="
  echo "Running ${define}"
  echo "================================================================="

  if ! ncverilog -f rtl_01.f +notimingchecks +access+r +define+${define} 2>&1 | tee "$log_file"; then
    echo "ncverilog returned a non-zero exit status for ${define}. Continuing to next test."
  fi

  final_line=$(grep -E '^(PASS|FAIL)$' "$log_file" | tail -n 1 || true)

  if [[ "$final_line" == "PASS" ]]; then
    status="PASS"
  elif [[ "$final_line" == "FAIL" ]]; then
    status="FAIL"
  else
    status="UNKNOWN"
  fi

  results+=("${define}:${status}:${log_file}")
  echo "Finished ${define} => ${status}"
  echo "Log: ${log_file}"
done

echo
echo "==================== FINAL SUMMARY ===================="
printf '%-8s %-8s %s\n' "TEST" "STATUS" "LOG"
for entry in "${results[@]}"; do
  IFS=':' read -r test status log <<< "$entry"
  printf '%-8s %-8s %s\n' "$test" "$status" "$log"
done

overall_status="PASS"
for entry in "${results[@]}"; do
  IFS=':' read -r _ status _ <<< "$entry"
  if [[ "$status" == "FAIL" ]]; then
    overall_status="FAIL"
    break
  elif [[ "$status" == "UNKNOWN" && "$overall_status" != "FAIL" ]]; then
    overall_status="UNKNOWN"
  fi
done

echo
if [[ "$overall_status" == "PASS" ]]; then
  echo "All testbenches passed." 
  exit 0
elif [[ "$overall_status" == "FAIL" ]]; then
  echo "One or more testbenches failed." >&2
  exit 2
else
  echo "Some testbenches returned unknown status. Please inspect the log files." >&2
  exit 3
fi
