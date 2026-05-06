#!/usr/bin/env bash

set -euo pipefail

readonly DEFAULT_PHOTO_QUALITY=80
readonly DEFAULT_VIDEO_CRF=32

input_path=""
output_directory=""
photo_quality="$DEFAULT_PHOTO_QUALITY"
video_crf="$DEFAULT_VIDEO_CRF"
only="all"
optimized_types=0

show_usage() {
    cat <<USAGE
Usage: $0 --input input_path [options]

Options:
  --input path               Media file or folder with media files to optimize.
  --output directory         Folder for optimized files. Defaults to input folder/optimized or file parent/optimized.
  --photo-quality value      WebP quality for images. Defaults to $DEFAULT_PHOTO_QUALITY.
  --video-crf value          CRF value for videos. Defaults to $DEFAULT_VIDEO_CRF.
  --only photos|videos|all   Optimize only one media type. Defaults to all.
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

    if [ -z "$output_directory" ]; then
        if [ -d "$input_path" ]; then
            output_directory="$input_path/optimized"
        else
            output_directory="$(dirname "$input_path")/optimized"
        fi
    fi

    case "$only" in
        photos|videos|all) ;;
        *) fail "--only must be photos, videos, or all." ;;
    esac

    [[ "$photo_quality" =~ ^[0-9]+$ ]] || fail "--photo-quality must be a number."
    [[ "$video_crf" =~ ^[0-9]+$ ]] || fail "--video-crf must be a number."
}

require_command() {
    command -v "$1" > /dev/null 2>&1 || fail "Required command is missing: $1"
}

collect_files() {
    local -n target_files=$1
    shift

    mapfile -d '' -t target_files < <(
        find "$input_path" -maxdepth 1 -type f \( "$@" \) -print0 | sort -z
    )
}

copy_photo_metadata() {
    local source_file="$1"
    local target_file="$2"

    exiv2 -ea- "$source_file" | exiv2 -ia- "$target_file" > /dev/null 2>&1 || true
}

copy_video_metadata() {
    local source_file="$1"
    local target_file="$2"

    exiftool -tagsFromFile "$source_file" "$target_file" > /dev/null
}

print_progress() {
    local processed_files="$1"
    local total_files="$2"
    local percent=$((processed_files * 100 / total_files))

    echo -ne "\r[$processed_files/$total_files] $percent% completed"
}

optimize_photos() {
    local -a photo_files=()
    collect_files photo_files \
        -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png'

    local total_files="${#photo_files[@]}"
    [ "$total_files" -gt 0 ] || return 0

    require_command cwebp
    require_command exiv2

    echo "Optimizing $total_files photo(s)..."

    local processed_files=0
    local photo_file filename output_file

    for photo_file in "${photo_files[@]}"; do
        filename="$(basename "${photo_file%.*}")"
        output_file="$output_directory/$filename.webp"

        cwebp -q "$photo_quality" "$photo_file" -o "$output_file" -quiet > /dev/null 2>&1
        copy_photo_metadata "$photo_file" "$output_file"

        processed_files=$((processed_files + 1))
        print_progress "$processed_files" "$total_files"
    done

    echo
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

        ffmpeg -i "$video_file" -vcodec libx265 -crf "$video_crf" "$output_file" -y > /dev/null 2>&1
        copy_video_metadata "$video_file" "$output_file"

        processed_files=$((processed_files + 1))
        print_progress "$processed_files" "$total_files"
    done

    echo
    optimized_types=$((optimized_types + 1))
}

main() {
    if [ "$#" -eq 0 ]; then
        show_usage
        fail "--input is required."
    fi

    parse_arguments "$@"
    validate_arguments
    mkdir -p "$output_directory"

    if [ "$only" = "photos" ] || [ "$only" = "all" ]; then
        optimize_photos
    fi

    if [ "$only" = "videos" ] || [ "$only" = "all" ]; then
        optimize_videos
    fi

    if [ "$optimized_types" -eq 0 ]; then
        fail "No supported media files found in: $input_path"
    fi

    echo "Optimized files saved to: $output_directory"
}

main "$@"
