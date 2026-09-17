# frozen_string_literal: true

# name: terrytrilla-seo
# about: Search and link-preview layer for TerryTrilla Community: hreflang only for translated languages, indexing rules, structured data, language of URLs for crawlers, link-preview images.
# version: 0.1.0
# authors: TerryTrilla
# url: https://github.com/mvsonm/terrytrilla-seo
# required_version: 2026.9.0

enabled_site_setting :terrytrilla_seo_enabled

module ::TerrytrillaSeo
  PLUGIN_NAME = "terrytrilla-seo"
end

after_initialize do
  # Every change to core behaviour is listed in README.md («Core touch points»),
  # so that a Discourse upgrade can be checked against that list.
end
