# @summary Manage OpenVPN Access Server (openvpnas) installation and basic config
#
# @param manage_repo
#   Whether to manage the OpenVPN Access Server yum repo.
# @param yumrepo_baseurl
#   Base URL of the OpenVPN Access Server repo.
# @param yumrepo_name
#   Human-friendly name for the repo.
# @param yumrepo_id
#   Repo ID.
# @param gpgkey_url
#   URL to the GPG key for the repo.
# @param package_name
#   Name of the package to install (default: openvpn-as).
# @param version
#   Package version to install. If undef, installs latest.
# @param versionlock_enable
#   Enable versionlock for the package.
# @param versionlock_release
#   Release string used by yum::versionlock when locking a specific version.
# @param manage_service
#   Whether to manage and enable the service.
# @param service_name
#   Service resource title/name (default: openvpnas).
# @param manage_web_certs
#   If true, create symlinks for web UI TLS certs to Let's Encrypt paths.
# @param cert_source_path
#   Where the Let's Encrypt certs live (cert.pem, privkey.pem, fullchain.pem).
# @param config
#   Optional hash of OpenVPN AS config keys to apply via sacli.
class openvpnas (
  Boolean $manage_repo           = false,
  String  $yumrepo_baseurl       = 'http://as-repository.openvpn.net/as/yum/rhel9/',
  String  $yumrepo_name          = 'openvpn-access-server',
  String  $yumrepo_id            = 'as-repo-rhel9',
  String  $gpgkey_url            = 'https://as-repository.openvpn.net/as-repo-public.gpg',
  String  $package_name          = 'openvpn-as',
  Optional[String] $version      = undef,
  Boolean $versionlock_enable    = false,
  String  $versionlock_release   = '1.el9',
  Boolean $manage_service        = true,
  String  $service_name          = 'openvpnas',
  Boolean $manage_web_certs      = false,
  String  $cert_source_path      = "/etc/letsencrypt/live/${facts['networking']['fqdn']}",
  Optional[Hash] $config         = undef,
) {

  $sacli = '/usr/local/openvpn_as/scripts/sacli'

  # ensure package is installed before calling sacli
  Package[$package_name] -> Service[$service_name]

  # Optional repo management
  if $manage_repo {
    yumrepo { $yumrepo_id:
      ensure   => present,
      name     => $yumrepo_name,
      descr    => $yumrepo_name,
      baseurl  => $yumrepo_baseurl,
      gpgkey   => $gpgkey_url,
      gpgcheck => 1,
      enabled  => 1,
    }
  }

  # Optional versionlock
  if $versionlock_enable {
    include yum::plugin::versionlock
    if $version == undef {
      fail('openvpnas::versionlock_enable requires a specific version')
    }
  }

  # Compute resource attributes to avoid selectors inside blocks
  $pkg_ensure = $version ? {
    undef   => present,
    default => $version,
  }

  $pkg_require = $manage_repo ? {
    true    => Yumrepo[$yumrepo_id],
    default => undef,
  }

  $pkg_notify = $versionlock_enable ? {
    true    => Yum::Versionlock[$package_name],
    default => undef,
  }

  package { $package_name:
    ensure  => $pkg_ensure,
    require => $pkg_require,
    notify  => $pkg_notify,
  }

  if $versionlock_enable {
    yum::versionlock { $package_name:
      ensure  => present,
      version => $version,
      release => $versionlock_release,
      arch    => 'x86_64',
    }
  }

  # Manage web cert symlinks if requested
  if $manage_web_certs {
    file { '/usr/local/openvpn_as/etc/web-ssl/server.crt':
      ensure  => link,
      target  => "${cert_source_path}/cert.pem",
      force   => true,
      require => Package[$package_name],
      notify  => Service[$service_name],
    }

    file { '/usr/local/openvpn_as/etc/web-ssl/server.key':
      ensure  => link,
      target  => "${cert_source_path}/privkey.pem",
      force   => true,
      require => Package[$package_name],
      notify  => Service[$service_name],
    }

    file { '/usr/local/openvpn_as/etc/web-ssl/ca.crt':
      ensure  => link,
      target  => "${cert_source_path}/fullchain.pem",
      force   => true,
      require => Package[$package_name],
      notify  => Service[$service_name],
    }
  }

  if $manage_service {
    service { $service_name:
      ensure  => running,
      enable  => true,
      require => Package[$package_name],
    }
  }

  # Wait for OpenVPN AS to be fully ready (ALWAYS, not just when $config is set)
  exec { 'wait_for_openvpnas_socket':
    command => '/bin/bash -c "for i in {1..30}; do [ -S /usr/local/openvpn_as/etc/sock/sagent ] && exit 0; sleep 2; done; exit 1"',
    unless  => '/usr/bin/test -S /usr/local/openvpn_as/etc/sock/sagent',
    require => Service[$service_name],
    timeout => 120,
    path    => ['/bin', '/usr/bin'],
  }

  # Anchor to ensure service is ready before any configuration
  anchor { 'openvpnas::ready':
    require => Exec['wait_for_openvpnas_socket'],
  }

  # Apply config keys if provided via the config parameter
  if $config and !empty($config) {
    $config.each |$k, $v| {
      openvpnas::config::key { $k:
        key   => $k,
        value => $v,
      }
    }
  }
}
