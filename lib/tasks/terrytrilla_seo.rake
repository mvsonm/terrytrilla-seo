# frozen_string_literal: true

desc "B8: recompute slugs of existing topics from their English titles (no-op when frozen)"
task "terrytrilla_seo:recompute_slugs" => :environment do
  unless TerrytrillaSeo::TopicSlug.active?
    puts "skipped: plugin disabled or slugs frozen"
    next
  end
  changed = TerrytrillaSeo::TopicSlug.recompute_all!
  changed.each { |id, old, new| puts "t/#{id}: #{old} → #{new}" }
  puts "changed: #{changed.size}"
end
