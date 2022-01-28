require 'google_drive'
require 'logger'

def usage
  puts "Usage:  #{__FILE__} <Drive folder ID>"
  abort
end

def env(key)
  ENV[key] || abort("Please define #{key} in environment")
end

def handle_file(f)
  obj = { :id => f.id, :title => f.title, :type => f.mime_type }

  begin
    obj[:bad_permissions] = f.acl
    .reject { |a| a.email_address =~ /adjusterpro.com\z/ }
    .map { |a| f.acl.delete(a); pretty_up(a) }
  rescue Google::Apis::ClientError => e
    raise e unless e.message =~ /insufficientFilePermissions/
    obj[:bad_permissions] = "[unauthorized]"
  end

  obj
end

logger = Logger.new(STDERR)
agent = GoogleDrive::Session.from_config(env('GCLOUD_OAUTH_CONFIG'))
folder_ids = [ARGV[0] || abort("Usage: #{__FILE__} <Drive folder ID>")]

i = 0
output = []

loop do
  agent.collection_by_id(folder_ids.shift)
  .files do |f|
    output << handle_file(f)

    if f.mime_type == 'application/vnd.google-apps.folder'
      folder_ids.push(f.id)
      logger.info("added subfolder to list: #{f.title}")
    end

    i += 1
    logger.info("processed #{i} objects") if i % 25 == 0
  end

  break if folder_ids.empty?
rescue Exception => e
  logger.error("Ended prematurely with #{e.class}: #{e.message}")
  break
end

puts JSON.pretty_generate(output)
