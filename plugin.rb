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

require_relative "lib/terrytrilla_seo/engine"
require_relative "lib/terrytrilla_seo/topic_slug"
require_relative "lib/terrytrilla_seo/indexing"
require_relative "lib/terrytrilla_seo/crawler_locale"
require_relative "lib/terrytrilla_seo/hreflang"
require_relative "lib/terrytrilla_seo/crawler_locale_redirect"
require_relative "lib/terrytrilla_seo/sitemap_topics"
require_relative "lib/terrytrilla_seo/sitemap_pages"
require_relative "lib/terrytrilla_seo/site_text"
require_relative "lib/terrytrilla_seo/topic_meta"
require_relative "lib/terrytrilla_seo/article_schema"
require_relative "lib/terrytrilla_seo/home_page"
require_relative "lib/terrytrilla_seo/ai_crawlers"

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
    content = TerrytrillaSeo::Indexing.robots_content(@topic_view&.topic)
    next if content.nil?
    current = response.headers["X-Robots-Tag"].to_s
    next if current.include?("noindex")
    response.headers["X-Robots-Tag"] = current.present? ? "#{content}, #{current}" : content
  end

  # Meta tag in both layouts: people (application) and crawlers (crawler layout).
  # B6 lives here too: the same rule says `noindex` or `max-image-preview:large`.
  %w[server:before-head-close server:before-head-close-crawler].each do |outlet|
    register_html_builder(outlet) do |controller|
      next "" unless controller.is_a?(TopicsController) && controller.action_name == "show"
      topic = controller.instance_variable_get(:@topic_view)&.topic
      content = TerrytrillaSeo::Indexing.robots_content(topic)
      content ? %(<meta name="robots" content="#{content}">) : ""
    end
  end

  # ── B3-бис: список групп вне индекса ───────────────────────────────────────
  # Ядро закрывает заголовком `/u`, `/badges` и `/search`, а `/g` остаётся
  # открытым: замер 18.09 агентом Googlebot — 200 БЕЗ `X-Robots-Tag`, и в секции
  # `Googlebot` файла robots.txt запрета тоже нет, он есть только у `*`. Страница
  # пустая (публичных групп нет), заголовок — имя сообщества, то есть дубль
  # главной. Ровно то тонкое, ради чего заведён B3.
  #
  # ⚠️ Заголовком это не чинится, хотя `after_action :add_noindex_header` у
  # `GroupsController` в ядре СТОИТ. На `index` оболочку рисует не действие, а
  # исключение `check_xhr`, и цепочка `after_action` при этом не исполняется —
  # поэтому не срабатывает ни callback ядра, ни такой же от плагина (проверено
  # спеком: заголовка нет). Мета-тег рисуется в самой оболочке и доезжает.
  %w[server:before-head-close server:before-head-close-crawler].each do |outlet|
    register_html_builder(outlet) do |controller|
      controller.is_a?(GroupsController) ? %(<meta name="robots" content="noindex">) : ""
    end
  end

  # ── B13-бис: карточка ссылки на главную для НЕ-краулера ────────────────────
  # Тема рисует свою главную, и ядро отдаёт под неё оболочку без мета-тегов; краулеру
  # вместо неё подставляется `categories`. Кто представляется браузером — видел ссылку
  # без описания и картинки (замер владельца 18.09).
  register_html_builder("server:before-head-close") do |controller|
    TerrytrillaSeo::HomePage.meta_tags(controller).to_s
  end

  # ── B12: crawler language on a URL without ?tl ─────────────────────────────
  Discourse.singleton_class.prepend(TerrytrillaSeo::CrawlerLocale)

  # ── B2: ?tl=en → 301 without tl, ?tl=pl → ?tl=pl_PL — crawlers only ──────────
  # Prepended so the redirect happens before any rendering. AnonymousCache stores only 200
  # and CrawlerHooks rewrites only 200, so nothing downstream intercepts the 301.
  ApplicationController.prepend_before_action do
    target = TerrytrillaSeo::CrawlerLocaleRedirect.target(request)
    redirect_to(target, status: :moved_permanently) if target
  end

  # ── B10: sitemap only from indexable topics ────────────────────────────────
  Sitemap.prepend(TerrytrillaSeo::SitemapTopics)

  # ── B10-бис: главная и разделы в карте сайта ───────────────────────────────
  # Запись в таблице `sitemaps` кладёт свою карту в индекс карт (`/sitemap.xml`) без
  # переопределения вида, а содержимое отдаёт свой контроллер: маршрут ядра принимает
  # только числовые имена (`:page => /[1-9][0-9]*/`), поэтому `/sitemap_pages.xml`
  # объявляется здесь.
  Sitemap.prepend(TerrytrillaSeo::SitemapPages::Model)
  Sitemap.singleton_class.prepend(TerrytrillaSeo::SitemapPages::ClassMethods)

  Discourse::Application.routes.append do
    scope path: nil, format: true, constraints: { format: :xml } do
      get "/sitemap_pages" => "terrytrilla_seo/sitemap_pages#show"
    end
  end

  # ── B4, B5: link card and Open Graph of a topic page ───────────────────────
  ApplicationHelper.prepend(TerrytrillaSeo::TopicMeta::Helper)

  # ── B14: тексты форума в мета-тегах — на языке страницы, на любой странице ──
  # Единственная точка, через которую ядро пропускает и заголовок, и описание
  # КАЖДОЙ страницы. Точечные правки этот класс не закрывали: 18.09 починили
  # заголовок темы, 19.09 — описание главной, а лента и раздел остались
  # английскими на всех двенадцати языках (замер 19.09).
  register_modifier(:meta_data_content) do |content, _тип, _опции|
    TerrytrillaSeo::SiteText.на_языке_страницы(content)
  end

  # ── B7: a knowledge-base article is an Article ─────────────────────────────
  register_modifier(:topic_crawler_container_schema) do |schema, topic|
    TerrytrillaSeo::ArticleSchema.container_schema(topic) || schema
  end

  register_html_builder("server:before-head-close-crawler") do |controller|
    topic_view = controller.instance_variable_get(:@topic_view)
    topic = topic_view&.topic
    next "" unless topic
    title = topic_view.title
    url = controller.instance_variable_get(:@canonical_url).presence || topic.url
    image =
      topic_view.image_url.presence || TerrytrillaSeo::TopicMeta.card_url(topic, I18n.locale, title)
    data = TerrytrillaSeo::ArticleSchema.json_ld(topic, title: title, url: url, image: image)
    next "" unless data
    %(<script type="application/ld+json">#{MultiJson.dump(data)}</script>)
  end

  # ── B1: hreflang only for translated languages ─────────────────────────────
  # Overrides core's common/_hreflang_tags partial (crawler layout). The view path is
  # global, so the partial itself falls back to core's markup when the plugin is off.
  ::ActionController::Base.prepend_view_path File.expand_path("../app/views", __FILE__)
end
