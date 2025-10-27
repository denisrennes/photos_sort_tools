<#
.SYNOPSIS
Rename photo files with a date-normalized file name, based on the date properties of the file.
.DESCRIPTION
Rename photo files with a date-normalized file name, based on the date properties of the file.

The date-normalized filename pattern is  YYYY-MM-dd_HH-mm-ss[-n].<ext> 
  “YYYY-MM-dd_HH-mm-ss” is the date and time, in ISO 8601 format, accurate to the second, but with “-” and “_” as separators, in order to stay compatible with old file systems.
  '-n' is an optionnal integer to avoid identical file names in the same directory. 
       if n -gt $MAX_SUFFIX_DATE_NORMALIZED_FILENAME then an exception is thrown: too much photos having the same date/time.
  '.<ext>' is the file name extension. It will be forced into lowercase if it is not already.

The date properties of the photo file: 'CreateDateExif','DateTimeOriginal','DateInFileName','LastWriteTime'

By default, files whose names are already date-normalized will not be renamed: use -Force_Already_Normalized to force renaming.

The files renaming process:


.NOTES
ExifTool by Phil Harvey (https://exiftool.org/) may be automatically installed and its directory put in the PATH environment variable.
.EXAMPLE
ren_normalized.ps1 '/home/denis/Documents/photo_sets/nostrucs/photo/2006/2006-04 Pâque + Ilan'
#>
using namespace System.Collections
using namespace System.Collections.Generic
[CmdletBinding()]
    param (
        # The photo files to be renamed with a date-normalized file name. Directories are not managed (too risky).
        # The list can be provided as a single comma-separated string to handle Nemo file manager actions with multiple selections.
        [Parameter(Mandatory, Position = 0)]
        [string[]]$Photo_File_List,

        # List of date properties, in order of priority for renaming
        [Parameter(Mandatory=$true, Position=1)]
        [string[]]$Date_Prop_List,

        # Force the renaming for the files already having a date-normalized file name
        [switch]$Force_Already_Normalized

    )


Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Load Sort-PhotoDateTools.ps1 (dot-sourcing call allows the 'module' to be in the same directory)
if ( (-not (Test-Path variable:Is_SortPhotoDateTools_Loaded)) -or (-not $Is_SortPhotoDateTools_Loaded) ) {
    . (Join-Path $PSScriptRoot "Sort-PhotoDateTools.ps1")
}

# Check the argument $Photo_File_List.
# The list can be provided as a single comma-separated string to handle Nemo file manager actions with multiple selections.
if ( $Photo_File_List.Count -eq 1 ) {
    $Photo_File_List = $Photo_File_List -split ','
}
# All files must exist and directories are not allowed
[List[FileInfo]]$file_list = $Photo_File_List | ForEach-Object {
    $file = Get-Item $_ -ErrorAction Stop
    if ( $file -isnot [System.IO.FileInfo] ) {
        throw "Incorrect Photo_File_List argument: this is not a file: '${$_}'"
    }
    $file
}

# Check the argument $Date_Prop_List
$Date_Prop_List | ForEach-Object {
    if ( $_ -notin $PROP_LIST ) {
        throw "Incorrect Date_Prop_List argument: this is not a supported date property ($(${PROP_LIST} -join ',')): '${$_}'"
    }
}

# Get [List[PhotoInfo]]PhotoInfo_List, the required date values for every file
if ( ('CreateDateExif' -notin $Date_Prop_List) -and ('DateTimeOriginal' -notin $Date_Prop_List) ) {
    
    # Calling ExifTool is not necessary as neither CreateDateExif nor DateTimeOriginal are required to rename the files 
    [List[PhotoInfo]]$PhotoInfo_List = @( foreach ( $file in $file_list )  {
        # Output a [PhotoInfo] object, whith null CreateDateExif and DateTimeOriginal properties, the other properties will be computed, like DateInFileName and LastWriteTime 
        [PhotoInfo]::New( $file.FullName, $null, $null, $false )
    } )
}
else {

    # Calling ExifTool is necessary as CreateDateExif and/or DateTimeOriginal are required to rename the files 
    [List[PhotoInfo]]$PhotoInfo_List = @( Get_Files_PhotoInfo $file_list -Compute_Hash:$false )

}

# Rename the files

# Nunmber of ok-named files for each property: either successfully renamed ot was already ok regarding this property name
$name_ok_number_by_prop = [ordered]@{ }
foreach ( $prop in $Date_Prop_List ) { $name_ok_number_by_prop += @{$prop = 0} }
# Number of skipped files, not renamed because they were already date-normalized
$skipped_number = 0

try {
    :Loop_File_Renaming Foreach ( $photoinfo in $PhotoInfo_List ) {

        $file_fullname = $photoinfo.FullName

        # By default, files whose names are already date-normalized will not be renamed: use -Force_Already_Normalized to force renaming.
        if ( -not $Force_Already_Normalized ) {
            if ( Is_DateNormalized_FileName $file_fullname ) {
                Out ([Out]::warning) "'${file_fullname}' skipped, not renamed because it is already date-normalized"
                $skipped_number += 1
                continue Loop_File_Renaming
            }
        }

        # Rename the file, date-normalized with the given date property list, in order of priority
        :Loop_date_prop_list foreach ( $prop in $Date_Prop_List ) {
            $date_time = $photoinfo.$prop
            if ( $null -ne $datetime ) {
                $new_name = Rename_DateNormalize $file_fullname $date_time
                if ( $new_name ) {
                    Out ([Out]::success) "'${file_fullname}' renamed as '${new_name}'}"
                }
                else {
                    Out ([Out]::success) "'${file_fullname}' was already date-normalized with its date property '${prop}'}"
                }
                $name_ok_number_by_prop[${prop}] += 1
                break Loop_date_prop_list
            }
        }
    }
}
catch {
    Out ([Out]::error) $_
    Out ([Out]::error) 'Renaming process is stopped.'
}

Out ([Out]::normal) ''
Out ([Out]::normal) '===== Renaming results ====='
Out ([Out]::normal) ("{0:4} files" -f $PhotoInfo_List.Count)

foreach ( $prop in $Date_Prop_List ) {
    Out ([Out]::normal) ("{0:4} ok-named files with property '{1}'" -f $name_ok_number_by_prop[${prop}],$prop ) 
}
if ( $skipped_number -gt 0 ) {
    Out ([Out]::warning) ("{0:4} skipped files, already date-normalized" -f $skipped_number ) 
}

$remaining_file_number = $PhotoInfo_List.Count - ($name_ok_number_by_prop.Values | Measure-Object -Sum).Sum - $skipped_number
if ( $remaining_file_number -gt 0 ) {
    Out ([Out]::error) ("{0:4} files still to be renamed (An error stopped the renaming process)" -f $remaining_file_number ) 
}
