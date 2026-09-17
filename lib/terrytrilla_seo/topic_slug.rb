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

    # Recompute and store the slug of one topic. Returns [old, new] when it changed.
    def self.recompute!(topic)
      return nil unless active?
      wanted = topic.slug_for_topic(topic.title)
      return nil if wanted.blank? || wanted == topic.read_attribute(:slug)
      old = topic.read_attribute(:slug)
      topic.update_column(:slug, wanted)
      [old, wanted]
    end

    def self.recompute_all!
      Topic.where(archetype: Archetype.default).find_each.filter_map do |topic|
        changed = recompute!(topic)
        changed && [topic.id, *changed]
      end
    end
  end
end
