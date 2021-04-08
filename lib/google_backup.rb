class GoogleBackup
  def initialize(session, options = {})
    @g = session
    @logger = options[:logger] || Logger.new(STDERR)
    @user_to_remove = options[:user_to_remove] || 'nobody@example.com'
    @dont_remove = options[:dont_remove].downcase || 'nobody@example.com'
    @remove_permissions = options[:remove_permissions] || false
  end

  def backup(from_id, to_id)
    copied = []
    from_folder = @g.collection_by_id(from_id)
    to_folder = @g.collection_by_id(to_id)

    from_folder.files do |file|
      if file.mime_type != 'application/vnd.google-apps.folder'
        file.copy(file.title, {parents: [to_folder.id]})
      else
        new_folder = to_folder.subfolder_by_name(file.title) || to_folder.create_subfolder(file.title)
        @logger.info("created/found folder '#{new_folder.title}' (#{new_folder.id}) as subfolder of '#{to_folder.title}' (#{to_folder.id})")
        copied += self.backup(file.id, new_folder.id)
      end
      removed = remove_permissions(file)
      copied << { :type => file.mime_type, :name => file.title, :id => file.id, :removed => removed }
    end
    copied
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


  def remove_permissions(file)
    return [] unless @remove_permissions
    file.acl.select { |acl| acl.role != "owner" && acl.email_address.downcase != @dont_remove }
    .map do |acl|
      file.acl.delete(acl)
      acl.email_address
    rescue => e
      @logger.error("#{e.class} raised for #{file.id} by acl.delete(#{acl.email_address}): #{e.message}")
    end
  rescue => e
    @logger.error("#{e.class} raised for #{file.id} by remove_permissions generally: #{e.message}")
    []
  end

  def interesting_acls(file, new_folder)
    file.acl.reject do |acl|
      acl.type != 'user' ||
      (acl.email_address && acl.email_address.downcase == @user_to_remove) ||
      new_folder.acl.any? { |n_acl| acl.email_address && n_acl.email_address && acl.email_address.downcase == n_acl.email_address.downcase }
    end
  end

end

def remove_user(file, user_to_remove)
  file.acl.each do |acl|
    next unless acl.email_address == user_to_remove
    file.acl.delete(acl)
  end
end

