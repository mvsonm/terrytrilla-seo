# frozen_string_literal: true

# B3. Checked with allow_index_in_robots_txt = true: on a closed forum core puts
# "noindex, nofollow" on EVERY page, and a spec there would prove nothing.
RSpec.describe TerrytrillaSeo::Indexing do
  fab!(:knowledge_base, :category)
  fab!(:questions, :category)
  fab!(:site_feedback, :category)
  fab!(:drafts) { Fabricate(:category, read_restricted: true) }

  fab!(:article) { Fabricate(:topic, category: knowledge_base) }
  fab!(:article_post) { Fabricate(:post, topic: article) }

  fab!(:question) { Fabricate(:topic, category: questions) }
  fab!(:question_post) { Fabricate(:post, topic: question) }

  fab!(:feedback) { Fabricate(:topic, category: site_feedback) }
  fab!(:feedback_post) { Fabricate(:post, topic: feedback) }
  fab!(:feedback_reply) { Fabricate(:post, topic: feedback) }

  before do
    SiteSetting.allow_index_in_robots_txt = true
    SiteSetting.terrytrilla_seo_enabled = true
    SiteSetting.terrytrilla_seo_indexable_categories =
      "#{knowledge_base.id}|#{questions.id}|#{drafts.id}"
    SiteSetting.terrytrilla_seo_knowledge_base_categories = knowledge_base.id.to_s
  end

  def robots_of(topic)
    get "/t/#{topic.slug}/#{topic.id}"
    expect(response.status).to eq(200)
    [
      response.headers["X-Robots-Tag"],
      response.body.include?('<meta name="robots" content="noindex">'),
    ]
  end

  it "does not index an unanswered question" do
    expect(robots_of(question)).to eq(["noindex", true])
  end

  it "indexes the question once somebody replies" do
    Fabricate(:post, topic: question)
    header, meta = robots_of(question.reload)
    expect(header.to_s).not_to include("noindex")
    expect(meta).to eq(false)
  end

  it "indexes a knowledge-base article without replies" do
    header, meta = robots_of(article)
    expect(header.to_s).not_to include("noindex")
    expect(meta).to eq(false)
  end

  it "does not index a category description topic, even with replies" do
    about = Fabricate(:topic, category: questions)
    Fabricate(:post, topic: about)
    Fabricate(:post, topic: about)
    questions.update!(topic_id: about.id)
    expect(robots_of(about.reload)).to eq(["noindex", true])
  end

  it "does not index a category missing from the explicit list, even with replies" do
    expect(robots_of(feedback)).to eq(["noindex", true])
  end

  it "does not index a restricted category even when listed" do
    topic = Fabricate(:topic, category: drafts)
    Fabricate(:post, topic: topic)
    Fabricate(:post, topic: topic)
    # ⚠️ reload: without it posts_count is 0 in memory, and the topic is "not indexable"
    # for having no replies — the spec stayed green with the read_restricted check removed.
    topic.reload
    expect(topic.posts_count).to eq(2)
    expect(described_class.indexable?(topic)).to eq(false)
  end

  it "adds the meta tag to the crawler view as well" do
    get "/t/#{question.slug}/#{question.id}",
        headers: {
          "User-Agent" => "Googlebot/2.1 (+http://www.google.com/bot.html)",
        }
    expect(response.body).to include('<meta name="robots" content="noindex">')
    expect(response.headers["X-Robots-Tag"]).to eq("noindex")
  end

  it "leaves core behaviour alone when the plugin is disabled (control)" do
    SiteSetting.terrytrilla_seo_enabled = false
    header, meta = robots_of(question)
    expect(header.to_s).not_to include("noindex")
    expect(meta).to eq(false)
  end

  # B6: the same rule also says what an indexable page asks for.
  it "asks for a large image and a full snippet on an indexable page" do
    get "/t/#{article.slug}/#{article.id}"
    content = "max-image-preview:large, max-snippet:-1"
    expect(response.headers["X-Robots-Tag"]).to eq(content)
    expect(response.body).to include(%(<meta name="robots" content="#{content}">))
  end

  it "never asks for a large image on a page it keeps out of the index" do
    get "/t/#{question.slug}/#{question.id}"
    expect(response.headers["X-Robots-Tag"]).to eq("noindex")
    expect(response.body).not_to include("max-image-preview")
  end

  it "keeps core's stronger noindex, nofollow on a closed forum" do
    SiteSetting.allow_index_in_robots_txt = false
    get "/t/#{question.slug}/#{question.id}"
    expect(response.headers["X-Robots-Tag"]).to eq("noindex, nofollow")
  end

  # B3-бис: список групп. Ядро закрывает /u, /badges и /search, а /g оставляло
  # открытым — пустая страница с заголовком главной шла бы в индекс.
  it "keeps the group list out of the index" do
    get "/g"
    expect(response.body).to include(%(<meta name="robots" content="noindex">))
  end

  it "leaves the group list to core when the plugin is disabled (control)" do
    SiteSetting.terrytrilla_seo_enabled = false
    get "/g"
    expect(response.body).not_to include("noindex")
  end

  # B16: страницы без темы. Замер 19.09 нашёл два расхождения сразу — дубли
  # заголовков у `/`, `/categories` и `/top` и отсутствие крупного превью у главной.
  describe "страницы без темы" do
    def robots_меты(path)
      get path, headers: { "User-Agent" => "Mozilla/5.0 (compatible; Googlebot/2.1)" }
      expect(response.status).to eq(200)
      Nokogiri.HTML5(response.body).css('meta[name="robots"]').map { |m| m["content"] }
    end

    it "просит крупное превью на главной" do
      expect(robots_меты("/")).to eq([TerrytrillaSeo::Indexing::INDEXABLE_ROBOTS])
    end

    it "просит крупное превью на странице раздела" do
      меты = robots_меты("/c/#{knowledge_base.slug}/#{knowledge_base.id}")

      expect(меты).to eq([TerrytrillaSeo::Indexing::INDEXABLE_ROBOTS])
    end

    it "закрывает списки: они повторяют главную на другом адресе" do
      %w[/latest /top /categories /new].each do |path|
        expect(robots_меты(path)).to eq(["noindex"]), "ожидался noindex на #{path}"
      end
    end

    it "не трогает страницы, которые ядро закрывает само (контроль)" do
      # `/u` и `/badges` ядро закрывает заголовком; своей меты там быть не должно.
      expect(robots_меты("/badges")).to eq([])
    end

    it "молчит с выключенным плагином (контроль)" do
      SiteSetting.terrytrilla_seo_enabled = false

      expect(robots_меты("/latest")).to eq([])
    end
  end
end
