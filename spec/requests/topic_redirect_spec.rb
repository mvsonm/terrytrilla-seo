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

  it "drops ?tl when the plugin is disabled — core behaviour (control)" do
    SiteSetting.terrytrilla_seo_enabled = false
    get "/t/wrong-slug/#{topic.id}?tl=ja"
    expect(response).to have_http_status(:moved_permanently)
    expect(response.location).not_to include("tl=ja")
  end
end
