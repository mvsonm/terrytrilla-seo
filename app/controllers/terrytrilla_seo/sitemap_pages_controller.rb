# frozen_string_literal: true

module ::TerrytrillaSeo
  # B10-бис: `/sitemap_pages.xml` — главная и разделы форума.
  #
  # Наследует `SitemapController`: оттуда берутся отключение вида-обёртки и проверка
  # `enable_sitemap` — выключенная карта обязана отвечать 404 целиком, а не по частям.
  #
  # Ключ кеша содержит дату самой свежей страницы, поэтому карта обновляется сама:
  # новый ответ в разделе меняет дату → меняется ключ → страница собирается заново.
  class SitemapPagesController < ::SitemapController
    # Штатный способ закрыть маршрут вместе с плагином: выключенный плагин → 404.
    requires_plugin ::TerrytrillaSeo::PLUGIN_NAME

    def show
      rows = SitemapPages.rows
      # Нечего отдавать — 404, а не пустой `urlset`: пустая карта читается поисковиком
      # как «страниц нет», и это сообщение о сайте, которого мы не делали.
      raise Discourse::NotFound if rows.empty?

      @output =
        Discourse
          .cache
          .fetch(SitemapPages.cache_key, expires_in: 24.hours) do
            @rows = rows
            render :show, content_type: "text/xml; charset=UTF-8"
          end

      render plain: @output, content_type: "text/xml; charset=UTF-8" unless performed?
    end
  end
end
