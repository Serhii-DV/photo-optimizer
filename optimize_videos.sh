#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 input_directory output_directory"
    exit 1
fi

# Assign input and output directories from script parameters
input_directory="$1"
output_directory="$2"

# Create the output directory if it does not exist
mkdir -p "$output_directory"

# Count total number of MP4 files
total_files=$(ls "$input_directory"/*.mp4 2>/dev/null | wc -l)

# Check if there are any MP4 files in the directory
if [ "$total_files" -eq 0 ]; then
    echo "No MP4 files found in the input directory."
    exit 1
fi

# Initialize processed files count
processed_files=0

# Loop through all MP4 files in the input directory
for video in "$input_directory"/*.mp4; do
    # Get the filename without the extension
    filename=$(basename "$video" .mp4)

    # Reduce video size and save in the output directory
    ffmpeg -i "$video" -vcodec libx265 -crf 32 "$output_directory/$filename-small.mp4" -y > /dev/null 2>&1

    # Copy metadata
    exiftool -tagsFromFile "$video" "$output_directory/$filename-small.mp4"

    # Increment the count of processed files
    processed_files=$((processed_files + 1))

    # Calculate the percentage of files processed
    percent=$((processed_files * 100 / total_files))

    # Output the progress
    echo -ne "\r[$processed_files/$total_files] $percent% completed"
done

# Print a new line after the final progress
echo