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

  exec { "openvpnas-set-${name}":
    path    => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    command => "/usr/local/openvpn_as/scripts/sacli -k ${key} -v '${string_value}' ConfigPut",
    unless  => "/usr/local/openvpn_as/scripts/sacli -k ${key} ConfigQuery | grep -q -- '${string_value}'",
    require => Exec['wait_for_openvpnas_ready'],
  }

  exec { "openvpnas-apply-${name}":
    path        => ['/bin', '/usr/bin', '/sbin', '/usr/sbin'],
    command     => '/usr/local/openvpn_as/scripts/sacli start',
    refreshonly => true,
    subscribe   => Exec["openvpnas-set-${name}"],
  }
}
