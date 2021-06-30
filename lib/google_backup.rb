def env(var)
  ENV[var] || raise("please define #{var}")
end

def pretty_up(acl)
  {
    :role => acl.role,
    :email_address => acl.email_address,
    :type => acl.type,
    :raw => acl.inspect
  }
end


class GoogleBackup
  attr_reader :g

  def initialize(session, myself, options = {})
#
# 'session' should be the return value of GoogleDrive::Session.from_config(), which
# in turn accepts a path to a JSON file from Google's developer
# console at console.cloud.google.com.
#
# The JSON file can either be:
#
#  (A) the full key info from a Service Account, in which 
#      case the script will gain access to whatever has been explicitly shared
#      with that Service Account -- or,
#
#  (B) basic auth info from a "Desktop"-type Oauth 2.0 Client ID,in which case
#      the script will give you the opportunity to authenticate to Google using any
#      Google Account that you control (and you will need to explicitly 
#      grant the Client ID's requested permissions, etc.)
#
#      N.B.: After you have authorized a Client ID, the script will save a
#      refresh token into the client ID's JSON config file. Eventually that
#      refresh token will expire and you'll get a non-helpful error message. The
#      fix is just to remove the refresh_token property from the JSON object.
#
    @g = session
    @logger = options[:logger] || Logger.new(STDERR)
    @user_to_remove = (options[:user_to_remove] || 'nobody@example.com').downcase
    @myself = myself.downcase
    @remove_permissions = options[:remove_permissions] || false
    @downgrade_permissions = options[:downgrade_permissions] || false
    @allowed_accounts ||= options[:allowed_accounts] || raise("GoogleBackup needs list of accounts allowed to retained access")
  end

  def backup(from_id, to_id)
    copied = []
    from_folder = @g.collection_by_id(from_id)
    to_folder = @g.collection_by_id(to_id)

    from_folder.files do |file|
      if file.mime_type != 'application/vnd.google-apps.folder'
        new_file = file.copy(file.title, {parents: [to_folder.id]})
      else
        new_folder = to_folder.subfolder_by_name(file.title) || to_folder.create_subfolder(file.title)
        @logger.info("created/found folder '#{new_folder.title}' (#{new_folder.id}) as subfolder of '#{to_folder.title}' (#{to_folder.id})")
        copied += self.backup(file.id, new_folder.id)
      end
      copied << {
        :type => file.mime_type, :name => file.title,
        :original_folder => from_folder.human_url,
        :original_id => file.id, :original_link => file.human_url, :original_owner => owner(file),
        :new_folder => to_folder.human_url,
        :new_id => (new_file || new_folder).id, :new_link => (new_file || new_folder).human_url,
        :downgraded => downgrade_permissions(file), :removed => remove_permissions(file)
      }
    end
    copied << {
      :type => from_folder.mime_type, :name => from_folder.title,
      :original_folder => nil,
      :original_id => from_folder.id, :original_link => from_folder.human_url, :original_owner => owner(from_folder),
      :new_folder => nil,
      :new_id => to_folder.id, :new_link => to_folder.human_url,
      :downgraded => downgrade_permissions(from_folder), :removed => remove_permissions(from_folder)
    }
    copied
  end

  def owner(file)
    acl = file.acl.find { |a| a.role=='owner' }
    { :owner => acl.email_address || acl.type, :raw => acl.inspect }
  end

  def remove_permissions(file)
    return [] unless @remove_permissions
    file.acl.reject { |acl| acl.role == "owner" || acl.email_address == @myself || retain_access?(acl.email_address) }
    .map do |acl|
      file.acl.delete(acl)
      { :removed => acl.email_address || acl.type, :raw => acl.inspect }
    rescue => e
      @logger.error("#{e.class} raised for #{file.id} by acl.delete(#{acl.email_address}): #{e.message}")
      { :couldnt_remove => acl.email_address || acl.type, :raw => acl.inspect }
    end
  rescue => e
    @logger.error("#{e.class} raised for #{file.id} by remove_permissions generally: #{e.message}")
    []
  end

  def downgrade_permissions(file)
    return [] unless @downgrade_permissions
    file.acl.reject { |acl| acl.role == 'owner' || acl.role == 'reader' || acl.email_address.downcase == @myself }
    .map do |acl|
      file.acl.delete(acl)
      file.acl.push({type: acl.type, email_address: acl.email_address, role: 'reader'})
      { :downgraded => acl.email_address || acl.type, :raw => acl.inspect }
    rescue => e
      @logger.error("#{e.class} raised for #{file.id} by acl.delete(#{acl.email_address}): #{e.message}")
      { :couldnt_downgrade => acl.email_address || acl.type, :raw => acl.inspect }
    end
  rescue => e
    @logger.error("#{e.class} raised for #{file.id} by remove_permissions generally: #{e.message}")
    []
  end

  def downgrade_anyone_access(file_id)
    file = g.file_by_id(file_id)

    acl = file.acl
    .find { |a| a.type == 'anyone' && a.role == 'writer' }

    new_acl = nil
    unless acl.nil?
      file.acl.delete(acl)
      new_acl = {type: acl.type, email_address: acl.email_address, role: 'reader'}
      file.acl.push(new_acl)
    end
    file.acl.map { |a| pretty_up(a) }
  end

  def retain_access?(email)
    email = (email || '').downcase
    @allowed_accounts['domains'].any? { |d| email =~ /@#{d}\z/ } || @allowed_accounts['addresses'].include?(email)
  end

#  def replicate_permissions
#  TODO need arguments etc
#      @logger.debug(new_folder.acl.inspect)
#      self.interesting_acls(file, new_folder)
#      .each do |acl|
#        @logger.debug("will add #{acl.inspect} to #{new_folder.title} (#{new_folder.id})")
#        new_folder.acl.push(
#          { type: acl.type, email_address: acl.email_address, role: acl.role },
#          { send_notification_email: false }
#        )
#      end
#   end
#
#  def interesting_acls(file, new_folder)
#    file.acl.reject do |acl|
#      acl.type != 'user' ||
#      (acl.email_address && acl.email_address.downcase == @user_to_remove) ||
#     new_folder.acl.any? { |n_acl| acl.email_address && n_acl.email_address && acl.email_address.downcase == n_acl.email_address.downcase }
#    end
#  end


end

def remove_user(file, user_to_remove)
  file.acl.each do |acl|
    next unless acl.email_address == user_to_remove
    file.acl.delete(acl)
  end
end

