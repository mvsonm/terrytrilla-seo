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

    def self.noindex_for?(topic)
      SiteSetting.terrytrilla_seo_enabled && !indexable?(topic)
    end
  end
end
