# frozen_string_literal: true

module ::TerrytrillaSeo
  # B9 (decision Р-9): AI crawlers are treated exactly as on the site —
  # search is welcome, training corpora are not.
  #
  # Two groups, and the split is not by company but by what the crawler does:
  #   • search and answer engines get the forum, minus the service paths that are
  #     useless to them (search, feeds, user pages);
  #   • collectors of training corpora get nothing.
  #
  # ⚠️ Core's robots.txt template can only write `Disallow`, and the `:robots_info`
  # event has no place for `Allow` — hence the connector
  # `app/views/connectors/robots_txt_index/`, which appends these groups to the file.
  #
  # ⚠️ While `overridden_robots_txt` is set (the closed forum before G1), core returns
  # that text and never renders the template — the connector is dead code until G1.
  # The same on `allow_index_in_robots_txt = false`: the file is `Disallow: /` for
  # everyone, and adding `Allow` under it would be a promise the forum does not keep.
  #
  # The lists mirror `apps/web/src/app/robots.ts` of the site. ⚠️ `ChatGPT-User`,
  # `Perplexity-User` and `meta-externalfetcher` are NOT here: they fetch on a
  # person's request and ignore robots.txt. Nothing is claimed about them in the file.
  module AiCrawlers
    # Search and answer engines: the forum is open to them.
    SEARCH_AGENTS = %w[
      ClaudeBot
      Claude-SearchBot
      GPTBot
      OAI-SearchBot
      PerplexityBot
      Google-Extended
    ].freeze

    # Collectors of training corpora: closed, as on the site (and in Cloudflare).
    TRAINING_AGENTS = %w[
      CCBot
      Bytespider
      Amazonbot
      meta-externalagent
      FacebookBot
      TikTokSpider
    ].freeze

    # Service paths: no use to an answer engine, and they multiply crawling.
    DENY_PATHS = %w[
      /admin/
      /auth/
      /email/
      /session
      /user-api-key
      /search
      /my
      /g
      /badges
      /u/
      /tag/*/l
      /t/*/*.rss
      /c/*.rss
    ].freeze

    def self.active?
      SiteSetting.terrytrilla_seo_enabled && SiteSetting.allow_index_in_robots_txt &&
        SiteSetting.overridden_robots_txt.blank?
    end

    # [[agent, [allow…], [disallow…]], …] — in the order they go into the file.
    def self.groups
      return [] unless active?

      search = SEARCH_AGENTS.map { |agent| [agent, ["/"], DENY_PATHS] }
      training = TRAINING_AGENTS.map { |agent| [agent, [], ["/"]] }
      search + training
    end
  end
end
