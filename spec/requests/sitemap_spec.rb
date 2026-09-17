# frozen_string_literal: true

# B10. The sitemap lists only what B3 lets into the index.
RSpec.describe TerrytrillaSeo::SitemapTopics do
  fab!(:knowledge_base, :category)
  fab!(:questions, :category)
  fab!(:site_feedback, :category)
  fab!(:drafts) { Fabricate(:category, read_restricted: true) }

  fab!(:article) { Fabricate(:topic, category: knowledge_base) }
  fab!(:article_post) { Fabricate(:post, topic: article) }

  fab!(:answered) { Fabricate(:topic, category: questions) }
  fab!(:answered_post) { Fabricate(:post, topic: answered) }
  fab!(:answered_reply) { Fabricate(:post, topic: answered) }

  fab!(:unanswered) { Fabricate(:topic, category: questions) }
  fab!(:unanswered_post) { Fabricate(:post, topic: unanswered) }

  fab!(:feedback) { Fabricate(:topic, category: site_feedback) }
  fab!(:feedback_post) { Fabricate(:post, topic: feedback) }
  fab!(:feedback_reply) { Fabricate(:post, topic: feedback) }

  before do
    SiteSetting.terrytrilla_seo_enabled = true
    SiteSetting.terrytrilla_seo_indexable_categories =
      "#{knowledge_base.id}|#{questions.id}|#{drafts.id}"
    SiteSetting.terrytrilla_seo_knowledge_base_categories = knowledge_base.id.to_s
    Sitemap.touch("1")
    Sitemap.touch(Sitemap::RECENT_SITEMAP_NAME)
    Discourse.cache.delete("sitemap/1/#{SiteSetting.sitemap_page_size}")
  end

  def urls(path)
    get path
    expect(response.status).to eq(200)
    Nokogiri::XML::Document.parse(response.body).remove_namespaces!.css("url")
  end

  def topic_ids(path)
    urls(path).map { |url| url.at_css("loc").text[%r{/(\d+)(\?|$)}, 1].to_i }
  end

  it "lists only indexable topics" do
    expect(topic_ids("/sitemap_1.xml")).to contain_exactly(article.id, answered.id)
  end

  it "applies the same rule to the recent sitemap" do
    expect(topic_ids("/sitemap_recent.xml")).to contain_exactly(article.id, answered.id)
  end

  it "keeps core's last-page link of a long topic in the recent sitemap" do
    answered.update_columns(posts_count: TopicView.chunk_size * 2 + 1)
    loc =
      urls("/sitemap_recent.xml")
        .map { |u| u.at_css("loc").text }
        .find { |l| l.include?("/#{answered.id}") }
    expect(loc).to end_with("/#{answered.id}?page=3")
  end

  it "leaves out a category description topic, even with replies" do
    about = Fabricate(:topic, category: questions)
    2.times { Fabricate(:post, topic: about) }
    questions.update!(topic_id: about.id)
    expect(topic_ids("/sitemap_1.xml")).not_to include(about.id)
  end

  it "keeps the SQL rule equal to indexable? on every topic" do
    about = Fabricate(:topic, category: questions)
    2.times { Fabricate(:post, topic: about) }
    questions.update!(topic_id: about.id)
    draft = Fabricate(:topic, category: drafts)
    2.times { Fabricate(:post, topic: draft) }
    hidden = Fabricate(:topic, category: questions, visible: false)
    2.times { Fabricate(:post, topic: hidden) }

    all = Topic.where(archetype: Archetype.default).reload.to_a
    by_sql = TerrytrillaSeo::Indexing.indexable_scope(Topic.all).pluck(:id)
    by_ruby = all.select { |topic| TerrytrillaSeo::Indexing.indexable?(topic) }.map(&:id)

    expect(by_ruby).to include(article.id, answered.id)
    expect(by_sql).to match_array(by_ruby)
  end

  it "dates a topic by the latest reply or revision of the first post" do
    answered.update_columns(last_posted_at: 5.days.ago, bumped_at: 5.days.ago)
    edited_at = 1.day.ago.change(usec: 0)
    answered_post.update_columns(last_version_at: edited_at)

    url = urls("/sitemap_1.xml").find { |u| u.at_css("loc").text.include?("/#{answered.id}") }
    expect(Time.zone.parse(url.at_css("lastmod").text)).to eq_time(edited_at)
  end

  it "lists every visible public topic when the plugin is disabled (control)" do
    SiteSetting.terrytrilla_seo_enabled = false
    expect(topic_ids("/sitemap_1.xml")).to include(unanswered.id, feedback.id)
  end
end
