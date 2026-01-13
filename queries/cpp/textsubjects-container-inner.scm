; {} blocks
(compound_statement . "{" . (_)+ @range . "}")
(declaration_list . "{" . (_)+ @range . "}")
(enumerator_list . "{" . (_)+ @range . "}")
(field_declaration_list . "{" . (_)+ @range . "}")
(initializer_list . "{" . (_)+ @range . "}")

; () blocks
(argument_list . "(" . (_)+ @range . ")")
(parameter_list . "(" . (_)+ @range . ")")
(decltype (_) @range)
(sizeof_expression (parenthesized_expression (_) @range)) ; sizeof(expr)
(sizeof_expression . "(" . (_) @range . ")" ) ; sizeof(type)
(static_assert_declaration . "(" . (_)+ @range . ")" )
(condition_clause (_) @range)
(do_statement condition: (parenthesized_expression (_) @range))
(for_statement . "(" . (_)+ @range . ")" . (_))
(for_range_loop . "(" . (_)+ @range . ")" . (_))

; <> blocks
(template_argument_list . "<" . (_)+ @range . ">")
(template_parameter_list . "<" . (_)+ @range . ">")
