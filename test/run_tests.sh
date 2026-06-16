#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS  $desc"; ((PASS++))
  else
    echo "  FAIL  $desc"
    echo "        expected: $expected"
    echo "        actual:   $actual"; ((FAIL++))
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS  $desc"; ((PASS++))
  else
    echo "  FAIL  $desc"
    echo "        expected to contain: $needle"; ((FAIL++))
  fi
}

echo "=== Parser Unit Tests ==="
echo ""

PARSER_DIR="$(dirname "$0")/parser"
cd "$PARSER_DIR"

# --- Apply once, dump all outputs to a JSON file ---
tofu apply -auto-approve -input=false 2>/dev/null
tofu output -json > /tmp/parser_outputs.json 2>/dev/null

jq_test() { jq -r "$1" /tmp/parser_outputs.json; }

echo "--- Valid fixture parsing ---"

# Entry counts
assert_eq "5 FQDN entries" "5" "$(jq_test '.fqdn_entries.value | length')"
assert_eq "6 CIDR entries" "6" "$(jq_test '.cidr_entries.value | length')"

# No invalid lines
assert_eq "no invalid FQDN lines" "[]" "$(jq_test '.fqdn_invalid_lines.value')"
assert_eq "no invalid CIDR lines" "[]" "$(jq_test '.cidr_invalid_lines.value')"

# Port spec expansion: * → 0-65535
jq_test '.fqdn_groups.value' | grep -q '"0-65535"' \
  && { echo "  PASS  * expands to 0-65535"; ((PASS++)); } \
  || { echo "  FAIL  * expands to 0-65535"; ((FAIL++)); }

# Comma split: 80,443 → individual ports
jq_test '.fqdn_groups.value' | grep -q '"80"' \
  && { echo "  PASS  80,443 splits to individual ports"; ((PASS++)); } \
  || { echo "  FAIL  80,443 splits to individual ports"; ((FAIL++)); }

# Range preserved: 8080-8090
jq_test '.fqdn_groups.value' | grep -q '"8080-8090"' \
  && { echo "  PASS  range 8080-8090 preserved"; ((PASS++)); } \
  || { echo "  FAIL  range 8080-8090 preserved"; ((FAIL++)); }

# CIDR exclusions
jq -c '.cidr_entries.value' /tmp/parser_outputs.json | grep -q '"deny":true,"ports":"\*","value":"10.1.0.0/16"' \
  && { echo "  PASS  10.1.0.0/16 is deny"; ((PASS++)); } \
  || { echo "  FAIL  10.1.0.0/16 is deny"; ((FAIL++)); }

jq -c '.cidr_entries.value' /tmp/parser_outputs.json | grep -q '"deny":false,"ports":"\*","value":"10.0.0.0/8"' \
  && { echo "  PASS  10.0.0.0/8 is allow"; ((PASS++)); } \
  || { echo "  FAIL  10.0.0.0/8 is allow"; ((FAIL++)); }

# Priority ranges
jq -c '.cidr_deny_groups.value' /tmp/parser_outputs.json | grep -q '"priority":2000' \
  && { echo "  PASS  deny groups at priority 2000+"; ((PASS++)); } \
  || { echo "  FAIL  deny groups at priority 2000+"; ((FAIL++)); }

jq -c '.cidr_allow_groups.value' /tmp/parser_outputs.json | grep -q '"priority":2100' \
  && { echo "  PASS  allow groups at priority 2100+"; ((PASS++)); } \
  || { echo "  FAIL  allow groups at priority 2100+"; ((FAIL++)); }

# Rule count = groups + deny + allow + 7 infra
NGROUPS=$(jq_test '.fqdn_group_count.value')
NDENY=$(jq_test '.cidr_deny_group_count.value')
NALLOW=$(jq_test '.cidr_allow_group_count.value')
TOTAL=$(jq_test '.total_rule_count.value')
EXPECTED=$((NGROUPS + NDENY + NALLOW + 7))
assert_eq "rule count = groups + 7 infra" "$EXPECTED" "$TOTAL"

# --- Negative test: invalid fixture should fail plan ---
echo ""
echo "--- Invalid fixture detection ---"

cp fixtures/hosts.txt fixtures/hosts.txt.bak
cp fixtures/hosts-invalid.txt fixtures/hosts.txt

PLAN_OUTPUT=$(tofu plan -input=false 2>&1 || true)
mv fixtures/hosts.txt.bak fixtures/hosts.txt

echo "$PLAN_OUTPUT" | grep -q "Check block assertion failed" \
  && { echo "  PASS  invalid line detected by check block"; ((PASS++)); } \
  || { echo "  FAIL  invalid line not detected"; ((FAIL++)); }

echo "$PLAN_OUTPUT" | grep -q "bad.example.com" \
  && { echo "  PASS  error names the offending line"; ((PASS++)); } \
  || { echo "  FAIL  error doesn't name the offending line"; ((FAIL++)); }

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
rm -f /tmp/parser_outputs.json
exit $FAIL
