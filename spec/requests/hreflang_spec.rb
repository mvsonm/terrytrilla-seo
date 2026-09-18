# frozen_string_literal: true

# B1. hreflang is rendered only in the crawler layout, so every request is a crawler's.
RSpec.describe TerrytrillaSeo::Hreflang do
  fab!(:knowledge_base, :category)
  fab!(:questions, :category)

  fab!(:article) { Fabricate(:topic, category: knowledge_base, locale: "en") }
  fab!(:first_post) { Fabricate(:post, topic: article, locale: "en") }
  fab!(:reply) { Fabricate(:post, topic: article, locale: "ru") }

  let(:googlebot) { "Googlebot/2.1 (+http://www.google.com/bot.html)" }
  let(:url) { "#{Discourse.base_url}/t/#{article.slug}/#{article.id}" }

  before do
    SiteSetting.content_localization_enabled = true
    SiteSetting.set_locale_from_param = true
    SiteSetting.content_localization_crawler_param = true
    SiteSetting.content_localization_supported_locales = "en|de|ru|pt_BR"
    SiteSetting.allow_index_in_robots_txt = true
    SiteSetting.terrytrilla_seo_enabled = true
    SiteSetting.terrytrilla_seo_indexable_categories = "#{knowledge_base.id}|#{questions.id}"
    SiteSetting.terrytrilla_seo_knowledge_base_categories = knowledge_base.id.to_s
  end

  def translate(topic, locale, posts:)
    Fabricate(:topic_localization, topic: topic, locale: locale)
    posts.each { |post| Fabricate(:post_localization, post: post, locale: locale) }
  end

  def hreflangs(path)
    get path, headers: { "User-Agent" => googlebot }
    expect(response.status).to eq(200)
    response.body.scan(/<link rel="alternate" href="([^"]+)" hreflang="([^"]+)"/).to_h(&:reverse)
  end

  it "declares a language only when the title and every post are translated" do
    translate(article, "de", posts: [first_post, reply])
    translate(article, "ru", posts: [first_post])

    expect(hreflangs("/t/#{article.slug}/#{article.id}")).to eq(
      "x-default" => url,
      "en" => url,
      "de" => "#{url}?tl=de",
      # ru: the reply is WRITTEN in Russian, so it needs no Russian translation
      "ru" => "#{url}?tl=ru",
    )
  end

  # B1-бис. У темы больше одного адреса: `/t/тема/51/1` отдаёт кнопка «Поделиться».
  # Ядро ставит там canonical на адрес БЕЗ номера — альтернативы обязаны вести туда
  # же. Пока они вели на себя, поисковик приводил их к тому же canonical, группа
  # языков схлопывалась на один адрес и пара отбрасывалась целиком.
  it "points the alternates at the canonical address, not at the post address" do
    translate(article, "de", posts: [first_post, reply])

    expect(hreflangs("/t/#{article.slug}/#{article.id}/1")).to eq(
      "x-default" => url,
      "en" => url,
      "de" => "#{url}?tl=de",
    )
  end

  it "does not declare a language when one post is missing its translation" do
    translate(article, "de", posts: [first_post])
    expect(hreflangs("/t/#{article.slug}/#{article.id}").keys).to eq(%w[x-default en])
  end

  it "does not declare a language when only the title is missing" do
    [first_post, reply].each { |post| Fabricate(:post_localization, post: post, locale: "de") }
    expect(hreflangs("/t/#{article.slug}/#{article.id}").keys).to eq(%w[x-default en])
  end

  it "ignores deleted and hidden posts" do
    translate(article, "de", posts: [first_post, reply])
    Fabricate(:post, topic: article, locale: "en", deleted_at: Time.zone.now)
    Fabricate(:post, topic: article, locale: "en", hidden: true)
    expect(hreflangs("/t/#{article.slug}/#{article.id}").keys).to include("de")
  end

  it "always declares the original language, with ?tl unless it is the default" do
    article.update_columns(locale: "pt_BR")
    expect(hreflangs("/t/#{article.slug}/#{article.id}")).to eq(
      "x-default" => url,
      "pt-BR" => "#{url}?tl=pt_BR",
    )
  end

  it "matches translations by base language, as the translator does" do
    translate(article, "pt", posts: [first_post, reply])
    expect(hreflangs("/t/#{article.slug}/#{article.id}")["pt-BR"]).to eq("#{url}?tl=pt_BR")
  end

  it "declares only x-default for a topic without a detected language" do
    article.update_columns(locale: nil)
    translate(article, "de", posts: [first_post, reply])
    expect(hreflangs("/t/#{article.slug}/#{article.id}")).to eq("x-default" => url)
  end

  it "drops a language listed as excluded, but never the original" do
    translate(article, "de", posts: [first_post, reply])
    SiteSetting.terrytrilla_seo_hreflang_excluded_locales = "de|en"
    expect(hreflangs("/t/#{article.slug}/#{article.id}").keys).to eq(%w[x-default en])
  end

  it "gives no hreflang to a topic that is not indexable" do
    question = Fabricate(:topic, category: questions, locale: "en")
    post = Fabricate(:post, topic: question, locale: "en")
    translate(question, "de", posts: [post])
    expect(hreflangs("/t/#{question.slug}/#{question.id}")).to eq({})
  end

  it "keeps core's full list on pages without a topic (control)" do
    expect(hreflangs("/latest").keys).to eq(%w[x-default en de ru pt-BR])
  end

  it "carries core's partial unchanged, so a core upgrade cannot drift silently" do
    core = Rails.root.join("app/views/common/_hreflang_tags.html.erb").read
    ours =
      File.read(File.expand_path("../../../app/views/common/_hreflang_tags.html.erb", __FILE__))
    ours_lines = ours.lines.map(&:strip)
    expect(core.lines.map(&:strip).reject(&:empty?) - ours_lines).to eq([])
  end

  it "keeps core's full list on a topic when the plugin is disabled (control)" do
    SiteSetting.terrytrilla_seo_enabled = false
    expect(hreflangs("/t/#{article.slug}/#{article.id}").keys).to eq(%w[x-default en de ru pt-BR])
  end
end
