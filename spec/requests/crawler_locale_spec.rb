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

  describe "what the plain URL serves (core asks with include_param: false since 2026.11)" do
    def request_for(user_agent)
      env =
        Rack::MockRequest.env_for(
          "/t/#{topic.slug}/#{topic.id}?tl=de",
          "HTTP_USER_AGENT" => user_agent,
          "HTTP_ACCEPT_LANGUAGE" => "de",
        )
      ActionDispatch::Request.new(env)
    end

    it "is the default language for a crawler, whatever ?tl and Accept-Language say" do
      expect(Discourse.anonymous_locale(request_for(bot), include_param: false)).to eq("en")
    end

    it "follows Accept-Language for people" do
      expect(Discourse.anonymous_locale(request_for(browser), include_param: false)).to eq("de")
    end

    it "keeps ?tl when core asks with the param (the page itself)" do
      expect(Discourse.anonymous_locale(request_for(bot))).to eq("de")
    end
  end

  it "serves a crawler a ?tl page while the crawler locale param is on (anonymous cache key)" do
    SiteSetting.content_localization_enabled = true
    SiteSetting.content_localization_supported_locales = "en|de"
    SiteSetting.content_localization_crawler_param = true
    expect(html_lang("/t/#{topic.slug}/#{topic.id}?tl=de", bot)).to eq("de")
    expect(html_lang("/t/#{topic.slug}/#{topic.id}", bot)).to eq("en")
  end

  it "lets the crawler follow Accept-Language when the plugin is disabled (control)" do
    SiteSetting.terrytrilla_seo_enabled = false
    expect(html_lang("/t/#{topic.slug}/#{topic.id}", bot)).to eq("de")
  end
end
