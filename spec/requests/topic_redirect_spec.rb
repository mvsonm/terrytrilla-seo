# frozen_string_literal: true

RSpec.describe TopicsController do
  fab!(:admin)
  fab!(:topic) { Fabricate(:topic, title: "Оглавление базы знаний") }

  before do
    SiteSetting.slug_generation_method = "ascii"
    SiteSetting.terrytrilla_seo_enabled = true
    TopicLocalization.create!(
      topic: topic,
      locale: "en",
      title: "Knowledge Base Table of Contents",
      fancy_title: "Knowledge Base Table of Contents",
      localizer_user_id: admin.id,
    )
    topic.reload
  end

  it "redirects the old placeholder URL to the English slug" do
    get "/t/topic/#{topic.id}"
    expect(response).to have_http_status(:moved_permanently)
    expect(response.location).to end_with("/t/knowledge-base-table-of-contents/#{topic.id}")
  end

  it "keeps ?tl on the redirect" do
    get "/t/topic/#{topic.id}?tl=ja"
    expect(response).to have_http_status(:moved_permanently)
    expect(response.location).to end_with("/t/knowledge-base-table-of-contents/#{topic.id}?tl=ja")
  end

  # Before 2026.11 core dropped ?tl on this redirect and the plugin's modifier put it back. Core keeps
  # it itself now, so the modifier only guards against a regression; the control states core's rule.
  it "keeps ?tl with the plugin disabled too — core behaviour since 2026.11 (control)" do
    SiteSetting.terrytrilla_seo_enabled = false
    get "/t/wrong-slug/#{topic.id}?tl=ja"
    expect(response).to have_http_status(:moved_permanently)
    expect(response.location).to end_with("/t/knowledge-base-table-of-contents/#{topic.id}?tl=ja")
  end
end
