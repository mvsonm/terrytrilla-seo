# frozen_string_literal: true

RSpec.describe TerrytrillaSeo::Hreflang do
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category, locale: "en") }

  before do
    SiteSetting.terrytrilla_seo_enabled = true
    SiteSetting.terrytrilla_seo_indexable_categories = category.id.to_s
    SiteSetting.terrytrilla_seo_knowledge_base_categories = category.id.to_s
  end

  # B1-бис. Адрес запроса и canonical здесь РАЗНЫЕ — иначе проверка прошла бы и на
  # коде, который canonical не читает вовсе.
  describe ".canonical_base" do
    let(:requested) { "https://forum.example.com/t/article/51/1" }
    let(:canonical) { "https://forum.example.com/t/article/51" }

    it "takes the canonical address, not the requested one" do
      expect(described_class.canonical_base(canonical, requested)).to eq(canonical)
    end

    it "drops the language parameter: it comes back per language below" do
      expect(described_class.canonical_base("#{canonical}?tl=ru", requested)).to eq(canonical)
    end

    it "keeps the other parameters: page two stays page two" do
      expect(described_class.canonical_base("#{canonical}?page=2&tl=ru", requested)).to eq(
        "#{canonical}?page=2",
      )
    end

    it "falls back to the requested address when there is no canonical (control)" do
      expect(described_class.canonical_base(nil, requested)).to eq(requested)
      expect(described_class.canonical_base("", requested)).to eq(requested)
    end
  end

  describe ".links" do
    # Язык темы (en) НЕ совпадает с языком форума по умолчанию (ru) — только так
    # проверяется склейка параметра: у языка по умолчанию его не бывает.
    before do
      SiteSetting.default_locale = "ru"
      SiteSetting.content_localization_supported_locales = "en|ru"
    end

    it "joins the language with & when the address already has parameters" do
      links = described_class.links(topic, "https://forum.example.com/t/article/51?page=2")

      expect(links).to include(["x-default", "https://forum.example.com/t/article/51?page=2"])
      expect(links).to include(["en", "https://forum.example.com/t/article/51?page=2&tl=en"])
    end

    it "joins the language with ? when the address has none (control)" do
      links = described_class.links(topic, "https://forum.example.com/t/article/51")

      expect(links).to include(["en", "https://forum.example.com/t/article/51?tl=en"])
    end
  end
end
