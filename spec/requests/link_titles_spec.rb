# frozen_string_literal: true

# B19. Заголовки внутренних ссылок — на языке читателя.
#
# Замер 19.09.2026 на японской статье: под постом тринадцать ссылок, у двенадцати
# японский заголовок лежит в базе, а читателю приезжал английский оригинал. Ядро
# собирает эти заголовки сырым SQL (`COALESCE(t.title, l.title)`), локализация туда
# не заходит.
#
# ⚠️ Проверяются ОБЕ раскладки. Прежний спек на имя раздела был зелёным ровно
# потому, что смотрел только браузерную: в ней заголовок собирается иначе, и дефект
# краулерной раскладки — той самой, которую читает Google, — он не видел.
RSpec.describe "B19 · заголовки ссылок на языке читателя" do
  fab!(:раздел) { Fabricate(:category, name: "Knowledge Base") }
  fab!(:цель) { Fabricate(:topic, title: "How the Studio picks its chords", category: раздел) }
  fab!(:цель_пост) { Fabricate(:post, topic: цель) }
  fab!(:источник) { Fabricate(:topic, title: "Scale Circle: what it is", category: раздел) }

  let(:перевод_ja) { "スタジオはどうやってコードを選ぶのか" }
  let(:перевод_источника_ja) { "スケールサークルとは：しくみ" }
  let(:краулер) { "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" }
  let(:браузер) do
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
      "(KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36"
  end

  let!(:источник_пост) do
    пост =
      Fabricate(
        :post,
        topic: источник,
        raw: "Смотри статью: #{Discourse.base_url}/t/#{цель.slug}/#{цель.id}",
      )
    TopicLink.extract_from(пост)
    пост
  end

  before do
    SiteSetting.terrytrilla_seo_enabled = true
    SiteSetting.content_localization_enabled = true
    SiteSetting.content_localization_supported_locales = "ja|ru"
    SiteSetting.allow_user_locale = true
    SiteSetting.set_locale_from_accept_language_header = true
    # ⚠️ Краулеру язык задаёт `?tl=`, а не `Accept-Language`: так устроен наш
    # `crawler_locale.rb`, и без этой настройки бот всегда получал бы язык по
    # умолчанию — проверка краулерной раскладки была бы зелёной впустую.
    SiteSetting.set_locale_from_param = true
    SiteSetting.content_localization_crawler_param = true

    цель.update!(locale: "en")
    источник.update!(locale: "en")
    TopicLocalization.create!(
      topic_id: цель.id,
      locale: "ja",
      title: перевод_ja,
      fancy_title: перевод_ja,
      localizer_user_id: Discourse.system_user.id,
    )
    TopicLocalization.create!(
      topic_id: источник.id,
      locale: "ja",
      title: перевод_источника_ja,
      fancy_title: перевод_источника_ja,
      localizer_user_id: Discourse.system_user.id,
    )
  end

  def ссылки_из_json(locale)
    get "/t/#{источник.id}.json",
        headers: {
          "User-Agent" => браузер,
          "Accept-Language" => locale,
        }
    expect(response.status).to eq(200)
    JSON
      .parse(response.body)
      .dig("post_stream", "posts")
      .flat_map { |п| п["link_counts"] || [] }
      .map { |с| с["title"] }
      .compact
  end

  it "блок ссылок под постом — на языке читателя" do
    expect(ссылки_из_json("ja")).to include(перевод_ja)
  end

  it "оригинала в блоке ссылок не остаётся" do
    expect(ссылки_из_json("ja")).not_to include(цель.title)
  end

  # ⚠️ Краулерный блок `crawler-linkback-list` показывает ОБРАТНЫЕ ссылки
  # (`linkbacks_for` отбирает `reflection`), поэтому открываем страницу ЦЕЛИ: это
  # на ней видно, кто на неё сослался. И язык краулеру задаёт `?tl=`, а не
  # `Accept-Language` — так устроен наш же `crawler_locale.rb`.
  it "краулерная раскладка тоже отдаёт перевод" do
    get "/t/#{цель.slug}/#{цель.id}?tl=ja", headers: { "User-Agent" => краулер }

    expect(response.status).to eq(200)
    блок = Nokogiri.HTML5(response.body).css(".crawler-linkback-list").text
    expect(блок).to include(перевод_источника_ja)
    expect(блок).not_to include(источник.title)
  end

  it "у языка без перевода остаётся оригинал (контроль)" do
    expect(ссылки_из_json("ru")).to include(цель.title)
  end

  it "с выключенным плагином подмены нет (контроль)" do
    SiteSetting.terrytrilla_seo_enabled = false

    expect(ссылки_из_json("ja")).to include(цель.title)
  end

  it "с выключенной локализацией содержимого подмены нет (контроль)" do
    SiteSetting.content_localization_enabled = false

    expect(ссылки_из_json("ja")).to include(цель.title)
  end

  it "ссылка на чужой сайт остаётся как есть (контроль)" do
    внешний =
      Fabricate(:post, topic: источник, raw: "Внешняя: https://terrytrilla.com/ru/scales/ionian")
    TopicLink.extract_from(внешний)

    get "/t/#{источник.id}.json", headers: { "User-Agent" => браузер, "Accept-Language" => "ja" }
    адреса =
      JSON
        .parse(response.body)
        .dig("post_stream", "posts")
        .flat_map { |п| п["link_counts"] || [] }
        .reject { |с| с["internal"] }
        .map { |с| с["url"] }

    expect(адреса).to include("https://terrytrilla.com/ru/scales/ionian")
  end
end
