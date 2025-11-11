<#
.SYNOPSIS
Rename photo files with a date-normalized file name, based on the date properties of the file.
.DESCRIPTION
Rename photo files with a date-normalized file name, based on the date properties of the file. (See the function Rename_DateNormalize.)

The date-normalized filename pattern is  YYYY-MM-dd_HH-mm-ss[_NN].<ext> 
  “YYYY-MM-dd_HH-mm-ss” is the date and time, in ISO 8601 format, accurate to the second, but with “-” and “_” as separators, in order to stay compatible with old file systems.
  '_NN' is an optionnal integer to avoid identical file names in the same directory. 
       if NN is greater than 99 then an exception is thrown: too much photos having the same date/time.
  '.<ext>' is the file name extension. It will be forced into lowercase if it is not already.

The date properties of the photo file: 'CreateDateExif','DateTimeOriginal','DateInFileName','LastWriteTime'

By default, files whose names are already date-normalized will not be renamed: use -Force_Already_Normalized to force renaming.
.NOTES
ExifTool by Phil Harvey (https://exiftool.org/) may be automatically installed and its directory put in the PATH environment variable.
.EXAMPLE
ren_normalized.ps1 '/home/denis/Documents/photo_sets/nostrucs/photo/2006/2006-04 Pâque + Ilan'
#>
using namespace System.Collections
using namespace System.Collections.Generic
[CmdletBinding()]
    param (
        # The photo files to be renamed with a date-normalized file name. All files must belong to the same Directory.
        # The list can be provided as a single comma-separated string to handle Nemo file manager actions with multiple selections.
        [Parameter(Mandatory, Position = 0)]
        [string[]]$Photo_File_List,

        # Reference property
        [Parameter(Position =1)]
        [string]$Ref_Prop = '',

        # Force the renaming for the files already having a date-normalized file name
        [switch]$Force_Already_Normalized
    )

# top-level try-catch to display detailed error messages 
try {


Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'


<#
.SYNOPSIS
Compute the skip or rename status of a photo file.
.DESCRIPTION
Compute the skip or rename status of a photo file, based on its [PhotoInfo], the reference property name and the $Force_Already_Normalized argument.

return:
    ' skip: No ref date'                     ==> Do not rename because [PhotoInfo] does not have a reference property ($null)
    ' skip: Already ok'                      ==> Do not rename because the file name is already ok, i.e. date-normalized based on its reference date property
    ' skip: Date-normalized'                 ==> Do not rename because $Force_Already_Normalized is false and the file name is already date-normalized (even though it is not based on the reference property)
    'RENAME to ref date'                     ==> Rename the file, date-normalized and based on its reference date property
#>
function Compute_Planned_Name_Change {
[CmdletBinding()]
    param (
        # The photo files to be renamed with a date-normalized file name. All files must belong to the same Directory.
        # The list can be provided as a single comma-separated string to handle Nemo file manager actions with multiple selections.
        [Parameter(Mandatory, Position = 0)]
        [PhotoInfo]$Photo_Info,

        # Reference property
        [Parameter(mandatory, Position = 1)]
        [string]$Ref_Prop,

        # Force the renaming for the files already having a date-normalized file name
        [Parameter(mandatory, Position = 2)]
        [bool]$Force_Already_Normalized
    )


    # No $ref_date_prop property?
    if ( $null -eq $Photo_Info.$Ref_Prop ) {
        return ' skip: No ref date'
    }
    
    # Already date-normalized based on the reference date?
    if ( Is_DateNormalized_FileName $Photo_Info.FullName $Photo_Info.${Ref_Prop} ) {
        return ' skip: Already ok'
    }

    # By default, files whose names are already date-normalized will not be renamed, unless $Force_Already_Normalized is true, to force renaming.
    if ( -not $Force_Already_Normalized ) {
        if (Is_DateNormalized_FileName $Photo_Info.FullName ) {
            return ' skip: Date-normalized'
        }
    }

    # Rename date-normalized, based on the reference date
    return 'RENAME to ref date'
}


# Load Sort-PhotoDateTools.ps1 (dot-sourcing call allows the 'module' to be in the same directory)
if ( (-not (Test-Path variable:Is_SortPhotoDateTools_Loaded)) -or (-not $Is_SortPhotoDateTools_Loaded) ) {
    . (Join-Path $PSScriptRoot "Sort-PhotoDateTools.ps1")
}

# Check the argument $Photo_File_List.
# The list can be provided as a single semicolon-separated string to handle Nemo file manager actions with multiple selections.
if ( $Photo_File_List.Count -eq 1 ) {
    $Photo_File_List = $Photo_File_List -split ';'
}
# All files must exist and must belong to the same directory. Directories are not allowed.
[List[System.IO.FileInfo]]$file_list = @( $Photo_File_List | ForEach-Object {
    try { $file = Get-Item $_ -ErrorAction Stop }
    catch { throw "This file does not exist: '${$_}'" }
    if ( $file -isnot [System.IO.FileInfo] ) {
        throw "Incorrect Photo_File_List argument: this is not a file: '${$_}'"
    }
    $file
} )
$dir_list = @( $file_list | Group-Object Directory -NoElement )
if ( $dir_list.Count -ne 1 ) {
    throw "All the files must belong to the same directory."
}

# Parent Directory
$directory_name = $file_list[0].Directory

# Check the argument $Ref_Prop
if ( $Ref_Prop ) {
    if ( $Ref_Prop -notin $PROP_LIST ) {
        throw "Incorrect Ref_Date_Prop argument: '${Ref_Prop}' is not a supported date property ($(${PROP_LIST} -join ','))."
    }
}


# Get [List[PhotoInfo]]PhotoInfo_List, the required date values for every file
[List[PhotoInfo]]$PhotoInfo_List = @( Get_Files_PhotoInfo $file_list -Compute_Hash:$false )

# Reference property
if ( $Ref_Prop ) {
    # the referenece property is given as argument
    $ref_date_prop = $Ref_Prop
}
else {
    # Compute the reference property name: the property having the greatest number of dates in the file list
    $ref_date_prop = ''
    $max_nb_date = 0
    foreach ( $date_prop in $PROP_LIST ) {
        $prop_nb_dates = @( $PhotoInfo_List.$date_prop | Where-Object { $null -ne $_ } ).Count
        if ( $prop_nb_dates -gt $max_nb_date ) {
            $ref_date_prop = $date_prop
            $max_nb_date = $prop_nb_dates
        }
    }
}

# Here $ref_date_prop cannot be empty: without any other property, it should be 'LastWriteTime'
if ( -not $ref_date_prop ) { throw "`$ref_date_prop is not supposed to be empty here." }







# Display the file data, confirm renaming or select another reference date property, or End/exit
Do {
    
    Out normal ''
    if ( -not $Force_Already_Normalized ) {
        Out normal "Files with date-normalized names will be skipped, even if the date in their name is not the reference property. (You can use -Force_Already_Normalized)"
    }
    else {
        Out Warning "Warning: Files that have already a date-normalized names WILL BE RENAMED if the date in their name is not the reference property. (-Force_Already_Normalized arg.)"
    }

    # Display the list of the photo files data, sorted by Directory and Name: dates are displayed compared to the reference date property
    Out normal ''
    Out normal "${directory_name}:"

    $formatted_table = $PhotoInfo_List | Sort-Object -Property Name | 
        Select-Object   Name, 
                        @{ Name='CreateDateExif';   Expression={ date_diff_ref_tostring $_.CreateDateExif   ($ref_date_prop -eq 'CreateDateExif')    ($ref_date_prop ? $_.$ref_date_prop : $null) } },
                        @{ Name='DateTimeOriginal'; Expression={ date_diff_ref_tostring $_.DateTimeOriginal ($ref_date_prop -eq 'DateTimeOriginal')  ($ref_date_prop ? $_.$ref_date_prop : $null) } },
                        @{ Name='DateInFileName';   Expression={ date_diff_ref_tostring $_.DateInFileName   ($ref_date_prop -eq 'DateInFileName')    ($ref_date_prop ? $_.$ref_date_prop : $null) } },
                        @{ Name='LastWriteTime';    Expression={ date_diff_ref_tostring $_.LastWriteTime    ($ref_date_prop -eq 'LastWriteTime')     ($ref_date_prop ? $_.$ref_date_prop : $null) } },
                        @{ Name='Rename_Or_Skip';   Expression={ Compute_Planned_Name_Change $_ $ref_date_prop $Force_Already_Normalized } }
        | Format-Table -AutoSize | Out-String -Stream 
        
    $formatted_table[0..2] | Out normal -Highlight_Text $ref_date_prop
    $formatted_table[3..($formatted_table.Count -1)] | Out normal -Highlight_Text 'RENAME to ref date'
    
    # user input 1: Confirm? y/n
    Do {
        $input_default = 'n'
        Out normal -NoNewLine "Confirm to rename the files with a date-normalized name, based on the '${ref_date_prop}' property? [y/n(default)]: " -Highlight_Text $ref_date_prop
        $user_input1 = Read-Host
        if (-not $user_input1 ) { $user_input1 = $input_default }
    } Until ( $user_input1 -in ('y','n') ) 

    if ( $user_input1 -eq 'n' ) {
        Out normal
        
        # User input 2: Select another date property, or Cancel
        Do {
            Out normal "Select another date property as reference for the renaming: "
            $input_default = 'E'  # Return ==> Exit
            Out normal -NoNewLine "Type C for 'CreateDateExif', O for 'DateTimeOriginal', F for 'DateInFileName', W for 'LastWriteTime' or E to End. [C,O,F,W,E(default)]: " -Highlight_Text $ref_date_prop
            $user_input2 = Read-Host
            if (-not $user_input2 ) { $user_input2 = $input_default }

        } Until ( $user_input2 -in ('C','O','F','W','E') ) 

        switch ($user_input2) {
            'C' { $ref_date_prop = 'CreateDateExif'; break }
            'O' { $ref_date_prop = 'DateTimeOriginal'; break }
            'F' { $ref_date_prop = 'DateInFileName'; break }
            'W' { $ref_date_prop = 'LastWriteTime'; break }
            
            default {
                # End/Exit
                Out warning "Canceled by the user."
                return
            }
        }
    }
} until ( ($user_input1 -eq 'y') )


# Rename the files
Out normal
Out normal "Renaming the files, date-normalized, based on '${ref_date_prop}..." -Highlight_Text $ref_date_prop


$number_already_ok = 0          # Number of files already having the right name: date-normalized based on the reference date
$number_skip_normalized = 0     # Number of skipped files, not renamed because they were already date-normalized
$number_no_refdate = 0          # Number of files not renamed because it does not have a reference date property
$number_renamed_success = 0     # Number of successfully renamed files
$number_rename_error = 0        # Number of failed file renaming

:Loop_File_Renaming Foreach ( $photoinfo in $PhotoInfo_List ) {

    $file_fullname = $photoinfo.FullName
    $file_name = $photoinfo.Name

    # No $ref_date_prop property?
    if ( $null -eq $photoinfo.$ref_date_prop ) {
        Out warning "'${file_name}' not renamed because it does not have a ${ref_date_prop} property" -Highlight_Text $ref_date_prop
        $number_no_refdate += 1
        continue Loop_File_Renaming
    }
    
    # Already date-normalized based on the reference date?
    if ( Is_DateNormalized_FileName $file_fullname $photoinfo.${ref_date_prop} ) {
        Out normal "'${file_name}' already date-normalized based on ${ref_date_prop}" -Highlight_Text $ref_date_prop
        $number_already_ok += 1
        continue Loop_File_Renaming
    }

    # By default, files whose names are already date-normalized will not be renamed: use -Force_Already_Normalized to force renaming.
    if ( -not $Force_Already_Normalized ) {
        if ( Is_DateNormalized_FileName $file_fullname ) {
            Out warning "'${file_name}' skipped, not renamed because it is date-normalized"
            $number_skip_normalized += 1
            continue Loop_File_Renaming
        }
    }

    # Rename the file, date-normalized with the reference property
    try { 
        $new_name = Rename_DateNormalize $file_fullname $photoinfo.$ref_date_prop
        Out success "ok: '${file_name}' was successfully renamed as '${new_name}'"
        $number_renamed_success += 1
    }
    catch {
        $err = $_
        $err_message = "ERROR trying to rename '${file_name}', date-normalized based on '$($photoinfo.$ref_date_prop.ToString($DEFAULT_DATE_FORMAT_PWSH))':"
        $err_message += "${NL}[$($err.Exception.Message)]" 
        Out error $err_message
        $number_rename_error += 1
    }
}

Out normal   ''
Out normal   '===== Renaming results ====='
Out normal   ("{0,4} files were selected" -f $PhotoInfo_List.Count)
Out success  ("{0,4} files were successfully renamed" -f $number_renamed_success)
if ( $number_already_ok -ne 0) {
    Out success  ("{0,4} files were already correctly named: date-normalized based on the reference date ${ref_date_prop}" -f $number_already_ok) -Highlight_Text $ref_date_prop
}
if ( $number_skip_normalized -ne 0) {
    Out warning  ("{0,4} files were not renamed because they were already date-normalized (and -Force_Already_Normalized is not used)" -f $number_skip_normalized)
}
if ( $number_rename_error -ne 0) {
    Out error  ("{0,4} files failed to be renamed due to some error" -f $number_rename_error)
}
if ( $number_no_refdate -ne 0) {
    Out warning  ("{0,4} files were not renamed because they do not have a the reference date property ${ref_date_prop}" -f $number_no_refdate) -Highlight_Text $ref_date_prop
}



# top-level try-catch to display detailed error messages 
}
catch {
    $err = $_
    write-host "$($err.Exception.Message)" -ForegroundColor Red

    $msg = ($err | Format-List *) | Out-String
    write-host $msg -ForegroundColor DarkRed
}
