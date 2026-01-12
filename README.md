<h1 align="center">
  <a href="https://github.com/RRethy/nvim-treesitter-textsubjects">nvim-treesitter-textsubjects</a>
</h1>

<h4 align="center">Location and syntax aware text objects which *do what you mean*</h4>

https://user-images.githubusercontent.com/21000943/148718905-afb4eed4-0adf-4dad-8f37-5179f9ddd055.mov

# Quick start

**Note**: This plugin requires the `main` branch of [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter).

Install and set up `nvim-treesitter` before using this plugin.

The default configuration sets the following mappings:
- `;` selects a syntactical container (class, function, and so on) depending on your location in the syntax tree.
- `i;` selects the body of a syntactical container depending on your location in the syntax tree.
- `.` selects the most relevant part of the syntax tree depending on your location in it.
- `,` repeats the last selection.

# Configuration

If you want to override the defaults, you can use the following configuration and modify it as needed.

```lua
require('nvim-treesitter-textsubjects').configure({
    prev_selection = ',',
    keymaps = {
        ['.'] = 'textsubjects-smart',
        [';'] = 'textsubjects-container-outer',
        ['i;'] = 'textsubjects-container-inner',
    },
})
```

*Note: I know these names are a bit confusing, but naming them is quite difficult.*

# Text subjects

**Note**: I'm open to adding more queries or support for another language, just open and issue or a PR and I can work with you to get the query working.

|                      | `container-inner`    | `container-outer`    | `smart`        |
| -------------------- | -------------------- | -------------------- | -------------- |
| `c`                  | :green_square:       | :green_square:       | :green_square: |
| `cpp`                | :green_square:       | :green_square:       | :green_square: |
| `elixir`             | :white_large_square: | :green_square:       | :green_square: |
| `foam`               | :white_large_square: | :green_square:       | :green_square: |
| `go`                 | :green_square:       | :green_square:       | :green_square: |
| `javascript` / `jsx` | :white_large_square: | :green_square:       | :green_square: |
| `julia`              | :white_large_square: | :green_square:       | :green_square: |
| `lua`                | :green_square:       | :green_square:       | :green_square: |
| `php`                | :green_square:       | :green_square:       | :green_square: |
| `python`             | :green_square:       | :green_square:       | :green_square: |
| `r`                  | :green_square:       | :green_square:       | :green_square: |
| `ruby`               | :green_square:       | :green_square:       | :green_square: |
| `rust`               | :green_square:       | :green_square:       | :green_square: |
| `scss`               | :white_large_square: | :white_large_square: | :green_square: |
| `typescript` / `tsx` | :white_large_square: | :green_square:       | :green_square: |
| `fennel`             | :green_square:       | :green_square:       | :green_square: |
| `nix`                | :white_large_square: | :white_large_square: | :green_square: |

## textsubjects-smart

**Patterns**: comments, consecutive line comments, function calls, function definitions, class definitions, loops, if statements, return values, arguments.

See `queries/*/textsubjects-smart.scm` for full information about the query.

## textsubjects-container-outer

**Patterns**: classes, structs, functions, methods.

See `queries/*/textsubjects-container-outer.scm` for full information about the query.

## textsubjects-container-inner

**Patterns**: insides of classes, structs, functions, methods.

See `queries/*/textsubjects-container-inner.scm` for full information about the query.

## Custom queries

You can define your own text subjects by creating a Tree-sitter query file in your runtime path (e.g. `queries/<lang>/textsubjects-foo.scm`) and using it in your configuration:

```lua
require('nvim-treesitter-textsubjects').configure({
    keymaps = {
        ['<cr>'] = 'textsubjects-foo',
    },
})
```

Queries use `@range` captures to define text objects' boundaries:

```scheme
(comment) @range
```

Quantified captures create ranges from multiple nodes (e.g. all statements in a block):

```scheme
(compound_statement (_)+ @range)
```

See `queries/*/textsubjects-smart.scm` for examples or open an issue if you need any help writing a query.

# Alternatives

- [nvim-treesitter-textobjects](https://github.com/nvim-treesitter/nvim-treesitter-textobjects): I still use this and it's a great plugin (especially the `lookahead` feature 😉). If you want to target the textobject exactly then this plugin is the way to go. However, it can quickly lead to having too many text object mappings (I had 8 before making this plugin) and it will always deal with whitespace based on the way you invoked it rather than handling this heuristically.
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)-incremental-selection-mod: This is similar but doesn't act as a text objects. When incrementing the selection it will do so strictly by scope or by looking at the parent node which is often way too strict for practical use. For example, it will select all the arguments in `(`,`)` then can be expanded a few times to reach the next scope inside `{`,`}`, but these can both be selected more directly with `ib` and `iB` respectively so it would make more sense to skip them since the user probably doesn't want to select them. Incremental selection sounds nice but often isn't how people edit text (at least not me). On top of all this, it's strict with whitespace whereas this plugin will try to handle it heuristically.
