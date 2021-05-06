require 'google_drive'
require 'logger'
load 'lib/google_backup.rb'

logger = Logger.new(STDERR)

def usage
  puts "usage: transfer.rb <source folder id> <dest folder id>"
  abort
end



agent = GoogleBackup.new(
  GoogleDrive::Session.from_config(env('GCLOUD_CONFIG'))
)

i = 0
begin
  output = []
  agent.g.files do |f|
    obj = { :id => f.id, :title => f.title, :type => f.mime_type }
    begin
      obj[:bad_permissions] = f.acl
      .reject { |a| email_ok?(a.email_address) }
      .map { |a| pretty_up(a) }
    rescue Google::Apis::ClientError => e
      raise e unless e.message =~ /insufficientFilePermissions/
      obj[:bad_permissions] = "[unauthorized]"
    end
    i += 1
    logger.info("processed #{i} files") if i % 25 == 0
    output << obj
  end
rescue Exception => e
  logger.error("Ended prematurely with #{e.class}: #{e.message}")
end

puts JSON.pretty_generate(output)
