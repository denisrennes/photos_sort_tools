<#
.SYNOPSIS
Extract photos from zip files for a photo set
.DESCRIPTION
Photo sets are subdirectories of "${Env:HOME}/Documents/photo_sets/". 

This script will extracts the files from the /zip subdirectory to the /photo subdirectory of the photo set.

Return:

.NOTES
Uses unzip command line
.EXAMPLE
. ./photoset_unzip.ps1 gdegau35

This script will extracts the files from "${Env:HOME}/Documents/photo_sets/gdegau35/zip to "${Env:HOME}/Documents/photo_sets/gdegau35/photo.
#>
using namespace System.Collections
using namespace System.Collections.Generic

[CmdletBinding()]
param (
    # The name of the photo data set, actually a subdirectory of "${Env:HOME}/Documents/photo_sets"
    [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
    [string]$photoset_name,

    # Delete the photos from destination directory before extraction, without asking for confirmation
    [switch]$Yes_redo,

    # Ensure that no collision is possible when extracting .zip files, even if the same file name/path is present in several .zip files.
    # This option produces more complex directory tree because the base name of the .zip is added as the first level destination subdirectory.
    # However, today 2025-02-10, this option is not required for Google TakeOut .zip files because they do not contain identical file names/paths in multiple zip files.
    [switch]$EnsureNoCollision
)
# top-level try-catch to display detailed error messages 
try {

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$this_script_name = $MyInvocation.MyCommand.Name
Write-Verbose "${this_script_name}: Extract photos from zip files for a photo set."

# Load Sort-PhotoDateTools.ps1 (dot-sourcing call allows the 'module' to be in the same directory)
if ( (-not (Test-Path variable:Is_SortPhotoDateTools_Loaded)) -or (-not $Is_SortPhotoDateTools_Loaded) ) {
    . (Join-Path $PSScriptRoot "Sort-PhotoDateTools.ps1")
}

Out normal "Data set name: '${photoset_name}'"
Out normal

# Directory where are the .zip files containing the photo files (possibly from exported from Google Photo with Google TakeOut)
$zip_dir = get_photoset_dir $photoset_name 'zip_dir' -No_Existence_test  # Throw an exception if the BASE directory of the data set does not exist

$zip_files = Get-ChildItem -File -Path (Join-Path $zip_dir *.zip) -ea SilentlyContinue
if ( -not $zip_files ) {
    throw "No zip files to extract from '${zip_dir}'."
}

# Photos directory: directory where are the photo files of the data set (possibly extracted from the zip directory)
# Do NOT create the Photos directory if it does not exist.
$photo_dir = get_photoset_dir $photoset_name 'photo_dir' -No_Existence_test  # Throw an exception if the data set BASE directory does not exist.(wrong data set name?)


# Empty the destination directory before extraction
if ( Test-Path -LiteralPath $photo_dir ) {

    if ( -not $Yes_redo ) {
        
        # User input: Confirm? y/n
        Do {
            $input_default = 'n'
            Out normal -NoNewLine "Confirm to delete `"${photo_dir}`" before? [y/n(default)]: " -Highlight_Text $photo_dir
            $user_input = Read-Host
            if (-not $user_input ) { $user_input = $input_default }
        } Until ( $user_input -in ('y','n') ) 

        if ( $user_input -eq 'n' ) {
            throw "Canceled by the user."
        }
    }

    Out normal "Deleting '${photo_dir}'... " -NoNewLine
    & rm -r ${photo_dir}
    Out normal "Done"
}

Out normal "Creating a new '${photo_dir}'... " -NoNewLine
New-Item $photo_dir -ItemType Directory 1>$null
Out normal "Done"

Out normal ""
     
# Extract       
Foreach ( $zip_file in $zip_files ) {
    if ( $EnsureNoCollision ) {
        $dest_dir = Join-Path $photo_dir ($zip_file.BaseName)   # No collision is possible here, even if the same file path name is present in multiple .zip files
    }
    else {
        $dest_dir = $photo_dir                                  # There may be some collisions here, if the same file path name is present in multiple .zip files
    }
    Out normal "Extracting from $($zip_file.Name) to ${dest_dir} ..."
    & unzip -q -d "${dest_dir}" "${zip_file}" 
    $EXIT_CODE = $LASTEXITCODE
    if ( $EXIT_CODE -ne 0 ) {
        throw "Extraction failure. Unzip returned the exit code ${EXIT_CODE}."
    }
}

# Results
Out normal "Counting the extracted photos..." -NoNewLine
$photo_count = Count_photo_dir $photo_dir
Out normal ": ${photo_count}"


# top-level try-catch to display detailed error messages 
}
catch {
    $err = $_
    write-host "$($err.Exception.Message)" -ForegroundColor Red

    $msg = ($err | Format-List *) | Out-String
    write-host $msg -ForegroundColor DarkRed
}
