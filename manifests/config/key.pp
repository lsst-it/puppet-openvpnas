# @summary Manage a single OpenVPN AS configuration key via sacli
#
# @param key
#   The configuration key (e.g., 'vpn.server.daemon.enable')
# @param value
#   Value to set. Converted to string for sacli.
define openvpnas::config::key (
  String[1] $key,
  Variant[String, Integer, Boolean] $value,
) {
  $string_value = $value ? {
    Boolean => $value ? {
      true  => 'true',
      false => 'false',
    },
    default => String($value),
  }

  # Build the require array based on the key
  $base_require = [Anchor['openvpnas::ready']]

  $full_require = $key ? {
    'auth.module.type' => $base_require + [
      Openvpnas::Config::Key['auth.ldap.0.server.0.host'],
      Openvpnas::Config::Key['auth.ldap.0.server.1.host'],
      Openvpnas::Config::Key['auth.ldap.0.bind_dn'],
      Openvpnas::Config::Key['auth.ldap.0.bind_pw'],
      Openvpnas::Config::Key['auth.ldap.0.enable'],
      Openvpnas::Config::Key['auth.ldap.0.users_base_dn'],
      Openvpnas::Config::Key['auth.ldap.0.uname_attr'],
    ],
    default => $base_require,
  }

  exec { "openvpnas-set-${name}":
    path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    command => "/usr/local/openvpn_as/scripts/sacli -k ${key} -v '${string_value}' ConfigPut",
    unless  => "/bin/bash -c '/usr/local/openvpn_as/scripts/sacli ConfigQuery 2>/dev/null | /bin/grep -q \"\\\"${key}\\\": \\\"${string_value}\\\"\"'",
    require => $full_require,
  }

  # Apply only if the key changed
  exec { "openvpnas-apply-${name}":
    path        => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    command     => '/usr/local/openvpn_as/scripts/sacli start',
    refreshonly => true,
    subscribe   => Exec["openvpnas-set-${name}"],
  }
}
