<#
.SYNOPSIS
Rename files to fix some old date-normalized names with -1, -2 ... -99 suffixes in the base name: change to _01, _02, ..., _99 suffixes.
.DESCRIPTION
Rename files to fix some old date-normalized names with -1, -2 ... -99 suffixes in the base name: change to _01, _02, ..., _99 suffixes.
.NOTES
ExifTool by Phil Harvey (https://exiftool.org/) may be automatically installed and its directory put in the PATH environment variable.
.EXAMPLE
ren_fix_normalized_suffix_99.ps1 '/home/denis/Documents/photo_sets/nostrucs/photo' -Recurse

#>
using namespace System.Collections
using namespace System.Collections.Generic
[CmdletBinding()]
    param (
        # The directory to scan, where are the photo files
        [Parameter(Mandatory, Position = 0)]
        [string]$Directory,

        # Process the subdirectories
        [Parameter()]
        [switch]$Recurse
    )

# top-level try-catch to display detailed error messages 
try {

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Fix_DateNormalized_FileName-n {
<#
.SYNOPSIS
Rename a file if it is an "OLD" date-normalized file name with a wrong 1 or 2 digit base name suffix, after a '-'separator (-1, -2,...,-99), which is no longer valid.
Rename it with a 2 digits base name suffix after a '_' separator : YYYY-MM-dd_HH-mm-ss[_NN].<ext>   (See function Rename_DateNormalize)
.DESCRIPTION
Rename a file if it is an "OLD" date-normalized file name with a wrong 1 or 2 digit base name suffix, after a '-'separator (-1, -2,...,-99), which is no longer valid.

The date-normalized filename pattern is  YYYY-MM-dd_HH-mm-ss[_NN].<ext> 
  “YYYY-MM-dd_HH-mm-ss” is the date and time, in ISO 8601 format, accurate to the second, but with “-” and “_” as separators, in order to stay compatible with old file systems.
  '-NN' is an optionnal integer to avoid identical file names in the same directory: from '_01','_02',...,'_99' 
        if NN is greter than 99 then an exception is thrown: too much photos having the same date/time.
  '.<ext>' is the file name extension. It will be forced into lowercase if it is not already.

Return:
=> The new name if the file has been successfully renamed: '2016-01-09_11-13-58.jpg' (or '2016-01-09_11-13-58_01.jpg'...)
=> or '' if the file is not an "OLD" date-normalized file name, so it has not been renamed
  .EXAMPLE
Get-ChilItem -Recurse -File ~/Documents/test_photos | Fix_DateNormalized_FileName-n

  Get-ChilItem -Recurse -File ~/Documents/test_photos | ForFix_DateNormalized_FileName-n ~/Documents/test_photos/

The file '2015-07-06_18-21-32-2.jpg' is renamed as "2015-07-06_18-21-32.jpg" if this file name did not exist, else "2015-07-06_18-21-32_01.jpg" or "2015-07-06_18-21-32_02.jpg", etc.
The new name is returned.

The file '2015-07-06_18-21-32-100.jpg' is not renamed because '-100' at the end of the base name is not allowed. It should be '-1','-2', ...,'-99'.
'' is returned.

The file '2015-07-06_18-21-32.JPG' is not renamed because 'IMG_...' is not an old date-normalized name.
'' is returned.

The file 'IMG_2015-07-06_18-21-32.jpg' is not renamed because it is not an old date-normalized name: the extension must be in lowercase.
'' is returned.
#>
[CmdletBinding()]
    param (
        # The file object
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [System.IO.FileInfo]$File
    )
    process {
       
        ### Check the file exitence and get its base name. Example '2015-07-06_18-21-32-100'
        ##$file = Get-Item $LiteralPath
        ##if ( $file -isnot ) {
        ##    throw "The file does not exist: '${LiteralPath}'"
        ##}
        $file_base_name = $File.BaseName
        $file_name = $File.Name

        # The left part of the file base name (will be later checked for the date-time value)
        if ( $file_base_name.Length -lt $DATE_NORMALIZED_FILENAME_FORMAT_PWSH_LEN ) {
            # The file base name is too short, it cannot be an old date-normalized file name
            return ''   
        }
        $file_base_name_left = $file_base_name.SubString(0, $DATE_NORMALIZED_FILENAME_FORMAT_PWSH_LEN)

        # The right part of the base name (will be later checked for the old suffix '-n')
        if ( $file_base_name.Length -le $file_base_name_left.Length ) {
            # Not an old date-normalized name: no trailing -n in its base name
            return ''
        }
        else {
            $file_base_name_right = $file_base_name.SubString($DATE_NORMALIZED_FILENAME_FORMAT_PWSH_LEN)
        }

        # Convert the left part to a [datetime], using the date-normalized file name format
        try {
            $date_in_filename = [DateTime]::ParseExact($file_base_name_left, $DATE_NORMALIZED_FILENAME_FORMAT_PWSH, $null)
        }
        catch {
            # Not an old date-normalized name: the left part of its name is not date-normalized
            return ''
        }

        # Search the old trailing '-n' in the base name: must be in '-1','-2', ...,'-99'
        if ( $file_base_name_right -match '^-(?<counter>\d\d?)$' ) {
            $counter = [int]($matches.counter)
            if ( $counter -eq 0 ) {
                # Not an old date-normalized name: The suffixe counter exists but it is 0
                return ''
            }
        }
        else {
            # Not an old date-normalized name: The right part, after the date-time part, does not match a correct suffix counter in '-1','-2', ... '-99'
            return ''
        }

        # The file extension must be in lowercase
        $ext = $File.Extension
        if ( $ext -cne $ext.ToLower() ) {
            # Not an old date-normalized name: The file extension is not lowercase
            return ''   
        }

        # Rename the file, date-normalized (current version) with the same date found in its previous name and the same counter but with the new '_NN' format instead of the old '-n' format
        $new_suffix = "_{0,2:d2}" -f $counter        # '_01', '_02', ...,'_99' 
        
        # New name of the file
        $new_name = $file_base_name_left + $new_suffix + $ext
        
        # Rename the file
        Rename-Item -NewName $new_name -LiteralPath $File.FullName -ErrorAction 'Stop'

        return $new_name
    }
}



# Load Sort-PhotoDateTools.ps1 (dot-sourcing call allows the 'module' to be in the same directory)
if ( (-not (Test-Path variable:Is_SortPhotoDateTools_Loaded)) -or (-not $Is_SortPhotoDateTools_Loaded) ) {
    . (Join-Path $PSScriptRoot "Sort-PhotoDateTools.ps1")
}

# Check the directory existence
$Dir_o = Get-Item $Directory
if ( $Dir_o -isnot [System.IO.DirectoryInfo] ) {
    throw "Not a directory: '${Directory}'"
}
$Directory = $Dir_o.FullName

if ( $Recurse ) {
    Out normal "Scanning the directory '${Directory}' and its subdirectories and renaming old date-normalized names with -1, -2 ... -99 suffixes in the base name: change to _01, _02, ..., _99 suffixes..."
}
else {
    Out normal "Scanning the directory '${Directory}' (NOT its subdirectories), and renaming old date-normalized names with -1, -2 ... -99 suffixes in the base name: change to _01, _02, ..., _99 suffixes..."
}

# Scan the directory for old date-normalized files and rename them with the correct current date-normalized name
$number_renamed_success = 0
$number_rename_error    = 0
$number_skipped         = 0
Get-ChildItem -File -Recurse:${Recurse} -LiteralPath $Directory | ForEach-Object {
    $file = $_
    $file_name = $file.Name
    try { 
        $new_name = Fix_DateNormalized_FileName-n $file
        if ( $new_name -eq '' ) {
            $number_skipped += 1
        }
        else {
            Out success "ok: '${file_name}' was successfully renamed as '${new_name}'"
            $number_renamed_success += 1
        }
    }
    catch {
        $err = $_
        $err_message = "ERROR trying to rename '${file_name}':"
        $err_message += "${NL}[$($err.Exception.Message)]" 
        Out error $err_message
        $number_rename_error += 1
    }
}


# Display the non-lowercase extensions with their file count 
Out normal 
Out normal  "======================================="

Out success "${number_renamed_success} files have been successfully renamed."
if ( $number_rename_error -gt 0 ) {
    Out error "${number_rename_error} files failed to be renamed."
}
else {
    Out success "${number_rename_error} files failed to be renamed."
}
Out normal "${number_skipped} files were skipped because they were not old date-normalized names with -1, -2 ... -99 suffixes in the base name."

Return



# top-level try-catch to display detailed error messages 
}
catch {
    $err = $_
    write-host "$($err.Exception.Message)" -ForegroundColor Red

    $msg = ($err | Format-List *) | Out-String
    write-host $msg -ForegroundColor DarkRed
}
