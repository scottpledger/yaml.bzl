"Iterative YAML parsing/serialization helpers."

NODE_DOCUMENT = "document"

ERROR_SYNTAX = "syntax_error"
ERROR_INDENTATION = "indentation_error"
ERROR_UNKNOWN_ALIAS = "unknown_alias"
ERROR_DUPLICATE_KEY = "duplicate_key"
_INTERNAL_MERGE_KEY = "__yaml_internal_merge_key__"

def _make_error(error_type, message, line = None):
    return struct(type = error_type, message = message, line = line)

def _set_mapping_value(mapping, key, value, errors, line_no, allow_override = False):
    if (not allow_override) and key in mapping:
        errors.append(_make_error(
            ERROR_DUPLICATE_KEY,
            "Duplicate mapping key '%s'" % str(key),
            line = line_no,
        ))
        return False
    mapping[key] = value
    return True

def _append_merge_source(mapping, value):
    if _INTERNAL_MERGE_KEY not in mapping:
        mapping[_INTERNAL_MERGE_KEY] = [value]
    else:
        mapping[_INTERNAL_MERGE_KEY].append(value)

def _check_frame_entry_indent(frame, indent, errors, line_no):
    key = "entry_indent" if frame["kind"] == "map" else "item_indent"
    expected = frame.get(key, None)
    if expected == None:
        frame[key] = indent
        return True
    if indent != expected:
        errors.append(_make_error(
            ERROR_INDENTATION,
            "Inconsistent indentation for %s entries: expected %d spaces, got %d" % (
                frame["kind"],
                expected,
                indent,
            ),
            line = line_no,
        ))
        return False
    return True

def _is_plain_merge_key_token(raw_key_text):
    s = raw_key_text.strip()
    return s == "<<"

def _count_indent(raw_line, errors = None, line_no = None):
    indent = 0
    for i in range(len(raw_line)):
        ch = raw_line[i]
        if ch == " ":
            indent += 1
        elif ch == "\t":
            if errors != None:
                errors.append(_make_error(
                    ERROR_INDENTATION,
                    "Tabs are not supported for indentation",
                    line = line_no,
                ))
            indent += 1
        else:
            break
    return indent

def _strip_comment(text):
    in_single = False
    in_double = False
    escaped = False
    for i in range(len(text)):
        ch = text[i]
        if escaped:
            escaped = False
            continue
        if in_double and ch == "\\":
            escaped = True
            continue
        if ch == "'" and not in_double:
            in_single = not in_single
            continue
        if ch == '"' and not in_single:
            in_double = not in_double
            continue
        if ch == "#" and not in_single and not in_double:
            if i == 0 or text[i - 1] in [" ", "\t"]:
                return text[:i].rstrip()
    return text.rstrip()

def _find_top_level_colon(text):
    in_single = False
    in_double = False
    escaped = False
    braces = 0
    brackets = 0
    for i in range(len(text)):
        ch = text[i]
        if escaped:
            escaped = False
            continue
        if in_double and ch == "\\":
            escaped = True
            continue
        if ch == "'" and not in_double:
            in_single = not in_single
            continue
        if ch == '"' and not in_single:
            in_double = not in_double
            continue
        if in_single or in_double:
            continue
        if ch == "{":
            braces += 1
        elif ch == "}":
            braces -= 1
        elif ch == "[":
            brackets += 1
        elif ch == "]":
            brackets -= 1
        elif ch == ":" and braces == 0 and brackets == 0:
            if i + 1 == len(text) or text[i + 1] in [" ", "\t"]:
                return i
    return -1

def _split_key_value(text):
    c = _find_top_level_colon(text)
    if c < 0:
        return (None, None, False)
    return (text[:c].strip(), text[c + 1:].strip(), True)

def _hex_value(ch):
    digits = "0123456789abcdef"
    pos = digits.find(ch.lower())
    return pos if pos >= 0 else None

def _parse_hex_digits(text):
    total = 0
    for i in range(len(text)):
        value = _hex_value(text[i])
        if value == None:
            return None
        total = total * 16 + value
    return total

def _to_hex_fixed(value, width):
    digits = "0123456789abcdef"
    n = value
    out = []
    for _ in range(width):
        out.append(digits[n % 16])
        n = n // 16
    out = out[::-1]
    return "".join(out)

def _codepoint_to_string(codepoint):
    if codepoint < 0 or codepoint > 0x10ffff:
        return None
    if codepoint <= 0xffff:
        return json.decode('"\\u%s"' % _to_hex_fixed(codepoint, 4))

    # Convert to UTF-16 surrogate pair for JSON decoding.
    cp = codepoint - 0x10000
    high = 0xd800 + (cp // 0x400)
    low = 0xdc00 + (cp % 0x400)
    return json.decode('"\\u%s\\u%s"' % (_to_hex_fixed(high, 4), _to_hex_fixed(low, 4)))

def _unescape_double_quoted(text, errors = None, line_no = None):
    out = []
    i = 0
    escape_map = {
        "0": "\0",
        "a": "\a",
        "b": "\b",
        "t": "\t",
        "n": "\n",
        "v": "\v",
        "f": "\f",
        "r": "\r",
        " ": " ",
        '"': '"',
        "/": "/",
        "\\": "\\",
    }
    for _ in range(len(text) + 1):
        if i >= len(text):
            break
        ch = text[i]
        if ch != "\\" or i + 1 >= len(text):
            out.append(ch)
            i += 1
            continue
        nxt = text[i + 1]
        if nxt in escape_map:
            out.append(escape_map[nxt])
        elif nxt == "e":
            out.append(_codepoint_to_string(0x1b))
        elif nxt in ["x", "u", "U"]:
            width = 2 if nxt == "x" else (4 if nxt == "u" else 8)
            if i + 1 + width >= len(text):
                if errors != None:
                    errors.append(_make_error(
                        ERROR_SYNTAX,
                        "Truncated unicode escape '\\%s' in double-quoted scalar" % nxt,
                        line = line_no,
                    ))
                out.append("\\" + nxt)
                i += 2
                continue

            digits = text[i + 2:i + 2 + width]
            parsed = _parse_hex_digits(digits)
            if parsed == None:
                if errors != None:
                    errors.append(_make_error(
                        ERROR_SYNTAX,
                        "Invalid unicode escape '\\%s%s' in double-quoted scalar" % (nxt, digits),
                        line = line_no,
                    ))
                out.append("\\" + nxt + digits)
                i += 2 + width
                continue

            converted = _codepoint_to_string(parsed if nxt != "x" else parsed)
            if converted == None:
                if errors != None:
                    errors.append(_make_error(
                        ERROR_SYNTAX,
                        "Unicode codepoint out of range in '\\%s%s'" % (nxt, digits),
                        line = line_no,
                    ))
                out.append("\\" + nxt + digits)
                i += 2 + width
                continue
            out.append(converted)
            i += 2 + width
            continue
        else:
            if errors != None:
                errors.append(_make_error(
                    ERROR_SYNTAX,
                    "Unknown escape sequence '\\%s' in double-quoted scalar" % nxt,
                    line = line_no,
                ))
            out.append("\\" + nxt)
        i += 2
    return "".join(out)

def _is_quoted_scalar(text):
    return (
        (len(text) >= 2 and text[0] == '"' and text[-1] == '"') or
        (len(text) >= 2 and text[0] == "'" and text[-1] == "'")
    )

def _is_valid_flow_plain_scalar(token):
    if token == "":
        return False
    if _is_quoted_scalar(token):
        return True
    if token.startswith("?") or token.startswith(":"):
        return False
    in_single = False
    in_double = False
    escaped = False
    for i in range(len(token)):
        ch = token[i]
        if escaped:
            escaped = False
            continue
        if in_double and ch == "\\":
            escaped = True
            continue
        if ch == "'" and not in_double:
            in_single = not in_single
            continue
        if ch == '"' and not in_single:
            in_double = not in_double
            continue
        if in_single or in_double:
            continue
        if ch in ["[", "]", "{", "}", ","]:
            return False
        if ch == ":" and (i + 1 == len(token) or _is_space(token[i + 1])):
            return False
        if ch == "#" and (i == 0 or _is_space(token[i - 1])):
            return False
    return True

def _is_space(ch):
    return ch in [" ", "\t", "\n", "\r"]

def _skip_spaces(text, i):
    pos = i
    for _ in range(len(text) + 1):
        if pos >= len(text) or not _is_space(text[pos]):
            break
        pos += 1
    return pos

def _read_flow_token(text, start, stop_chars):
    i = start
    in_single = False
    in_double = False
    escaped = False
    for _ in range(len(text) + 1):
        if i >= len(text):
            break
        ch = text[i]
        if escaped:
            escaped = False
            i += 1
            continue
        if in_double and ch == "\\":
            escaped = True
            i += 1
            continue
        if ch == "'" and not in_double:
            in_single = not in_single
            i += 1
            continue
        if ch == '"' and not in_single:
            in_double = not in_double
            i += 1
            continue
        if not in_single and not in_double and ch in stop_chars:
            break
        i += 1
    return (text[start:i].strip(), i)

def _parse_flow_token_value(token, anchors, errors, line_no = None):
    key, value, is_pair = _split_key_value(token)
    if is_pair:
        result = {}
        parsed_key = _to_hashable_key(_parse_nonflow_scalar(key.strip(), anchors, errors, line_no = line_no))
        parsed_value = _parse_nonflow_scalar(value.strip(), anchors, errors, line_no = line_no)
        _set_mapping_value(result, parsed_key, parsed_value, errors, line_no)
        return result
    if not _is_valid_flow_plain_scalar(token):
        errors.append(_make_error(
            ERROR_SYNTAX,
            "Invalid plain scalar in flow context: '%s'" % token,
            line = line_no,
        ))
    return _parse_nonflow_scalar(token, anchors, errors, line_no = line_no)

def _parse_flow_collection(text, anchors, errors, line_no = None):
    s = text.strip()
    if not s or s[0] not in ["[", "{"]:
        return (None, False)

    stack = []

    # frame: kind(seq/map), value, expect, pending_key
    root_kind = "seq" if s[0] == "[" else "map"
    root_close = "]" if root_kind == "seq" else "}"
    root_value = [] if root_kind == "seq" else {}
    stack.append(struct(
        kind = root_kind,
        close = root_close,
        value = root_value,
        expect = "value_or_end" if root_kind == "seq" else "key_or_end",
        pending_key = None,
    ))
    i = 1

    def _frame_with(frame, expect = None, pending_key = None):
        return struct(
            kind = frame.kind,
            close = frame.close,
            value = frame.value,
            expect = frame.expect if expect == None else expect,
            pending_key = frame.pending_key if pending_key == None else pending_key,
        )

    def _push_value(value):
        if not stack:
            return
        top = stack[-1]
        if top.kind == "seq":
            if top.expect != "value_or_end":
                errors.append(_make_error(ERROR_SYNTAX, "Unexpected sequence value in flow collection", line = line_no))
                return
            top.value.append(value)
            stack[-1] = _frame_with(top, expect = "comma_or_end")
            return

        # map
        if top.expect != "value":
            errors.append(_make_error(ERROR_SYNTAX, "Unexpected mapping value in flow collection", line = line_no))
            return
        _set_mapping_value(top.value, top.pending_key, value, errors, line_no)
        stack[-1] = _frame_with(top, expect = "comma_or_end", pending_key = None)

    for _ in range(len(s) * 4 + 1):
        if not stack:
            break
        i = _skip_spaces(s, i)
        if i >= len(s):
            errors.append(_make_error(ERROR_SYNTAX, "Unterminated flow collection", line = line_no))
            return (None, True)

        top = stack[-1]
        ch = s[i]

        if top.kind == "seq":
            if top.expect == "value_or_end":
                if ch == top.close:
                    completed = top.value
                    stack = stack[:-1]
                    i += 1
                    if not stack:
                        i = _skip_spaces(s, i)
                        if i != len(s):
                            errors.append(_make_error(ERROR_SYNTAX, "Trailing content after flow collection", line = line_no))
                            return (None, True)
                        return (completed, True)
                    _push_value(completed)
                    continue
                if ch == "[" or ch == "{":
                    kind = "seq" if ch == "[" else "map"
                    stack.append(struct(
                        kind = kind,
                        close = "]" if kind == "seq" else "}",
                        value = [] if kind == "seq" else {},
                        expect = "value_or_end" if kind == "seq" else "key_or_end",
                        pending_key = None,
                    ))
                    i += 1
                    continue
                token, token_end = _read_flow_token(s, i, [",", top.close])
                if token == "":
                    errors.append(_make_error(ERROR_SYNTAX, "Expected sequence value in flow collection", line = line_no))
                    return (None, True)
                _push_value(_parse_flow_token_value(token, anchors, errors, line_no = line_no))
                i = token_end
                continue

            # comma_or_end
            if ch == ",":
                stack[-1] = _frame_with(top, expect = "value_or_end")
                i += 1
                continue
            if ch == top.close:
                completed = top.value
                stack = stack[:-1]
                i += 1
                if not stack:
                    i = _skip_spaces(s, i)
                    if i != len(s):
                        errors.append(_make_error(ERROR_SYNTAX, "Trailing content after flow collection", line = line_no))
                        return (None, True)
                    return (completed, True)
                _push_value(completed)
                continue
            errors.append(_make_error(ERROR_SYNTAX, "Expected ',' or closing bracket in flow sequence", line = line_no))
            return (None, True)

        # map
        if top.expect == "key_or_end":
            if ch == top.close:
                completed = top.value
                stack = stack[:-1]
                i += 1
                if not stack:
                    i = _skip_spaces(s, i)
                    if i != len(s):
                        errors.append(_make_error(ERROR_SYNTAX, "Trailing content after flow collection", line = line_no))
                        return (None, True)
                    return (completed, True)
                _push_value(completed)
                continue
            token, token_end = _read_flow_token(s, i, [":", top.close, ","])
            if token == "":
                errors.append(_make_error(ERROR_SYNTAX, "Expected mapping key in flow collection", line = line_no))
                return (None, True)
            key = _to_hashable_key(_parse_nonflow_scalar(token, anchors, errors, line_no = line_no))
            i = _skip_spaces(s, token_end)
            if i >= len(s) or s[i] != ":":
                errors.append(_make_error(ERROR_SYNTAX, "Expected ':' after mapping key in flow collection", line = line_no))
                return (None, True)
            stack[-1] = _frame_with(top, expect = "value", pending_key = key)
            i += 1
            continue
        if top.expect == "value":
            i = _skip_spaces(s, i)
            if i >= len(s):
                errors.append(_make_error(ERROR_SYNTAX, "Expected mapping value in flow collection", line = line_no))
                return (None, True)
            ch = s[i]
            if ch == "[" or ch == "{":
                kind = "seq" if ch == "[" else "map"
                stack.append(struct(
                    kind = kind,
                    close = "]" if kind == "seq" else "}",
                    value = [] if kind == "seq" else {},
                    expect = "value_or_end" if kind == "seq" else "key_or_end",
                    pending_key = None,
                ))
                i += 1
                continue
            token, token_end = _read_flow_token(s, i, [",", top.close])
            if token == "":
                errors.append(_make_error(ERROR_SYNTAX, "Expected mapping value in flow collection", line = line_no))
                return (None, True)
            _push_value(_parse_flow_token_value(token, anchors, errors, line_no = line_no))
            i = token_end
            continue

        # comma_or_end
        if ch == ",":
            stack[-1] = _frame_with(top, expect = "key_or_end")
            i += 1
            continue
        if ch == top.close:
            completed = top.value
            stack = stack[:-1]
            i += 1
            if not stack:
                i = _skip_spaces(s, i)
                if i != len(s):
                    errors.append(_make_error(ERROR_SYNTAX, "Trailing content after flow collection", line = line_no))
                    return (None, True)
                return (completed, True)
            _push_value(completed)
            continue
        errors.append(_make_error(ERROR_SYNTAX, "Expected ',' or closing brace in flow mapping", line = line_no))
        return (None, True)

    if stack:
        errors.append(_make_error(ERROR_SYNTAX, "Unterminated flow collection", line = line_no))
        return (None, True)
    return (None, True)

def _clone_value(value):
    t = type(value)
    if t == "list":
        return [v for v in value]
    if t == "dict":
        return dict(value)
    return value

def _parse_based_int(text, base):
    digits = "0123456789abcdef"
    sign = 1
    s = text.lower()
    if s.startswith("-"):
        sign = -1
        s = s[1:]
    elif s.startswith("+"):
        s = s[1:]

    if base == 16:
        s = s[2:]
    elif base == 8:
        s = s[2:]

    if s == "":
        return None

    # YAML numeric separators.
    normalized = []
    prev_digit = False
    for i in range(len(s)):
        ch = s[i]
        if ch == "_":
            if i == 0 or i == len(s) - 1 or not prev_digit:
                return None
            nxt = s[i + 1]
            nxt_pos = digits.find(nxt)
            if nxt_pos < 0 or nxt_pos >= base:
                return None
            prev_digit = False
            continue
        pos = digits.find(ch)
        if pos < 0 or pos >= base:
            return None
        normalized.append(ch)
        prev_digit = True
    s = "".join(normalized)

    total = 0
    for i in range(len(s)):
        ch = s[i]
        pos = digits.find(ch)
        if pos < 0 or pos >= base:
            return None
        total = total * base + pos
    return sign * total

def _normalize_decimal_number(s):
    if "_" not in s:
        return s
    if s.startswith("_") or s.endswith("_"):
        return None
    out = []
    for i in range(len(s)):
        ch = s[i]
        if ch != "_":
            out.append(ch)
            continue
        prev = s[i - 1] if i > 0 else ""
        nxt = s[i + 1] if i + 1 < len(s) else ""
        if not (prev.isdigit() and nxt.isdigit()):
            return None
    return "".join(out)

def _parse_scientific_float(text):
    normalized = _normalize_decimal_number(text)
    if normalized == None:
        return None
    s = normalized.lower()
    e_pos = s.find("e")
    if e_pos < 0:
        return None
    left = s[:e_pos]
    right = s[e_pos + 1:]
    if right == "":
        return None
    if right[0] in ["+", "-"]:
        if len(right) == 1 or not right[1:].isdigit():
            return None
    elif not right.isdigit():
        return None

    # left side can be int or float-like
    left_ok = False
    if left.isdigit() or (len(left) > 1 and left[0] in ["+", "-"] and left[1:].isdigit()):
        left_ok = True
    elif left.count(".") == 1:
        parts = left.split(".")
        whole = parts[0]
        frac = parts[1]
        left_ok = (whole.isdigit() or whole in ["+", "-"] or (len(whole) > 1 and whole[0] in ["+", "-"] and whole[1:].isdigit())) and frac.isdigit()
    if not left_ok:
        return None
    return float(normalized)

def _parse_nonflow_scalar(s, anchors, errors, line_no = None):
    if s.startswith("*"):
        alias = s[1:].strip()
        if alias not in anchors:
            errors.append(_make_error(
                ERROR_UNKNOWN_ALIAS,
                "Unknown alias '*%s'" % alias,
                line = line_no,
            ))
            value = None
        else:
            value = _clone_value(anchors[alias])
    elif len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        value = _unescape_double_quoted(s[1:-1], errors = errors, line_no = line_no)
    elif len(s) >= 2 and s[0] == "'" and s[-1] == "'":
        value = s[1:-1].replace("''", "'")
    else:
        if s and s[0] in ["@", "`"]:
            errors.append(_make_error(
                ERROR_SYNTAX,
                "Invalid plain scalar start character '%s'" % s[0],
                line = line_no,
            ))
            return s
        if s.startswith("? ") or s.startswith(": ") or s.startswith("- ") or s == "?" or s == ":":
            errors.append(_make_error(
                ERROR_SYNTAX,
                "Ambiguous plain scalar '%s' must be quoted" % s,
                line = line_no,
            ))
            return s

        lower = s.lower()
        normalized = _normalize_decimal_number(s)
        num = normalized if normalized != None else s
        if lower in ["null", "~"]:
            value = None
        elif lower == "true":
            value = True
        elif lower == "false":
            value = False
        elif (num.isdigit()) or (len(num) > 1 and num[0] in ["-", "+"] and num[1:].isdigit()):
            value = int(num)
        elif len(num) > 2 and num[0:2].lower() == "0x":
            parsed = _parse_based_int(num, 16)
            value = parsed if parsed != None else s
        elif len(num) > 2 and num[0:2].lower() == "0o":
            parsed = _parse_based_int(num, 8)
            value = parsed if parsed != None else s
        elif lower in [".inf", "+.inf"]:
            value = float("inf")
        elif lower == "-.inf":
            value = float("-inf")
        elif lower == ".nan":
            value = float("nan")
        else:
            sci = _parse_scientific_float(num)
            if sci != None:
                return sci
            dot = num.count(".")
            if dot == 1:
                split = num.split(".")
                left = split[0]
                right = split[1]
                left_ok = left.isdigit() or left in ["-", "+"] or (len(left) > 1 and left[0] in ["-", "+"] and left[1:].isdigit())
                if left_ok and right.isdigit():
                    value = float(num)
                else:
                    value = s
            else:
                value = s

    return value

def _parse_scalar_atom(s, anchors, errors, line_no = None):
    if s and s[0] in ["[", "{"]:
        value, ok = _parse_flow_collection(s, anchors, errors, line_no = line_no)
        if ok:
            return value

    return _parse_nonflow_scalar(s, anchors, errors, line_no = line_no)

def _normalize_tag(tag, tag_handles, errors, line_no = None):
    t = tag
    if t.startswith("!<") and t.endswith(">"):
        t = t[2:-1]
    elif t.startswith("!") and t.count("!") >= 2:
        # Handle form: !handle!suffix
        second = t.find("!", 1)
        if second > 1:
            handle = t[:second + 1]
            suffix = t[second + 1:]
            if handle in tag_handles:
                t = tag_handles[handle] + suffix
            else:
                errors.append(_make_error(
                    ERROR_SYNTAX,
                    "Unknown tag handle '%s'" % handle,
                    line = line_no,
                ))
    elif t.startswith("!") and len(t) > 1 and t.count("!") == 1:
        # Primary tag shorthand: !suffix (after %TAG ! <prefix>)
        suffix = t[1:]
        if "!" in tag_handles:
            t = tag_handles["!"] + suffix
    if t.startswith("tag:yaml.org,2002:"):
        t = "!!" + t[len("tag:yaml.org,2002:"):]
    return t

def _parse_int_string(text):
    s = text.strip()
    normalized = _normalize_decimal_number(s)
    if normalized == None:
        return None
    s = normalized
    if (s.isdigit()) or (len(s) > 1 and s[0] in ["-", "+"] and s[1:].isdigit()):
        return int(s)
    if len(s) > 2 and s[0:2].lower() == "0x":
        return _parse_based_int(s, 16)
    if len(s) > 2 and s[0:2].lower() == "0o":
        return _parse_based_int(s, 8)
    return None

def _parse_float_string(text):
    s = text.strip()
    normalized = _normalize_decimal_number(s)
    if normalized == None:
        return None
    s = normalized
    lower = s.lower()
    if lower in [".inf", "+.inf"]:
        return float("inf")
    if lower == "-.inf":
        return float("-inf")
    if lower == ".nan":
        return float("nan")
    sci = _parse_scientific_float(s)
    if sci != None:
        return sci
    if s.count(".") == 1:
        parts = s.split(".")
        left = parts[0]
        right = parts[1]
        left_ok = left.isdigit() or left in ["-", "+"] or (len(left) > 1 and left[0] in ["-", "+"] and left[1:].isdigit())
        if left_ok and right.isdigit():
            return float(s)
    return None

def _apply_explicit_tag(tag, raw_value, parsed_value, anchors, tag_handles, errors, line_no = None):
    t = _normalize_tag(tag, tag_handles, errors, line_no = line_no)
    if t in ["!!str", "!str"]:
        if type(parsed_value) == "string":
            return parsed_value
        return raw_value

    if t in ["!!int", "!int"]:
        if type(parsed_value) == "int":
            return parsed_value
        candidate = parsed_value if type(parsed_value) == "string" else raw_value
        parsed = _parse_int_string(candidate)
        if parsed != None:
            return parsed
        errors.append(_make_error(ERROR_SYNTAX, "Invalid !!int value '%s'" % raw_value, line = line_no))
        return 0

    if t in ["!!float", "!float"]:
        if type(parsed_value) == "float":
            return parsed_value
        candidate = parsed_value if type(parsed_value) == "string" else raw_value
        parsed = _parse_float_string(candidate)
        if parsed != None:
            return parsed
        errors.append(_make_error(ERROR_SYNTAX, "Invalid !!float value '%s'" % raw_value, line = line_no))
        return 0.0

    if t in ["!!bool", "!bool"]:
        if type(parsed_value) == "bool":
            return parsed_value
        candidate = parsed_value if type(parsed_value) == "string" else raw_value
        lower = candidate.strip().lower()
        if lower in ["true", "yes", "on"]:
            return True
        if lower in ["false", "no", "off"]:
            return False
        errors.append(_make_error(ERROR_SYNTAX, "Invalid !!bool value '%s'" % raw_value, line = line_no))
        return False

    if t in ["!!null", "!null"]:
        return None

    if t in ["!!seq", "!seq"]:
        if type(parsed_value) == "list":
            return parsed_value
        value, ok = _parse_flow_collection(raw_value.strip(), anchors, errors, line_no = line_no)
        if ok and type(value) == "list":
            return value
        errors.append(_make_error(ERROR_SYNTAX, "Invalid !!seq value '%s'" % raw_value, line = line_no))
        return []

    if t in ["!!map", "!map"]:
        if type(parsed_value) == "dict":
            return parsed_value
        value, ok = _parse_flow_collection(raw_value.strip(), anchors, errors, line_no = line_no)
        if ok and type(value) == "dict":
            return value
        errors.append(_make_error(ERROR_SYNTAX, "Invalid !!map value '%s'" % raw_value, line = line_no))
        return {}

    return parsed_value

def _parse_scalar(text, anchors, errors, line_no = None, tag_handles = None):
    s = text.strip()
    if s == "":
        return None

    handles = tag_handles if tag_handles != None else {
        "!": "!",
        "!!": "tag:yaml.org,2002:",
    }

    anchor_name = None
    explicit_tag = None
    for _ in range(4):
        if not s:
            break
        if s.startswith("&"):
            split = s.split(" ", 1)
            anchor_name = split[0][1:]
            s = split[1].strip() if len(split) > 1 else ""
            continue
        if s.startswith("!"):
            split = s.split(" ", 1)
            explicit_tag = split[0]
            s = split[1].strip() if len(split) > 1 else ""
            continue
        break

    value = _parse_scalar_atom(s, anchors, errors, line_no = line_no)
    if explicit_tag != None:
        value = _apply_explicit_tag(explicit_tag, s, value, anchors, handles, errors, line_no = line_no)

    if anchor_name:
        anchors[anchor_name] = _clone_value(value)
    return value

def _to_hashable_key(value):
    t = type(value)
    if t in ["string", "int", "float", "bool", "NoneType", "tuple"]:
        return value
    if t in ["list", "dict"]:
        return json.encode(value)
    return str(value)

def _split_ws_tokens(text):
    raw_parts = text.replace("\t", " ").split(" ")
    parts = []
    for part in raw_parts:
        if part:
            parts.append(part)
    return parts

def _parse_tag_directive(stripped, tag_handles, errors, line_no):
    # %TAG !e! tag:example.com,2020:app/
    parts = _split_ws_tokens(stripped)
    if len(parts) != 3:
        errors.append(_make_error(
            ERROR_SYNTAX,
            "Invalid %TAG directive format",
            line = line_no,
        ))
        return
    handle = parts[1]
    prefix = parts[2]
    tag_handles[handle] = prefix

def _parse_yaml_directive(stripped, errors, line_no):
    # %YAML 1.2
    parts = _split_ws_tokens(stripped)
    if len(parts) != 2:
        errors.append(_make_error(
            ERROR_SYNTAX,
            "Invalid %YAML directive format",
            line = line_no,
        ))
        return
    version = parts[1]
    if version != "1.2":
        errors.append(_make_error(
            ERROR_SYNTAX,
            "Unsupported YAML version '%s' (expected 1.2)" % version,
            line = line_no,
        ))

def _parse_block_scalar(lines, start_idx, parent_indent, indicator):
    style = indicator[0]
    chomping = ""
    explicit_indent = 0
    for i in range(1, len(indicator)):
        ch = indicator[i]
        if ch in ["+", "-"] and chomping == "":
            chomping = ch
        elif ch.isdigit() and explicit_indent == 0:
            explicit_indent = int(ch)

    idx = start_idx
    raw_values = []
    min_indent = -1
    for _ in range(len(lines) + 1):
        if idx >= len(lines):
            break
        raw = lines[idx]
        if not raw.strip():
            raw_values.append((0, ""))
            idx += 1
            continue
        indent = _count_indent(raw)
        if indent <= parent_indent:
            break
        if min_indent < 0 or indent < min_indent:
            min_indent = indent
        raw_values.append((indent, raw))
        idx += 1

    if explicit_indent > 0:
        content_indent = parent_indent + explicit_indent
    elif min_indent >= 0:
        content_indent = min_indent
    else:
        content_indent = parent_indent + 1

    values = []
    for _indent, raw in raw_values:
        if raw == "":
            values.append("")
            continue
        cut = content_indent
        values.append(raw[cut:] if len(raw) > cut else "")

    if style == "|":
        text = "\n".join(values)
    else:
        pieces = []
        prev_blank = False
        has_text = False
        prev_line = ""
        for line in values:
            if line == "":
                if has_text:
                    pieces.append("\n")
                prev_blank = True
            else:
                if has_text:
                    if prev_blank:
                        pieces.append("\n")
                    elif line.startswith(" ") or prev_line.startswith(" "):
                        pieces.append("\n")
                    else:
                        pieces.append(" ")
                pieces.append(line)
                prev_blank = False
                has_text = True
                prev_line = line
        text = "".join(pieces)

    trailing_blank_lines = 0
    for i in range(len(values) - 1, -1, -1):
        if values[i] == "":
            trailing_blank_lines += 1
        else:
            break

    # Remove any trailing newlines before applying chomping.
    for _ in range(len(text) + 1):
        if not text.endswith("\n"):
            break
        text = text[:-1]

    if chomping == "+":
        text += "\n"
        for _ in range(trailing_blank_lines):
            text += "\n"
    elif chomping == "":
        text += "\n"

    return (text, idx)

def _consume_block_plain_scalar(lines, start_idx, parent_indent, initial_text):
    idx = start_idx
    parts = [initial_text]
    blank_run = 0

    for _ in range(len(lines) + 1):
        if idx >= len(lines):
            break

        raw = lines[idx]
        stripped = raw.strip()
        indent = _count_indent(raw)

        if stripped == "":
            blank_run += 1
            idx += 1
            continue

        if indent <= parent_indent:
            break

        text = _strip_comment(raw[indent:])
        if text == "":
            blank_run += 1
            idx += 1
            continue

        # If this line clearly starts a nested structure, stop folding.
        if text == "-" or text.startswith("- ") or text.startswith("? ") or text.startswith(": "):
            break

        # A clear mapping entry at deeper indent likely starts structure.
        key, _value, ok = _split_key_value(text)
        if ok and key.strip() != "":
            break

        if blank_run > 0:
            for _ in range(blank_run):
                parts.append("\n")
        parts.append(text)
        blank_run = 0
        idx += 1

    result = ""
    for part in parts:
        if part == "\n":
            result += "\n"
            continue
        if result != "" and not result.endswith("\n"):
            result += " "
        result += part
    return (result, idx)

def _attach_child(parent, key_or_index, value):
    if type(parent) == "dict":
        parent[key_or_index] = value
    else:
        parent[key_or_index] = value

def _finalize_merge_key(mapping, errors = None, line_no = None):
    if _INTERNAL_MERGE_KEY not in mapping:
        return

    merge_sources = mapping[_INTERNAL_MERGE_KEY]
    bases = []
    for merge_value in merge_sources:
        if type(merge_value) == "dict":
            bases.append(merge_value)
        elif type(merge_value) == "list":
            for item in merge_value:
                if type(item) == "dict":
                    bases.append(item)
                elif errors != None:
                    errors.append(_make_error(
                        ERROR_SYNTAX,
                        "Merge list entries must be mappings",
                        line = line_no,
                    ))
        elif errors != None:
            errors.append(_make_error(
                ERROR_SYNTAX,
                "Merge value must be a mapping or sequence of mappings",
                line = line_no,
            ))

    for base in bases:
        for k, v in base.items():
            if k not in mapping:
                mapping[k] = v
    mapping.pop(_INTERNAL_MERGE_KEY)

def _parse_single_document(lines):
    errors = []
    anchors = {}
    tag_handles = {
        "!": "!",
        "!!": "tag:yaml.org,2002:",
    }
    root = None
    stack = []
    pending = None
    explicit_pending = None
    saw_directive = False
    require_doc_start = False
    idx = 0

    for _ in range(len(lines) + 1):
        if idx >= len(lines):
            break
        raw = lines[idx]
        stripped = raw.strip()

        if not stripped or stripped.startswith("#"):
            idx += 1
            continue

        if require_doc_start and stripped != "---" and not stripped.startswith("%"):
            errors.append(_make_error(
                ERROR_SYNTAX,
                "Directives must be followed by '---' document start marker",
                line = idx + 1,
            ))
            require_doc_start = False

        if stripped.startswith("%"):
            if root != None or stack:
                errors.append(_make_error(
                    ERROR_SYNTAX,
                    "Directive found after document content",
                    line = idx + 1,
                ))
                idx += 1
                continue
            saw_directive = True
            require_doc_start = True
            if stripped.startswith("%TAG "):
                _parse_tag_directive(stripped, tag_handles, errors, idx + 1)
            elif stripped.startswith("%YAML "):
                _parse_yaml_directive(stripped, errors, idx + 1)
            else:
                errors.append(_make_error(
                    ERROR_SYNTAX,
                    "Unknown directive '%s'" % stripped,
                    line = idx + 1,
                ))
            idx += 1
            continue
        if stripped in ["---", "..."]:
            if stripped == "---" and saw_directive:
                require_doc_start = False
            idx += 1
            continue

        indent = _count_indent(raw, errors, idx + 1)
        text = _strip_comment(raw[indent:])
        if text == "":
            idx += 1
            continue

        for _ in range(len(stack) + 1):
            if not stack:
                break
            top = stack[-1]
            if indent > top["indent"]:
                break
            if top["kind"] == "map":
                _finalize_merge_key(top["value"], errors = errors, line_no = idx + 1)
            stack = stack[:-1]

        if pending != None:
            if indent > pending["indent"]:
                child = [] if (text == "-" or text.startswith("- ")) else {}
                if pending.get("merge_pending", False):
                    _append_merge_source(pending["parent"], child)
                else:
                    _attach_child(pending["parent"], pending["slot"], child)
                if pending.get("anchor", None) != None:
                    anchors[pending["anchor"]] = child
                stack.append({
                    "kind": "seq" if type(child) == "list" else "map",
                    "indent": pending["indent"],
                    "value": child,
                    "entry_indent": None,
                    "item_indent": None,
                })
            pending = None

        if root == None and not stack:
            if text == "-" or text.startswith("- "):
                root = []
                stack.append({"kind": "seq", "indent": indent - 1, "value": root, "entry_indent": None, "item_indent": None})
            elif _find_top_level_colon(text) >= 0 or text.startswith("? "):
                root = {}
                stack.append({"kind": "map", "indent": indent - 1, "value": root, "entry_indent": None, "item_indent": None})
            else:
                root = _parse_scalar(text, anchors, errors, line_no = idx + 1, tag_handles = tag_handles)
                idx += 1
                continue

        if not stack:
            idx += 1
            continue

        current = stack[-1]

        if current["kind"] == "map":
            if not _check_frame_entry_indent(current, indent, errors, idx + 1):
                idx += 1
                continue
            if explicit_pending != None:
                if indent > explicit_pending["indent"]:
                    explicit_pending["parent"][explicit_pending["key"]] = None
                    explicit_pending = None
                elif text.startswith(":") and explicit_pending["parent"] == current["value"] and indent == explicit_pending["indent"]:
                    key = explicit_pending["key"]
                    is_merge_key = explicit_pending.get("is_merge_key", False)
                    explicit_pending = None
                    value_text = text[1:].strip()
                    anchor_only = None
                    if value_text.startswith("&") and " " not in value_text:
                        anchor_only = value_text[1:]

                    if value_text == "" or anchor_only != None:
                        parsed_value = None
                        if is_merge_key:
                            _append_merge_source(current["value"], parsed_value)
                        else:
                            _set_mapping_value(current["value"], key, parsed_value, errors, idx + 1)
                        pending = {
                            "parent": current["value"],
                            "slot": key if not is_merge_key else _INTERNAL_MERGE_KEY,
                            "indent": indent,
                            "anchor": anchor_only,
                            "merge_pending": is_merge_key,
                        }
                        idx += 1
                        continue

                    if value_text.startswith("|") or value_text.startswith(">"):
                        parsed, new_idx = _parse_block_scalar(lines, idx + 1, indent, value_text)
                        if is_merge_key:
                            _append_merge_source(current["value"], parsed)
                        else:
                            _set_mapping_value(current["value"], key, parsed, errors, idx + 1)
                        idx = new_idx
                        continue

                    parsed_value = _parse_scalar(value_text, anchors, errors, line_no = idx + 1, tag_handles = tag_handles)
                    if is_merge_key:
                        _append_merge_source(current["value"], parsed_value)
                    else:
                        _set_mapping_value(current["value"], key, parsed_value, errors, idx + 1)
                    idx += 1
                    continue
                else:
                    _set_mapping_value(explicit_pending["parent"], explicit_pending["key"], None, errors, idx + 1)
                    explicit_pending = None

            if text.startswith("? "):
                explicit_key_text = text[2:].strip()
                explicit_pending = {
                    "parent": current["value"],
                    "key": _to_hashable_key(_parse_scalar(explicit_key_text, anchors, errors, line_no = idx + 1, tag_handles = tag_handles)),
                    "indent": indent,
                    "is_merge_key": _is_plain_merge_key_token(explicit_key_text),
                }
                idx += 1
                continue

            key_text, value_text, ok = _split_key_value(text)
            if not ok:
                errors.append(_make_error(
                    ERROR_SYNTAX,
                    "Expected mapping entry at line %d" % (idx + 1),
                    line = idx + 1,
                ))
                idx += 1
                continue
            if key_text.strip() == "":
                errors.append(_make_error(
                    ERROR_SYNTAX,
                    "Empty implicit mapping key at line %d" % (idx + 1),
                    line = idx + 1,
                ))
                idx += 1
                continue

            key = _to_hashable_key(_parse_scalar(key_text, anchors, errors, line_no = idx + 1, tag_handles = tag_handles))
            is_merge_key = _is_plain_merge_key_token(key_text)
            anchor_only = None
            if value_text.startswith("&") and " " not in value_text:
                anchor_only = value_text[1:]

            if value_text == "" or anchor_only != None:
                parsed_value = None
                if is_merge_key:
                    _append_merge_source(current["value"], parsed_value)
                else:
                    _set_mapping_value(current["value"], key, parsed_value, errors, idx + 1)
                pending = {
                    "parent": current["value"],
                    "slot": key if not is_merge_key else _INTERNAL_MERGE_KEY,
                    "indent": indent,
                    "anchor": anchor_only,
                    "merge_pending": is_merge_key,
                }
                idx += 1
                continue

            if value_text.startswith("|") or value_text.startswith(">"):
                parsed, new_idx = _parse_block_scalar(lines, idx + 1, indent, value_text)
                if is_merge_key:
                    _append_merge_source(current["value"], parsed)
                else:
                    _set_mapping_value(current["value"], key, parsed, errors, idx + 1)
                idx = new_idx
                continue

            parsed_value = _parse_scalar(value_text, anchors, errors, line_no = idx + 1, tag_handles = tag_handles)
            if type(parsed_value) == "string" and not _is_quoted_scalar(value_text.strip()):
                parsed_value, next_idx = _consume_block_plain_scalar(
                    lines,
                    idx + 1,
                    indent,
                    parsed_value,
                )
                idx = next_idx
            else:
                idx += 1
            if is_merge_key:
                _append_merge_source(current["value"], parsed_value)
            else:
                _set_mapping_value(current["value"], key, parsed_value, errors, idx + 1)
            continue

        # Sequence case
        if not _check_frame_entry_indent(current, indent, errors, idx + 1):
            idx += 1
            continue
        if not (text == "-" or text.startswith("- ")):
            errors.append(_make_error(
                ERROR_SYNTAX,
                "Expected sequence item at line %d" % (idx + 1),
                line = idx + 1,
            ))
            idx += 1
            continue

        rest = text[1:].strip()
        if rest == "":
            current["value"].append(None)
            pending = {
                "parent": current["value"],
                "slot": len(current["value"]) - 1,
                "indent": indent,
                "anchor": None,
            }
            idx += 1
            continue

        if _find_top_level_colon(rest) >= 0:
            k, v, ok = _split_key_value(rest)
            if ok:
                item = {}
                inline_key = _to_hashable_key(_parse_scalar(k, anchors, errors, line_no = idx + 1, tag_handles = tag_handles))
                _set_mapping_value(
                    item,
                    inline_key,
                    _parse_scalar(v, anchors, errors, line_no = idx + 1, tag_handles = tag_handles) if v else None,
                    errors,
                    idx + 1,
                )
                current["value"].append(item)
                stack.append({
                    "kind": "map",
                    "indent": indent,
                    "value": item,
                    "entry_indent": None,
                    "item_indent": None,
                })
                if v == "":
                    pending = {
                        "parent": item,
                        "slot": inline_key,
                        "indent": indent,
                        "anchor": None,
                    }
                idx += 1
                continue

        if rest.startswith("|") or rest.startswith(">"):
            parsed, new_idx = _parse_block_scalar(lines, idx + 1, indent, rest)
            current["value"].append(parsed)
            idx = new_idx
            continue

        seq_value = _parse_scalar(rest, anchors, errors, line_no = idx + 1, tag_handles = tag_handles)
        if type(seq_value) == "string" and not _is_quoted_scalar(rest):
            seq_value, next_idx = _consume_block_plain_scalar(
                lines,
                idx + 1,
                indent,
                seq_value,
            )
            idx = next_idx
        else:
            idx += 1
        current["value"].append(seq_value)

    if explicit_pending != None:
        _set_mapping_value(explicit_pending["parent"], explicit_pending["key"], None, errors, idx + 1 if idx < len(lines) else None)

    for frame in stack:
        if frame["kind"] == "map":
            _finalize_merge_key(frame["value"], errors = errors, line_no = idx + 1 if idx < len(lines) else None)

    if root == None:
        root = None

    return struct(node_type = NODE_DOCUMENT, value = root, errors = errors)

def _split_documents(yaml_string):
    normalized = yaml_string.replace("\r\n", "\n").replace("\r", "\n")
    lines = normalized.split("\n")
    docs = []
    current = []
    saw_content = False

    for line in lines:
        stripped = line.strip()
        if stripped == "---":
            if saw_content:
                docs.append(current)
                current = []
                saw_content = False
            else:
                has_directive = False
                for candidate in current:
                    if candidate.strip().startswith("%"):
                        has_directive = True
                        break
                if has_directive:
                    current.append(line)
                    saw_content = True
            continue
        if stripped == "...":
            docs.append(current)
            current = []
            saw_content = False
            continue
        current.append(line)
        if stripped and not stripped.startswith("#") and not stripped.startswith("%"):
            saw_content = True

    has_non_empty = False
    for line in current:
        s = line.strip()
        if s and not s.startswith("#"):
            has_non_empty = True
            break
    if has_non_empty or not docs:
        docs.append(current)
    return docs

def parse_yaml(yaml_string, strict = False):
    docs = parse_all_yaml(yaml_string, strict = strict)
    return docs[0]

def parse_all_yaml(yaml_string, strict = False):
    """Parse a YAML character stream into a list of document nodes.

    Args:
      yaml_string: Full stream text (may contain multiple documents).
      strict: If true, fail when any document records parse errors.

    Returns:
      List of struct(node_type, value, errors) document nodes.
    """

    # JSON is a valid YAML subset, so prefer fast path.
    trimmed = yaml_string.strip()
    if trimmed and trimmed[0] in ["{", "["]:
        value = json.decode(trimmed)
        return [struct(node_type = NODE_DOCUMENT, value = value, errors = [])]

    result = []
    stream_errors = []
    for doc_lines in _split_documents(yaml_string):
        joined = "\n".join(doc_lines).strip()
        if joined and joined[0] in ["{", "["]:
            doc = struct(node_type = NODE_DOCUMENT, value = json.decode(joined), errors = [])
        else:
            doc = _parse_single_document(doc_lines)
        result.append(doc)
        stream_errors.extend(doc.errors)

    if strict and stream_errors:
        fail("YAML parsing failed with %d error(s)" % len(stream_errors))

    if not result:
        result = [struct(node_type = NODE_DOCUMENT, value = None, errors = [])]
    return result

def has_errors(document):
    return len(document.errors) > 0

def get_errors(document):
    return list(document.errors)

def get_value(document):
    return document.value

def is_document(node):
    return hasattr(node, "node_type") and node.node_type == NODE_DOCUMENT

def is_mapping(value):
    return type(value) == "dict"

def is_sequence(value):
    return type(value) == "list"

def is_scalar(value):
    return type(value) in ["string", "int", "float", "bool", "NoneType"]

def make_yaml_tag(tag, value):
    if type(tag) != "string" or tag.strip() == "":
        fail("yaml.tag() requires a non-empty string tag")
    return struct(_yaml_emit_kind = "tagged", tag = tag.strip(), value = value)

def make_yaml_anchor(name, value):
    if type(name) != "string" or name.strip() == "":
        fail("yaml.anchor() requires a non-empty string name")
    return struct(_yaml_emit_kind = "anchored", name = name.strip(), value = value)

def make_yaml_alias(name):
    if type(name) != "string" or name.strip() == "":
        fail("yaml.alias() requires a non-empty string name")
    return struct(_yaml_emit_kind = "alias", name = name.strip())

def _indent_prefix(level, indent_str):
    out = ""
    for _ in range(level):
        out += indent_str
    return out

def _key_sort_rank(key):
    kind = type(key)
    if kind == "NoneType":
        return 0
    if kind == "bool":
        return 1
    if kind == "int":
        return 2
    if kind == "float":
        return 3
    if kind == "string":
        return 4
    return 5

def _key_sort_token(key):
    rank = _key_sort_rank(key)
    kind = type(key)
    if kind in ["NoneType", "bool", "int", "float"]:
        text = _render_inline_scalar(key)
    elif kind == "string":
        text = key
    else:
        text = json.encode(key)
    return "%d|%s" % (rank, text)

def _sort_keys_for_emit(keys):
    arr = list(keys)
    for i in range(1, len(arr)):
        current = arr[i]
        current_token = _key_sort_token(current)
        j = i - 1
        for _ in range(i + 1):
            if j < 0:
                break
            prev_token = _key_sort_token(arr[j])
            if prev_token <= current_token:
                break
            arr[j + 1] = arr[j]
            j -= 1
        arr[j + 1] = current
    return arr

def _looks_like_resolved_scalar(text):
    lower = text.lower()
    if lower in ["null", "~", "true", "false", ".inf", "+.inf", "-.inf", ".nan", "yes", "no", "on", "off"]:
        return True
    if _parse_int_string(text) != None:
        return True
    if _parse_float_string(text) != None:
        return True
    return False

def _string_needs_quotes(text):
    if text == "":
        return True
    if text != text.strip():
        return True
    if text.startswith("? ") or text.startswith(": ") or text.startswith("- "):
        return True
    if text in ["?", ":", "-", "null", "~", "true", "false", "True", "False"]:
        return True
    if text[0] in ["@", "`", "!", "&", "*", "#", "{", "}", "[", "]", ",", "|", ">", "%", '"', "'"]:
        return True
    if ": " in text or " #" in text or text.endswith(":"):
        return True
    if "#" in text and (text[0] == "#" or " #" in text):
        return True
    if _looks_like_resolved_scalar(text):
        return True
    return False

def _render_inline_scalar(value):
    kind = type(value)
    if kind == "NoneType":
        return "null"
    if kind == "bool":
        return "true" if value else "false"
    if kind == "int":
        return str(value)
    if kind == "float":
        s = str(value)
        if s == "inf":
            return ".inf"
        if s == "-inf":
            return "-.inf"
        if s == "nan":
            return ".nan"
        return s
    if kind == "string":
        if _string_needs_quotes(value):
            return json.encode(value)
        return value
    return json.encode(value)

def _render_key(key):
    key_kind = type(key)
    if key_kind == "string":
        if "\n" in key:
            return json.encode(key)
        if _string_needs_quotes(key):
            return json.encode(key)
        return key
    if key_kind in ["NoneType", "bool", "int", "float"]:
        return _render_inline_scalar(key)
    return json.encode(key)

def _build_block_scalar_header(text):
    if text.endswith("\n\n"):
        return "|+"
    if text.endswith("\n"):
        return "|"
    return "|-"

def _append_block_scalar(lines, indent_level, prefix, text, indent_str):
    header = _build_block_scalar_header(text)
    lines.append(_indent_prefix(indent_level, indent_str) + prefix + " " + header)

    body_lines = text.split("\n")
    if text.endswith("\n"):
        body_lines = body_lines[:-1]

    if not body_lines:
        body_lines = [""]

    content_prefix = _indent_prefix(indent_level + 1, indent_str)
    for line in body_lines:
        lines.append(content_prefix + line)

def _is_inline_renderable(value):
    value_kind = type(value)
    if value_kind in ["NoneType", "bool", "int", "float"]:
        return True
    if value_kind == "string":
        return "\n" not in value
    if value_kind == "list":
        return len(value) == 0
    if value_kind == "dict":
        return len(value) == 0
    return True

def _build_map_items(mapping, sort_keys):
    keys = list(mapping.keys())
    if sort_keys:
        keys = _sort_keys_for_emit(keys)
    items = []
    for key in keys:
        items.append(struct(key = key, value = mapping[key]))
    return items

def _unwrap_emit_value(value):
    prefixes = []
    current = value
    alias_name = None

    for _ in range(16):
        if type(current) != "struct" or not hasattr(current, "_yaml_emit_kind"):
            break
        kind = current._yaml_emit_kind
        if kind == "tagged":
            prefixes.append(current.tag)
            current = current.value
            continue
        if kind == "anchored":
            prefixes.append("&" + current.name)
            current = current.value
            continue
        if kind == "alias":
            alias_name = current.name
            break
        break

    return struct(prefixes = prefixes, value = current, alias_name = alias_name)

def _join_prefixes(prefixes):
    if not prefixes:
        return ""
    out = prefixes[0]
    for i in range(1, len(prefixes)):
        out += " " + prefixes[i]
    return out

def _emit_yaml_lines(value, indent, indent_str, sort_keys):
    lines = []
    stack = [struct(kind = "value", value = value, indent = indent)]
    max_steps = len(str(value)) * 32 + 1024

    for _ in range(max_steps):
        if not stack:
            break

        frame = stack.pop()
        if frame.kind == "value":
            unwrapped = _unwrap_emit_value(frame.value)
            prefix_text = _join_prefixes(unwrapped.prefixes)
            val = unwrapped.value
            val_kind = type(val)

            if unwrapped.alias_name != None:
                alias_text = "*" + unwrapped.alias_name
                if prefix_text:
                    alias_text = prefix_text + " " + alias_text
                lines.append(_indent_prefix(frame.indent, indent_str) + alias_text)
                continue

            if _is_inline_renderable(val):
                rendered_inline = ""
                if val_kind in ["list", "dict"] and len(val) == 0:
                    rendered_inline = "[]" if val_kind == "list" else "{}"
                else:
                    rendered_inline = _render_inline_scalar(val)
                if prefix_text:
                    rendered_inline = prefix_text + " " + rendered_inline
                lines.append(_indent_prefix(frame.indent, indent_str) + rendered_inline)
                continue

            if val_kind == "string":
                _append_block_scalar(lines, frame.indent, prefix_text, val, indent_str)
                continue

            if val_kind == "dict":
                if prefix_text:
                    lines.append(_indent_prefix(frame.indent, indent_str) + prefix_text)
                items = _build_map_items(val, sort_keys)
                stack.append(struct(
                    kind = "map_iter",
                    items = items,
                    idx = 0,
                    indent = frame.indent,
                ))
                continue

            if val_kind == "list":
                if prefix_text:
                    lines.append(_indent_prefix(frame.indent, indent_str) + prefix_text)
                stack.append(struct(
                    kind = "seq_iter",
                    values = val,
                    idx = 0,
                    indent = frame.indent,
                ))
                continue

            rendered = _render_inline_scalar(val)
            if prefix_text:
                rendered = prefix_text + " " + rendered
            lines.append(_indent_prefix(frame.indent, indent_str) + rendered)
            continue

        if frame.kind == "map_iter":
            if frame.idx >= len(frame.items):
                continue

            entry = frame.items[frame.idx]
            key_text = _render_key(entry.key)
            unwrapped = _unwrap_emit_value(entry.value)
            prefix_text = _join_prefixes(unwrapped.prefixes)
            val = unwrapped.value
            val_kind = type(val)

            stack.append(struct(kind = "map_iter", items = frame.items, idx = frame.idx + 1, indent = frame.indent))

            if unwrapped.alias_name != None:
                alias_text = "*" + unwrapped.alias_name
                if prefix_text:
                    alias_text = prefix_text + " " + alias_text
                lines.append(_indent_prefix(frame.indent, indent_str) + key_text + ": " + alias_text)
                continue

            if _is_inline_renderable(val):
                rendered_inline = ""
                if val_kind in ["list", "dict"] and len(val) == 0:
                    rendered_inline = "[]" if val_kind == "list" else "{}"
                else:
                    rendered_inline = _render_inline_scalar(val)
                if prefix_text:
                    rendered_inline = prefix_text + " " + rendered_inline
                lines.append(_indent_prefix(frame.indent, indent_str) + key_text + ": " + rendered_inline)
                continue

            if val_kind == "string":
                block_prefix = key_text + ":"
                if prefix_text:
                    block_prefix += " " + prefix_text
                _append_block_scalar(lines, frame.indent, block_prefix, val, indent_str)
                continue

            line = key_text + ":"
            if prefix_text:
                line += " " + prefix_text
            lines.append(_indent_prefix(frame.indent, indent_str) + line)
            stack.append(struct(kind = "value", value = val, indent = frame.indent + 1))
            continue

        if frame.kind == "seq_iter":
            if frame.idx >= len(frame.values):
                continue

            unwrapped = _unwrap_emit_value(frame.values[frame.idx])
            prefix_text = _join_prefixes(unwrapped.prefixes)
            val = unwrapped.value
            val_kind = type(val)
            stack.append(struct(kind = "seq_iter", values = frame.values, idx = frame.idx + 1, indent = frame.indent))

            if unwrapped.alias_name != None:
                alias_text = "*" + unwrapped.alias_name
                if prefix_text:
                    alias_text = prefix_text + " " + alias_text
                lines.append(_indent_prefix(frame.indent, indent_str) + "- " + alias_text)
                continue

            if _is_inline_renderable(val):
                rendered_inline = ""
                if val_kind in ["list", "dict"] and len(val) == 0:
                    rendered_inline = "[]" if val_kind == "list" else "{}"
                else:
                    rendered_inline = _render_inline_scalar(val)
                if prefix_text:
                    rendered_inline = prefix_text + " " + rendered_inline
                lines.append(_indent_prefix(frame.indent, indent_str) + "- " + rendered_inline)
                continue

            if val_kind == "string":
                block_prefix = "-"
                if prefix_text:
                    block_prefix += " " + prefix_text
                _append_block_scalar(lines, frame.indent, block_prefix, val, indent_str)
                continue

            line = "-"
            if prefix_text:
                line += " " + prefix_text
            lines.append(_indent_prefix(frame.indent, indent_str) + line)
            stack.append(struct(kind = "value", value = val, indent = frame.indent + 1))
            continue

    if stack:
        # Best-effort fallback for unexpected traversal budget exhaustion.
        return [str(value)]
    return lines

def _tag_handle_char_ok(ch):
    return ch.isalnum() or ch in ["-", "_"]

def _is_valid_tag_handle_for_directive(handle):
    if type(handle) != "string" or handle == "":
        return False
    if handle != handle.strip():
        return False
    if not handle.startswith("!"):
        return False
    if handle == "!":
        return True
    if handle == "!!":
        return True
    if not handle.endswith("!"):
        return False
    inner = handle[1:-1]
    if inner == "":
        return False
    for i in range(len(inner)):
        if not _tag_handle_char_ok(inner[i]):
            return False
    return True

def _is_valid_tag_uri_prefix(prefix):
    if type(prefix) != "string" or prefix.strip() == "":
        return False
    if prefix != prefix.strip():
        return False
    for i in range(len(prefix)):
        if prefix[i] in [" ", "\t", "\n", "\r"]:
            return False
    return True

def validate_dump_directives(yaml_version, tag_directives):
    """Check dump()/dump_all() directive arguments before emitting YAML.

    Args:
      yaml_version: Optional version string; if set must be "1.2".
      tag_directives: None, a dict of handle to prefix, or a list of [handle, prefix] pairs.

    Returns:
      List of human-readable problem strings; empty if arguments are valid.
    """
    errors = []
    if yaml_version != None:
        if type(yaml_version) != "string":
            errors.append("yaml_version must be a string or None, got %s" % type(yaml_version))
        else:
            v = yaml_version.strip()
            if v == "":
                errors.append("yaml_version must not be empty when provided")
            elif v != "1.2":
                errors.append(
                    "yaml_version must be '1.2' when provided (matches parser support), got '%s'" % yaml_version,
                )
    if tag_directives == None:
        return errors
    if type(tag_directives) == "dict":
        if len(tag_directives) == 0:
            return errors
        handles = list(tag_directives.keys())
        handles = _sort_keys_for_emit(handles)
        for handle in handles:
            if not _is_valid_tag_handle_for_directive(handle):
                errors.append(
                    "invalid TAG handle '%s' (use '!', '!!', or '!name!' with alphanumeric name)" % str(handle),
                )
            prefix = tag_directives[handle]
            if type(prefix) != "string":
                errors.append("TAG prefix for handle '%s' must be a string" % str(handle))
            elif not _is_valid_tag_uri_prefix(prefix):
                errors.append("invalid TAG prefix for handle '%s' (non-empty, no whitespace)" % str(handle))
        return errors
    if type(tag_directives) == "list":
        for i in range(len(tag_directives)):
            entry = tag_directives[i]
            if type(entry) != "list" or len(entry) != 2:
                errors.append("tag_directives[%d] must be a two-element [handle, prefix] list" % i)
                continue
            handle = entry[0]
            prefix = entry[1]
            if not _is_valid_tag_handle_for_directive(handle):
                errors.append(
                    "invalid TAG handle '%s' at index %d" % (str(handle), i),
                )
            if type(prefix) != "string" or not _is_valid_tag_uri_prefix(prefix):
                errors.append("invalid TAG prefix at index %d" % i)
        return errors
    errors.append("tag_directives must be None, a dict, or a list, got %s" % type(tag_directives))
    return errors

def dump_yaml(
        value,
        indent = 0,
        indent_str = "  ",
        explicit_start = False,
        explicit_end = False,
        sort_keys = False,
        flow_style = False,
        yaml_version = None,
        tag_directives = None):
    """Serialize a Starlark value as a YAML document string.

    Args:
      value: Mapping, sequence, or scalar to emit.
      indent: Base indentation level (spaces).
      indent_str: String repeated per indent level for nested block content.
      explicit_start: If true, prefix the document with "---".
      explicit_end: If true, suffix the document with "...".
      sort_keys: If true, emit mapping keys in a stable sorted order.
      flow_style: If true, emit JSON-style flow collections instead of block style.
      yaml_version: Optional "%YAML" directive value (must be "1.2" if set).
      tag_directives: Optional "%TAG" handles for dump output.

    Returns:
      A single YAML document as a string.
    """
    directive_errors = validate_dump_directives(yaml_version, tag_directives)
    if directive_errors:
        fail("yaml.dump: " + "; ".join(directive_errors))
    if flow_style:
        text = json.encode(value)
    else:
        body_lines = _emit_yaml_lines(value, indent, indent_str, sort_keys)
        text = "\n".join(body_lines)
    parts = []

    has_directives = False

    if yaml_version != None:
        has_directives = True
        parts.append("%%YAML %s" % str(yaml_version))

    if tag_directives != None:
        if type(tag_directives) == "dict":
            handles = list(tag_directives.keys())
            handles = _sort_keys_for_emit(handles)
            for handle in handles:
                parts.append("%%TAG %s %s" % (str(handle), str(tag_directives[handle])))
                has_directives = True
        elif type(tag_directives) == "list":
            for entry in tag_directives:
                if type(entry) == "list" and len(entry) == 2:
                    parts.append("%%TAG %s %s" % (str(entry[0]), str(entry[1])))
                    has_directives = True

    if explicit_start or has_directives:
        parts.append("---")
    parts.append(text)
    if explicit_end:
        parts.append("...")
    return "\n".join(parts)

def dump_all_yaml(
        values,
        indent = 0,
        indent_str = "  ",
        explicit_start = True,
        explicit_end = False,
        sort_keys = False,
        flow_style = False,
        yaml_version = None,
        tag_directives = None):
    """Serialize a list of values as a multi-document YAML stream.

    Args:
      values: List of document roots to emit in order.
      indent: Base indentation level (spaces).
      indent_str: String repeated per indent level for nested block content.
      explicit_start: If true, each document starts with "---" (default true).
      explicit_end: If true, each document ends with "..."; may be forced for streams with directives.
      sort_keys: If true, emit mapping keys in a stable sorted order.
      flow_style: If true, emit JSON-style flow collections instead of block style.
      yaml_version: Optional "%YAML" directive value per document (must be "1.2" if set).
      tag_directives: Optional "%TAG" handles applied to each document.

    Returns:
      Concatenated YAML stream text.
    """
    docs = []
    force_end_markers = (yaml_version != None or tag_directives != None) and len(values) > 1
    for value in values:
        docs.append(dump_yaml(
            value,
            indent = indent,
            indent_str = indent_str,
            explicit_start = explicit_start,
            explicit_end = explicit_end or force_end_markers,
            sort_keys = sort_keys,
            flow_style = flow_style,
            yaml_version = yaml_version,
            tag_directives = tag_directives,
        ))
    return "\n".join(docs)
