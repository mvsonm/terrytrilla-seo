# frozen_string_literal: true

module ::TerrytrillaSeo
  # B2 (decision Р-7): one language — one URL, for crawlers.
  #
  # Measured on 17.09: the URL without `?tl` and `?tl=en` served the same English page, both
  # self-canonical. And `?tl=pl` served Polish (`lang=pl-PL`) while canonical dropped `tl`,
  # because the supported locale is `pl_PL`.
  #
  # For a crawler:
  #   ?tl=en (the default language, any spelling) → 301 to the URL without `tl`;
  #   ?tl=pl, ?tl=pt, ?tl=pt-BR                    → 301 to ?tl=pl_PL, ?tl=pt_BR.
  # Other query parameters (`page`) are kept.
  #
  # People are never redirected: for them a URL without `?tl` follows the browser language,
  # and a German reader following a link "in English" would get German (PREFLIGHT П-5).
  # Only a crawler gets the default language on a plain URL — that is B12, same detection.
  module CrawlerLocaleRedirect
    def self.base(locale)
      locale.to_s.downcase.tr("-", "_").split("_").first
    end

    # The address to redirect to, or nil.
    def self.target(request)
      return unless SiteSetting.terrytrilla_seo_enabled
      return unless ContentLocalization.crawler_locale_param_enabled?
      return unless request.get?

      value = request.query_parameters[Discourse::LOCALE_PARAM]
      return unless value.is_a?(String) && value.present?
      return unless CrawlerDetection.crawler_layout_request?(request)
      return unless CrawlerDetection.crawler?(request.user_agent, request.headers["HTTP_VIA"])

      language = base(value)
      replacement =
        if language == base(SiteSetting.default_locale)
          nil
        else
          supported =
            SiteSetting.content_localization_supported_locales.to_s.split("|").reject(&:blank?)
          return if supported.include?(value)
          matches = supported.select { |locale| base(locale) == language }
          return if matches.size != 1
          matches.first
        end

      query = request.query_parameters.except(Discourse::LOCALE_PARAM)
      query[Discourse::LOCALE_PARAM] = replacement if replacement
      query.empty? ? request.path : "#{request.path}?#{query.to_query}"
    end
  end
end
