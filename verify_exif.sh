#!/usr/bin/env bash

set -euo pipefail

input_path=""
checked_files=0
files_with_exif=0
files_without_exif=0
failed_files=0

show_usage() {
    cat <<USAGE
Usage: $0 --input input_path

Options:
  --input path   Image file or folder with image files to verify.
  -h, --help     Show this help message.
USAGE
}

fail() {
    echo "Error: $1" >&2
    exit 1
}

parse_arguments() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --input)
                [ "$#" -ge 2 ] || fail "--input requires a file or directory."
                input_path="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                fail "Unknown argument: $1"
                ;;
        esac
    done
}

validate_arguments() {
    [ -n "$input_path" ] || fail "--input is required."
    [ -e "$input_path" ] || fail "Input path does not exist: $input_path"
    [ -f "$input_path" ] || [ -d "$input_path" ] || fail "Input path must be a file or directory: $input_path"
}

require_command() {
    command -v "$1" > /dev/null 2>&1 || fail "Required command is missing: $1"
}

collect_image_files() {
    local -n target_files=$1

    if [ -f "$input_path" ]; then
        target_files=("$input_path")
        return
    fi

    mapfile -d '' -t target_files < <(
        find "$input_path" -maxdepth 1 -type f \( \
            -iname '*.jpg' -o \
            -iname '*.jpeg' -o \
            -iname '*.png' -o \
            -iname '*.webp' -o \
            -iname '*.tif' -o \
            -iname '*.tiff' -o \
            -iname '*.heic' -o \
            -iname '*.heif' -o \
            -iname '*.avif' \
        \) -print0 | sort -z
    )
}

count_lines() {
    local value="$1"

    if [ -z "$value" ]; then
        printf "0"
        return
    fi

    printf "%s\n" "$value" | wc -l
}

verify_exif() {
    local image_file="$1"
    local current_file="$2"
    local total_files="$3"
    local exif_output tag_count

    checked_files=$((checked_files + 1))

    if ! exif_output=$(exiftool -EXIF:all -s "$image_file" 2>&1); then
        failed_files=$((failed_files + 1))
        printf "[%d/%d] %s: error while reading EXIF\n%s\n" \
            "$current_file" \
            "$total_files" \
            "$(basename "$image_file")" \
            "$exif_output" >&2
        return
    fi

    if [ -n "$exif_output" ]; then
        files_with_exif=$((files_with_exif + 1))
        tag_count="$(count_lines "$exif_output")"
        printf "[%d/%d] %s: has EXIF (%d tag(s))\n" \
            "$current_file" \
            "$total_files" \
            "$(basename "$image_file")" \
            "$tag_count"
        return
    fi

    files_without_exif=$((files_without_exif + 1))
    printf "[%d/%d] %s: missing EXIF\n" \
        "$current_file" \
        "$total_files" \
        "$(basename "$image_file")"
}

main() {
    if [ "$#" -eq 0 ]; then
        show_usage
        fail "--input is required."
    fi

    parse_arguments "$@"
    validate_arguments
    require_command exiftool

    local -a image_files=()
    collect_image_files image_files

    local total_files="${#image_files[@]}"
    [ "$total_files" -gt 0 ] || fail "No supported image files found in: $input_path"

    local index=0
    local image_file

    for image_file in "${image_files[@]}"; do
        index=$((index + 1))
        verify_exif "$image_file" "$index" "$total_files"
    done

    printf "Summary: %d checked, %d with EXIF, %d missing EXIF, %d failed.\n" \
        "$checked_files" \
        "$files_with_exif" \
        "$files_without_exif" \
        "$failed_files"

    if [ "$files_without_exif" -gt 0 ] || [ "$failed_files" -gt 0 ]; then
        exit 1
    fi
}

main "$@"
