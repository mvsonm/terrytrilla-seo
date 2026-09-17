# frozen_string_literal: true

module ::TerrytrillaSeo
  # B8 (decision Р-4): a topic URL is built from the English title.
  #
  # Discourse builds the slug from the original title. With `default_locale = en` the
  # ascii generator drops Cyrillic, Japanese, Korean and Arabic letters entirely, so every
  # such topic gets the placeholder slug `topic` — `/t/topic/27`. For those topics the slug
  # is taken from the English TopicLocalization instead.
  #
  # - Titles written in Latin script (English, Portuguese, German…) keep the core slug:
  #   it is readable, and there is no English translation of an English topic anyway.
  # - The translation usually appears AFTER the topic is created, and core has no event
  #   for it, so the slug is recomputed from an after_commit callback on TopicLocalization.
  # - Once the forum is open to search, slugs must not move (every change is a 301):
  #   `terrytrilla_seo_freeze_slugs` stops all recomputation.
  module TopicSlug
    PLACEHOLDER = "topic"

    def self.active?
      SiteSetting.terrytrilla_seo_enabled && !SiteSetting.terrytrilla_seo_freeze_slugs
    end

    # Latin letters are fewer than half of all letters → the core slug is not readable.
    def self.non_latin?(title)
      letters = title.to_s.scan(/\p{L}/)
      return false if letters.empty?
      letters.count { |c| c.match?(/\p{Latin}/) } * 2 < letters.size
    end

    # Hook for Topic.slug_computed_callbacks: (topic, slug, title) → slug
    def self.computed(topic, slug, title)
      return slug unless active?
      return slug unless non_latin?(title)
      english_slug(topic) || slug
    end

    def self.english_slug(topic)
      return nil unless topic&.id
      english = TopicLocalization.find_by(topic_id: topic.id, locale: "en")&.title
      return nil if english.blank?
      candidate = Slug.for(english)
      candidate == PLACEHOLDER ? nil : candidate
    end

    # Store the slug from the English title of one topic. Returns [old, new] when it changed.
    #
    # ⚠️ Only ever moves a slug TO the English one. On 17.09 the first rollout recomputed
    # with core's generator instead, and two topics whose slugs had been transliterated
    # when the forum still ran in Russian (t/2, t/6 — no English translation) became
    # `topic`. A topic without an English title keeps whatever slug it has.
    def self.recompute!(topic)
      return nil unless active?
      return nil unless non_latin?(topic.title)
      wanted = english_slug(topic)
      return nil if wanted.nil? || wanted == topic.read_attribute(:slug)
      old = topic.read_attribute(:slug)
      topic.update_column(:slug, wanted)
      # ⚠️ Карта сайта кешируется на 24 часа, и адрес в ней остаётся старым: шлюз
      # запуска 17.09 нашёл в карте `/t/topic/15` через час после того, как тема
      # получила английский адрес. Сброс здесь — там же, где адрес меняется.
      SitemapTopics.flush_cache
      [old, wanted]
    end

    def self.recompute_all!
      Topic
        .where(archetype: Archetype.default)
        .find_each
        .filter_map do |topic|
          changed = recompute!(topic)
          changed && [topic.id, *changed]
        end
    end
  end
end
