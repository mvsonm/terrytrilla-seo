# frozen_string_literal: true

module ::TerrytrillaSeo
  # B1 (decision Р-6): hreflang only for languages a topic is actually translated into.
  #
  # Core declares every supported locale on every page. Measured on 17.09: 8 of 15 public
  # topics without a single translation declared 12 languages, and under `?tl=de` the
  # crawler got the Russian or English original — "language of the body = declared
  # language" failed.
  #
  # A language is declared for a topic when
  #   - it is the topic's original language (always, unless unsupported), or
  #   - the title has a TopicLocalization in it AND every visible post is either written
  #     in it or has a PostLocalization in it.
  # ⚠️ `has_localization?` is NOT used: it falls back to the default locale
  # (`content_localization_use_default_locale_when_unsupported`), measured
  # `has_localization?("xx") = true`.
  #
  # Locales are compared by base language (`pt` = `pt_BR`), as the AI translator does.
  module Hreflang
    def self.active?
      SiteSetting.terrytrilla_seo_enabled
    end

    def self.base(locale)
      locale.to_s.downcase.tr("-", "_").split("_").first
    end

    def self.supported_locales
      SiteSetting.content_localization_supported_locales.to_s.split("|").reject(&:blank?)
    end

    # Languages taken out of hreflang by hand, e.g. after a core update hits one language
    # (TZ §8): they are removed, not "fixed". The original language is never excluded.
    def self.excluded_bases
      SiteSetting.terrytrilla_seo_hreflang_excluded_locales.to_s.split("|").map { |l| base(l) }
    end

    # Posts a crawler reads on the topic page. Deleted posts are already out: Post is
    # Trashable, its default scope drops them.
    def self.visible_posts(topic)
      topic
        .posts
        .where(hidden: false)
        .where(post_type: [Post.types[:regular], Post.types[:moderator_action]])
        .where.not(raw: [nil, ""])
    end

    # Supported locales (in the form of the setting) the topic is declared in.
    # A topic without a detected language gets none: only x-default.
    def self.locales_for(topic)
      return [] if topic.locale.blank?

      original = base(topic.locale)
      excluded = excluded_bases
      title_bases = TopicLocalization.where(topic_id: topic.id).pluck(:locale).map { |l| base(l) }

      posts = visible_posts(topic).pluck(:id, :locale)
      post_bases = Hash.new { |hash, key| hash[key] = [] }
      PostLocalization
        .where(post_id: posts.map(&:first))
        .pluck(:post_id, :locale)
        .each { |post_id, locale| post_bases[post_id] << base(locale) }

      supported_locales.select do |locale|
        language = base(locale)
        next true if language == original
        next false if excluded.include?(language)
        next false if title_bases.exclude?(language)
        posts.all? do |post_id, post_locale|
          base(post_locale) == language || post_bases[post_id].include?(language)
        end
      end
    end

    # [[hreflang, href], …] for a topic page. `url` is the address without query.
    # A topic that is not indexable (B3) gets no hreflang at all.
    def self.links(topic, url)
      return [] if Indexing.noindex_for?(topic)

      default = base(SiteSetting.default_locale)
      links = [["x-default", url]]
      locales_for(topic).each do |locale|
        href = base(locale) == default ? url : "#{url}?#{Discourse::LOCALE_PARAM}=#{locale}"
        links << [locale.tr("_", "-"), href]
      end
      links
    end
  end
end
