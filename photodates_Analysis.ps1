<#
.SYNOPSIS
Analyze the dates of the photos in a folder and compare them with the folder's date range, which is calculated from its normalized name. (See function Get_DateRange_From_Normalized_Folder_Name.)
This operation is performed for each subfolder of the given folder, if applicable.
.DESCRIPTION
The folder's date range is calculated from its normalized name: "YYYY-MM blabla" or "YYYY-MM-DD blabla" or "YYYY-MM-DD(xd) blabla". (See function Get_DateRange_From_Normalized_Folder_Name.)

The computed results are for the folder and for the exif or file dates: CreateDateExif, DateTimeOriginal, DateInFileName and LastWriteTime. (See function Get-PhotoDir_Data.)

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
* For an "YYYY-MM-DD(xd)"" pattern, the date range of these dates is the same as the folder date range.

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
    [string]$photo_folder
)
begin {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    if ( -not $Is_SortPhotoDateTools_Loaded ) {
        . (Join-Path $PSScriptRoot "Sort-PhotoDateTools.ps1") -Verbose:$false
    }

    $prop_list = ('CreateDateExif','DateTimeOriginal','DateInFileName','LastWriteTime')
    $max_prop_length = ($prop_list | Measure-Object -Maximum -Property Length).Maximum
    function display_normal {
        param (
            $message
        )
        Write-Host $message
    }
    function display_ok {
        param (
            $message
        )
        Write-Host $message -ForegroundColor Green
    }
    function display_notok {
        param (
            $message
        )
        Write-Host $message -ForegroundColor Red
    }
    function display_warning {
        param (
            $message
        )
        Write-Host $message -ForegroundColor DarkYellow
    }
    function date_range_string {
        param (
            [datetime]$min_date,
            [datetime]$max_date
        )
        $nb_days = "{0,2}" -f (($max_date - $min_date).TotalDays)
        Return "[$($min_date.ToString('yyyy-MM-dd')), $($max_date.ToString('yyyy-MM-dd'))[ (${nb_days} days)"
    }
}
process {

    # check the folder existence
    $main_folder = Get-Item $photo_folder
    if ( -not ($main_folder.PSIsContainer) ) {
        throw "Not a folder: '${photo_folder}'"
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
        $folder_result_ok_property_list = @()        # Names of the properties that are compliant with the folder date range
        $is_main_folder = $false
        $folder_name = $photo_dir.Substring($main_folder_fullname.Length)       # Folder name, relative to the main folder
        if ( $folder_name.Length -le 0 ) {
            $is_main_folder = $true
            $folder_name = $main_folder_fullname            # folder name: fullname for the main folder
        }

        # Get date data for all photo files contained in the photo folder
        $photo_list = [ArrayList]@()
        Get-PhotoDir_Data $photo_dir ([ref]$photo_list) -no_recurse -Verbose:$false
        
        # Number of photo files in this folder
        $nb_photos = $photo_list.Count

        # Force result ok for the main folder without direct child photo files but with subfolders
        if ( $is_main_folder -and ($nb_photos -eq 0) -and $global_main_has_subfolders ) {
            $folder_result_ok = $true
        }
        
        $prop_result = [ordered]@{}
        # Date results Hash table for this folder. The key is the property name 'CreateDateExif','DateInFileName','LastWriteTime'), the value is a [PSCustomObject], one per date property name:
        # [PSCustomObject]@{
        #     is_prop_result_ok         = [bool]...            # Is the result ok for this prop?
        #     nb_dates                  = [int32]...           # number of files having a valid date for this property
        #     nb_OutOfRange_dates       = [int32]...           # number of files having a valid date but out of the the folder date range 
        #     nb_days_missing           = [int32]...           # Number of days missing in the property date range, to be equal to the folder's Date Range. (Only if the property date range is included in the folder date range.)
        #     min_date                  = [DateTime]...        # Minimum date limit (date-only, no time) for this property. (INCLUDED: property dates are greater than or equal to this limit.)
        #     max_date                  = [DateTime]...        # Maximum date limit (date-only, no time) for this property. (EXCLUDED: property dates are lower than this limit.)
        # }


        # Folder date range, computed from the folder name
        $date_range = Get_DateRange_From_Normalized_Folder_Name $photo_dir
        $min_date_folder = $date_range.Min_date
        $max_date_folder = $date_range.Max_date
        $Folder_Type = $date_range.Folder_Type

        foreach ( $date_prop in $prop_list ) {
            
            $is_prop_result_ok = $false
            $nb_dates = -1
            $nb_OutOfRange_dates = -1
            $nb_days_missing = -1
            $min_date = [DateTime]::MinValue
            $max_date = [DateTime]::MinValue

            # sorted list of the dates of this property (date-only, the time part is discarded)
            $sorted_dates = @( $photo_list.$date_prop | Where-Object { ( $_ -ne [DateTime]::MinValue ) } | Sort-Object | ForEach-Object { $_.Date } )
            $nb_dates = $sorted_dates.Count

            if ( $nb_dates -ne 0 ) {

                # Dates out of folder date range
                if ($min_date_folder -eq [DateTime]::MinValue) {
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
                if ($min_date_folder -ne [DateTime]::MinValue) {
                    if ( ($min_date -ge $min_date_folder) -and ($max_date -le $max_date_folder) ) {
                        $nb_days_missing = ($min_date - $min_date_folder).TotalDays + ($max_date_folder - $max_date).TotalDays
                    }
                }

                # The result of the photo file analysis is ok for a property if all of the following conditions are met (AND):
                # * All photos have this property date
                # * All dates are within the folder date range.
                # * For "YYYY-MM-DD(xd)" or "YYYY-MM-DD" patterns, the range of these dates must also be the same as the folder date range.
                if ( ( $nb_dates -eq $nb_photos ) -and ( $nb_OutOfRange_dates -eq 0 ) ) {
                    # Here all photos have this property date and all dates are within the folder date range: the analyse result of the folder may be ok
                    if ( $Folder_Type -in ([PhotoFolderType]::DayRange, [PhotoFolderType]::Day) ) {
                        # For "YYYY-MM-DD(xd)" or "YYYY-MM-DD" patterns, the range of these dates must also be the same as the folder date range.
                        if ( ($min_date -eq $min_date_folder) -and ($max_date -eq $max_date_folder) ) {
                            $is_prop_result_ok = $true
                        }
                    }
                    else {
                        # For other folder date ranges (Month...), this property result is ok
                        $is_prop_result_ok = $true
                    }
                    if ($is_prop_result_ok) {
                        $folder_result_ok = $true
                        $result_ok_property_list += $date_prop    # Names of the properties that are compliant with the folder date range
                    }
                }

            }


            # Add the result custom object for the dates of this property
            $prop_result[${date_prop}] = [PSCustomObject]@{
                is_prop_result_ok         = $is_prop_result_ok
                nb_dates                  = $nb_dates
                nb_OutOfRange_dates       = $nb_OutOfRange_dates
                nb_days_missing           = $nb_days_missing
                min_date                  = $min_date
                max_date                  = $max_date
            }
            
        } # for each prop

        # Update the global number of folders not ok
        if ( -not $folder_result_ok ) {
            $global_result_nb_folder_NOT_ok += 1
        }



        ###### DISPLAY FOLDER RESULTS ######

        display_normal ""

    
        # display folder name
        if ( $is_main_folder -and ($nb_photos -eq 0) -and $global_main_has_subfolders ) {
            # for the main folder without photo files and with subfolders, just display the full name
            display_normal $folder_name
        }
        else {
            if ( $folder_result_ok ) {
                display_ok $folder_name
            }
            else {
                display_notok $folder_name
            }
        }

        # main folder specific
        if ( $is_main_folder ) {
            
            # Display a warning if the depth of the subdirectory tree if more than 1 sub-level (Typically only  "/YYYY-MM", "/YYYY-MM-dd" or "/YYYY-MM-dd(xd)" inside the given "YYYY" folder.)
            $level_3_subdir_list = Get-ChildItem -Directory -Recurse ($main_folder_fullname + '/*/*')
            if ( $level_3_subdir_list.Count -ge 1 ) {
                display_warning "Warning: there are more than one level of subdirectories in the main folder. Ex: $($level_3_subdir_list[0].FullName.Substring($main_folder_fullname.Length))"
            }

            # No photos but subfolders into the main folder: do not display anything else. Next subfolder
            if ( ($nb_photos -eq 0) -and $global_main_has_subfolders ) {
                continue Next_subfolder
            }

            # Display a warning if there are sub-folders and some photos files not in sub-folders
            if ( ($nb_photos -gt 0)-and $global_main_has_subfolders ) {
                display_warning "Warning: there are photo files in the main folder that are not in subfolders. Ex: '$($level_1_subfile_list[0].FullName)'"
            }
        }
        
        # First line: general per-folder results
        $line = "  {0,-$($max_prop_length + 2)} : {1,4} photos" -f 'Folder', $nb_photos
        if ( $min_date_folder -ne [datetime]::MinValue ) {
            $line += ", " + (date_range_string $min_date_folder $max_date_folder)
        }
        else {
            $line += ",    - No date range -    "
        }
        if ( $folder_result_ok ) {
            display_ok $line
        }
        else {
            display_notok $line
        }
        
        if ( $nb_photos -eq 0 ) {
            # No photos in this subfolder: display a warning message but nothing else: Next subfolder
            display_warning "  Warning: no photos in this folder."           
            continue Next_subfolder
        }
        else {

            # Next lines: Per-property results for this folder (only if not empty)
            foreach ( $date_prop in $prop_list ) {

                $is_prop_result_ok        = $prop_result[${date_prop}].is_prop_result_ok
                $nb_dates                 = $prop_result[${date_prop}].nb_dates
                $nb_OutOfRange_dates      = $prop_result[${date_prop}].nb_OutOfRange_dates
                $nb_days_missing          = $prop_result[${date_prop}].nb_days_missing
                $min_date                 = $prop_result[${date_prop}].min_date
                $max_date                 = $prop_result[${date_prop}].max_date
        
                # Date range for this property
                $line = "    {0,-$($max_prop_length)} : {1,4} dates " -f $date_prop, $nb_dates
                if ( $min_date -ne [DateTime]::MinValue ) {
                    $line += ", " + (date_range_string $min_date $max_date)
                }
                
                if ( $min_date_folder -ne [datetime]::MinValue ) {
                    # Nb of files which property date is out of the folder date range
                    if ( $nb_OutOfRange_dates -gt 0 ) {
                        $line += ", {0,4} out of folder range " -f $nb_OutOfRange_dates
                    }
                    else {
                        $line += ", - All in folder range - "

                        # Nb of days missing for the property date range to be equal to the folder date range (only if the property date range is included in the folder date range)
                        if ( $nb_days_missing -gt 0 ) {
                            $line += ", {0,4} days missing " -f $nb_days_missing
                        }
                        else {
                            $line += ", Full folder range  "
                        }
                    }

                }

                # display the property line
                if ( $is_prop_result_ok ) { 
                    display_ok $line 
                } 
                else { 
                    display_notok $line 
                }

            }
        }
        
    }   # foreach ( $photo_dir ...

    # End of photo_dir list
    if ( $global_main_has_subfolders ) {
        display_normal ""
        display_normal "============================"
        if ( $global_result_nb_folder_NOT_ok -eq 0 ) {
            display_ok "OK: all $($photo_subdir_list.Count) subfolders are ok."
        }
        else {
            display_notok "NOT ok: ${global_result_nb_folder_NOT_ok} / $($photo_subdir_list.Count) subfolders are NOT ok."
        }
    }

} # process