# frozen_string_literal: true

RSpec.describe TerrytrillaSeo::CrawlerLocale do
  fab!(:topic) { Fabricate(:topic, title: "Minor key chords and the dominant") }
  fab!(:first_post) { Fabricate(:post, topic: topic) }

  let(:bot) { "Twitterbot/1.0" }
  let(:browser) do
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
  end

  before do
    SiteSetting.default_locale = "en"
    SiteSetting.allow_user_locale = true
    SiteSetting.set_locale_from_accept_language_header = true
    SiteSetting.set_locale_from_param = true
    SiteSetting.terrytrilla_seo_enabled = true
  end

  def html_lang(path, user_agent)
    get path, headers: { "User-Agent" => user_agent, "Accept-Language" => "de" }
    expect(response.status).to eq(200)
    response.body[/<html[^>]*\blang="([^"]+)"/, 1]
  end

  it "serves a crawler the default language on a URL without ?tl" do
    expect(html_lang("/t/#{topic.slug}/#{topic.id}", bot)).to eq("en")
  end

  it "still honours ?tl for a crawler" do
    expect(html_lang("/t/#{topic.slug}/#{topic.id}?tl=de", bot)).to eq("de")
  end

  it "keeps Accept-Language for people" do
    expect(html_lang("/t/#{topic.slug}/#{topic.id}", browser)).to eq("de")
  end

  it "lets the crawler follow Accept-Language when the plugin is disabled (control)" do
    SiteSetting.terrytrilla_seo_enabled = false
    expect(html_lang("/t/#{topic.slug}/#{topic.id}", bot)).to eq("de")
  end
end
