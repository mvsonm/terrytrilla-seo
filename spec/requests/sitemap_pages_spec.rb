# frozen_string_literal: true

# B10-бис. В карте сайта не только темы: главная и разделы.
RSpec.describe TerrytrillaSeo::SitemapPages do
  fab!(:knowledge_base, :category)
  fab!(:questions, :category)
  fab!(:theory, :category)
  fab!(:drafts) { Fabricate(:category, read_restricted: true) }

  fab!(:article) { Fabricate(:topic, category: knowledge_base) }
  fab!(:article_post) { Fabricate(:post, topic: article) }

  fab!(:answered) { Fabricate(:topic, category: questions) }
  fab!(:answered_post) { Fabricate(:post, topic: answered) }
  fab!(:answered_reply) { Fabricate(:post, topic: answered) }

  # Раздел «Теория» открыт поиску, но в нём только вопрос без ответа: страница раздела
  # пуста по смыслу, и в карте её быть не должно.
  fab!(:unanswered) { Fabricate(:topic, category: theory) }
  fab!(:unanswered_post) { Fabricate(:post, topic: unanswered) }

  fab!(:draft) { Fabricate(:topic, category: drafts) }
  fab!(:draft_post) { Fabricate(:post, topic: draft) }
  fab!(:draft_reply) { Fabricate(:post, topic: draft) }

  before do
    SiteSetting.terrytrilla_seo_enabled = true
    SiteSetting.terrytrilla_seo_indexable_categories =
      "#{knowledge_base.id}|#{questions.id}|#{theory.id}|#{drafts.id}"
    SiteSetting.terrytrilla_seo_knowledge_base_categories = knowledge_base.id.to_s
    Sitemap.regenerate_sitemaps
  end

  # Кеш сбрасывается руками: его ключ считается по дате в секундах, а в спеке две
  # правки подряд попадают в одну секунду — карта отдалась бы из кеша, и проверка
  # показала бы прежний состав.
  def urls(path = "/sitemap_pages.xml")
    Discourse.cache.delete(described_class.cache_key)
    get path
    expect(response.status).to eq(200)
    Nokogiri::XML::Document.parse(response.body).remove_namespaces!.css("url")
  end

  def locs(path = "/sitemap_pages.xml")
    urls(path).map { |url| url.at_css("loc").text }
  end

  def lastmod_of(loc)
    url = urls.find { |u| u.at_css("loc").text == loc }
    expect(url).to be_present
    Time.zone.parse(url.at_css("lastmod").text)
  end

  describe "состав карты" do
    it "содержит главную и разделы с индексируемыми темами" do
      expect(locs).to contain_exactly(
        "#{Discourse.base_url}/",
        "#{Discourse.base_url}#{knowledge_base.url}",
        "#{Discourse.base_url}#{questions.url}",
      )
    end

    it "не содержит раздела без индексируемых тем" do
      expect(locs).not_to include("#{Discourse.base_url}#{theory.url}")
    end

    it "не содержит закрытого раздела" do
      expect(locs).not_to include("#{Discourse.base_url}#{drafts.url}")
    end

    it "адресует раздел так же, как его canonical: /c/slug/id" do
      expect(locs).to include("#{Discourse.base_url}/c/#{questions.slug}/#{questions.id}")
    end

    # Ровно то, о чём просил владелец: новая страница попадает в карту сама.
    it "добавляет раздел сам, как только в нём появился ответ" do
      expect(locs).not_to include("#{Discourse.base_url}#{theory.url}")

      Fabricate(:post, topic: unanswered)
      unanswered.reload

      expect(locs).to include("#{Discourse.base_url}#{theory.url}")
    end

    it "убирает раздел сам, когда индексируемых тем не осталось" do
      answered_reply.trash!
      answered.update_columns(posts_count: 1)

      expect(locs).not_to include("#{Discourse.base_url}#{questions.url}")
    end

    it "отвечает 404, когда индексировать нечего (control)" do
      Topic.update_all(visible: false)
      Discourse.cache.delete(described_class.cache_key)
      get "/sitemap_pages.xml"
      expect(response.status).to eq(404)
    end

    it "отвечает 404 при выключенном плагине (control)" do
      SiteSetting.terrytrilla_seo_enabled = false
      get "/sitemap_pages.xml"
      expect(response.status).to eq(404)
    end
  end

  describe "даты" do
    it "датирует раздел последним осмысленным изменением его темы" do
      answered.update_columns(last_posted_at: 5.days.ago, bumped_at: 5.days.ago)
      # Раздел создан фабрикой только что, и его собственная дата иначе перебила бы дату
      # темы: у страницы раздела два источника изменения, и здесь проверяется второй.
      questions.update_columns(updated_at: 5.days.ago)
      edited_at = 1.day.ago.change(usec: 0)
      answered_post.update_columns(last_version_at: edited_at)

      expect(lastmod_of("#{Discourse.base_url}#{questions.url}")).to eq_time(edited_at)
    end

    it "показывает правку описания раздела, если она свежее его тем" do
      answered.update_columns(last_posted_at: 5.days.ago)
      answered_post.update_columns(last_version_at: 5.days.ago)
      described_at = 1.hour.ago.change(usec: 0)
      questions.update_columns(updated_at: described_at)

      expect(lastmod_of("#{Discourse.base_url}#{questions.url}")).to eq_time(described_at)
    end

    it "датирует главную самой свежей из страниц" do
      freshest = 2.hours.ago.change(usec: 0)
      Topic.update_all(last_posted_at: 10.days.ago, bumped_at: 10.days.ago)
      Post.update_all(last_version_at: 10.days.ago)
      Category.update_all(updated_at: 10.days.ago)
      answered.update_columns(last_posted_at: freshest)

      expect(lastmod_of("#{Discourse.base_url}/")).to eq_time(freshest)
    end
  end

  describe "индекс карт" do
    def index_locs
      get "/sitemap.xml"
      expect(response.status).to eq(200)
      Nokogiri::XML::Document.parse(response.body).remove_namespaces!.css("sitemap loc").map(&:text)
    end

    it "перечисляет карту страниц" do
      expect(index_locs).to include("#{Discourse.base_url}/sitemap_pages.xml")
    end

    it "датирует её самой свежей страницей" do
      get "/sitemap.xml"
      doc = Nokogiri::XML::Document.parse(response.body).remove_namespaces!
      node = doc.css("sitemap").find { |s| s.at_css("loc").text.end_with?("/sitemap_pages.xml") }
      # В XML дата пишется с точностью до секунды — сравнение точнее секунды сравнивало бы
      # не даты, а округление.
      expect(Time.zone.parse(node.at_css("lastmod").text)).to be_within(1.second).of(
        described_class.latest,
      )
    end

    # Ядро выключает карты, имён которых не знает. Без этого плагин отдавал бы карту
    # страниц, а из индекса она исчезала бы после ночного Jobs::RegenerateSitemaps.
    it "не теряет карту страниц при пересчёте карт" do
      Sitemap.regenerate_sitemaps
      expect(Sitemap.find_by(name: described_class::NAME)).to be_enabled
      expect(index_locs).to include("#{Discourse.base_url}/sitemap_pages.xml")
    end

    it "убирает карту страниц из индекса при выключенном плагине (control)" do
      SiteSetting.terrytrilla_seo_enabled = false
      Sitemap.regenerate_sitemaps
      expect(index_locs).not_to include("#{Discourse.base_url}/sitemap_pages.xml")
    end

    # `sitemap_topics` ядра считает offset из имени карты: для «pages» это −1 страница,
    # и запрос упал бы прямо в индексе карт (там читается last_posted_topic).
    it "не спрашивает у карты страниц темы" do
      expect(Sitemap.find_by(name: described_class::NAME).topics).to eq([])
    end
  end

  describe "кеш" do
    it "меняет ключ, когда страница изменилась" do
      before_key = described_class.cache_key
      answered.update_columns(last_posted_at: 1.minute.from_now)
      expect(described_class.cache_key).not_to eq(before_key)
    end
  end
end
