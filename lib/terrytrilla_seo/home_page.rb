# frozen_string_literal: true

module ::TerrytrillaSeo
  # B13: the home page a crawler gets.
  #
  # The theme draws its own landing page for people, so a crawler is served
  # `custom_homepage_crawler_route` instead (`categories` — the section names and
  # descriptions are already on that page, decision of the TZ). Core's crawler view of
  # that page is a bare table: no H1 and no word about what the community is. The point
  # `server:custom-homepage-crawler-view` is not reachable there, so the view itself is
  # overridden and this heading is added on top of core's markup.
  #
  # The name and the description are the site settings, in the language of the request:
  # core keeps their translations in `SiteSettingLocalization` (About page of the admin).
  # Without a translation the default language is used — the page never loses its heading.
  module HomePage
    def self.active?(request)
      SiteSetting.terrytrilla_seo_enabled && request.path == "/"
    end

    def self.localized(setting, locale)
      SiteSettingLocalization.value_for(setting, locale: locale.to_s)
    rescue StandardError
      SiteSetting.get(setting)
    end

    def self.heading(locale)
      { title: localized(:title, locale), description: localized(:site_description, locale) }
    end
  end
end
