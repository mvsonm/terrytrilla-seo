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

    # B13-бис (замер владельца 18.09). Карточка ссылки на ГЛАВНУЮ появлялась не везде:
    # Telegram и Facebook её рисуют, а сканер с обычным браузерным UA — нет.
    #
    # Причина не в карточке, а в том, ЧТО отдаётся на «/». Тема рисует свою главную
    # (модификатор `custom_homepage`), и ядро отдаёт под неё пустую оболочку без единого
    # мета-тега: страницу собирает JS. Краулеру вместо неё подставляется
    # `custom_homepage_crawler_route` (categories) — вот там теги есть. Кто представляется
    # браузером, получает главную без описания и без картинки.
    #
    # Поэтому теги печатаются здесь — ровно тем же вызовом ядра, что и на остальных
    # страницах, значит карточка выходит такой же (включая размеры брендовой картинки
    # и `summary_large_image`, см. TopicMeta).
    def self.своя_главная?(controller)
      return false unless SiteSetting.terrytrilla_seo_enabled
      request = controller.request
      return false unless request.path == "#{Discourse.base_path}/"
      # Спрашиваем у ядра, а не угадываем: то же решение, что оно приняло для страницы.
      HomepageHelper.resolve(request, controller.current_user) == "custom"
    rescue StandardError
      false
    end

    def self.meta_tags(controller)
      return "" unless своя_главная?(controller)
      надпись = heading(I18n.locale)
      controller.view_context.crawlable_meta_data(
        title: надпись[:title],
        description: надпись[:description],
        # Без явного адреса ядро подставит `request.fullpath`, и «/?ref=x» уехало бы
        # в `og:url` вторым адресом той же страницы.
        url: "#{Discourse.base_url}/",
      )
    end
  end
end
