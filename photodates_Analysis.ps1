<#
.SYNOPSIS
Analyze the dates of the photos in a folder and compare them with the folder's date range, which is calculated from its normalized name. (See function Get_DateRange_From_Normalized_Folder_Name.)
This operation is performed for each subfolder of the given folder, if applicable.
.DESCRIPTION
The folder's date range is calculated from its normalized name: "YYYY-MM blabla" or "YYYY-MM-DD blabla" or "YYYY-MM-DD(xd) blabla". (See function Get_DateRange_From_Normalized_Folder_Name.)

The computed results are for the folder and for the exif or file dates: CreateDateExif, DateTimeOriginal, DateInFileName and LastWriteTime. (See function Get_Directory_PhotoInfo.)

Computed for the folder:
* Number of photo files in this folder.
* Date range of the folder, computed from its name: $min_date_folder (included), $max_date_folder (excluded). See function Get_DateRange_From_Normalized_Folder_Name.

Computed for each property CreateDateExif, DateTimeOriginal,DateInFileName and LastWriteTime:
* Number of photo files having a valid date for this property.
* Number of photo files having a date out of the Folder Date Range for this property.
* Date range for this property: [$min_date, $max_date[
* Number of days missing in the property date range, to be equal to the folder's Date Range. (Only if the property date range is included in the folder date range.)

The result of the photo file analysis is ok for a property if all of the following conditions are met (AND):
* All photos have this property date
* All dates are within the folder date range.
* For "YYYY-MM-DD(xd)" and "YYYY-MM-DD" patterns, the date range of these dates is the same as the folder date range.
* All dates are equal (+- 1 minutes) to the reference property, which is the property having the greatest number of dates (the first property in the property list order)

Throw an exception if the directory does not exist or if its name does not allow to compute its date range. 
.NOTES
ExifTool by Phil Harvey (https://exiftool.org/) may be automatically installed and its directory put in the PATH environment variable.
.EXAMPLE
photo_dates_Analysis.ps1 '/home/denis/Documents/photo_sets/nostrucs/photo/2006/2006-04 Pâque + Ilan'
#>
using namespace System.Collections
using namespace System.Collections.Generic
[CmdletBinding()]
    param (
        # The directory to be analyzed
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string]$Photo_Folder,

        # Display the list of the photo files data for each subfolder 
        [switch]$List_Files,

        # Reference property
        [Parameter(Mandatory=$False)]
        [string]$Ref_Prop = $null

    )

# top-level try-catch to display detailed error messages 
try {
    

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Load Sort-PhotoDateTools.ps1 (dot-sourcing call allows the 'module' to be in the same directory)
if ( (-not (Test-Path variable:Is_SortPhotoDateTools_Loaded)) -or (-not $Is_SortPhotoDateTools_Loaded) ) {
    . (Join-Path $PSScriptRoot "Sort-PhotoDateTools.ps1")
}

# Check the directory existence
$main_folder = Get-Item $Photo_Folder
if ( $main_folder -isnot [System.IO.DirectoryInfo] ) {
    throw "Not a directory: '${Photo_Folder}'"
}

# check $reg_prop argument if provided
if ( $Ref_Prop ) {
    if ( $Ref_Prop -notin $PROP_LIST ) {
        throw "Invalid -ref_prop argument, not in $($PROP_LIST -join ',')"
    }
}


# Full path of the folder
$main_folder_fullname = $main_folder.FullName

# list of all directories and subdirectories to process
[List[String]]$photo_subdir_list = @( Get-ChildItem -Directory -Recurse $main_folder_fullname | Select-Object -ExpandProperty FullName | Sort-Object )
$photo_subdir_list.Insert(0, $main_folder_fullname)

# global results for all subfolders
$global_result_nb_folder_NOT_ok = 0
$global_main_has_subfolders = ($photo_subdir_list.Count -ge 2)

# Process each folder
:Next_subfolder foreach ( $photo_dir in $photo_subdir_list ) {

    ###### COMPUTE FOLDER RESULTS ######

    # Results for the folder analysis
    $folder_result_ok = $false 
    $is_main_folder = $false
    $folder_name = $photo_dir.Substring($main_folder_fullname.Length)       # Folder name, relative to the main folder
    if ( $folder_name.Length -le 0 ) {
        $is_main_folder = $true
        $folder_name = $main_folder_fullname            # folder name: fullname for the main folder
    }

    # Get [PhotoInfo] objects for all photo files in a photo directory.
    [List[PhotoInfo]]$PhotoInfo_List = @( Get_Directory_PhotoInfo $photo_dir -Recurse:$false -Compute_Hash:$false  )
    
    # Number of photo files in this folder
    $nb_photos = $PhotoInfo_List.Count

    # Number of date-normalized photo file names in this folder
    $nb_datenormalized_filenames = @( $PhotoInfo_List | Where-Object { $_.IsNormalizedName } ).Count

    # Force result ok for the main folder without direct child photo files but with subfolders
    if ( $is_main_folder -and ($nb_photos -eq 0) -and $global_main_has_subfolders ) {
        $folder_result_ok = $true
    }
    
    $prop_result = [ordered]@{}
    # Date results Hash table for this folder. The key is the property name 'CreateDateExif','DateInFileName','LastWriteTime'), the value is a [PSCustomObject], one per date property name:
    # [PSCustomObject]@{
    #     nb_dates                  = [int32]...            # number of files having a valid date for this property
    #     nb_OutOfRange_dates       = [int32]...            # number of files having a valid date but out of the the folder date range 
    #     nb_days_missing           = [int32]...            # Number of days missing in the property date range, to be equal to the folder's Date Range. (Only if the property date range is included in the folder date range.)
    #     min_date                  = [DateTime]...         # Minimum date limit (date-only, no time) for this property. (INCLUDED: property dates are greater than or equal to this limit.)
    #     max_date                  = [DateTime]...         # Maximum date limit (date-only, no time) for this property. (EXCLUDED: property dates are lower than this limit.)
    #     is_prop_ref               = [bool]...             # Is this the reference property to compare dates between properties? (The first property having the greatest number of dates, within the folder range)
    #     nb_dates_eq_ref           = [int32]...            # number of dates equal to the date of the reference property
    #     is_prop_result_ok         = [bool]...             # Is the result ok for this prop?
    # }


    # Folder date range, computed from the folder name
    $date_range = Get_DateRange_From_Normalized_Folder_Name $photo_dir
    $min_date_folder = $date_range.Min_date
    $max_date_folder = $date_range.Max_date
    $Folder_Type = $date_range.Folder_Type

    # Compute property results, step #1
    foreach ( $date_prop in $PROP_LIST ) {
        
        $nb_dates = 0
        $nb_OutOfRange_dates = 0
        $nb_days_missing = 0
        $min_date = $null
        $max_date = $null

        # sorted list of the dates of this property (date-only, the time part is discarded)
        if ( $PhotoInfo_List.Count -eq 0 ) {
            $nb_dates = 0
        }
        else {
            $sorted_dates = @( $PhotoInfo_List.$date_prop | Sort-Object | ForEach-Object { $_.Date } )
            $nb_dates = $sorted_dates.Count
        }

        if ( $nb_dates -ne 0 ) {

            # Dates out of folder date range
            if ( $null -eq $min_date_folder ) {
                $nb_OutOfRange_dates = $nb_dates        # all property dates are assumed out of range because there is no folder range
            }
            else {
                $OutOfRange_date_list = @( $sorted_dates | Where-Object { ( $_ -lt $min_date_folder ) -or ( $_ -ge $max_date_folder ) } )
                $nb_OutOfRange_dates = $OutOfRange_date_list.Count
            }
            
            # Date range for this property:  [ $min_date, $max_date [   <== Date only, no time. min_date in included, max_date is excluded
            $min_date = ($sorted_dates[0]).Date     
            $max_date = (($sorted_dates[-1]).Date).AddDays(1)


            # Number of days missing in the property date range, to be equal to the folder's Date Range. (Only if the property date range is included in the folder date range.)
            if ( $null -ne $min_date_folder ) {
                if ( ($min_date -ge $min_date_folder) -and ($max_date -le $max_date_folder) ) {
                    $nb_days_missing = ($min_date - $min_date_folder).TotalDays + ($max_date_folder - $max_date).TotalDays
                }
            }

        }

        # Add the result custom object for the dates of this property
        $prop_result[${date_prop}] = [PSCustomObject]@{
            nb_dates                    = $nb_dates
            nb_OutOfRange_dates         = $nb_OutOfRange_dates
            nb_days_missing             = $nb_days_missing
            min_date                    = $min_date
            max_date                    = $max_date
            is_prop_ref                 = $false                    # will be computed at step #2
            nb_dates_eq_ref             = 0                        # will be computed at step #3
            is_prop_result_ok           = $false                    # will be computed at step #4
        }
        
    } # property results step #1


    # Reference property
    if ( $Ref_Prop ) {
        # the referenece property is given as argument
        $ref_date_prop = $Ref_Prop
    }
    else {
        # Compute property results, step #2: compute the reference property name, the property having the greatest number of dates within the folder range
        $ref_date_prop = ''
        $max_nb_date_in_folder_range = 0
        if ( $null -ne $min_date_folder  ) {        # only for the folders having a date folder range
            foreach ( $date_prop in $PROP_LIST ) {
                $nb_date_in_folder_range = $prop_result[${date_prop}].nb_dates - $prop_result[${date_prop}].nb_OutOfRange_dates
                if ( $nb_date_in_folder_range -gt 0 ) {
                    if ( $nb_date_in_folder_range -gt $max_nb_date_in_folder_range ) {
                        $ref_date_prop = $date_prop          # The reference property name: The first property having the greatest number of dates within the folder range
                        $max_nb_date_in_folder_range = $nb_date_in_folder_range
                    }
                }
            }
        }
        # $ref_date_prop can be empty
    }
    if ( $ref_date_prop ) {
        $prop_result[${ref_date_prop}].is_prop_ref = $true                                          # this is the reference property
        $prop_result[${ref_date_prop}].nb_dates_eq_ref  = $prop_result[${ref_date_prop}].nb_dates   # all the dates of this property, even out of folder range
    }

    if ( $ref_date_prop ) {
        # Compute property results, step #3
        foreach ( $date_prop in $PROP_LIST ) {

            # Nb dates of this property equal to the dates of the reference property (date difference is less than $MAX_SECONDS_IDENTICAL_DATE_DIFF seconds)
            if ( $date_prop -ne $ref_date_prop ) {
                $prop_result[${date_prop}].nb_dates_eq_ref  = 0
                foreach ( $photo in $PhotoInfo_List ) {
                    if ( ($null -ne $photo.$date_prop) -and ($null -ne $photo.$ref_date_prop) ) {
                        if ( are_identical_dates $photo.$date_prop $photo.$ref_date_prop ) {
                            $prop_result[${date_prop}].nb_dates_eq_ref  += 1
                        }
                    }
                }
            }
        }
    }

    # Compute property results, step #4
    # The result of the photo file analysis is ok for a property if all of the following conditions are met (AND):
    # 1) All photos have this property date
    # 2) All dates are within the folder date range
    # 3) For "YYYY-MM-DD(xd)" and "YYYY-MM-DD" patterns, the range of these dates must also be the same as the folder date range (i.e. no missing days)
    # 4) All dates are equal to the reference property
        
    foreach ( $date_prop in $PROP_LIST ) {

        $prop_result[${date_prop}].is_prop_result_ok = $false

        # 1) All photos have this property date
        if ( $prop_result[${date_prop}].nb_dates -ne $nb_photos ) {
            continue
        }

        # 2) All dates are within the folder date range
        if ( $prop_result[${date_prop}].nb_OutOfRange_dates -gt 0 ) {
            continue
        }

        # 3) For "YYYY-MM-DD(xd)" and "YYYY-MM-DD" patterns, the range of these dates must also be the same as the folder date range (i.e. no missing days)
        if ( $Folder_Type -in ([PhotoFolderType]::DayRange, [PhotoFolderType]::Day) ) {
            if ( $prop_result[${date_prop}].nb_days_missing -gt 0 ) {
                continue
            }               
        }

        # 4) All dates are equal to the reference property
        if ( $ref_date_prop ) {
            if ( $prop_result[${date_prop}].nb_dates_eq_ref -ne $prop_result[${date_prop}].nb_dates ) {
                continue
            }
        }

        $prop_result[${date_prop}].is_prop_result_ok = $true
        
        # The folder result is ok if at least one property's result is ok
        $folder_result_ok = $true

    }

    
    # Update the global number of folders not ok
    if ( -not $folder_result_ok ) {
        $global_result_nb_folder_NOT_ok += 1
    }



    ###### DISPLAY FOLDER RESULTS ######

    Out normal  ''      # new line


    # display folder name
    if ( $is_main_folder -and ($nb_photos -eq 0) -and $global_main_has_subfolders ) {
        # for the main folder without photo files and with subfolders, just display the full name
        Out normal  $folder_name
    }
    else {
        if ( $folder_result_ok ) {
            Out success $folder_name
        }
        else {
            Out error $folder_name
        }
    }

    # main folder specific
    if ( $is_main_folder ) {
        
        # Display a warning if the depth of the subdirectory tree if more than 1 sub-level (Typically only  "/YYYY-MM", "/YYYY-MM-dd" or "/YYYY-MM-dd(xd)" inside the given "YYYY" folder.)
        $level_3_subdir_list = @( Get-ChildItem -Directory -Recurse ($main_folder_fullname + '/*/*') )
        if ( $level_3_subdir_list.Count -ge 1 ) {
            Out warning "Warning: there are more than one level of subdirectories in the main folder. Ex: $($level_3_subdir_list[0].FullName.Substring($main_folder_fullname.Length))"
        }

        # No photos but subfolders into the main folder: do not display anything else. Next subfolder
        if ( ($nb_photos -eq 0) -and $global_main_has_subfolders ) {
            continue Next_subfolder
        }

        # Display a warning if there are sub-folders and some photos files not in sub-folders
        if ( ($nb_photos -gt 0)-and $global_main_has_subfolders ) {
            Out warning "Warning: there are photo files in the main folder that are not in subfolders.)'"
        }
    }
    
    # First line: general per-folder results
    $line = "  {0,-$($MAX_PROP_LENGTH + 2)} : {1,4} photos" -f 'Folder', $nb_photos
    
    if ( $null -ne $min_date_folder  ) {
        $line += ", " + (date_range_tostring $min_date_folder $max_date_folder)
    }
    else {
        $line += ",    - No date range -    "
    }

    if ( $nb_photos -gt 0 ) {
        if ( $nb_datenormalized_filenames -eq $nb_photos ) {
            $line += ", All file names are date-normalized"
        }
        else {
            $line += ", {0,4} file names are not date-normalized" -f ($nb_photos - $nb_datenormalized_filenames)
        }
    }

    if ( $folder_result_ok ) {
        if ( $nb_datenormalized_filenames -eq $nb_photos ) {
            Out success $line
        }else {
            Out warning $line
        }
    }
    else {
        Out error $line
    }
    
    if ( $nb_photos -eq 0 ) {
        # No photos in this subfolder: display a warning message but nothing else: Next subfolder
        Out warning "  Warning: no photos in this folder."           
        continue Next_subfolder
    }
    else {

        # Next lines: Per-property results for this folder (only if not empty)
        foreach ( $date_prop in $PROP_LIST ) {

            $nb_dates                 = $prop_result[${date_prop}].nb_dates
            $nb_OutOfRange_dates      = $prop_result[${date_prop}].nb_OutOfRange_dates
            $nb_days_missing          = $prop_result[${date_prop}].nb_days_missing
            $min_date                 = $prop_result[${date_prop}].min_date
            $max_date                 = $prop_result[${date_prop}].max_date
            $is_prop_ref              = $prop_result[${date_prop}].is_prop_ref 
            $nb_dates_eq_ref          = $prop_result[${date_prop}].nb_dates_eq_ref 
            $is_prop_result_ok        = $prop_result[${date_prop}].is_prop_result_ok

    
            # Date range for this property
            $line = "    {0,-$($MAX_PROP_LENGTH)} : {1,4} dates " -f $date_prop, $nb_dates
            if ( $min_date ) {
                $line += ", " + (date_range_tostring $min_date $max_date)
            }
            
            if ( ($nb_dates -ge 1) -and $min_date_folder ) {
                
                # Nb of files which property date is out of the folder date range
                if ( $nb_OutOfRange_dates -gt 0 ) {
                    $line += ", {0,4} out of folder range" -f $nb_OutOfRange_dates
                }
                else {
                    $line += ", All in folder range     "

                    # Nb of days missing for the property date range to be equal to the folder date range (only if the property date range is included in the folder date range)
                    if ( $nb_days_missing -gt 0 ) {
                        $line += ", {0,4} days missing" -f $nb_days_missing
                    }
                    else {
                        $line += ", Full folder range"
                    }

                    # Nb of dates not equal to the reference property
                    if ( $ref_date_prop ) {
                        if ( $is_prop_ref ) {
                            $line += ",     >> Ref <<    "
                        }
                        elseif ( $nb_dates_eq_ref -eq $prop_result[${ref_date_prop}].nb_dates ) {
                            $line += ", Identical to Ref"
                        }
                        elseif ( $nb_dates_eq_ref -ge 0 ) {
                                $line += ", {0,4} dates = Ref" -f $nb_dates_eq_ref
                        }
                    }
                }

            }

            # display the property line
            if ( $is_prop_result_ok ) { 
                Out success $line -Highlight_Text '>> Ref <<'
            } 
            else { 
                Out error $line -Highlight_Text '>> Ref <<' 
            }

        }


        # Display the list of the photo files data
        if( $List_Files ) {

           $PhotoInfo_List | Sort-Object -Property Name | 
                Select-Object   Name, 
                                @{ Name='CreateDateExif';   Expression={ date_diff_ref_tostring $_.CreateDateExif   ($ref_date_prop -eq 'CreateDateExif')    ($ref_date_prop ? $_.$ref_date_prop : $null) } },
                                @{ Name='DateTimeOriginal'; Expression={ date_diff_ref_tostring $_.DateTimeOriginal ($ref_date_prop -eq 'DateTimeOriginal')  ($ref_date_prop ? $_.$ref_date_prop : $null) } },
                                @{ Name='DateInFileName';   Expression={ date_diff_ref_tostring $_.DateInFileName   ($ref_date_prop -eq 'DateInFileName')    ($ref_date_prop ? $_.$ref_date_prop : $null) } },
                                @{ Name='LastWriteTime';    Expression={ date_diff_ref_tostring $_.LastWriteTime    ($ref_date_prop -eq 'LastWriteTime')     ($ref_date_prop ? $_.$ref_date_prop : $null) } }
                | Format-Table -AutoSize | Out-String -Stream  | Out normal -Highlight_Text $ref_date_prop

         }

    }
    
}   # foreach ( $photo_dir ...

# End of photo_dir list
if ( $global_main_has_subfolders ) {
    
    # Some subfolders: display a global result
    Out normal  ''      # new line
    Out normal  "============================"
    if ( $global_result_nb_folder_NOT_ok -eq 0 ) {
        Out success "OK: all $($photo_subdir_list.Count) subfolders are ok."
    }
    else {
        Out error "NOT ok: ${global_result_nb_folder_NOT_ok} / $($photo_subdir_list.Count) subfolders are NOT ok."
    }

}





# top-level try-catch to display detailed error messages 
}
catch {
    $err = $_
    write-host "$($err.Exception.Message)" -ForegroundColor Red

    $msg = ($err | Format-List *) | Out-String
    write-host $msg -ForegroundColor DarkRed
}
