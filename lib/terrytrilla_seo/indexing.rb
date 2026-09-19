# frozen_string_literal: true

module ::TerrytrillaSeo
  # B3 (decisions Р-5, Р-12): what goes into search indexes.
  #
  # Usefulness is judged over the whole site, and a young forum is mostly thin pages, so
  # only topics that already carry an answer — plus knowledge-base articles — are
  # indexable. Everything else gets `noindex` (header and meta), stays reachable for
  # people and is NOT unlisted: an unanswered question becomes indexable by itself once
  # someone replies.
  #
  # ONE method answers the question for every task that needs it: B1 (hreflang),
  # B6 (meta robots), B10 (sitemap), B13 (home page).
  module Indexing
    def self.category_ids(setting)
      SiteSetting.get(setting).to_s.split("|").map(&:to_i).reject(&:zero?)
    end

    def self.indexable_category_ids
      category_ids(:terrytrilla_seo_indexable_categories)
    end

    def self.knowledge_base_category_ids
      category_ids(:terrytrilla_seo_knowledge_base_categories)
    end

    # Categories are indexable only from an explicit list: a closed-today but translated
    # category (KB Drafts) must not enter the index the moment someone opens it.
    def self.indexable?(topic)
      return false if topic.nil? || topic.deleted_at.present?
      return false unless topic.archetype == Archetype.default
      return false unless topic.visible
      return false if topic.category.nil? || topic.category.read_restricted
      return false if indexable_category_ids.exclude?(topic.category_id)
      return false if topic.is_category_topic?
      return true if knowledge_base_category_ids.include?(topic.category_id)
      topic.posts_count.to_i > 1
    end

    # The same rule as SQL, for lists of topics (B10 sitemap, B13 home page).
    # ⚠️ Must stay equal to indexable? — a spec compares both on the same topics.
    def self.indexable_scope(relation)
      ids = indexable_category_ids
      return relation.none if ids.empty?

      kb = knowledge_base_category_ids
      answered =
        (
          if kb.empty?
            "topics.posts_count > 1"
          else
            ["topics.category_id IN (?) OR topics.posts_count > 1", kb]
          end
        )

      relation
        .where(archetype: Archetype.default, visible: true, category_id: ids)
        .joins(:category)
        .where(categories: { read_restricted: false })
        .where("NOT EXISTS (SELECT 1 FROM categories c WHERE c.topic_id = topics.id)")
        .where(answered)
    end

    def self.noindex_for?(topic)
      SiteSetting.terrytrilla_seo_enabled && !indexable?(topic)
    end

    # B6: what the robots directive of a topic page says. An indexable page asks for a
    # large image and a full snippet — without them there is no large picture in Discover.
    # ⚠️ Never `nosnippet` or `max-snippet:0`: that also switches off AI Overviews.
    INDEXABLE_ROBOTS = "max-image-preview:large, max-snippet:-1"

    def self.robots_content(topic)
      return nil unless SiteSetting.terrytrilla_seo_enabled
      return nil if topic.nil?
      indexable?(topic) ? INDEXABLE_ROBOTS : "noindex"
    end

    # B16 (замер владельца 19.09). Правило индексации для страниц БЕЗ темы.
    #
    # До него правило знало только темы, и на страницах без темы получалось два
    # расхождения с требованиями Google сразу:
    #
    #   • `/`, `/categories` и `/top` отдавали ОДИН И ТОТ ЖЕ заголовок
    #     «TerryTrilla Community», каждая самоканонична и открыта индексу. Для
    #     краулера `/` и `/categories` — вообще одна страница: ядро подставляет
    #     `custom_homepage_crawler_route = categories`. Это дубли на разных адресах;
    #   • у главной и разделов не было `max-image-preview:large`, хотя у тем было:
    #     без него в выдаче и в Discover нет крупной картинки.
    #
    # Правило решает по АДРЕСУ, а не по контроллеру: содержимое главной рисует
    # контроллер разделов, и по нему `/` и `/categories` неразличимы.
    #
    # Списки и служебные страницы закрываются, главная и разделы — открыты и просят
    # крупное превью. Это тот же Р-5, что и у тем: в индексе только то, что несёт
    # содержание, а не ещё один срез одного и того же списка.
    СПИСКИ = %w[
      /latest
      /top
      /categories
      /new
      /unread
      /hot
      /tags
      /docs
      /filter
      /review
    ].freeze

    def self.robots_meta_for_page(controller)
      return nil unless SiteSetting.terrytrilla_seo_enabled
      return nil if controller.is_a?(TopicsController) && controller.action_name == "show"

      # `/g` ядро оставляет открытым, а заголовком это не чинится: оболочку рисует
      # исключение `check_xhr`, и цепочка `after_action` не исполняется.
      return "noindex" if controller.is_a?(GroupsController)

      путь = controller.request.path.to_s.chomp("/")
      путь = "/" if путь.empty?
      return INDEXABLE_ROBOTS if путь == "/" || путь.start_with?("/c/")
      return "noindex" if СПИСКИ.any? { |список| путь == список || путь.start_with?("#{список}/") }
      nil
    rescue StandardError
      nil
    end
  end
end
