# created the role_helpers.rb module to centralize and reuse role-based access control (RBAC) logic across multiple entities and API endpoints
module RoleHelpers
  def self.is_staff?(my_role)
    [Role.tutor_id, Role.convenor_id, Role.admin_id, Role.auditor_id].include?(my_role.id) unless my_role.nil?
  end

  def self.can_read_unit_config?(my_role)
    [Role.convenor_id, Role.admin_id, Role.auditor_id].include?(my_role.id) unless my_role.nil?
  end
end
