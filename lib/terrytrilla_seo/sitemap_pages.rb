# frozen_string_literal: true

module ::TerrytrillaSeo
  # B10-бис: в карте сайта не только темы, но и главная с разделами.
  #
  # Ядро кладёт в карту ТОЛЬКО темы (`Sitemap#topics` → `/t/slug/id`). Главная и
  # страницы разделов — такие же страницы со своим текстом и списком тем, и поисковик
  # о них из карты не узнаёт вовсе.
  #
  # Состав считается ИЗ БАЗЫ, а не перечислен списком адресов: раздел появляется в карте
  # сам, как только в нём появляется первая индексируемая тема (B3), и уходит, если тем
  # не осталось. Новый раздел не требует правки кода — так же собирается карта основного
  # сайта.
  #
  # Почему не «все открытые разделы»: из семи открытых поиску разделов на 18.09 наполнены
  # два. Пустая страница в карте — заявка «зайди, здесь есть что индексировать», которая
  # не исполняется; по правилу Б4 шлюза запуска это смешанный сигнал.
  #
  # ⚠️ Адрес обязан совпадать с `canonical` страницы: главная СО слэшем
  # (`https://terrytrilla.club/`), раздел БЕЗ (`/c/questions/6`). Иначе карта предъявляет
  # поисковику второй адрес той же страницы — и сама создаёт дубликат.
  module SitemapPages
    NAME = "pages"

    # Разделы с их датами изменения: { category_id => lastmod темы }.
    # Дата темы считается так же, как в карте тем (B10) — по осмысленному изменению.
    def self.lastmod_by_category
      Indexing
        .indexable_scope(Topic.all)
        .group(:category_id)
        .pluck(:category_id, Arel.sql("MAX(#{SitemapTopics::LASTMOD_SQL})"))
        .to_h
    end

    # [[абсолютный адрес, дата изменения], …] — главная первой, разделы по id.
    def self.rows
      return [] unless SiteSetting.terrytrilla_seo_enabled

      by_category = lastmod_by_category
      return [] if by_category.empty?

      categories = Category.where(id: by_category.keys, read_restricted: false).order(:id).to_a
      return [] if categories.empty?

      rows =
        categories.map do |category|
          # Правку описания раздела тоже показываем: страница раздела — это и его текст.
          lastmod = [by_category[category.id], category.updated_at].compact.max
          [UrlHelper.absolute(category.url), lastmod]
        end

      # Главная показывает разделы и свежие темы: её дата — самая поздняя из них.
      home = rows.map(&:last).max
      [["#{Discourse.base_url}/", home], *rows]
    end

    # Дата карты страниц — для `<lastmod>` в индексе карт и для ключа кеша.
    def self.latest
      rows.map(&:last).max
    end

    def self.cache_key
      "sitemap/#{NAME}/#{latest.to_i}"
    end

    # Запись в таблице `sitemaps` нужна затем, что индекс карт (`/sitemap.xml`) ядро
    # строит по ней: своя карта попадает в индекс без переопределения вида.
    module Model
      def last_posted_topic
        return super unless name == NAME
        SitemapPages.latest
      end

      # Тем в этой карте нет — адреса собирает контроллер. Без этой заглушки ядро
      # посчитало бы `offset = ("pages".to_i - 1) * page_size` = −50 и уронило запрос.
      def topics
        return super unless name == NAME
        []
      end
    end

    module ClassMethods
      # Ядро выключает карты, имён которых не знает: `where.not(name: names_used)`.
      # Поэтому своё имя добавляется здесь же, после пересчёта — иначе ночной
      # `Jobs::RegenerateSitemaps` убирал бы карту страниц из индекса каждые сутки.
      def regenerate_sitemaps
        super

        if SiteSetting.terrytrilla_seo_enabled && SitemapPages.rows.any?
          touch(SitemapPages::NAME)
        else
          where(name: SitemapPages::NAME).update_all(enabled: false)
        end
      end
    end
  end
end
