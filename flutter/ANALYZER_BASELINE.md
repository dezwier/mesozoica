# Flutter analyzer baseline

`flutter analyze --no-fatal-infos` reports no errors or warnings. The 42
remaining findings are informational and predate the structural refactor; the
quality gate keeps them visible without making them fatal.

| Informational rule | Count | Classification |
| --- | ---: | --- |
| `use_build_context_synchronously` | 19 | Presentation lifecycle follow-up |
| `use_null_aware_elements` | 5 | Style-only |
| `deprecated_member_use` | 4 | SDK/plugin migration; behavior-sensitive |
| `prefer_initializing_formals` | 4 | Style-only |
| `curly_braces_in_flow_control_structures` | 3 | Style-only |
| `no_leading_underscores_for_local_identifiers` | 2 | Test style-only |
| `unnecessary_import` | 2 | Test cleanup |
| `constant_identifier_names` | 1 | Existing serialized enum semantics |
| `unnecessary_library_name` | 1 | Style-only |
| `prefer_function_declarations_over_variables` | 1 | Test style-only |

New errors and warnings are not baselined. Architecture checks separately ban
`BuildContext` and presentation imports from feature `domain/` and `data/`.
