# terrytrilla-seo

Discourse plugin for [TerryTrilla Community](https://terrytrilla.club): the search and
link-preview layer of a forum that is written in twelve languages.

What it will do (tasks B1–B13 of the forum launch plan):

- declare `hreflang` only for languages a topic is actually translated into;
- decide what goes into the index: knowledge base, answered topics, listed categories;
- serve crawlers the forum language on URLs without `?tl`, and redirect `?tl=en` for them;
- build topic slugs from the English title;
- `Article` structured data for knowledge-base articles, `og:type`, `og:locale`,
  `max-image-preview:large`;
- link-preview images per topic and language, titles in the page language;
- a sitemap built only from indexable pages;
- a search-engine friendly home page.

The plugin is **off by default** (`terrytrilla_seo_enabled`).

## Core touch points

Every place where the plugin changes Discourse core behaviour (`prepend`, `register_*`,
modifiers, overridden views) is listed here, so that a Discourse upgrade can be checked
against this list.

| file | what | why |
|---|---|---|
| — | none yet | skeleton |

## Development

The plugin is developed against a local Discourse of **the same version as production**
(`2026.9.0-latest`, core commit `c124ff3e49fd3810cc7453cb714571e48a3d7744`), never on the
live forum. CI runs lint and specs on `discourse/discourse_test` with the same core commit.

```bash
# inside a Discourse checkout at that commit, with this repo in plugins/terrytrilla-seo
LOAD_PLUGINS=1 bin/rspec plugins/terrytrilla-seo/spec
```

## Installation

Added to `containers/app.yml` hooks like any Discourse plugin:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/mvsonm/terrytrilla-seo.git
```

## License

MIT
