# frozen_string_literal: true

# B17. Подзаголовок форума в заголовке главной — на языке страницы.
#
# Спек проверяет не только проводку, но и САМ ПЕРЕВОД: в каждом языке должны стоять
# те же слова, что в утверждённом описании форума и в глоссарии проекта
# (`docs/Discourse/GLOSSARY.md`: лад/гамма, аккорд, гармония). Перевод «на слух»
# разошёлся бы с сайтом и каталогом, а это ровно то, ради чего заведён глоссарий.
RSpec.describe "Подзаголовок форума" do
  # язык → [лад, аккорд, гармония] в той форме, что принята в этом языке
  ТЕРМИНЫ = {
    "en" => %w[scales chords harmony],
    "ru" => %w[гаммы аккорды гармония],
    "uk" => %w[гами акорди гармонія],
    "de" => %w[Tonleitern Akkorde Harmonie],
    "es" => %w[escalas acordes armonía],
    "fr" => %w[gammes accords harmonie],
    "it" => %w[scale accordi armonia],
    "pl_PL" => %w[skale akordy harmonia],
    "pt_BR" => %w[escalas acordes harmonia],
    "ja" => %w[スケール コード ハーモニー],
    "ko" => %w[음계 코드 화성],
    "ar" => %w[السلالم الأكوردات الهارموني],
  }.freeze

  before { SiteSetting.terrytrilla_seo_enabled = true }

  it "переведён на все двенадцать языков сайта" do
    отсутствуют =
      ТЕРМИНЫ.keys.reject do |код|
        I18n.t("terrytrilla_seo.tagline", locale: код, default: nil).present?
      end

    expect(отсутствуют).to eq([])
  end

  ТЕРМИНЫ.each do |код, слова|
    it "на языке #{код} называет понятия словами глоссария" do
      текст = I18n.t("terrytrilla_seo.tagline", locale: код, default: "")

      слова.each { |слово| expect(текст).to include(слово) }
    end
  end

  it "не повторяет один и тот же текст на разных языках (контроль)" do
    тексты = ТЕРМИНЫ.keys.map { |код| I18n.t("terrytrilla_seo.tagline", locale: код, default: "") }

    expect(тексты.uniq.size).to eq(тексты.size)
  end

  it "подставляется только на главной" do
    ru = TerrytrillaSeo::SiteText.подзаголовок("ru")

    expect(TerrytrillaSeo::SiteText.заголовок_главной("TerryTrilla Community", "/", "ru")).to eq(
      "TerryTrilla Community - #{ru}",
    )
    внутри = TerrytrillaSeo::SiteText.заголовок_главной("Тема - Раздел", "/t/x/1", "ru")
    expect(внутри).to eq("Тема - Раздел")
  end

  it "не удваивается, если уже стоит (контроль)" do
    ru = TerrytrillaSeo::SiteText.подзаголовок("ru")
    уже = "TerryTrilla Community - #{ru}"

    expect(TerrytrillaSeo::SiteText.заголовок_главной(уже, "/", "ru")).to eq(уже)
  end

  it "с выключенным плагином подзаголовка нет (контроль)" do
    SiteSetting.terrytrilla_seo_enabled = false

    expect(TerrytrillaSeo::SiteText.подзаголовок("ru")).to be_nil
  end
end
