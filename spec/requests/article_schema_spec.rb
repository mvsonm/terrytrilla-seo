# frozen_string_literal: true

# B7. Structured data of the crawler view: an article of the knowledge base is an Article.
RSpec.describe TerrytrillaSeo::ArticleSchema do
  fab!(:knowledge_base, :category)
  fab!(:questions, :category)

  fab!(:article) { Fabricate(:topic, category: knowledge_base, title: "How chords are built") }
  fab!(:article_post) { Fabricate(:post, topic: article) }

  fab!(:discussion) { Fabricate(:topic, category: questions) }
  fab!(:discussion_post) { Fabricate(:post, topic: discussion) }
  fab!(:discussion_reply) { Fabricate(:post, topic: discussion) }

  let(:bot) { "Googlebot/2.1 (+http://www.google.com/bot.html)" }

  before do
    SiteSetting.terrytrilla_seo_enabled = true
    SiteSetting.terrytrilla_seo_indexable_categories = "#{knowledge_base.id}|#{questions.id}"
    SiteSetting.terrytrilla_seo_knowledge_base_categories = knowledge_base.id.to_s
    SiteSetting.company_name = "TerryTrilla"
    SiteSetting.terrytrilla_seo_organization_url = "https://site.example"
  end

  def page(topic)
    get "/t/#{topic.slug}/#{topic.id}", headers: { "User-Agent" => bot }
    expect(response.status).to eq(200)
    doc = Nokogiri.HTML5(response.body)
    json =
      doc
        .css('script[type="application/ld+json"]')
        .map { |s| JSON.parse(s.text) }
        .find { |d| d["@type"] == "Article" }
    [doc.css("[itemtype]").map { |n| n["itemtype"] }, json]
  end

  it "marks a knowledge-base article as an Article written by the project" do
    types, json = page(article)
    expect(types).to include("https://schema.org/Article")
    expect(types).not_to include("http://schema.org/DiscussionForumPosting")
    expect(json["headline"]).to eq("How chords are built")
    expect(json["author"]).to eq(
      { "@type" => "Organization", "name" => "TerryTrilla", "url" => "https://site.example" },
    )
    expect(json["publisher"]).to eq(json["author"])
    expect(json["mainEntityOfPage"]).to end_with("/t/#{article.slug}/#{article.id}")
    expect(json["inLanguage"]).to eq("en")
  end

  it "dates the article by the first post" do
    published = 3.days.ago.change(usec: 0)
    modified = 1.day.ago.change(usec: 0)
    article_post.update_columns(created_at: published, last_version_at: modified)
    _, json = page(article)
    expect(Time.zone.parse(json["datePublished"])).to eq_time(published)
    expect(Time.zone.parse(json["dateModified"])).to eq_time(modified)
  end

  it "leaves a discussion as a forum posting (control)" do
    types, json = page(discussion)
    expect(types).to include("http://schema.org/DiscussionForumPosting")
    expect(json).to be_nil
  end

  it "gives no Article to a knowledge-base topic that is out of the index" do
    SiteSetting.terrytrilla_seo_indexable_categories = questions.id.to_s
    types, json = page(article)
    expect(types).not_to include("https://schema.org/Article")
    expect(json).to be_nil
  end

  it "leaves core alone when the plugin is disabled (control)" do
    SiteSetting.terrytrilla_seo_enabled = false
    types, json = page(article)
    expect(types).to include("http://schema.org/DiscussionForumPosting")
    expect(json).to be_nil
  end
end
