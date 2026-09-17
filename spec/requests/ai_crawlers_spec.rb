# frozen_string_literal: true

# B9. robots.txt: search engines get the forum, training corpora do not (Р-9).
RSpec.describe TerrytrillaSeo::AiCrawlers do
  before do
    SiteSetting.terrytrilla_seo_enabled = true
    SiteSetting.allow_index_in_robots_txt = true
    SiteSetting.overridden_robots_txt = ""
    SiteSetting.allowed_crawler_user_agents = ""
  end

  def robots
    get "/robots.txt"
    expect(response.status).to eq(200)
    response.body
  end

  # Группа агента: строки до следующей пустой строки после его User-agent.
  def группа(текст, агент)
    блок =
      текст
        .split(/\n\s*\n/)
        .find { |b| b.include?("User-agent: #{агент}\n") || b.end_with?("User-agent: #{агент}") }
    блок.to_s.lines.map(&:strip).reject(&:empty?)
  end

  it "opens the forum to search and answer engines" do
    строки = группа(robots, "GPTBot")
    expect(строки).to include("Allow: /")
    expect(строки).to include("Disallow: /search")
    expect(строки).not_to include("Disallow: /")
  end

  it "closes the forum to collectors of training corpora" do
    строки = группа(robots, "CCBot")
    expect(строки).to include("Disallow: /")
    expect(строки).not_to include("Allow: /")
  end

  it "says nothing about crawlers that ignore robots.txt (Р-9)" do
    текст = robots
    %w[ChatGPT-User Perplexity-User meta-externalfetcher].each do |агент|
      expect(текст).not_to include("User-agent: #{агент}")
    end
  end

  it "keeps core's own groups (control)" do
    текст = robots
    expect(текст).to include("User-agent: *")
    expect(текст).to include("Disallow: /admin/")
    expect(текст).to include("Sitemap:")
  end

  it "promises nothing while the forum is closed to search" do
    SiteSetting.allow_index_in_robots_txt = false
    текст = robots
    expect(текст).to include("Disallow: /")
    TerrytrillaSeo::AiCrawlers::SEARCH_AGENTS.each do |агент|
      expect(текст).not_to include("User-agent: #{агент}")
    end
  end

  it "steps aside for a robots.txt written by hand" do
    SiteSetting.overridden_robots_txt = "User-agent: *\nDisallow: /"
    expect(robots).not_to include("GPTBot")
  end

  it "adds nothing when the plugin is disabled (control)" do
    SiteSetting.terrytrilla_seo_enabled = false
    expect(robots).not_to include("GPTBot")
  end

  # ⚠️ Двух условий правила сам файл НЕ сторожит: при закрытом индексе ядро рисует
  # другой шаблон, а при своём robots.txt не рисует ни одного — группы не попали бы
  # в файл и без нашей проверки (мутации 17.09 прошли зелёными). Поэтому условия
  # проверяются прямо у правила: страховка обязана работать, если однажды коннектор
  # позовут из другого места.
  describe ".groups" do
    it "is empty while the forum is closed to search" do
      SiteSetting.allow_index_in_robots_txt = false
      expect(described_class.groups).to eq([])
    end

    it "is empty when robots.txt is written by hand" do
      SiteSetting.overridden_robots_txt = "User-agent: *\nDisallow: /"
      expect(described_class.groups).to eq([])
    end

    it "names every agent once (control)" do
      агенты = described_class.groups.map(&:first)
      expect(агенты.uniq.size).to eq(агенты.size)
      expect(агенты).to include("GPTBot", "CCBot")
    end
  end
end
