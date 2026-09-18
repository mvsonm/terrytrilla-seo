# frozen_string_literal: true

module ::TerrytrillaSeo
  # B10: the sitemap lists only indexable topics (B3).
  #
  # Core lists every visible topic of a public category — unanswered questions, category
  # description topics, site feedback — i.e. URLs that answer `noindex`. A sitemap URL with
  # noindex is a mixed signal (check Б4 of gate §7.1).
  #
  # `sitemap_topics` is private and returns a relation: callers pluck and take maximum, so
  # the filter is added to the relation (SQL WHERE comes before core's LIMIT/OFFSET, so
  # pages stay correct).
  #
  # lastmod: core writes bumped_at. The TZ asks for the date of a meaningful change — a new
  # reply or an edit of the first post — so the third plucked column becomes
  # GREATEST(last reply, last revision of the first post). Edits within the grace period
  # make no revision and do not move it.
  #
  # ⚠️ Pages are cached for 24 hours in Redis and survive a rebuild: after rollout delete
  # `sitemap/*` (OPERATIONS.md).
  module SitemapTopics
    # Страницы карты живут в кеше 24 часа. Сбрасывается при смене адреса темы
    # (B8) и после выката (`apply-seo-plugin.rb`).
    def self.flush_cache
      Sitemap.all.each { |s| Discourse.cache.delete("sitemap/#{s.name}/#{s.max_page_size}") }
      # У карты страниц (B10-бис) ключ кеша составлен из даты, а не из размера страницы:
      # цикл выше его не покрывает.
      Discourse.cache.delete(SitemapPages.cache_key)
    end

    LASTMOD_SQL = <<~SQL.squish
      GREATEST(
        topics.last_posted_at,
        (SELECT p.last_version_at FROM posts p
          WHERE p.topic_id = topics.id AND p.post_number = 1 AND p.deleted_at IS NULL)
      )
    SQL

    def topics
      return super unless SiteSetting.terrytrilla_seo_enabled
      return super if name == Sitemap::NEWS_SITEMAP_NAME

      lastmod = Arel.sql(LASTMOD_SQL)
      if name == Sitemap::RECENT_SITEMAP_NAME
        sitemap_topics.pluck(:id, :slug, lastmod, :updated_at, :posts_count)
      else
        sitemap_topics.pluck(:id, :slug, lastmod, :updated_at)
      end
    end

    private

    def sitemap_topics
      relation = super
      return relation unless SiteSetting.terrytrilla_seo_enabled
      Indexing.indexable_scope(relation)
    end
  end
end
