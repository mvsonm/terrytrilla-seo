# frozen_string_literal: true

module ::TerrytrillaSeo
  # B18 (замер владельца 19.09): значок вкладки не подстраивается под схему.
  #
  # Знак у нас один и тёмный: на светлой полосе вкладок он читается, на тёмной
  # сливается на 76 % (замер по точкам самого файла). У владельца полоса вкладок
  # тёмная — оттуда и вопрос.
  #
  # ⚠️ Значок следует за схемой БРАУЗЕРА, а не за темой сайта: полосу вкладок
  # красит браузер, и тема страницы на неё не влияет. Поэтому условие —
  # `prefers-color-scheme`, а не активная цветовая схема Discourse.
  #
  # ⚠️ Ядро отдаёт РОВНО ОДИН значок (`SiteSetting.favicon`), парной настройки у
  # него нет — проверено по списку настроек. Поэтому второй тег печатаем сами.
  #
  # Что важно знать про поддержку (проверено, не по памяти):
  #   • Chrome, Edge и Safari `media` у `rel=icon` понимают;
  #   • Firefox — НЕТ: баг 1603885 открыт, статус NEW, и в нём Mozilla советует
  #     переключать схему внутри самого значка (SVG с `prefers-color-scheme`);
  #   • Google SVG не читает вовсе, поэтому базовым остаётся PNG — иначе в выдаче
  #     снова будет пустой значок (это чинили 19.09 же).
  #
  # Значит базовый PNG ядра трогать нельзя: он для поиска и для Firefox. Наш тег
  # добавляется ВТОРЫМ и работает там, где `media` поддержан.
  module Favicon
    def self.тег(controller)
      return "" unless SiteSetting.terrytrilla_seo_enabled
      return "" if controller.request.path.start_with?("#{Discourse.base_path}/admin")

      значок = SiteSetting.terrytrilla_seo_favicon_dark
      return "" unless значок.respond_to?(:url) && значок.url.present?

      адрес = UrlHelper.absolute(значок.url)
      %(<link rel="icon" type="#{тип(значок)}" href="#{адрес}" ) +
        %(media="(prefers-color-scheme: dark)">)
    rescue StandardError
      ""
    end

    def self.тип(значок)
      MiniMime.lookup_by_extension(значок.extension.to_s)&.content_type || "image/png"
    end
  end
end
