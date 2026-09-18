# frozen_string_literal: true

require "digest"

module ::TerrytrillaSeo
  # B4 and B5: Open Graph of a topic page — the link card in messengers and social networks.
  #
  # B4 (decision Р-2). A topic without an image of its own gets a card drawn by the site
  # for this topic in the page language: `<card base>?topic=<id>&locale=<locale>&v=<version>`
  # (D6, AFel). Discourse takes image sizes from an upload, and an external image has none,
  # so width, height and type are set here; `og:image:alt` is the title in the page
  # language. Core writes `twitter:card = summary_large_image` only with a large image in
  # the options, so the same card goes there too. `v` changes with the title, so a
  # retitled topic is not stuck with the old card in messenger caches.
  #
  # B5. `og:type` is hardcoded `website` in core — on a topic it becomes `article`, with
  # `og:locale` of the page language and `article:modified_time` = the last revision of
  # the first post (not the last reply: a reply does not change the article).
  # ⚠️ Only on a topic page: without that check `/latest` became `article` too (probe).
  #
  # `og:url` = the canonical URL: core takes `request.fullpath` and carries any query junk.
  module TopicMeta
    CARD_WIDTH = 1200
    CARD_HEIGHT = 630

    # Discourse locale → Open Graph locale (TZ B5). Unknown → nil, no tag.
    OG_LOCALES = {
      "en" => "en_US",
      "ru" => "ru_RU",
      "de" => "de_DE",
      "es" => "es_ES",
      "fr" => "fr_FR",
      "ar" => "ar_AR",
      "it" => "it_IT",
      "ja" => "ja_JP",
      "ko" => "ko_KR",
      "pl" => "pl_PL",
      "pt" => "pt_BR",
      "uk" => "uk_UA",
    }.freeze

    def self.og_locale(locale)
      OG_LOCALES[locale.to_s.downcase.tr("-", "_").split("_").first]
    end

    def self.card_url(topic, locale, title)
      base = SiteSetting.terrytrilla_seo_og_card_base.to_s.strip
      return if base.blank?
      version = Digest::SHA1.hexdigest("#{topic.id}|#{locale}|#{title}")[0, 8]
      query = { topic: topic.id, locale: locale.to_s, v: version }.to_query
      "#{base}?#{query}"
    end

    def self.modified_time(topic)
      Post.where(topic_id: topic.id, post_number: 1).pick(:last_version_at)&.iso8601
    end

    def self.tag(helper, attributes)
      helper.tag(:meta, attributes)
    end

    # На страницах БЕЗ темы (главная, разделы, списки) картинку карточки даёт
    # настройка форума, и ядро не объявляет её размеры: размеры оно берёт только
    # у картинки темы. Клиенты мессенджеров без размеров иногда не рисуют карточку
    # вовсе (17.09: владелец не увидел карточку главной в Telegram).
    #
    # Размеры берутся у самой загрузки, а не пишутся числом: заменят картинку —
    # объявление останется правдой.
    def self.с_размерами_бренда(opts)
      opts = (opts || {}).dup
      return opts if opts[:image].present?

      upload = SiteSetting.opengraph_image
      return opts unless upload.respond_to?(:width) && upload.width.to_i.positive?

      opts[:image] = UrlHelper.absolute(upload.url)
      # ⚠️ `x_summary_large_image` обязателен ВМЕСТЕ с `image`. Ядро ставит его само,
      # но только когда картинку подставляет тоже само (application_helper.rb:
      # `if opts[:image].blank?`). Стоило подставить картинку раньше — и
      # `twitter:card` стал `summary`: карточка главной в Telegram сжалась в иконку
      # (замер владельца 18.09). Размеры добавились, а карточка испортилась.
      opts[:x_summary_large_image] = opts[:image]
      opts[:image_width] = upload.width
      opts[:image_height] = upload.height
      type = MiniMime.lookup_by_extension(upload.extension.to_s)&.content_type
      opts[:image_type] = type if type
      opts
    end

    module Helper
      def crawlable_meta_data(opts = nil)
        topic_view = instance_variable_get(:@topic_view)
        на_теме =
          topic_view && controller.is_a?(TopicsController) && controller.action_name == "show"
        return super unless SiteSetting.terrytrilla_seo_enabled
        return super(TopicMeta.с_размерами_бренда(opts)) unless на_теме

        topic = topic_view.topic
        opts = (opts || {}).dup
        opts[:url] = @canonical_url if @canonical_url.present?

        card = nil
        if opts[:image].blank?
          card = TopicMeta.card_url(topic, I18n.locale, opts[:title])
          if card
            opts[:image] = card
            opts[:x_summary_large_image] = card
            opts[:image_width] = CARD_WIDTH
            opts[:image_height] = CARD_HEIGHT
            opts[:image_type] = "image/png"
          end
        end

        html = super(opts)

        html =
          html.sub('property="og:type" content="website"', 'property="og:type" content="article"')

        extra = []
        if (locale = TopicMeta.og_locale(I18n.locale))
          extra << TopicMeta.tag(self, property: "og:locale", content: locale)
        end
        if (modified = TopicMeta.modified_time(topic))
          extra << TopicMeta.tag(self, property: "article:modified_time", content: modified)
        end

        if card && opts[:title].present?
          alt = TopicMeta.tag(self, property: "og:image:alt", content: opts[:title])
          # Right after the card's own og:image:* tags: a consumer reads og:image:* as
          # properties of the og:image above them (check Ж3 of gate §7.1).
          anchor = /<meta property="og:image:type"[^>]*>/
          html = anchor.match?(html) ? html.sub(anchor) { |m| "#{m}\n#{alt}" } : html
        end

        [html, *extra].join("\n")
      end
    end
  end
end
