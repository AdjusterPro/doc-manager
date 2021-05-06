require 'google_drive'
require 'logger'
load 'lib/google_backup.rb'

logger = Logger.new(STDERR)

def usage
  raise("Usage: ad-hoc.rb <JSON output of find-bad-permissions.rb>")
end

agent = GoogleBackup.new(
  GoogleDrive::Session.from_config(env('GCLOUD_CONFIG'))
)

output = []
JSON.parse(File.read(ARGV[0] || usage))
.reject { |f| f['bad_permissions'] == '[unauthorized]' }
.select { |f| f['bad_permissions'].any? { |a| a['type'] == 'anyone' && a['role'] == 'writer' } }
.each do |f|
  begin
    f.merge!({
      :good_permissions => agent.downgrade_anyone_access(f['id'])
    })
  rescue Exception => e
    STDERR.puts("caught #{e.class}: #{e.message} for file #{f['id']}")
  end
  output << f
end

puts JSON.pretty_generate(output)


