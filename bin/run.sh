#!/usr/bin/env bash

# Synopsis:
# Run the test runner on a solution.

# Arguments:
# $1: exercise slug
# $2: path to solution folder
# $3: path to output directory

# Output:
# Writes the test results to a results.json file in the passed-in output
# directory. The test results are formatted according to the specifications at
# https://github.com/exercism/docs/blob/main/building/tooling/test-runners/interface.md

# Example:
# ./bin/run.sh two-fer path/to/solution/folder/ path/to/output/directory/

set -uo pipefail

# The platform reads results.json as an unprivileged user; this script runs
# as root in the container. Nothing here may create root-only files.
umask 022

# Cap on the top-level message field of results.json; the interface allows
# 65535 characters.
: "${MAX_MESSAGE_BYTES:=65535}"

runner_dir=$(dirname "$(realpath "$0")")
scan_tests="${runner_dir}/scan-tests.awk"

usage() {
    echo "usage: $0 exercise-slug path/to/solution/folder/ path/to/output/directory/" >&2
    exit 1
}

[[ -z "${1:-}" || -z "${2:-}" || -z "${3:-}" ]] && usage

slug="$1"
solution_dir=$(realpath "${2%/}")
output_dir=$(realpath "${3%/}")

[[ -d "${solution_dir}" ]] || usage
mkdir -p "${output_dir}"

results_file="${output_dir}/results.json"
test_file="${slug}-test.arr"

# Assigned before use so the trap can always expand it.
work_dir=""
trap 'rm -rf "${work_dir}"' EXIT

# A fault in the runner itself is still reported through results.json when
# possible: an empty output directory tells the platform nothing.
die() {
    echo "$*" >&2
    if [[ -n "${work_dir}" ]]; then
        printf '%s\n' "$*" > "${work_dir}/died"
        finish_with error "${work_dir}/died"
    fi
    exit 1
}

# capped <file>: copy at most MAX_MESSAGE_BYTES of a capture to stdout,
# noting the cut. Callers redirect this into a file, which is what jq's
# --rawfile reads to build the message.
capped() {
    local file="$1"
    head -c "${MAX_MESSAGE_BYTES}" "${file}"
    if (( $(wc -c < "${file}") > MAX_MESSAGE_BYTES )); then
        printf '\n[output truncated]'
    fi
}

# sanitize <file>: Pyret's diagnostics, made fit for a student, on stdout.
# Paths lose the staging directory, so a location reads "two-fer.arr:3:1";
# the two parser lines that differ between platforms are dropped, as is
# trailing whitespace.
sanitize() {
    local file="$1"
    sed -E \
        -e "s#file://${stage_dir}/##g" \
        -e '/^There were [0-9]+ potential parses\.$/d' \
        -e '/^Parse failed, next token is /d' \
        -e 's/[[:space:]]+$//' \
        "${file}"
}

# finish_with <pass|fail|error> <message-file>: results.json without
# per-test entries, for everything that stops before tests can be reported.
finish_with() {
    local status="$1" message_file="$2"
    if ! grep -q '[^[:space:]]' "${message_file}" 2>/dev/null; then
        printf 'the test run produced no output\n' > "${message_file}"
    fi
    capped "${message_file}" > "${message_file}.capped"
    jq -n --arg status "${status}" --rawfile message "${message_file}.capped" \
        '{version: 3, status: $status,
          message: ($message | sub("^\n+"; "") | sub("\n+$"; ""))}' \
        > "${results_file}"
    echo "${slug}: done"
}

main() {
    [[ -f "${scan_tests}" ]] || die "missing ${scan_tests}"
    work_dir=$(mktemp -d) || die "cannot create a work directory"

    echo "${slug}: testing..."

    # Work on a copy: pyret writes a .pyret cache directory and the compiled
    # .jarr next to the program, and the student's directory is not ours to
    # build in.
    stage_dir="${work_dir}/solution"
    mkdir "${stage_dir}" || die "cannot create the staging directory"
    cp -r "${solution_dir}/." "${stage_dir}" || die "cannot stage the solution"

    if [[ ! -f "${stage_dir}/${test_file}" ]]; then
        printf 'no test file found (expected %s)\n' "${test_file}" \
            > "${work_dir}/message"
        finish_with error "${work_dir}/message"
        return 0
    fi

    # --checks main runs only the test file's check blocks, so a student's
    # own where: blocks cannot alter the result. --checks-format json makes
    # Pyret print one JSON object describing every block as the last line
    # of stdout. The streams stay apart: Pyret has been seen to hang more
    # often with stderr redirected into stdout.
    (
        cd "${stage_dir}" || exit 1
        pyret -q --checks main --checks-format json "${test_file}" \
            > "${work_dir}/stdout" 2> "${work_dir}/stderr"
    )

    # Anything the solution prints lands on stdout ahead of the JSON, on the
    # same line if it did not end with a newline. The JSON opens with the
    # test file's URI, which includes the random name of the work directory,
    # so a solution cannot print a convincing forgery.
    local marker="{\"file://${stage_dir}/${test_file}\":"
    local last_line checks=""
    last_line=$(tail -n 1 "${work_dir}/stdout")
    if [[ "${last_line}" == *"${marker}"* ]]; then
        checks="${marker}${last_line#*"${marker}"}"
        jq -e . <<< "${checks}" > /dev/null 2>&1 || checks=""
    fi
    # Through a file, not an argument: every block carries the report so
    # far, so the JSON grows with the square of the block count and a long
    # test file overflows the argument list.
    printf '%s\n' "${checks}" > "${work_dir}/checks.json"

    if [[ -z "${checks}" ]]; then
        # Nothing ran to completion: a parse or compile error, a solution
        # that raised while loading, or a test file without a single check
        # block. Pyret's explanation is on stderr.
        if grep -q '[^[:space:]]' "${work_dir}/stderr"; then
            sanitize "${work_dir}/stderr" > "${work_dir}/message"
        elif [[ "${last_line}" == "{}" ]]; then
            printf 'no check blocks were run\n' > "${work_dir}/message"
        else
            sanitize "${work_dir}/stdout" > "${work_dir}/message"
        fi
        finish_with error "${work_dir}/message"
        return 0
    fi

    # Each block's source and task id, keyed by the block's first line.
    LC_ALL=C gawk -f "${scan_tests}" "${stage_dir}/${test_file}" \
        > "${work_dir}/blocks.jsonl" || die "cannot scan the test file"

    # Pyret lists blocks, and the results within a block, last first; the
    # interface wants test-file order. The location string gives the line.
    jq -n \
        --slurpfile checks "${work_dir}/checks.json" \
        --arg uri "file://${stage_dir}/${test_file}" \
        --arg prefix "file://${stage_dir}/" \
        --slurpfile blocks "${work_dir}/blocks.jsonl" \
        '
        def start_line:
            .loc | capture(":(?<line>[0-9]+):[0-9]+-[0-9]+:[0-9]+$")
            | .line | tonumber;
        def clean:
            split($prefix) | join("")
            | gsub("[ \t]+\n"; "\n") | gsub("\n{3,}"; "\n\n")
            | sub("^[ \t\n]+"; "") | sub("[ \t\n]+$"; "");
        def outcome:
            if (.errored | type) == "string" then
                {status: "error", message: (.errored | clean)}
            elif .failed > 0 then
                {status: "fail",
                 message: (.results | sort_by(start_line)
                           | map(select(.passed | not) | .message | clean)
                           | join("\n\n"))}
            else
                {status: "pass"}
            end;
        ($blocks | map({key: (.line | tostring), value: .}) | from_entries)
            as $source
        | ($checks[0][$uri] // [] | sort_by(start_line)
           | map(($source[start_line | tostring] // {}) as $src
                 | {name}
                   + outcome
                   + (if $src.test_code != null
                      then {test_code: $src.test_code} else {} end)
                   + (if $src.task_id != null
                      then {task_id: $src.task_id} else {} end)))
            as $tests
        | {version: 3,
           status: (if all($tests[]; .status == "pass") then "pass"
                    else "fail" end),
           tests: $tests}
        ' > "${results_file}" || die "cannot encode the test results"
    echo "${slug}: done"
}

main "$@"
