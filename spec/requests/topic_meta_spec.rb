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
end
