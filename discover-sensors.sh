#!/bin/bash

shopt -s nullglob

hwmon_root="${OMARCHY_SYSMON_HWMON_ROOT:-/sys/class/hwmon}"

for hwmon in "$hwmon_root"/hwmon*; do
  [[ -r "$hwmon/name" ]] || continue
  IFS= read -r name <"$hwmon/name"
  [[ "$name" == "coretemp" || "$name" == "k10temp" || "$name" == "zenpower" ]] || continue

  selected=""
  for label_file in "$hwmon"/temp*_label; do
    IFS= read -r label <"$label_file"
    if [[ "$label" == "Package id 0" || "$label" == "Tctl" ]]; then
      candidate="${label_file%_label}_input"
      [[ -r "$candidate" ]] && selected="$candidate"
      break
    fi
  done

  if [[ -z "$selected" ]]; then
    for candidate in "$hwmon"/temp*_input; do
      [[ -r "$candidate" ]] && selected="$candidate" && break
    done
  fi

  if [[ -n "$selected" ]]; then
    printf 'cpu_temp\t%s\n' "$selected"
    break
  fi
done

for hwmon in "$hwmon_root"/hwmon*; do
  [[ -r "$hwmon/name" ]] || continue
  IFS= read -r name <"$hwmon/name"
  [[ "$name" == "macsmc_hwmon" ]] || continue

  for input in "$hwmon"/temp*_input; do
    [[ -r "$input" ]] || continue
    label=""
    label_file="${input%_input}_label"
    if [[ -r "$label_file" ]]; then
      IFS= read -r label <"$label_file"
      label="${label#"${label%%[![:space:]]*}"}"
      label="${label%"${label##*[![:space:]]}"}"
    fi
    if [[ -z "$label" ]]; then
      label="Temperature ${input##*temp}"
      label="${label%_input}"
    fi
    printf 'platform_sensor\t%s\ttemp\t%s\n' "$input" "$label"
  done

  for input in "$hwmon"/power*_input; do
    [[ -r "$input" ]] || continue
    label=""
    label_file="${input%_input}_label"
    if [[ -r "$label_file" ]]; then
      IFS= read -r label <"$label_file"
      label="${label#"${label%%[![:space:]]*}"}"
      label="${label%"${label##*[![:space:]]}"}"
    fi
    if [[ -z "$label" ]]; then
      label="Power ${input##*power}"
      label="${label%_input}"
    fi
    printf 'platform_sensor\t%s\tpower\t%s\n' "$input" "$label"
  done

  for input in "$hwmon"/fan*_input; do
    [[ -r "$input" ]] || continue
    label=""
    label_file="${input%_input}_label"
    if [[ -r "$label_file" ]]; then
      IFS= read -r label <"$label_file"
      label="${label#"${label%%[![:space:]]*}"}"
      label="${label%"${label##*[![:space:]]}"}"
    fi
    fan_index="${input##*fan}"
    fan_index="${fan_index%_input}"
    [[ -z "$label" ]] && label="Fan $fan_index"
    min=""
    [[ -r "${input%_input}_min" ]] && IFS= read -r min <"${input%_input}_min"
    max=""
    [[ -r "${input%_input}_max" ]] && IFS= read -r max <"${input%_input}_max"
    printf 'fan\t%s\t%s\t%s\t%s\t%s\n' "$input" "$fan_index" "$label" "${min:-0}" "${max:-0}"
  done

  break
done

for block_path in /sys/class/block/*; do
  device="${block_path##*/}"
  [[ -e "$block_path/partition" ]] && continue
  [[ -e "$block_path/device" ]] || continue
  case "$device" in
    loop*|ram*|zram*|fd*|sr*) continue ;;
  esac
  printf 'disk\t%s\n' "$device"
done

drm_root="${OMARCHY_SYSMON_DRM_ROOT:-/sys/class/drm}"

best_rank=-1
best_vram=-1
gpu_busy=""
gpu_temp=""
gpu_vram_used=""
gpu_vram_total=""

for card in "$drm_root"/card*; do
  name="${card##*/}"
  [[ "$name" =~ ^card[0-9]+$ ]] || continue
  device="$card/device"
  [[ -d "$device" ]] || continue

  busy=""
  [[ -r "$device/gpu_busy_percent" ]] && busy="$device/gpu_busy_percent"

  temp=""
  for hwmon in "$device"/hwmon/hwmon*; do
    if [[ -r "$hwmon/temp1_input" ]]; then
      temp="$hwmon/temp1_input"
    elif [[ -r "$hwmon/temp2_input" ]]; then
      temp="$hwmon/temp2_input"
    else
      continue
    fi
    break
  done

  [[ -n "$busy" || -n "$temp" ]] || continue

  vram=0
  [[ -r "$device/mem_info_vram_total" ]] && IFS= read -r vram <"$device/mem_info_vram_total"
  [[ "$vram" =~ ^[0-9]+$ ]] || vram=0

  if [[ -n "$busy" ]]; then rank=2; else rank=1; fi
  if (( rank > best_rank )) || { (( rank == best_rank )) && (( vram > best_vram )); }; then
    best_rank=$rank
    best_vram=$vram
    gpu_busy="$busy"
    gpu_temp="$temp"
    gpu_vram_used=""
    gpu_vram_total=""
    [[ -r "$device/mem_info_vram_used" ]] && gpu_vram_used="$device/mem_info_vram_used"
    [[ -r "$device/mem_info_vram_total" ]] && gpu_vram_total="$device/mem_info_vram_total"
  fi
done

[[ -n "$gpu_busy" ]] && printf 'gpu_busy\t%s\n' "$gpu_busy"
[[ -n "$gpu_temp" ]] && printf 'gpu_temp\t%s\n' "$gpu_temp"
[[ -n "$gpu_vram_used" ]] && printf 'gpu_vram_used\t%s\n' "$gpu_vram_used"
[[ -n "$gpu_vram_total" ]] && printf 'gpu_vram_total\t%s\n' "$gpu_vram_total"
exit 0
