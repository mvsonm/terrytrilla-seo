# frozen_string_literal: true

module ::TerrytrillaSeo
  # B7 (decision Р-8): a knowledge-base article is an `Article`, not a forum discussion.
  #
  # Core hardcodes `DiscussionForumPosting` as the container of the crawler view, and
  # discourse-solved replaces it with `QAPage` when a topic has an accepted answer. Both
  # are wrong for the knowledge base: the article is written by the project, not asked by
  # a reader. The container type comes from the same modifier (plugins apply in
  # alphabetical order, so `terrytrilla-seo` has the last word over `discourse-solved`).
  #
  # The template's own microdata says headline, dates and publisher, but names the author
  # as the person who posted. For the knowledge base the author is the project, so the
  # article is also described by JSON-LD, which is what search engines read first.
  module ArticleSchema
    def self.article?(topic)
      return false unless SiteSetting.terrytrilla_seo_enabled
      return false if topic.nil?
      return false if Indexing.knowledge_base_category_ids.exclude?(topic.category_id)
      Indexing.indexable?(topic)
    end

    def self.container_schema(topic)
      return nil unless article?(topic)
      { itemscope: true, itemtype: "https://schema.org/Article" }
    end

    def self.organization
      site = SiteSetting.terrytrilla_seo_organization_url.to_s.strip
      org = {
        "@type" => "Organization",
        "name" => SiteSetting.company_name.presence || SiteSetting.title,
      }
      org["url"] = site if site.present?
      org
    end

    # `title` and `image` come from the page: the title is in the language of the page,
    # the image is the card of B4.
    def self.json_ld(topic, title:, url:, image: nil)
      return nil unless article?(topic)

      first_post =
        Post.where(topic_id: topic.id, post_number: 1).pick(:created_at, :last_version_at)
      published, modified = first_post

      data = {
        "@context" => "https://schema.org",
        "@type" => "Article",
        "headline" => title.presence || topic.title,
        "mainEntityOfPage" => url,
        "datePublished" => (published || topic.created_at).iso8601,
        "dateModified" => (modified || published || topic.created_at).iso8601,
        "author" => organization,
        "publisher" => organization,
        "inLanguage" => I18n.locale.to_s.tr("_", "-"),
      }
      data["image"] = image if image.present?
      data
    end
  end
end
