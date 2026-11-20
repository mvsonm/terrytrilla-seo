# frozen_string_literal: true

module ::TerrytrillaSeo
  # B12 (decision Р-10): a URL without `?tl` is the forum's default language FOR CRAWLERS.
  #
  # Core picks the anonymous locale from `?tl`, then the `locale` cookie, then
  # Accept-Language. For people that is right. For crawlers it is not: the plain URL carries
  # hreflang `en`/`x-default`, and measured on 17.09 Googlebot with `Accept-Language: de`
  # got German text under the English URL. Link-preview bots and other search engines do
  # send the header.
  #
  # So for a crawler without `?tl` Accept-Language is ignored. `?tl=de` still works, and
  # people are untouched. The anonymous cache key is built from the same method
  # (Middleware::AnonymousCache#key_locale), so the cache stays consistent.
  #
  # Since 2026.11 core also asks what the plain URL would serve (`include_param: false`): for the
  # anonymous cache key of a `?tl` page and to choose between the plain URL and `?tl=<default>`
  # in hreflang, canonical and links. A crawler gets the same rule there — the param is left out,
  # so the default language unless a locale cookie says otherwise.
  module CrawlerLocale
    def anonymous_locale(request, include_param: true)
      if SiteSetting.terrytrilla_seo_enabled &&
           (!include_param || request.params[Discourse::LOCALE_PARAM].blank?) &&
           CrawlerDetection.crawler?(request.user_agent, request.get_header("HTTP_VIA"))
        return HttpLanguageParser.parse(locale_from_cookie(request))
      end
      super
    end
  end
end
