# frozen_string_literal: true

module TerrytrillaSeo
  # Движок нужен ровно за одним: без него каталоги `app/` плагина не попадают в
  # автозагрузку, и маршрут `/sitemap_pages.xml` падал с
  # `uninitialized constant TerrytrillaSeo::SitemapPagesController` (замер 18.09).
  # Так же объявляют свои контроллеры плагины ядра (discourse-solved).
  class Engine < ::Rails::Engine
    engine_name PLUGIN_NAME
    isolate_namespace TerrytrillaSeo
  end
end
