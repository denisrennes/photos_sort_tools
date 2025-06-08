<#
.SYNOPSIS
Process a Google TakeOut photo set. 
The final goal will be to sort the photos/videos by the CreateDate exif tag.
.DESCRIPTION
Process a Google TakeOut photo set. 
The final goal will be to sort the photos/videos by the CreateDate exif tag.

* Convert .mkv files to .mp4 files (with ffmpeg), so that ExifTool will be able to write Exif Tags like CreateDate.
.EXAMPLE
. ./photos_Process.ps1 photos_google_test | Tee-Object ./photos_google_test.Analysis.log
#>
[CmdletBinding()]
    param (
        # The name of the google photo data set, also a subdirectory of "${Env:HOME}/Documents"
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string]$photoset_name
    )

$ErrorActionPreference = 'Stop'

Write-Host "Data set name: '${photoset_name}' "

# Call the Analysis script?
if ( -not $photo_list ) {
    $Do_Call_Analysis_Script = $True        # call the analysis script to initialise the analysis variables 
}
else {
    $user_input = $null
    while ( $user_input -notin ("Y","N")) {
        $user_input = Read-Host "Call the Analysis script? [Y/N]"
    }
    if ( $user_input -eq "Y" ) { 
        $Do_Call_Analysis_Script = $True
    }
    else {
        $Do_Call_Analysis_Script = $False
    }
}
if ( $Do_Call_Analysis_Script -eq $True ) {
    Write-Host 'Dot-calling the Analysis script... '
    $analysis_script = Join-Path $PSScriptRoot "photos_google_degau35_Analysis.ps1"
    . $analysis_script
}

############# PROCESS #################

## 2024-01-29: 6 .mkv files were converted to .mp4
# /home/denis/Documents/photos_google_degau35/takeout/takeout-20250119T144149Z-001/Takeout/Google Photos/Mew chasse le faisant/Mew_chasse_le_faisant.mkv
# /home/denis/Documents/photos_google_degau35/takeout/takeout-20250119T144149Z-005/Takeout/Google Photos/Photos from 2022/Mew_chasse_le_faisant.mkv
# /home/denis/Documents/photos_google_degau35/takeout/takeout-20250119T144149Z-006/Takeout/Google Photos/randos vélo/2_chiens.mkv
# /home/denis/Documents/photos_google_degau35/takeout/takeout-20250119T144149Z-011/Takeout/Google Photos/Photos from 2019/2018-03-05_Benjamin_Victor.mkv
# /home/denis/Documents/photos_google_degau35/takeout/takeout-20250119T144149Z-012/Takeout/Google Photos/Benjamin Victor/2018-03-05_Benjamin_Victor.mkv
# /home/denis/Documents/photos_google_degau35/takeout/takeout-20250119T144149Z-015/Takeout/Google Photos/Photos from 2021/2_chiens.mkv
#
Write-Host "Convert .mkv files to .mp4 files (with ffmpeg), so that ExifTool will be able to write Exif Tags like CreateDate..."
$mkv_files = $photo_list | ? Extension -eq '.MKV'
Write-Host " $($mkv_files) .mkv files to convert to .mp4."
Foreach ( $file in $mkv_files) {
    $src_fullname = $file.Fullname
    $dest_fullname = $src_fullname.substring( 0, $src_fullname.length - '.mkv'.Length ) + '.mp4'
    Write-Host "Converting '$($file.Fullname)' to .mp4 ..." -NoNewline

    Remove-Item -LiteralPath $dest_fullname -EA 'SilentlyContinue'
    & ffmpeg -i "$src_fullname" -c:v copy -c:a copy "$dest_fullname" 1>$null
    if ( Test-Path $dest_fullname -PathType Leaf ) {
        Remove-Item -LiteralPath $src_fullname  # delete the .mkv
        Write-Host " => OK."
    }
    else {
        throw "ERROR: '${}' does not exist."
    }

}
