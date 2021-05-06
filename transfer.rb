require 'google_drive'
load 'lib/google_backup.rb'

def usage
  puts "usage: transfer.rb <source folder id> <dest folder id>"
  abort
end

def env(var)
  ENV[var] || raise("please define #{var}")
end

BACKUP_FROM = ARGV[0] || usage
BACKUP_TO = ARGV[1] || usage

service_account_config = env('GCLOUD_SERVICE_ACCT_CONFIG')

session = GoogleDrive::Session.from_config(service_account_config)

agent = GoogleBackup.new(
  session,
  JSON.parse(File.read(service_account_config))['client_email'],
  remove_permissions: true,
  downgrade_permissions: true,
  allowed_accounts: JSON.parse(File.read(env('DOC_MGR_OK_EMAILS')))
)

puts JSON.pretty_generate(
  agent.backup(BACKUP_FROM, BACKUP_TO)
)
