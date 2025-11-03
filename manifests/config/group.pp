# @summary
#   Manage an OpenVPN Access Server user group via sacli
#
# @param user
#   Group name (e.g., 'vpn-it', 'vpn-default')
# @param superuser
#   Whether to grant admin privileges (default: false)
#
define openvpnas::config::group (
  String[1] $user,
  Boolean   $superuser = false,
) {
  $sacli = '/usr/local/openvpn_as/scripts/sacli'

  # Create the group and declare it
  exec { "openvpnas-create-group-${user}":
    command => "${sacli} --user '${user}' --key 'type' --value 'group' UserPropPut && \
                ${sacli} --user '${user}' --key 'group_declare' --value 'true' UserPropPut",
    # Check for the actual group name in the output
    unless  => "${sacli} --user '${user}' UserPropGet 2>/dev/null | grep -q '\"${user}\"'",
    path    => ['/usr/local/openvpn_as/scripts', '/usr/bin', '/bin'],
    require => Anchor['openvpnas::ready'],
  }

  # Optionally grant admin (superuser) privileges
  if $superuser {
    exec { "openvpnas-grant-admin-${user}":
      command => "${sacli} --user '${user}' --key 'prop_superuser' --value 'true' UserPropPut",
      # Check if the group object contains prop_superuser: true
      unless  => "${sacli} --user '${user}' UserPropGet 2>/dev/null | grep '\"${user}\":' -A3 | grep -q '\"prop_superuser\": \"true\"'",
      path    => ['/usr/local/openvpn_as/scripts', '/usr/bin', '/bin'],
      require => Exec["openvpnas-create-group-${user}"],
    }
  }

  # Build a safe subscription list
  $subscriptions = $superuser ? {
    true    => [ "Exec[openvpnas-create-group-${user}]", "Exec[openvpnas-grant-admin-${user}]" ],
    default => [ "Exec[openvpnas-create-group-${user}]" ],
  }

  # Restart OpenVPN Access Server if group changes occur
  exec { "restart_openvpnas_after_group_${user}":
    command     => "${sacli} start",
    refreshonly => true,
    subscribe   => $subscriptions,
    path        => ['/usr/local/openvpn_as/scripts', '/usr/bin', '/bin'],
  }
}
