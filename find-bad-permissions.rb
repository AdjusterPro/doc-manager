require 'google_drive'
require 'logger'
load 'lib/google_backup.rb'

logger = Logger.new(STDERR)

def usage
  puts "usage: transfer.rb <source folder id> <dest folder id>"
  abort
end

def env(var)
  ENV[var] || raise("please define #{var}")
end

def email_ok?(email)
  ok_config ||= JSON.parse(File.read(env('DOC_MGR_OK_EMAILS')))

  email = (email || '').downcase
  ok_config['domains'].any? { |d| email =~ /@#{d}\z/ } || ok_config['addresses'].include?(email)
end

def pretty_up(acl)
  {
    :role => acl.role,
    :email_address => acl.email_address,
    :type => acl.type,
    :raw => acl.inspect
  }
end


agent = GoogleBackup.new(
  GoogleDrive::Session.from_config(env('GCLOUD_SERVICE_ACCT_CONFIG'))
)

i = 0
output = agent.g.files.map do |f|
  obj = { :id => f.id, :title => f.title }
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
  obj
end

puts JSON.pretty_generate(output)
