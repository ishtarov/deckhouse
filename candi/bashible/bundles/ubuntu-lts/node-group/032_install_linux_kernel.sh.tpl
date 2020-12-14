{{- $manage_kernel := true }}
{{- if hasKey .nodeGroup "operatingSystem" }}
  {{- if not .nodeGroup.operatingSystem.manageKernel }}
    {{- $manage_kernel = false }}
  {{- end }}
{{- end }}

{{- if $manage_kernel }}
{{- if ne .runType "ImageBuilding" }}
bb-event-on 'bb-package-installed' 'post-install'
post-install() {
  bb-log-info "Setting reboot flag due to kernel was updated"
  bb-flag-set reboot
}
{{- end }}

metapackages="$(
  dpkg --get-selections | grep -E '^(linux|linux-image|linux-headers)-(aws|azure|gcp|generic|gke|kvm|lowlatency|oem|oracle|virtual)\s+(install|hold)' | awk '{print $1}' || true
)"
if [ -n "$metapackages" ]; then
  bb-apt-remove $metapackages
fi

if bb-is-ubuntu-version? 20.04 ; then
  desired_version="5.4.0-54-generic"
  allowed_versions_pattern=""
elif bb-is-ubuntu-version? 18.04 ; then
  desired_version="5.3.0-51-generic"
  allowed_versions_pattern=""
elif bb-is-ubuntu-version? 16.04 ; then
  desired_version="4.18.0-20-generic"
  allowed_versions_pattern=""
else
  bb-log-error "Unsupported Ubuntu version"
  exit 1
fi

if [ -f /var/lib/bashible/kernel_version_config_by_cloud_provider ]; then
  source /var/lib/bashible/kernel_version_config_by_cloud_provider
fi

should_install_kernel=true
version_in_use="$(uname -r)"
if test -n "$allowed_versions_pattern" && grep -Eq "$allowed_versions_pattern" <<< "$version_in_use"; then
  should_install_kernel=false
fi

if [[ "$version_in_use" == "$desired_version" ]]; then
  should_install_kernel=false
fi

# Example: "5.4.0-54-generic" -> "^linux-[a-z0-9.-]+(5.4.0-54|5.4.0-54-generic)$"
desired_version_pattern="$(echo "$desired_version" | sed -r 's/([0-9\.-]+)-([^0-9]+)$/^linux-[a-z0-9\.-]+(\1|\1-\2)$/')"
version_in_use_pattern="$(echo "$version_in_use" | sed -r 's/([0-9\.-]+)-([^0-9]+)$/^linux-[a-z0-9\.-]+(\1|\1-\2)$/')"

if [[ "$should_install_kernel" == true ]]; then
  bb-deckhouse-get-disruptive-update-approval
  if bb-is-ubuntu-version? 20.04 ; then
    bb-apt-install "linux-image-${desired_version}" "linux-modules-${desired_version}" "linux-modules-extra-${desired_version}" "linux-headers-${desired_version}"
  elif bb-is-ubuntu-version? 18.04 ; then
    bb-apt-install "linux-image-${desired_version}" "linux-modules-${desired_version}" "linux-modules-extra-${desired_version}" "linux-headers-${desired_version}"
  elif bb-is-ubuntu-version? 16.04 ; then
    bb-apt-install "linux-image-unsigned-${desired_version}" "linux-modules-${desired_version}" "linux-modules-extra-${desired_version}" "linux-headers-${desired_version}" "linux-headers-${desired_version}"
  fi
  packages_to_remove="$(
    dpkg --get-selections | grep -E '^linux-.*\s(install|hold)$' | awk '{print $1}' | grep -Ev "$desired_version_pattern" | grep -Ev 'linux-[^0-9]+$' || true
  )"
else
  packages_to_remove="$(
    dpkg --get-selections | grep -E '^linux-.*\s(install|hold)$' | awk '{print $1}' | grep -Ev "$version_in_use_pattern" | grep -Ev 'linux-[^0-9]+$' || true
  )"
fi

if [ -n "$packages_to_remove" ]; then
  bb-apt-remove $packages_to_remove
fi

rm -f /var/lib/bashible/kernel_version_config_by_cloud_provider
{{- end }}
