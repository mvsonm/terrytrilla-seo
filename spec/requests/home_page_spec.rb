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

  it "carries core's view unchanged, so a core upgrade cannot drift silently" do
    core = Rails.root.join("app/views/layouts/_noscript_header.html.erb").read
    ours =
      File.read(File.expand_path("../../../app/views/layouts/_noscript_header.html.erb", __FILE__))
    expect(core.lines.map(&:strip).reject(&:empty?) - ours.lines.map(&:strip)).to eq([])
  end
end
