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

Settings:

| setting | default | meaning |
|---|---|---|
| `terrytrilla_seo_enabled` | false | the whole layer |
| `terrytrilla_seo_freeze_slugs` | false | never change topic URLs again — turn on when the forum opens to search |

One-off task after installing: `bin/rake terrytrilla_seo:recompute_slugs`.

## Core touch points

Every place where the plugin changes Discourse core behaviour (`prepend`, `register_*`,
modifiers, overridden views) is listed here, so that a Discourse upgrade can be checked
against this list.

| file | what | why |
|---|---|---|
| `plugin.rb` | `Topic.slug_computed_callbacks` | B8: slug of a non-Latin title from its English translation |
| `plugin.rb` | `add_model_callback(TopicLocalization, :after_commit)` | B8: the English translation appears after the topic; core has no event for it |
| `plugin.rb` | modifier `redirect_to_correct_topic_additional_query_parameters` + `:tl` | B8: the 301 from an old topic URL kept dropping the language |

## Development

> ⚠️ `required_version` is `2026.9.0-latest`, not `2026.9.0`: production reports
> `2026.9.0-latest`, which version comparison treats as a pre-release of 2026.9.0 —
> with `2026.9.0` the plugin silently does not activate ("discourse does not meet
> required version").


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
