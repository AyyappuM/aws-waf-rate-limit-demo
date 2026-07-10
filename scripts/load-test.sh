#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <ALB_DNS_NAME> [-n total_requests] [-c concurrency]"
  echo ""
  echo "  ALB_DNS_NAME     DNS name of the ALB (from deploy.sh output)"
  echo "  -n total_requests  Total number of requests to send (default: 500)"
  echo "  -c concurrency      Number of requests in flight at once (default: 20)"
  exit 1
}

if [ $# -lt 1 ]; then
  usage
fi

ALB_DNS_NAME="$1"
shift

TOTAL=500
CONCURRENCY=20

while getopts "n:c:" opt; do
  case "${opt}" in
    n) TOTAL="${OPTARG}" ;;
    c) CONCURRENCY="${OPTARG}" ;;
    *) usage ;;
  esac
done

URL="http://${ALB_DNS_NAME}/hit"
RESULTS_FILE="$(mktemp)"
trap 'rm -f "${RESULTS_FILE}"' EXIT

echo "==> Target: ${URL}"
echo "==> Sending ${TOTAL} requests at concurrency ${CONCURRENCY}"
echo "==> Watch the status codes below: 200 = allowed, 403 = blocked by WAF"
echo ""

seq 1 "${TOTAL}" | xargs -P "${CONCURRENCY}" -I{} curl -s -o /dev/null -w "%{http_code}\n" "${URL}" \
  | tee "${RESULTS_FILE}" \
  | while read -r code; do
      if [ "${code}" = "200" ]; then
        printf "\033[32m%s \033[0m" "${code}"
      elif [ "${code}" = "403" ]; then
        printf "\033[31m%s \033[0m" "${code}"
      else
        printf "\033[33m%s \033[0m" "${code}"
      fi
    done

echo ""
echo ""

TOTAL_SENT="$(wc -l < "${RESULTS_FILE}" | tr -d ' ')"
COUNT_200="$(grep -c '^200$' "${RESULTS_FILE}" || true)"
COUNT_403="$(grep -c '^403$' "${RESULTS_FILE}" || true)"
FIRST_BLOCK_LINE="$(grep -n '^403$' "${RESULTS_FILE}" | head -n 1 | cut -d: -f1 || true)"

echo "==> Summary"
echo "    Total requests sent : ${TOTAL_SENT}"
echo "    200 OK              : ${COUNT_200}"
echo "    403 Blocked (WAF)   : ${COUNT_403}"

if [ -n "${FIRST_BLOCK_LINE}" ]; then
  echo "    First block seen at : request #${FIRST_BLOCK_LINE}"
  echo ""
  echo "==> Rate limiting is working — WAF started blocking once the threshold was crossed."
else
  echo ""
  echo "==> No 403s observed. Troubleshooting tips:"
  echo "    - WAF Web ACL association can take up to ~1 minute to propagate after deploy."
  echo "    - Try increasing concurrency/total requests: $0 ${ALB_DNS_NAME} -n 1000 -c 40"
  echo "    - Check that rate_limit_requests / evaluation_window_sec (03-waf) are low enough to cross quickly."
  exit 1
fi
