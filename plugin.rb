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
require_relative "lib/terrytrilla_seo/indexing"
require_relative "lib/terrytrilla_seo/crawler_locale"
require_relative "lib/terrytrilla_seo/hreflang"

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

  # ── B3: what goes into search indexes ───────────────────────────────────────
  # Header. ⚠️ While the forum is closed (allow_index_in_robots_txt = false) core sets
  # "noindex, nofollow" on every page — but only if the header is still empty, and this
  # callback runs BEFORE core's. Writing "noindex" here would silently weaken the closed
  # forum to plain "noindex" (caught by a spec). So on a closed forum: leave it to core.
  TopicsController.after_action(only: :show) do
    next unless SiteSetting.allow_index_in_robots_txt
    topic = @topic_view&.topic
    next unless TerrytrillaSeo::Indexing.noindex_for?(topic)
    current = response.headers["X-Robots-Tag"].to_s
    next if current.include?("noindex")
    response.headers["X-Robots-Tag"] = current.present? ? "noindex, #{current}" : "noindex"
  end

  # Meta tag in both layouts: people (application) and crawlers (crawler layout).
  %w[server:before-head-close server:before-head-close-crawler].each do |outlet|
    register_html_builder(outlet) do |controller|
      next "" unless controller.is_a?(TopicsController) && controller.action_name == "show"
      topic = controller.instance_variable_get(:@topic_view)&.topic
      TerrytrillaSeo::Indexing.noindex_for?(topic) ? '<meta name="robots" content="noindex">' : ""
    end
  end

  # ── B12: crawler language on a URL without ?tl ─────────────────────────────
  Discourse.singleton_class.prepend(TerrytrillaSeo::CrawlerLocale)

  # ── B1: hreflang only for translated languages ─────────────────────────────
  # Overrides core's common/_hreflang_tags partial (crawler layout). The view path is
  # global, so the partial itself falls back to core's markup when the plugin is off.
  ::ActionController::Base.prepend_view_path File.expand_path("../app/views", __FILE__)
end
