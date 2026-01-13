; {} blocks
(compound_statement . "{" . (_)+ @range . "}")
(declaration_list . "{" . (_)+ @range . "}")
(enumerator_list . "{" . (_)+ @range . "}")
(field_declaration_list . "{" . (_)+ @range . "}")
(initializer_list . "{" . (_)+ @range . "}")

; () blocks
(argument_list . "(" . (_)+ @range . ")")
(parameter_list . "(" . (_)+ @range . ")")
(sizeof_expression (parenthesized_expression (_) @range)) ; sizeof(expr)
(sizeof_expression . "(" . (_) @range . ")" ) ; sizeof(type)
(do_statement condition: (parenthesized_expression (_) @range))
(if_statement condition: (parenthesized_expression (_) @range))
(switch_statement condition: (parenthesized_expression (_) @range))
(while_statement condition: (parenthesized_expression (_) @range))
(for_statement . "(" . (_)+ @range . ")" . (_))

