# frozen_string_literal: true

# B14. Тексты форума в мета-тегах — на языке страницы, на ЛЮБОЙ странице.
#
# Замер 19.09.2026: у статьи и «/about» всё на языке читателя, а у ленты и раздела
# заголовок с описанием оставались английскими на всех двенадцати языках. Точечные
# правки этот класс не закрывали, поэтому проверяется сразу набор страниц.
RSpec.describe TerrytrillaSeo::SiteText do
  fab!(:knowledge_base) { Fabricate(:category, name: "Knowledge Base") }
  fab!(:topic) { Fabricate(:topic, category: knowledge_base) }
  fab!(:post) { Fabricate(:post, topic: topic) }

  let(:браузер) do
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
      "(KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36"
  end
  let(:описание_ja) { "ハーモニー、スケール、コード" }
  let(:раздел_ja) { "ナレッジベース" }

  before do
    SiteSetting.terrytrilla_seo_enabled = true
    # Без этого ядро молча отдаёт значение по умолчанию вместо перевода.
    SiteSetting.content_localization_enabled = true
    SiteSetting.content_localization_supported_locales = "ja|ru|de"
    SiteSetting.allow_user_locale = true
    SiteSetting.set_locale_from_accept_language_header = true
    SiteSetting.title = "TerryTrilla Community"
    SiteSetting.site_description = "Harmony, scales and chords"
    SiteSettingLocalization.create!(
      setting_name: "site_description",
      locale: "ja",
      value: описание_ja,
      localizer_user_id: Discourse.system_user.id,
    )
    # ⚠️ Язык оригинала у раздела обязателен: ядро не переводит раздел без него
    # (`show_translated_category?`). На форуме он проставлен у всех одиннадцати
    # разделов (`locale = "en"`, замер 19.09), а фабрика его не ставит — без этой
    # строки проверка краулерного заголовка красная на ИСПРАВНОМ коде.
    knowledge_base.update!(locale: "en")
    CategoryLocalization.create!(
      category_id: knowledge_base.id,
      locale: "ja",
      name: раздел_ja,
      description: "スタジオの使い方",
    )
  end

  def мета(path, locale)
    get path, headers: { "User-Agent" => браузер, "Accept-Language" => locale }
    expect(response.status).to eq(200)
    doc = Nokogiri.HTML5(response.body)
    {
      title: doc.css("title").text,
      description: doc.css('meta[name="description"]').first&.[]("content"),
      og_description: doc.css('meta[property="og:description"]').first&.[]("content"),
    }
  end

  it "переводит описание форума на списковых страницах" do
    expect(мета("/latest", "ja")[:description]).to eq(описание_ja)
  end

  it "переводит название раздела в заголовке страницы раздела" do
    заголовок = мета("/c/#{knowledge_base.slug}/#{knowledge_base.id}", "ja")[:title]

    expect(заголовок).to include(раздел_ja)
    expect(заголовок).not_to include("Knowledge Base")
  end

  # B19-бис. ⚠️ Прежний спек выше смотрел ТОЛЬКО браузерную раскладку и был зелёным,
  # пока краулерная — та, которую читает Google, — отдавала «最新 Knowledge Base
  # トピック» на всех языках. Заголовок там собирается интерполяцией
  # (`js.filters.with_category`), и целой подменой имя раздела не ловится.
  it "переводит название раздела в заголовке страницы раздела и для краулера" do
    SiteSetting.set_locale_from_param = true
    SiteSetting.content_localization_crawler_param = true
    # ⚠️ Без этой строки спек зелёный на СЛОМАННОМ коде — проверено мутацией.
    # Ядро берёт интерполированный заголовок («Последние темы в …») только когда
    # фильтр не совпадает с главной; в чистой установке главная и есть `latest`,
    # и заголовок собирается как «Имя раздела - Имя сайта» — целую подмену он
    # проходит и без правки. На форуме главная своя (тема), поэтому там боевой
    # случай другой. Двигаем главную так же.
    SiteSetting.top_menu = "categories|latest|new|top"
    get "/c/#{knowledge_base.slug}/#{knowledge_base.id}?tl=ja",
        headers: {
          "User-Agent" => "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
        }
    expect(response.status).to eq(200)
    заголовок = Nokogiri.HTML5(response.body).css("title").text

    expect(заголовок).to include(раздел_ja)
    expect(заголовок).not_to include("Knowledge Base")
  end

  it "переводит название раздела в хвосте заголовка темы" do
    заголовок = мета("/t/#{topic.slug}/#{topic.id}", "ja")[:title]

    expect(заголовок).to include(раздел_ja)
    expect(заголовок).not_to include("Knowledge Base")
  end

  it "описание страницы и её карточка на одном языке" do
    страница = мета("/latest", "ja")

    expect(страница[:og_description]).to eq(страница[:description])
  end

  it "у языка без перевода остаётся текст по умолчанию (контроль)" do
    expect(мета("/latest", "de")[:description]).to eq("Harmony, scales and chords")
  end

  it "с выключенным плагином ничего не подменяется (контроль)" do
    SiteSetting.terrytrilla_seo_enabled = false

    expect(мета("/latest", "ja")[:description]).to eq("Harmony, scales and chords")
  end

  it "с выключенной локализацией содержимого — тексты по умолчанию (контроль)" do
    SiteSetting.content_localization_enabled = false

    страница = мета("/c/#{knowledge_base.slug}/#{knowledge_base.id}", "ja")

    expect(страница[:title]).to include("Knowledge Base")
    expect(страница[:description]).to eq("Harmony, scales and chords")
  end
end
