# frozen_string_literal: true

RSpec.describe TerrytrillaSeo do
  it "is registered with Discourse" do
    expect(Discourse.plugins.map(&:name)).to include("terrytrilla-seo")
  end

  it "is disabled until explicitly enabled" do
    expect(SiteSetting.terrytrilla_seo_enabled).to eq(false)
  end

  it "can be enabled" do
    SiteSetting.terrytrilla_seo_enabled = true
    expect(SiteSetting.terrytrilla_seo_enabled).to eq(true)
  end
end
