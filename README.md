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
- a sitemap built only from indexable pages — topics, the home page and the categories;
- a search-engine friendly home page.

The plugin is **off by default** (`terrytrilla_seo_enabled`).

Settings:

| setting | default | meaning |
|---|---|---|
| `terrytrilla_seo_enabled` | false | the whole layer |
| `terrytrilla_seo_freeze_slugs` | false | never change topic URLs again — turn on when the forum opens to search |
| `terrytrilla_seo_indexable_categories` | — | the ONLY categories whose topics may be indexed |
| `terrytrilla_seo_knowledge_base_categories` | — | articles indexable without replies (must also be in the list above) |
| `terrytrilla_seo_organization_url` | `https://terrytrilla.com` | author and publisher of knowledge-base articles in structured data |
| `terrytrilla_seo_og_card_base` | `https://terrytrilla.com/api/og/forum` | link-card generator of the site; empty — topics keep the forum card |
| `terrytrilla_seo_hreflang_excluded_locales` | — | languages removed from hreflang by hand; the original language of a topic is always declared |

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
| `plugin.rb` | `TopicsController.after_action(only: :show)` — `X-Robots-Tag: noindex` | B3: non-indexable topics; skipped while `allow_index_in_robots_txt` is off, otherwise it would weaken core’s `noindex, nofollow` |
| `plugin.rb` | `register_html_builder` `server:before-head-close` and `-crawler` — meta robots | B3: the same rule in both layouts |
| `app/views/common/_hreflang_tags.html.erb` + `prepend_view_path` in `plugin.rb` | overrides core’s partial of the same name (crawler layout) | B1: a topic page declares only translated languages; every other page renders core’s markup, **copied into the partial — compare it with core’s file on every upgrade** |
| `plugin.rb` | `ApplicationController.prepend_before_action` — 301 | B2: for a crawler `?tl=en` → URL without `tl` (other parameters kept), `?tl=pl` → `?tl=pl_PL`; people never redirected; AnonymousCache and CrawlerHooks handle only 200, so nothing intercepts it |
| `lib/terrytrilla_seo/topic_meta.rb` | `ApplicationHelper.prepend` — `crawlable_meta_data` on a topic page | B4: the site card per topic and language with size, type and alt, `og:url` = canonical; B5: `og:type=article`, `og:locale`, `article:modified_time` |
| `app/views/layouts/_noscript_header.html.erb` + `prepend_view_path` | overrides core’s header of the crawler layout | B13: on the crawler home page the community name becomes the H1 and the description is taken in the language of the request (core prints it in the default language); core’s markup is **copied into the partial — compare it with core’s file on every upgrade** |
| `app/views/connectors/robots_txt_index/` | connector appended to core’s robots.txt | B9: search and answer engines get the forum, collectors of training corpora get `Disallow: /`; core’s template can only write `Disallow`, so `Allow` lives here. Dead until G1: while `overridden_robots_txt` is set the template is not rendered |
| `lib/terrytrilla_seo/article_schema.rb` + `plugin.rb` | modifier `topic_crawler_container_schema`, JSON-LD in `server:before-head-close-crawler` | B7: a knowledge-base article is `Article` (last word over `discourse-solved`), author and publisher — the project |
| `lib/terrytrilla_seo/sitemap_topics.rb` | `Sitemap.prepend` — private `sitemap_topics` (relation, filtered by `Indexing.indexable_scope`) and `topics` (lastmod column) | B10: only indexable topics in the sitemap; lastmod = latest reply or revision of the first post. ⚠️ Sitemap pages are cached 24 h and survive a rebuild — delete `sitemap/*` after rollout |
| `lib/terrytrilla_seo/sitemap_pages.rb`, `app/controllers/terrytrilla_seo/sitemap_pages_controller.rb` | `Sitemap.prepend` (`last_posted_topic`, `topics`), `Sitemap.singleton_class.prepend` (`regenerate_sitemaps`), route `/sitemap_pages.xml` appended to core routes | B10-bis: the home page and the categories in the sitemap. Core lists topics only, and its route accepts numeric sitemap names only. The record in `sitemaps` puts the map into core's index without overriding the view; `regenerate_sitemaps` must re-add the name, otherwise the nightly job disables it |
| `lib/terrytrilla_seo/crawler_locale.rb` | `Discourse.singleton_class.prepend` — `anonymous_locale` | B12: a crawler without `?tl` gets the default language, Accept-Language ignored; the anonymous cache key uses the same method |

## Indexing rule (B3)

`TerrytrillaSeo::Indexing.indexable?(topic)` — one method for every task that needs it (hreflang, meta robots, sitemap, home page). A topic is indexable when it is a regular visible topic, its category is public and in the explicit list, it is not a category description, and it is either a knowledge-base article or has at least one reply.

## hreflang (B1)

`TerrytrillaSeo::Hreflang.locales_for(topic)`. A language is declared when it is the topic’s original language, or the title is translated into it **and** every visible post is written in it or translated into it. Languages are compared by base (`pt` = `pt_BR`), as the AI translator does. A topic without a detected language gets only `x-default`; a non-indexable topic (B3) gets no hreflang. The default language (`en`) and `x-default` point at the URL without `?tl`. `has_localization?` is not used: it falls back to the default locale and answers `true` for any language.

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
