#!/usr/bin/gawk -f
# Scan a Pyret test file for its check blocks.
#
# Reads the test file on stdin or as an argument and writes one JSON object
# per top-level check block to stdout, for jq --slurpfile:
#
#     {"line":N,"task_id":N,"test_code":"..."}
#
# A block starts at a line beginning in column 0 with `check`, optionally
# followed by a quoted name, and a colon, and ends at the next `end` in
# column 0. `line` is the block's first line, the same number Pyret reports
# in the block's location, so the runner can join the two.
#
# `test_code` is the block body with the indentation shared by every line
# removed and blank lines at either end dropped. A body line holding only
# a comment of the form `## task N` links the block to task N of a concept
# exercise; it sets `task_id` and is left out of `test_code`. Blocks with
# no such comment have no `task_id` key.
#
# Run under LC_ALL=C: bytes are copied through untouched, whatever encoding
# the file uses.

BEGIN {
    in_block = 0
    for (b = 0; b < 256; b++) {
        BYTE[sprintf("%c", b)] = b
    }
}

function json_string(s,        out, pos, c, code) {
    out = "\""
    for (pos = 1; pos <= length(s); pos++) {
        c = substr(s, pos, 1)
        code = BYTE[c]
        if      (c == "\"" || c == "\\") out = out "\\" c
        else if (c == "\n")              out = out "\\n"
        else if (c == "\r")              out = out "\\r"
        else if (c == "\t")              out = out "\\t"
        else if (code < 32)              out = out sprintf("\\u%04x", code)
        else                             out = out c
    }
    return out "\""
}

# Width of the leading whitespace of a line.
function indent_of(s,        m) {
    match(s, /^[ \t]*/)
    return RLENGTH
}

function emit_block(        first, last, i, indent, width, code) {
    # Drop blank lines at either end of the body.
    first = 1
    last = n_body
    while (first <= last && body[first] ~ /^[ \t]*$/) first++
    while (last >= first && body[last] ~ /^[ \t]*$/) last--

    # Remove the indentation every non-blank line shares.
    indent = -1
    for (i = first; i <= last; i++) {
        if (body[i] ~ /^[ \t]*$/) continue
        width = indent_of(body[i])
        if (indent < 0 || width < indent) indent = width
    }
    if (indent < 0) indent = 0

    code = ""
    for (i = first; i <= last; i++) {
        if (i > first) code = code "\n"
        code = code substr(body[i], indent + 1)
    }

    printf "{\"line\":%d", start_line
    if (task_id != "") printf ",\"task_id\":%d", task_id
    printf ",\"test_code\":%s}\n", json_string(code)
}

!in_block && /^check([ \t]+("[^"]*"|'[^']*'))?[ \t]*:/ {
    in_block = 1
    start_line = NR
    task_id = ""
    n_body = 0
    delete body
    next
}

in_block && /^end([ \t]|$)/ {
    emit_block()
    in_block = 0
    next
}

in_block && /^[ \t]*##[ \t]*task[ \t]+[0-9]+[ \t]*$/ {
    match($0, /[0-9]+/)
    task_id = substr($0, RSTART, RLENGTH)
    next
}

in_block {
    line = $0
    sub(/[ \t\r]+$/, "", line)
    body[++n_body] = line
}
