"Public API for yaml.bzl."

load(
    "//private:yaml_impl.bzl",
    _ERROR_DUPLICATE_KEY = "ERROR_DUPLICATE_KEY",
    _ERROR_INDENTATION = "ERROR_INDENTATION",
    _ERROR_SYNTAX = "ERROR_SYNTAX",
    _ERROR_UNKNOWN_ALIAS = "ERROR_UNKNOWN_ALIAS",
    _dump_all_yaml = "dump_all_yaml",
    _dump_yaml = "dump_yaml",
    _get_errors = "get_errors",
    _get_value = "get_value",
    _has_errors = "has_errors",
    _is_document = "is_document",
    _is_mapping = "is_mapping",
    _is_scalar = "is_scalar",
    _is_sequence = "is_sequence",
    _make_yaml_alias = "make_yaml_alias",
    _make_yaml_anchor = "make_yaml_anchor",
    _make_yaml_tag = "make_yaml_tag",
    _parse_all_yaml = "parse_all_yaml",
    _parse_yaml = "parse_yaml",
    _validate_dump_directives = "validate_dump_directives",
)

yaml = struct(
    # Parsing
    parse = _parse_yaml,
    parse_all = _parse_all_yaml,

    # Serialization
    dump = _dump_yaml,
    dump_all = _dump_all_yaml,
    validate_dump_directives = _validate_dump_directives,
    tag = _make_yaml_tag,
    anchor = _make_yaml_anchor,
    alias = _make_yaml_alias,

    # Document helpers
    get_value = _get_value,
    has_errors = _has_errors,
    get_errors = _get_errors,

    # Type helpers
    is_document = _is_document,
    is_mapping = _is_mapping,
    is_sequence = _is_sequence,
    is_scalar = _is_scalar,

    # Error constants
    ERROR_SYNTAX = _ERROR_SYNTAX,
    ERROR_INDENTATION = _ERROR_INDENTATION,
    ERROR_UNKNOWN_ALIAS = _ERROR_UNKNOWN_ALIAS,
    ERROR_DUPLICATE_KEY = _ERROR_DUPLICATE_KEY,
)
