# frozen_string_literal: true

# B4, B5. Open Graph of a topic page as a link-preview bot sees it.
RSpec.describe TerrytrillaSeo::TopicMeta do
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category, title: "Minor key chords and the dominant") }
  fab!(:first_post) { Fabricate(:post, topic: topic) }

  let(:bot) { "Twitterbot/1.0" }
  let(:base) { "https://site.example/api/og/forum" }

  before do
    SiteSetting.content_localization_enabled = true
    SiteSetting.set_locale_from_param = true
    SiteSetting.content_localization_crawler_param = true
    SiteSetting.content_localization_supported_locales = "en|de|pt_BR"
    SiteSetting.allow_user_locale = true
    SiteSetting.terrytrilla_seo_enabled = true
    SiteSetting.terrytrilla_seo_og_card_base = base
  end

  def meta(path)
    get path, headers: { "User-Agent" => bot }
    expect(response.status).to eq(200)
    doc = Nokogiri.HTML5(response.body)
    tags =
      doc.css("meta[property], meta[name]").map { |m| [m["property"] || m["name"], m["content"]] }
    [tags, tags.to_h]
  end

  let(:path) { "/t/#{topic.slug}/#{topic.id}" }

  describe "B4: the card" do
    it "points a topic without an image at the site's card in the page language" do
      _, m = meta("#{path}?tl=de")
      uri = URI.parse(m["og:image"])
      expect("#{uri.scheme}://#{uri.host}#{uri.path}").to eq(base)
      q = Rack::Utils.parse_query(uri.query)
      expect(q["topic"]).to eq(topic.id.to_s)
      expect(q["locale"]).to eq("de")
      expect(q["v"]).to match(/\A\h{8}\z/)
      expect(m["twitter:image"]).to eq(m["og:image"])
      expect(m["twitter:card"]).to eq("summary_large_image")
    end

    it "declares size, type and alt right after its own og:image" do
      tags, m = meta(path)
      names = tags.map(&:first)
      i = names.index("og:image")
      expect(names[i + 1, 4]).to eq(%w[og:image:width og:image:height og:image:type og:image:alt])
      expect(m["og:image:width"]).to eq("1200")
      expect(m["og:image:height"]).to eq("630")
      expect(m["og:image:type"]).to eq("image/png")
      expect(m["og:image:alt"]).to eq(m["og:title"])
    end

    it "changes the version when the title changes" do
      _, before = meta(path)
      topic.update!(title: "Minor key chords and why the dominant is major")
      _, after = meta("/t/#{topic.reload.slug}/#{topic.id}")
      expect(after["og:image"]).not_to eq(before["og:image"])
    end

    it "keeps a topic's own image" do
      upload = Fabricate(:image_upload, width: 800, height: 400)
      topic.update_columns(image_upload_id: upload.id)
      _, m = meta(path)
      expect(m["og:image"]).not_to start_with(base)
      expect(m["og:image:alt"]).to be_nil
    end

    it "uses the canonical URL for og:url, without query junk" do
      _, m = meta("#{path}?tl=de&u=someone")
      expect(m["og:url"]).to eq("#{Discourse.base_url}#{path}?tl=de")
    end

    it "keeps the forum card when the base is empty" do
      SiteSetting.terrytrilla_seo_og_card_base = ""
      _, m = meta(path)
      expect(m["og:image"].to_s).not_to start_with(base)
    end
  end

  # 17.09: владелец не увидел карточку главной в Telegram — у картинки из настройки
  # форума ядро не объявляет размеры.
  describe "B4: карточка страниц без темы" do
    fab!(:brand) { Fabricate(:image_upload, width: 1200, height: 630) }

    before do
      SiteSetting.opengraph_image = brand
      # ⚠️ В свежей тестовой установке "/" — страница установщика, а не главная.
      SiteSetting.has_login_hint = false
    end

    def карточка(путь)
      get путь, headers: { "User-Agent" => bot }
      expect(response.status).to eq(200)
      Nokogiri.HTML5(response.body).css("meta[property]").to_h { |t| [t["property"], t["content"]] }
    end

    it "оставляет карточку большой — её показывает Telegram" do
      get "/", headers: { "User-Agent" => bot }
      m = Nokogiri.HTML5(response.body).css("meta[name]").to_h { |t| [t["name"], t["content"]] }
      expect(m["twitter:card"]).to eq("summary_large_image")
      expect(m["twitter:image"]).to include(brand.url)
    end

    it "объявляет размеры брендовой картинки на главной" do
      m = карточка("/")
      expect(m["og:image"]).to include(brand.url)
      expect(m["og:image:width"]).to eq("1200")
      expect(m["og:image:height"]).to eq("630")
      expect(m["og:image:type"]).to eq("image/png")
    end

    it "не объявляет размеров при выключенном плагине (контроль)" do
      SiteSetting.terrytrilla_seo_enabled = false
      get "/", headers: { "User-Agent" => bot }
      expect(response.body).not_to include('property="og:image:width"')
    end
  end

  describe "B5: article" do
    it "marks a topic as an article in the page language" do
      _, m = meta("#{path}?tl=pt_BR")
      expect(m["og:type"]).to eq("article")
      expect(m["og:locale"]).to eq("pt_BR")
    end

    it "dates the article by the last revision of the first post, not the last reply" do
      edited = Time.zone.parse("2026-09-10 10:00:00")
      first_post.update_columns(last_version_at: edited)
      Fabricate(:post, topic: topic)
      _, m = meta(path)
      expect(Time.zone.parse(m["article:modified_time"])).to eq_time(edited)
      expect(m["og:locale"]).to eq("en_US")
    end

    it "leaves list pages a website" do
      get "/latest", headers: { "User-Agent" => bot }
      expect(response.body).to include('property="og:type" content="website"')
      expect(response.body).not_to include("og:locale")
    end

    it "leaves core alone when the plugin is disabled (control)" do
      SiteSetting.terrytrilla_seo_enabled = false
      _, m = meta(path)
      expect(m["og:type"]).to eq("website")
      expect(m["og:image"].to_s).not_to start_with(base)
      expect(m["og:locale"]).to be_nil
    end
  end

  # B5-бис: страница на языке человека, а карточка — на языке оригинала.
  # Ядро локализует содержимое темы только для краулерной раскладки, поэтому у
  # обычного браузера (и у сканеров, которые им представляются) мета-теги оставались
  # английскими при русском тексте на экране (замер владельца 18.09).
  describe "B5-бис: карточка на языке страницы" do
    let(:человек) do
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
        "(KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36"
    end

    before do
      SiteSetting.content_localization_supported_locales = "en|de|ru|pt_BR"
      SiteSetting.set_locale_from_accept_language_header = true
      topic.update_columns(locale: "en")
      first_post.update_columns(locale: "en")
      TopicLocalization.create!(
        topic: topic,
        locale: "de",
        title: "Moll-Akkorde und die Dominante",
        fancy_title: "Moll-Akkorde und die Dominante",
        localizer_user_id: Discourse.system_user.id,
      )
      PostLocalization.create!(
        post: first_post,
        locale: "de",
        raw: "Warum ist die fünfte Stufe in Moll ein Dur-Akkord? Hier die Erklärung.",
        cooked: "<p>Warum ist die fünfte Stufe in Moll ein Dur-Akkord? Hier die Erklärung.</p>",
        post_version: first_post.version,
        localizer_user_id: Discourse.system_user.id,
      )
    end

    def карточка_человеку(язык)
      get path, headers: { "User-Agent" => человек, "Accept-Language" => язык }
      expect(response.status).to eq(200)
      Nokogiri
        .HTML5(response.body)
        .css("meta[property], meta[name]")
        .to_h { |m| [m["property"] || m["name"], m["content"]] }
    end

    it "человеку с немецким браузером даёт немецкий заголовок и описание" do
      m = карточка_человеку("de")
      expect(m["og:title"]).to eq("Moll-Akkorde und die Dominante")
      expect(m["og:description"]).to include("fünfte Stufe")
      expect(m["twitter:description"]).to eq(m["og:description"])
    end

    it "подписывает карточку тем же языком, что и заголовок" do
      m = карточка_человеку("de")
      expect(m["og:image:alt"]).to eq("Moll-Akkorde und die Dominante")
      expect(m["og:image"]).to include("locale=de")
    end

    it "без перевода на язык человека оставляет оригинал (контроль)" do
      m = карточка_человеку("pt-BR")
      expect(m["og:title"]).to eq(topic.title)
      expect(m["og:description"]).not_to include("fünfte Stufe")
    end

    it "не трогает страницу на языке оригинала (контроль)" do
      m = карточка_человеку("en")
      expect(m["og:title"]).to eq(topic.title)
    end

    it "краулеру ничего не ломает: у него локализует ядро (контроль)" do
      _, m = meta("#{path}?tl=de")
      expect(m["og:title"]).to eq("Moll-Akkorde und die Dominante")
      expect(m["og:locale"]).to eq("de_DE")
    end

    it "при выключенном плагине карточка остаётся как у ядра (контроль)" do
      SiteSetting.terrytrilla_seo_enabled = false
      m = карточка_человеку("de")
      expect(m["og:title"]).to eq(topic.title)
    end
  end

  # B4-бис: у статей базы знаний первая картинка поста — квадратный скриншот Круга
  # ладов (826×826 на 18.09). В карточку 1.91:1 он не влезает, и клиент рисует
  # маленькое превью сбоку вместо крупной карточки.
  describe "B4-бис: какая картинка идёт в карточку" do
    def тема_с_картинкой(ширина, высота)
      upload = Fabricate(:image_upload, width: ширина, height: высота)
      post = Fabricate(:post, topic: topic, raw: "![скрин](#{upload.url})")
      topic.update_columns(image_upload_id: upload.id)
      post
    end

    it "квадратную картинку темы в карточку не берёт — рисует карточку сайта" do
      тема_с_картинкой(826, 826)
      _, m = meta(path)
      expect(m["og:image"]).to start_with(base)
      expect(m["og:image:width"]).to eq("1200")
      expect(m["og:image:height"]).to eq("630")
      expect(m["twitter:card"]).to eq("summary_large_image")
    end

    it "вертикальную — тоже не берёт" do
      тема_с_картинкой(858, 1277)
      _, m = meta(path)
      expect(m["og:image"]).to start_with(base)
      expect(m["twitter:card"]).to eq("summary_large_image")
    end

    it "узкую по ширине — не берёт, даже если она вытянута правильно (контроль порога)" do
      тема_с_картинкой(400, 210)
      _, m = meta(path)
      expect(m["og:image"]).to start_with(base)
    end

    it "широкую картинку темы берёт и объявляет крупной карточкой" do
      upload = Fabricate(:image_upload, width: 1200, height: 630)
      Fabricate(:post, topic: topic, raw: "![скрин](#{upload.url})")
      topic.update_columns(image_upload_id: upload.id)

      _, m = meta(path)
      expect(m["og:image"]).to include(upload.url)
      expect(m["og:image"]).not_to start_with(base)
      expect(m["twitter:card"]).to eq("summary_large_image")
      expect(m["twitter:image"]).to eq(m["og:image"])
    end

    it "различает пропорции сама по себе (контроль правила)" do
      правило = ->(w, h) { described_class.широкая?(image_width: w, image_height: h) }
      expect(правило.call(1200, 630)).to eq(true)
      expect(правило.call(826, 826)).to eq(false)
      expect(правило.call(858, 1277)).to eq(false)
      expect(правило.call(400, 210)).to eq(false)
      expect(правило.call(nil, nil)).to eq(false)
    end
  end
end
