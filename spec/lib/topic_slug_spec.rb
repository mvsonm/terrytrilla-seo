# frozen_string_literal: true

RSpec.describe TerrytrillaSeo::TopicSlug do
  fab!(:admin)

  def translate(topic, title, locale: "en")
    TopicLocalization.create!(
      topic: topic,
      locale: locale,
      title: title,
      fancy_title: title,
      localizer_user_id: admin.id,
    )
  end

  before do
    SiteSetting.terrytrilla_seo_enabled = true
    SiteSetting.slug_generation_method = "ascii"
  end

  describe ".non_latin?" do
    it "tells scripts apart" do
      expect(described_class.non_latin?("Оглавление базы знаний")).to eq(true)
      expect(described_class.non_latin?("ギターのスケール練習")).to eq(true)
      expect(described_class.non_latin?("Что такое Студия TerryTrilla")).to eq(true)
      expect(described_class.non_latin?("Campo harmônico menor")).to eq(false)
      expect(described_class.non_latin?("Scale Circle: what it is")).to eq(false)
      expect(described_class.non_latin?("2026 — 12")).to eq(false)
    end
  end

  describe "slug from the English translation" do
    fab!(:topic) { Fabricate(:topic, title: "Оглавление базы знаний") }

    it "is the core placeholder before the translation (control)" do
      expect(topic.slug).to eq("topic")
    end

    it "is taken from the English title once the translation is saved" do
      translate(topic, "Knowledge Base Table of Contents")
      expect(topic.reload.slug).to eq("knowledge-base-table-of-contents")
    end

    it "survives an edit of the original title" do
      translate(topic, "Knowledge Base Table of Contents")
      topic.reload
      topic.title = "Оглавление базы знаний и статьи"
      topic.save!
      expect(topic.reload.slug).to eq("knowledge-base-table-of-contents")
    end

    it "ignores translations into other languages" do
      translate(topic, "Inhaltsverzeichnis der Wissensdatenbank", locale: "de")
      expect(topic.reload.slug).to eq("topic")
    end

    it "keeps the placeholder when the plugin is disabled (control)" do
      SiteSetting.terrytrilla_seo_enabled = false
      translate(topic, "Knowledge Base Table of Contents")
      expect(topic.reload.slug).to eq("topic")
    end

    it "does not move once slugs are frozen" do
      SiteSetting.terrytrilla_seo_freeze_slugs = true
      translate(topic, "Knowledge Base Table of Contents")
      expect(topic.reload.slug).to eq("topic")
    end
  end

  describe "Latin-script titles" do
    it "keep the core slug even with an English translation" do
      topic = Fabricate(:topic, title: "Campo harmônico menor: por que o V grau vira maior?")
      core = topic.slug
      translate(topic, "Minor key chords: why is the V chord major?")
      expect(topic.reload.slug).to eq(core)
      expect(core).to start_with("campo-harmonico-menor")
    end
  end

  describe ".recompute_all!" do
    it "fixes existing topics and reports what changed" do
      topic = Fabricate(:topic, title: "Синкопа в аккомпанементе")
      translate(topic, "Syncopation in the accompaniment")
      topic.update_column(:slug, "topic")

      changed = described_class.recompute_all!
      expect(changed).to include([topic.id, "topic", "syncopation-in-the-accompaniment"])
      expect(topic.reload.slug).to eq("syncopation-in-the-accompaniment")
      expect(described_class.recompute_all!).to eq([])
    end

    # 17.09 on production: t/2 and t/6 lost their transliterated slugs to `topic`.
    it "leaves a topic without an English title as it is" do
      topic = Fabricate(:topic, title: "Описание категории Персонал")
      topic.update_column(:slug, "opisanie-kategorii-personal")

      expect(described_class.recompute_all!).to eq([])
      expect(topic.reload.slug).to eq("opisanie-kategorii-personal")
    end

    it "leaves a Latin-script topic as it is" do
      topic = Fabricate(:topic, title: "Campo harmônico menor: por que o V grau vira maior?")
      translate(topic, "Minor key chords: why is the V chord major?")
      topic.update_column(:slug, "old-slug")

      expect(described_class.recompute_all!).to eq([])
      expect(topic.reload.slug).to eq("old-slug")
    end
  end
end
