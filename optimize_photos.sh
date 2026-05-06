#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 input_directory output_directory quantity"
    exit 1
fi

# Assign input and output directories from script parameters
input_directory="$1"
output_directory="$2"
quantity=$3

# Create the output directory if it does not exist
mkdir -p "$output_directory"

# Count total number of JPG files
total_files=$(ls "$input_directory"/*.jpg 2>/dev/null | wc -l)

# Check if there are any JPG files in the directory
if [ "$total_files" -eq 0 ]; then
    echo "No JPG files found in the input directory."
    exit 1
fi

# Initialize processed files count
processed_files=0

# Loop through all JPG files in the input directory
for img in "$input_directory"/*.jpg; do
    # Get the filename without the extension
    filename=$(basename "$img" .jpg)

    # Convert JPG to WEBP
    cwebp -q $quantity "$img" -o "$output_directory/$filename.webp" -quiet > /dev/null 2>&1

    # Copy all metadata
    exiv2 -ea- "$img" | exiv2 -ia- "$output_directory/$filename.webp"


    # Increment the count of processed files
    processed_files=$((processed_files + 1))

    # Calculate the percentage of files processed
    percent=$((processed_files * 100 / total_files))

    # Output the progress
    echo -ne "\r[$processed_files/$total_files] $percent% completed"
done

# Print a new line after the final progress
echo