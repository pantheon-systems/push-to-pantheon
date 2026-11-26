#!/usr/bin/env bash
#
# Regenerates the Inputs and Outputs tables in readme.md from action.yml.
#
# Replaces the content between the AUTO-DOC-INPUT and AUTO-DOC-OUTPUT marker
# comments. Everything outside the markers is left untouched.
#
# Usage: scripts/generate-readme-docs.sh [action.yml] [readme.md]
#
# Requires: yq (https://github.com/mikefarah/yq) v4+

set -euo pipefail

ACTION_FILE="${1:-action.yml}"
README_FILE="${2:-readme.md}"

# Render a markdown table for the given top-level key ("inputs" or "outputs").
# Rows are sorted by name. Descriptions have newlines collapsed and pipes
# escaped so they cannot break the table.
render_table() {
    local key="$1" singular="$2" header

    if [[ "${key}" == "inputs" ]]; then
        header="| INPUT | TYPE | REQUIRED | DEFAULT | DESCRIPTION |"$'\n'"|---|---|---|---|---|"
    else
        header="| OUTPUT | TYPE | DESCRIPTION |"$'\n'"|---|---|---|"
    fi

    printf '%s\n' "${header}"

    # These are yq expressions, not shell: single quotes are intentional.
    # shellcheck disable=SC2016
    local description='((.value.description // "") | sub("\s*\n\s*"; " ") | sub("\s+$"; "") | sub("\|"; "\|"))'
    local name='"<a name=\"'"${singular}"'_" + .key + "\"></a>[" + .key + "](#'"${singular}"'_" + .key + ")"'
    local row
    if [[ "${key}" == "inputs" ]]; then
        # shellcheck disable=SC2016
        local default='(select(.value | has("default")) | .value.default | tostring | select(. != "") | "`\"" + . + "\"`") // ""'
        row="\"| \" + ${name} + \" | string | \" + ((.value.required // false) | tostring) + \" | \" + (${default}) + \" | \" + ${description} + \" |\""
    else
        row="\"| \" + ${name} + \" | string | \" + ${description} + \" |\""
    fi

    yq -r ".${key} // {} | to_entries | sort_by(.key) | .[] | ${row}" "${ACTION_FILE}"
}

# Replace the lines between START and END markers (exclusive) in the readme
# with the content of the given file.
replace_block() {
    local marker="$1" content_file="$2" tmp
    tmp="$(mktemp)"

    awk -v marker="${marker}" -v content_file="${content_file}" '
        index($0, "<!-- " marker ":START") == 1 {
            print
            print ""
            while ((getline line < content_file) > 0) print line
            print ""
            skipping = 1
            next
        }
        index($0, "<!-- " marker ":END") == 1 { skipping = 0 }
        !skipping { print }
    ' "${README_FILE}" > "${tmp}"

    cat "${tmp}" > "${README_FILE}"
    rm -f "${tmp}"
}

main() {
    # Not local: the EXIT trap runs after main returns.
    inputs_file="$(mktemp)"
    outputs_file="$(mktemp)"
    trap 'rm -f "${inputs_file}" "${outputs_file}"' EXIT

    for marker in AUTO-DOC-INPUT AUTO-DOC-OUTPUT; do
        if ! grep -q "<!-- ${marker}:START" "${README_FILE}" || ! grep -q "<!-- ${marker}:END" "${README_FILE}"; then
            echo "Missing ${marker} START/END markers in ${README_FILE}" >&2
            exit 1
        fi
    done

    render_table inputs input > "${inputs_file}"
    render_table outputs output > "${outputs_file}"

    replace_block AUTO-DOC-INPUT "${inputs_file}"
    replace_block AUTO-DOC-OUTPUT "${outputs_file}"
}

main "$@"
