# frozen_string_literal: true

module ::TerrytrillaSeo
  # B19: заголовки ВНУТРЕННИХ ссылок — на языке читателя.
  #
  # Замер 19.09.2026 на японской статье (t/23): под постом тринадцать ссылок, у
  # двенадцати японский заголовок лежит в `TopicLocalization`, а читателю приезжал
  # английский оригинал. То же в краулерной раскладке — блок `crawler-linkback-list`,
  # то есть английские заголовки видел и Google на японской странице.
  #
  # Почему так: заголовок ссылки собирается СЫРЫМ SQL — `COALESCE(t.title, l.title)`
  # в `TopicLink.counts_for` и `TopicLink.topic_map`. Локализация туда не заходит
  # вовсе. Что это недосмотр ядра, а не решение, видно по соседям: тот же
  # `PostSerializer` явно локализует oneboxes, заголовки тем ядро переводит в пяти
  # других сериализаторах, а в `TopicLinkSerializer` строка `# :fancy_title` стоит
  # закомментированной.
  #
  # ⚠️ Правка стоит в ЕДИНСТВЕННОЙ точке — в самих методах `TopicLink`, а не в
  # сериализаторах. Через них идут ВСЕ потребители: блок под постом
  # (`TopicView#link_counts`), карта темы (`TopicView#links` → `details.links`),
  # краулерная раскладка (`linkbacks_for`) и ответы `PostsController` после
  # создания и правки поста. Чинить по сериализаторам значило бы повторить то, что
  # 18–19.09 уже не сработало с мета-тегами: чинишь одно место, класс остаётся.
  module LinkTitles
    # Адрес темы: `/t/slug/123`, `/t/topic/123`, `/t/slug/123/45`. Хвост после id —
    # номер поста, он на выбор темы не влияет.
    АДРЕС_ТЕМЫ = %r{\A/t/(?:[^/?#]+/)?(\d+)(?:[/?#]|\z)}

    def self.активно?
      SiteSetting.terrytrilla_seo_enabled && SiteSetting.content_localization_enabled
    end

    # Ряды приходят двух видов: у `counts_for` это Hash с символьными ключами, у
    # `topic_map` — объект mini_sql с методами. Оба изменяемы, но по-разному.
    def self.прочитать(ряд, ключ)
      return ряд[ключ] if ряд.is_a?(Hash)
      ряд.respond_to?(ключ) ? ряд.public_send(ключ) : nil
    end

    def self.записать(ряд, ключ, значение)
      if ряд.is_a?(Hash)
        ряд[ключ] = значение
      elsif ряд.respond_to?("#{ключ}=")
        ряд.public_send("#{ключ}=", значение)
      end
    end

    def self.ид_темы(ряд)
      прямой = прочитать(ряд, :link_topic_id)
      return прямой.to_i if прямой.present?

      # У `counts_for` в ряду id темы нет — берём из адреса. Чужие сайты сюда не
      # попадают: у них `internal` ложно, а путь не начинается с нашей базы.
      return nil unless прочитать(ряд, :internal)
      адрес = прочитать(ряд, :url).to_s
      путь = адрес.sub(/\A#{Regexp.escape(Discourse.base_url)}/, "")
      путь = путь.sub(/\A#{Regexp.escape(Discourse.base_path)}/, "") if Discourse.base_path.present?
      return nil unless путь.start_with?("/t/")
      путь[АДРЕС_ТЕМЫ, 1]&.to_i
    end

    # Меняет заголовки на месте и возвращает те же ряды.
    #
    # ⚠️ Решение «показывать ли перевод» принимает ЯДРО
    # (`ContentLocalization.translated_topic_title`), а не мы: там же живут правила
    # «читатель понимает язык оригинала» и «переводить автоматически». Своя копия
    # этих правил разошлась бы с ядром при первом же обновлении.
    def self.перевести!(ряды, guardian)
      return ряды if ряды.blank? || !активно?

      пары =
        Array(ряды).filter_map do |ряд|
          ид = ид_темы(ряд)
          [ряд, ид] if ид
        end
      return ряды if пары.empty?

      темы = Topic.includes(:localizations).where(id: пары.map(&:last).uniq).index_by(&:id)
      пары.each do |ряд, ид|
        тема = темы[ид]
        next if тема.nil?
        перевод = ContentLocalization.translated_topic_title(тема, guardian)
        записать(ряд, :title, перевод) if перевод.present?
      end

      ряды
    rescue StandardError => e
      # Список ссылок — украшение страницы. Свалить из-за него отрисовку темы
      # нельзя: пусть лучше заголовок останется оригинальным.
      Rails.logger.warn(
        "terrytrilla-seo: не смог перевести заголовки ссылок: #{e.class}: #{e.message}",
      )
      ряды
    end

    # Накладка на класс `TopicLink`. Оба метода получают guardian — он и решает,
    # кому показывать перевод.
    module Накладка
      def counts_for(guardian, topic, posts)
        итог = super
        итог.each_value { |ряды| ::TerrytrillaSeo::LinkTitles.перевести!(ряды, guardian) }
        итог
      end

      def topic_map(guardian, topic_id)
        ::TerrytrillaSeo::LinkTitles.перевести!(super, guardian)
      end
    end
  end
end
