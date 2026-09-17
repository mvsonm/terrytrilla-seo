# frozen_string_literal: true

# name: terrytrilla-seo
# about: Search and link-preview layer for TerryTrilla Community: hreflang only for translated languages, indexing rules, structured data, language of URLs for crawlers, link-preview images.
# version: 0.2.0
# authors: TerryTrilla
# url: https://github.com/mvsonm/terrytrilla-seo
# required_version: 2026.9.0-latest

enabled_site_setting :terrytrilla_seo_enabled

module ::TerrytrillaSeo
  PLUGIN_NAME = "terrytrilla-seo"
end

require_relative "lib/terrytrilla_seo/topic_slug"

after_initialize do
  # Every change to core behaviour is listed in README.md («Core touch points»),
  # so that a Discourse upgrade can be checked against that list.

  # ── B8: topic URL from the English title ────────────────────────────────────
  Topic.slug_computed_callbacks << ->(topic, slug, title) do
    TerrytrillaSeo::TopicSlug.computed(topic, slug, title)
  end

  add_model_callback(TopicLocalization, :after_commit, on: %i[create update]) do
    next unless locale == "en"
    next unless TerrytrillaSeo::TopicSlug.active?
    TerrytrillaSeo::TopicSlug.recompute!(topic) if topic
  end

  # The 301 from an old topic URL used to drop `?tl`: /t/topic/27?tl=ja → /t/…/27.
  register_modifier(:redirect_to_correct_topic_additional_query_parameters) do |params|
    SiteSetting.terrytrilla_seo_enabled ? params + [:tl] : params
  end
end
