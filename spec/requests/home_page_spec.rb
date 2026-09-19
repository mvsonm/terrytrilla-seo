# frozen_string_literal: true

# B13. The home page a crawler gets: core's crawler view of the category list has no H1.
#
# On production the theme draws the landing page for people and a crawler is sent to
# `custom_homepage_crawler_route = categories`. Here the same page is reached through
# `top_menu`: the point is the view of "/", not how the route is chosen.
RSpec.describe TerrytrillaSeo::HomePage do
  fab!(:category) { Fabricate(:category, name: "Questions") }
  fab!(:topic) { Fabricate(:topic, category: category) }
  fab!(:post) { Fabricate(:post, topic: topic) }

  let(:bot) { "Twitterbot/1.0" }

  before do
    SiteSetting.content_localization_enabled = true
    SiteSetting.set_locale_from_param = true
    SiteSetting.content_localization_crawler_param = true
    SiteSetting.content_localization_supported_locales = "en|ja"
    SiteSetting.allow_user_locale = true
    # ⚠️ In a fresh test install "/" is the installer page, not the home page.
    SiteSetting.has_login_hint = false
    SiteSetting.top_menu = "categories|latest"
    SiteSetting.title = "TerryTrilla Community"
    SiteSetting.site_description = "Harmony, scales and chords"
    SiteSetting.terrytrilla_seo_enabled = true
  end

  def home(path = "/")
    get path, headers: { "User-Agent" => bot }
    expect(response.status).to eq(200)
    Nokogiri.HTML5(response.body)
  end

  it "names the community once and says what it is" do
    doc = home
    expect(doc.css("h1").map(&:text).map(&:strip)).to eq(["TerryTrilla Community"])
    expect(doc.css("p").map(&:text)).to include("Harmony, scales and chords")
    expect(doc.css("table.category-list a").map(&:text).map(&:strip)).to include("Questions")
    # core prints its own description in the header — ours must replace it, not double it
    expect(doc.css("p").map(&:text).count("Harmony, scales and chords")).to eq(1)
  end

  it "says it in the language of the request" do
    SiteSettingLocalization.create!(
      setting_name: "site_description",
      locale: "ja",
      value: "和音とスケールの話をする場所",
      localizer_user_id: Discourse.system_user.id,
    )
    doc = home("/?tl=ja")
    expect(doc.css("p").map(&:text)).to include("和音とスケールの話をする場所")
  end

  it "falls back to the default language without a translation" do
    doc = home("/?tl=ja")
    expect(doc.css("p").map(&:text)).to include("Harmony, scales and chords")
  end

  it "adds nothing to the category list at its own address" do
    doc = home("/categories")
    expect(doc.css("h1")).to be_empty
    expect(doc.css("header p")).to be_empty
  end

  it "leaves core's view alone when the plugin is disabled (control)" do
    SiteSetting.terrytrilla_seo_enabled = false
    expect(home.css("h1")).to be_empty
  end

  # B13-бис. Замер владельца 18.09: у ссылки на раздел карточка есть везде, у ссылки на
  # главную — только там, где клиент представляется ботом. Причина в том, что тема рисует
  # свою главную, и ядро отдаёт под неё оболочку без единого мета-тега.
  describe "карточка ссылки на свою главную" do
    let(:человек) do
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
        "(KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36"
    end
    let(:плагин) { Plugin::Instance.new }
    let(:своя_главная) { proc { true } }

    # Брендовая картинка — как на проде: без неё ядро ставит маленькую карточку, и
    # проверка «крупная карточка» проходила бы мимо сути.
    fab!(:бренд) { Fabricate(:image_upload, width: 1200, height: 630) }

    before { SiteSetting.opengraph_image = бренд }

    def включить_свою_главную
      DiscoursePluginRegistry.register_modifier(плагин, :custom_homepage_enabled, &своя_главная)
      @своя_главная_включена = true
    end

    after do
      next unless @своя_главная_включена
      DiscoursePluginRegistry.unregister_modifier(плагин, :custom_homepage_enabled, &своя_главная)
    end

    def теги(path = "/", ua: человек)
      get path, headers: { "User-Agent" => ua }
      expect(response.status).to eq(200)
      doc = Nokogiri.HTML5(response.body)
      doc
        .css("meta")
        .filter_map do |m|
          имя = m["property"] || m["name"]
          [имя, m["content"]] if имя&.start_with?("og:", "twitter:")
        end
    end

    it "оболочка своей главной не несёт мета-тегов сама (контроль дефекта)" do
      включить_свою_главную
      SiteSetting.terrytrilla_seo_enabled = false
      expect(теги.map(&:first)).to be_empty
    end

    it "даёт человеку то же, что боту: имя, описание, картинку и крупную карточку" do
      включить_свою_главную
      карточка = теги.to_h
      expect(карточка["og:title"]).to eq("TerryTrilla Community")
      expect(карточка["og:description"]).to eq("Harmony, scales and chords")
      expect(карточка["twitter:card"]).to eq("summary_large_image")
      expect(карточка["og:url"]).to eq("#{Discourse.base_url}/")
    end

    it "печатает карточку ровно один раз" do
      включить_свою_главную
      expect(теги.map(&:first).count("og:title")).to eq(1)
    end

    it "не тащит в адрес карточки параметры ссылки" do
      включить_свою_главную
      expect(теги("/?ref=telegram").to_h["og:url"]).to eq("#{Discourse.base_url}/")
    end

    it "молчит на главной, которую рисует ядро: там теги уже есть (контроль)" do
      expect(теги.map(&:first).count("og:title")).to eq(1)
    end

    it "молчит на остальных страницах (контроль)" do
      включить_свою_главную
      expect(теги("/categories").map(&:first).count("og:title")).to eq(1)
    end

    it "не удваивает теги краулеру: ему ядро отдаёт categories (контроль)" do
      включить_свою_главную
      expect(теги("/", ua: bot).map(&:first).count("og:title")).to eq(1)
    end

    # B13-в (замер владельца 19.09). У одной страницы два писателя: `og:description`
    # печатает плагин и берёт перевод, а `description` ставит ядро прямо из настройки.
    # Русскому читателю выходила карточка по-русски при английском описании.
    describe "язык страницы один" do
      let(:перевод) { "Гармония, гаммы и аккорды" }

      before do
        SiteSetting.set_locale_from_accept_language_header = true
        SiteSettingLocalization.create!(
          setting_name: "site_description",
          locale: "ru",
          value: перевод,
          localizer_user_id: Discourse.system_user.id,
        )
      end

      def описание_и_карточка(locale)
        get "/", headers: { "User-Agent" => человек, "Accept-Language" => locale }
        expect(response.status).to eq(200)
        doc = Nokogiri.HTML5(response.body)
        [
          doc.css('meta[name="description"]').first&.[]("content"),
          doc.css('meta[property="og:description"]').first&.[]("content"),
        ]
      end

      it "описание и карточка на языке читателя и совпадают" do
        включить_свою_главную
        описание, карточка = описание_и_карточка("ru")

        expect(описание).to eq(перевод)
        expect(карточка).to eq(описание)
      end

      it "у читателя без перевода — язык по умолчанию, и снова одинаково (контроль)" do
        включить_свою_главную
        описание, карточка = описание_и_карточка("de")

        expect(описание).to eq(SiteSetting.site_description)
        expect(карточка).to eq(описание)
      end

      it "на главной от ядра описание остаётся ядровым (контроль)" do
        описание, = описание_и_карточка("ru")

        expect(описание).to eq(SiteSetting.site_description)
      end
    end
  end

  it "carries core's view unchanged, so a core upgrade cannot drift silently" do
    core = Rails.root.join("app/views/layouts/_noscript_header.html.erb").read
    ours =
      File.read(File.expand_path("../../../app/views/layouts/_noscript_header.html.erb", __FILE__))
    expect(core.lines.map(&:strip).reject(&:empty?) - ours.lines.map(&:strip)).to eq([])
  end
end
