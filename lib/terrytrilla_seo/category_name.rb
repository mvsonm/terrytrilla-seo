# frozen_string_literal: true

module ::TerrytrillaSeo
  # B19-бис: имя раздела на странице раздела — на языке читателя, ВЕЗДЕ.
  #
  # Замер 19.09.2026 по четырём языкам: краулерная раскладка `/c/knowledge-base/10`
  # отдавала «最新 Knowledge Base トピック», «Aktuell in Knowledge Base», «최신
  # Knowledge Base 주제». В браузере там же «ナレッジベース» — то есть английское имя
  # раздела видел ровно Google.
  #
  # Первая правка подменяла имя в готовой строке заголовка. Она работала, но была
  # заплаткой: сразу после выката тот же разбор нашёл английское имя ещё в двух
  # местах той же страницы — в `<h1>` (`app/views/list/list.erb` печатает
  # `@category.name` напрямую) и в подписи ленты RSS. Чинить их по одному значило
  # повторить то, от чего мы ушли в B14.
  #
  # Поэтому подмена стоит там, где ядро КЛАДЁТ раздел в запрос — в
  # `ListController#set_category`. Дальше из этого одного объекта ядро само берёт и
  # заголовок страницы (`list_controller.rb:109` и `:290`), и `<h1>`, и подпись RSS,
  # и хлебные крошки.
  #
  # ⚠️ Имя подменяется НА СИНГЛТОНЕ объекта, а не присваиванием `@category.name =`.
  # Присваивание пометило бы запись изменённой, и любой `save` внутри запроса —
  # свой или чужой, сегодняшний или завтрашний — записал бы перевод в саму
  # категорию. Сингтон-метод виден только на чтение и в базу не попадает никогда.
  module CategoryName
    def set_category
      результат = super
      ::TerrytrillaSeo::CategoryName.подменить(@category)
      результат
    end

    def self.подменить(раздел)
      return if раздел.nil?
      return unless SiteSetting.terrytrilla_seo_enabled
      # Решение «переводить ли» принимает ядро: у него же живут правила про язык
      # оригинала и про выключенную локализацию содержимого.
      return unless ContentLocalization.show_translated_category?(раздел, nil)

      перевод = раздел.get_localization(I18n.locale)&.name
      return if перевод.blank? || перевод == раздел.name

      раздел.define_singleton_method(:name) { перевод }
    rescue StandardError => e
      Rails.logger.warn("terrytrilla-seo: имя раздела не переведено: #{e.class}: #{e.message}")
    end
  end
end
