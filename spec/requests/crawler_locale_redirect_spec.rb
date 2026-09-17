# frozen_string_literal: true

RSpec.describe TerrytrillaSeo::CrawlerLocaleRedirect do
  fab!(:topic) { Fabricate(:topic, title: "Minor key chords and the dominant") }
  fab!(:first_post) { Fabricate(:post, topic: topic) }

  let(:bot) { "Twitterbot/1.0" }
  let(:browser) do
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
  end
  let(:path) { "/t/#{topic.slug}/#{topic.id}" }

  before do
    SiteSetting.default_locale = "en"
    SiteSetting.allow_user_locale = true
    SiteSetting.content_localization_enabled = true
    SiteSetting.set_locale_from_param = true
    SiteSetting.content_localization_crawler_param = true
    SiteSetting.content_localization_supported_locales = "en|ru|pl_PL|pt_BR"
    SiteSetting.terrytrilla_seo_enabled = true
  end

  def fetch(url, user_agent)
    get url, headers: { "User-Agent" => user_agent }
    response
  end

  it "redirects a crawler from ?tl=en to the URL without tl" do
    res = fetch("#{path}?tl=en", bot)
    expect(res.status).to eq(301)
    expect(res.location).to end_with(path)
  end

  it "keeps other parameters when dropping tl" do
    res = fetch("#{path}?tl=en&page=2", bot)
    expect(res.status).to eq(301)
    expect(res.location).to end_with("#{path}?page=2")
  end

  it "redirects a crawler from a short code to the supported one" do
    expect(fetch("#{path}?tl=pl", bot).location).to end_with("#{path}?tl=pl_PL")
    expect(fetch("#{path}?tl=pt-BR", bot).location).to end_with("#{path}?tl=pt_BR")
    expect(response.status).to eq(301)
  end

  it "serves a supported non-default language to a crawler" do
    expect(fetch("#{path}?tl=ru", bot).status).to eq(200)
    expect(fetch("#{path}?tl=pl_PL", bot).status).to eq(200)
  end

  it "leaves an unknown language alone" do
    expect(fetch("#{path}?tl=xx", bot).status).to eq(200)
  end

  it "does not guess when a short code matches two supported locales" do
    SiteSetting.content_localization_supported_locales = "en|zh_CN|zh_TW"
    expect(fetch("#{path}?tl=zh", bot).status).to eq(200)
  end

  it "never redirects people" do
    expect(fetch("#{path}?tl=en", browser).status).to eq(200)
    expect(fetch("#{path}?tl=pl", browser).status).to eq(200)
  end

  it "does not redirect people on the print view, which also uses the crawler layout" do
    expect(fetch("#{path}?tl=en&print=true", browser).status).to eq(200)
  end

  it "does not redirect JSON requests of a crawler" do
    expect(fetch("#{path}.json?tl=en", bot).status).to eq(200)
  end

  it "does nothing when the plugin is disabled (control)" do
    SiteSetting.terrytrilla_seo_enabled = false
    expect(fetch("#{path}?tl=en", bot).status).to eq(200)
  end
end
