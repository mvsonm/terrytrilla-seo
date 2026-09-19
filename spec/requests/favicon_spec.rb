# frozen_string_literal: true

# B18. Значок вкладки для тёмной схемы браузера.
#
# Ядро отдаёт ровно один значок, парной настройки у него нет. Наш тег добавляется
# вторым и включается по `prefers-color-scheme: dark` — там, где браузер это
# понимает (Chrome, Edge, Safari; Firefox — нет, баг 1603885).
RSpec.describe TerrytrillaSeo::Favicon do
  fab!(:светлый_знак) { Fabricate(:image_upload, width: 512, height: 512) }
  fab!(:тёмный_знак) { Fabricate(:image_upload, width: 512, height: 512) }

  let(:браузер) do
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
      "(KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36"
  end

  before do
    SiteSetting.terrytrilla_seo_enabled = true
    # ⚠️ В свежей тестовой установке «/» — страница установщика, и наши теги там
    # не печатаются. На это уже наступал спек главной.
    SiteSetting.has_login_hint = false
    SiteSetting.top_menu = "categories|latest"
  end

  def значки(path = "/")
    get path, headers: { "User-Agent" => браузер }
    expect(response.status).to eq(200)
    Nokogiri
      .HTML5(response.body)
      .css('link[rel="icon"]')
      .map { |t| { href: t["href"], media: t["media"] } }
  end

  it "печатает по значку на каждую схему" do
    SiteSetting.terrytrilla_seo_favicon_light = светлый_знак
    SiteSetting.terrytrilla_seo_favicon_dark = тёмный_знак

    по_схемам = значки.filter_map { |з| [з[:media], з[:href]] if з[:media].present? }.to_h

    expect(по_схемам.keys).to contain_exactly(
      "(prefers-color-scheme: light)",
      "(prefers-color-scheme: dark)",
    )
    expect(по_схемам["(prefers-color-scheme: light)"]).to include(светлый_знак.sha1[0, 8])
    expect(по_схемам["(prefers-color-scheme: dark)"]).to include(тёмный_знак.sha1[0, 8])
  end

  it "печатает только заданное: одна настройка — один тег (контроль)" do
    SiteSetting.terrytrilla_seo_favicon_light = светлый_знак

    expect(значки.count { |з| з[:media].present? }).to eq(1)
  end

  it "оставляет базовый значок без условия — он для поиска и для Firefox (контроль)" do
    SiteSetting.favicon = Fabricate(:image_upload, width: 512, height: 512)
    SiteSetting.terrytrilla_seo_favicon_light = светлый_знак

    без_условия = значки.reject { |з| з[:media].present? }

    expect(без_условия).not_to be_empty
  end

  it "молчит, пока значок не задан (контроль)" do
    SiteSetting.terrytrilla_seo_favicon_light = ""
    SiteSetting.terrytrilla_seo_favicon_dark = ""

    expect(значки.count { |з| з[:media].present? }).to eq(0)
  end

  it "молчит с выключенным плагином (контроль)" do
    SiteSetting.terrytrilla_seo_favicon_light = светлый_знак
    SiteSetting.terrytrilla_seo_enabled = false

    expect(значки.count { |з| з[:media].present? }).to eq(0)
  end
end
