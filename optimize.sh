#!/usr/bin/env bash

set -euo pipefail

readonly DEFAULT_PHOTO_QUALITY=80
readonly DEFAULT_VIDEO_CRF=32
readonly METADATA_COPY_ATTEMPTS=5
readonly METADATA_COPY_RETRY_DELAY_SECONDS=1

input_path=""
input_list_path=""
output_directory=""
photo_quality="$DEFAULT_PHOTO_QUALITY"
video_crf="$DEFAULT_VIDEO_CRF"
only="all"
existing_policy="keep"
optimized_types=0
optimized_files=0
skipped_files=0
total_original_bytes=0
total_optimized_bytes=0

show_usage() {
    cat <<USAGE
Usage: $0 (--input input_path | --input-list file_path) [options]

Options:
  --input path               Media file or folder with media files to optimize.
  --input-list file          Text file with media file paths to optimize, one path per line.
  --output directory         Folder for optimized files. Defaults to input folder/optimized or file parent/optimized.
  --photo-quality value      WebP quality for images. Defaults to $DEFAULT_PHOTO_QUALITY.
  --video-crf value          CRF value for videos. Defaults to $DEFAULT_VIDEO_CRF.
  --only photos|videos|all   Optimize only one media type. Defaults to all.
  --existing keep|rewrite    Keep or rewrite already optimized files. Defaults to keep.
  -h, --help                 Show this help message.
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
            --input-list)
                [ "$#" -ge 2 ] || fail "--input-list requires a text file."
                input_list_path="$2"
                shift 2
                ;;
            --output)
                [ "$#" -ge 2 ] || fail "--output requires a directory."
                output_directory="$2"
                shift 2
                ;;
            --photo-quality)
                [ "$#" -ge 2 ] || fail "--photo-quality requires a value."
                photo_quality="$2"
                shift 2
                ;;
            --video-crf)
                [ "$#" -ge 2 ] || fail "--video-crf requires a value."
                video_crf="$2"
                shift 2
                ;;
            --only)
                [ "$#" -ge 2 ] || fail "--only requires photos, videos, or all."
                only="$2"
                shift 2
                ;;
            --existing)
                [ "$#" -ge 2 ] || fail "--existing requires keep or rewrite."
                existing_policy="$2"
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
    [ -n "$input_path" ] || [ -n "$input_list_path" ] || fail "--input or --input-list is required."
    [ -z "$input_path" ] || [ -z "$input_list_path" ] || fail "Use either --input or --input-list, not both."

    if [ -n "$input_path" ]; then
        [ -e "$input_path" ] || fail "Input path does not exist: $input_path"
        [ -f "$input_path" ] || [ -d "$input_path" ] || fail "Input path must be a file or directory: $input_path"
    else
        [ -f "$input_list_path" ] || fail "Input list file does not exist: $input_list_path"
    fi

    if [ -z "$output_directory" ]; then
        if [ -n "$input_list_path" ]; then
            output_directory="$(dirname "$input_list_path")/optimized"
        elif [ -d "$input_path" ]; then
            output_directory="$input_path/optimized"
        else
            output_directory="$(dirname "$input_path")/optimized"
        fi
    fi

    case "$only" in
        photos|videos|all) ;;
        *) fail "--only must be photos, videos, or all." ;;
    esac

    case "$existing_policy" in
        keep|rewrite) ;;
        *) fail "--existing must be keep or rewrite." ;;
    esac

    [[ "$photo_quality" =~ ^[0-9]+$ ]] || fail "--photo-quality must be a number."
    [[ "$video_crf" =~ ^[0-9]+$ ]] || fail "--video-crf must be a number."
}

require_command() {
    command -v "$1" > /dev/null 2>&1 || fail "Required command is missing: $1"
}

collect_files() {
    local target_name="$1"
    local -n target_files=$target_name
    shift

    if [ -n "$input_list_path" ]; then
        collect_files_from_list "$target_name" "$@"
        return
    fi

    mapfile -d '' -t target_files < <(
        find "$input_path" -maxdepth 1 -type f \( "$@" \) -print0 | sort -z
    )
}

collect_files_from_list() {
    local -n target_files=$1
    shift

    local -a listed_files=()
    local listed_file

    while IFS= read -r listed_file || [ -n "$listed_file" ]; do
        [ -n "$listed_file" ] || continue
        case "$listed_file" in
            \#*) continue ;;
        esac
        [ -f "$listed_file" ] || fail "Listed file does not exist: $listed_file"
        listed_files+=("$listed_file")
    done < "$input_list_path"

    if [ "${#listed_files[@]}" -eq 0 ]; then
        target_files=()
        return
    fi

    mapfile -d '' -t target_files < <(
        find "${listed_files[@]}" -maxdepth 0 -type f \( "$@" \) -print0 | sort -z
    )
}

is_folder_input() {
    [ -n "$input_path" ] && [ -d "$input_path" ]
}

copy_photo_metadata() {
    local source_file="$1"
    local target_file="$2"

    copy_metadata_with_retries \
        "$target_file" \
        exiftool -m -q -overwrite_original_in_place -tagsFromFile "$source_file" -all:all -unsafe "$target_file"
}

copy_video_metadata() {
    local source_file="$1"
    local target_file="$2"

    copy_metadata_with_retries \
        "$target_file" \
        exiftool -m -q -overwrite_original_in_place -tagsFromFile "$source_file" "$target_file"
}

copy_metadata_with_retries() {
    local target_file="$1"
    shift

    local attempt metadata_output

    for ((attempt = 1; attempt <= METADATA_COPY_ATTEMPTS; attempt++)); do
        if metadata_output=$("$@" 2>&1); then
            return 0
        fi

        if [ "$attempt" -lt "$METADATA_COPY_ATTEMPTS" ]; then
            sleep "$METADATA_COPY_RETRY_DELAY_SECONDS"
        fi
    done

    printf "Warning: failed to copy metadata to %s after %d attempts\n%s\n" \
        "$target_file" \
        "$METADATA_COPY_ATTEMPTS" \
        "$metadata_output" >&2
}

ensure_output_parent_directory() {
    local target_file="$1"

    mkdir -p "$(dirname "$target_file")"
}

prepare_output_directory() {
    local directory="$1"

    mkdir -p "$directory"
    cd "$directory" && pwd -P
}

convert_photo() {
    local source_file="$1"
    local target_file="$2"
    local conversion_output

    ensure_output_parent_directory "$target_file"

    if ! conversion_output=$(cwebp -q "$photo_quality" -metadata all "$source_file" -o "$target_file" -quiet 2>&1); then
        printf "Error: failed to optimize photo %s\n%s\n" "$source_file" "$conversion_output" >&2
        return 1
    fi
}

convert_video() {
    local source_file="$1"
    local target_file="$2"
    local conversion_output move_output temporary_file

    ensure_output_parent_directory "$target_file"
    temporary_file="$(mktemp --suffix=.mp4)"

    if ! conversion_output=$(ffmpeg -nostdin -hide_banner -i "$source_file" -vcodec libx265 -crf "$video_crf" "$temporary_file" -y 2>&1); then
        printf "Error: failed to optimize video %s\n%s\n" "$source_file" "$conversion_output" >&2
        return 1
    fi

    if ! move_output=$(mv -f "$temporary_file" "$target_file" 2>&1); then
        printf "Error: failed to move optimized video to %s\n%s\n" "$target_file" "$move_output" >&2
        return 1
    fi
}

format_bytes() {
    local bytes="$1"

    numfmt --to=iec-i --suffix=B "$bytes"
}

format_percent() {
    local value="$1"
    local base="$2"

    if [ "$base" -eq 0 ]; then
        printf "0.00%%"
        return
    fi

    local sign=""
    if [ "$value" -lt 0 ]; then
        sign="-"
        value=$((value * -1))
    fi

    local scaled=$((value * 10000 / base))
    printf "%s%d.%02d%%" "$sign" "$((scaled / 100))" "$((scaled % 100))"
}

print_file_result() {
    local current_file="$1"
    local total_files="$2"
    local source_file="$3"
    local output_file="$4"

    local original_bytes optimized_bytes saved_bytes
    original_bytes=$(stat -c%s "$source_file")
    optimized_bytes=$(stat -c%s "$output_file")
    saved_bytes=$((original_bytes - optimized_bytes))

    total_original_bytes=$((total_original_bytes + original_bytes))
    total_optimized_bytes=$((total_optimized_bytes + optimized_bytes))
    optimized_files=$((optimized_files + 1))

    local saved_label="saved"
    if [ "$saved_bytes" -lt 0 ]; then
        saved_label="increased"
    fi

    local absolute_saved_bytes="$saved_bytes"
    if [ "$absolute_saved_bytes" -lt 0 ]; then
        absolute_saved_bytes=$((absolute_saved_bytes * -1))
    fi

    printf "[%d/%d] %s: %s (%d bytes) -> %s (%d bytes), %s %s (%d bytes, %s)\n" \
        "$current_file" \
        "$total_files" \
        "$(basename "$source_file")" \
        "$(format_bytes "$original_bytes")" \
        "$original_bytes" \
        "$(format_bytes "$optimized_bytes")" \
        "$optimized_bytes" \
        "$saved_label" \
        "$(format_bytes "$absolute_saved_bytes")" \
        "$absolute_saved_bytes" \
        "$(format_percent "$saved_bytes" "$original_bytes")"
}

print_skipped_file() {
    local current_file="$1"
    local total_files="$2"
    local source_file="$3"
    local output_file="$4"

    skipped_files=$((skipped_files + 1))

    printf "[%d/%d] %s: skipped, optimized file already exists: %s\n" \
        "$current_file" \
        "$total_files" \
        "$(basename "$source_file")" \
        "$output_file"
}

print_processing_file() {
    local current_file="$1"
    local total_files="$2"
    local source_file="$3"
    local output_file="$4"

    printf "[%d/%d] %s: optimizing -> %s\n" \
        "$current_file" \
        "$total_files" \
        "$(basename "$source_file")" \
        "$output_file"
}

print_summary() {
    is_folder_input || [ -n "$input_list_path" ] || return 0
    [ "$optimized_files" -gt 0 ] || [ "$skipped_files" -gt 0 ] || return 0

    if [ "$optimized_files" -eq 0 ]; then
        printf "Summary: 0 optimized, %d skipped.\n" "$skipped_files"
        return
    fi

    local saved_bytes=$((total_original_bytes - total_optimized_bytes))
    local saved_label="saved"
    if [ "$saved_bytes" -lt 0 ]; then
        saved_label="increased"
    fi

    local absolute_saved_bytes="$saved_bytes"
    if [ "$absolute_saved_bytes" -lt 0 ]; then
        absolute_saved_bytes=$((absolute_saved_bytes * -1))
    fi

    printf "Summary: %d optimized, %d skipped, %s (%d bytes) -> %s (%d bytes), %s %s (%d bytes, %s)\n" \
        "$optimized_files" \
        "$skipped_files" \
        "$(format_bytes "$total_original_bytes")" \
        "$total_original_bytes" \
        "$(format_bytes "$total_optimized_bytes")" \
        "$total_optimized_bytes" \
        "$saved_label" \
        "$(format_bytes "$absolute_saved_bytes")" \
        "$absolute_saved_bytes" \
        "$(format_percent "$saved_bytes" "$total_original_bytes")"
}

optimize_photos() {
    local -a photo_files=()
    collect_files photo_files \
        -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp'

    local total_files="${#photo_files[@]}"
    [ "$total_files" -gt 0 ] || return 0

    require_command cwebp
    require_command exiftool

    echo "Optimizing $total_files photo(s)..."

    local processed_files=0
    local photo_file filename output_file

    for photo_file in "${photo_files[@]}"; do
        filename="$(basename "${photo_file%.*}")"
        output_file="$output_directory/$filename.webp"

        processed_files=$((processed_files + 1))

        if [ "$existing_policy" = "keep" ] && [ -e "$output_file" ]; then
            print_skipped_file "$processed_files" "$total_files" "$photo_file" "$output_file"
            continue
        fi

        print_processing_file "$processed_files" "$total_files" "$photo_file" "$output_file"
        convert_photo "$photo_file" "$output_file"
        copy_photo_metadata "$photo_file" "$output_file"

        print_file_result "$processed_files" "$total_files" "$photo_file" "$output_file"
    done

    optimized_types=$((optimized_types + 1))
}

optimize_videos() {
    local -a video_files=()
    collect_files video_files \
        -iname '*.mp4' -o -iname '*.mov' -o -iname '*.m4v'

    local total_files="${#video_files[@]}"
    [ "$total_files" -gt 0 ] || return 0

    require_command ffmpeg
    require_command exiftool

    echo "Optimizing $total_files video(s)..."

    local processed_files=0
    local video_file filename output_file

    for video_file in "${video_files[@]}"; do
        filename="$(basename "${video_file%.*}")"
        output_file="$output_directory/$filename-small.mp4"

        processed_files=$((processed_files + 1))

        if [ "$existing_policy" = "keep" ] && [ -e "$output_file" ]; then
            print_skipped_file "$processed_files" "$total_files" "$video_file" "$output_file"
            continue
        fi

        print_processing_file "$processed_files" "$total_files" "$video_file" "$output_file"
        convert_video "$video_file" "$output_file"
        copy_video_metadata "$video_file" "$output_file"

        print_file_result "$processed_files" "$total_files" "$video_file" "$output_file"
    done

    optimized_types=$((optimized_types + 1))
}

main() {
    if [ "$#" -eq 0 ]; then
        show_usage
        fail "--input or --input-list is required."
    fi

    parse_arguments "$@"
    validate_arguments
    require_command numfmt
    require_command stat
    output_directory="$(prepare_output_directory "$output_directory")"

    if [ "$only" = "photos" ] || [ "$only" = "all" ]; then
        optimize_photos
    fi

    if [ "$only" = "videos" ] || [ "$only" = "all" ]; then
        optimize_videos
    fi

    if [ "$optimized_types" -eq 0 ]; then
        if [ -n "$input_list_path" ]; then
            fail "No supported media files found in: $input_list_path"
        fi

        fail "No supported media files found in: $input_path"
    fi

    echo "Optimized files saved to: $output_directory"
    print_summary
}

main "$@"
