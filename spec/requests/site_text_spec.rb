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
end
