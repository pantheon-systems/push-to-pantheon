#!/usr/bin/env bats
# Tests for scripts/generate-readme-docs.sh

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
    SCRIPT="${REPO_ROOT}/scripts/generate-readme-docs.sh"
    TMP="$(mktemp -d)"

    cat > "${TMP}/action.yml" <<'EOF'
name: Test
inputs:
  zeta:
    description: 'Last input'
    required: true
  alpha:
    description: "Has a pipe | and
      a second line"
    required: false
    default: "yes"
outputs:
  result:
    description: 'The result'
EOF

    cat > "${TMP}/readme.md" <<'EOF'
# Title

Intro text.

<!-- AUTO-DOC-INPUT:START - Do not remove or modify this section -->
stale input content
<!-- AUTO-DOC-INPUT:END -->

Middle text.

<!-- AUTO-DOC-OUTPUT:START - Do not remove or modify this section -->
stale output content
<!-- AUTO-DOC-OUTPUT:END -->

Footer.
EOF
}

teardown() {
    rm -rf "${TMP}"
}

@test "replaces stale content and sorts inputs by name" {
    run "${SCRIPT}" "${TMP}/action.yml" "${TMP}/readme.md"
    [ "${status}" -eq 0 ]
    ! grep -q "stale" "${TMP}/readme.md"
    alpha_line="$(grep -n 'input_alpha"' "${TMP}/readme.md" | head -1 | cut -d: -f1)"
    zeta_line="$(grep -n 'input_zeta"' "${TMP}/readme.md" | head -1 | cut -d: -f1)"
    [ "${alpha_line}" -lt "${zeta_line}" ]
}

@test "renders required, default, escaped pipes and collapsed newlines" {
    "${SCRIPT}" "${TMP}/action.yml" "${TMP}/readme.md"
    grep -qF '| string | false | `"yes"` | Has a pipe \| and a second line |' "${TMP}/readme.md"
    grep -qF '| string | true |  | Last input |' "${TMP}/readme.md"
}

@test "renders outputs table" {
    "${SCRIPT}" "${TMP}/action.yml" "${TMP}/readme.md"
    grep -qF '[result](#output_result) | string | The result |' "${TMP}/readme.md"
}

@test "leaves content outside the markers untouched" {
    "${SCRIPT}" "${TMP}/action.yml" "${TMP}/readme.md"
    grep -qx "Intro text." "${TMP}/readme.md"
    grep -qx "Middle text." "${TMP}/readme.md"
    grep -qx "Footer." "${TMP}/readme.md"
}

@test "is idempotent" {
    "${SCRIPT}" "${TMP}/action.yml" "${TMP}/readme.md"
    cp "${TMP}/readme.md" "${TMP}/first.md"
    "${SCRIPT}" "${TMP}/action.yml" "${TMP}/readme.md"
    cmp "${TMP}/first.md" "${TMP}/readme.md"
}

@test "fails when markers are missing" {
    echo "no markers here" > "${TMP}/readme.md"
    run "${SCRIPT}" "${TMP}/action.yml" "${TMP}/readme.md"
    [ "${status}" -ne 0 ]
    [[ "${output}" == *"Missing AUTO-DOC-INPUT"* ]]
}
