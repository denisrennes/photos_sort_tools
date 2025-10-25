<#
.SYNOPSIS
.DESCRIPTION
.NOTES
ExifTool by Phil Harvey (https://exiftool.org/) may be automatically installed and its directory put in the PATH environment variable.
.EXAMPLE
photo_dates_Analysis.ps1 '/home/denis/Documents/photo_sets/nostrucs/photo/2006/2006-04 Pâque + Ilan'
#>
using namespace System.Collections
using namespace System.Collections.Generic
[CmdletBinding()]
param (
    # The files to be analyzed
    [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
    [string[]]$Path_List,

    # Reference property
    [Parameter(Mandatory=$False)]
    [string]$Ref_Prop = $null,

    # Split the path list using comma as separator. 
    [switch]$Do_comma_split_pathlist

)
begin {
    Set-StrictMode -Version 3.0
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    # Load Sort-PhotoDateTools.ps1 (dot-sourcing call allows the 'module' to be in the same directory)
    if ( (-not (Test-Path variable:Is_SortPhotoDateTools_Loaded)) -or (-not $Is_SortPhotoDateTools_Loaded) ) {
        . (Join-Path $PSScriptRoot "Sort-PhotoDateTools.ps1") -Verbose:$false
    }

    # check $reg_prop argument if provided
    if ( $Ref_Prop ) {
        if ( $Ref_Prop -notin $PROP_LIST ) {
            throw "Invalid -ref_prop argument, not in $($PROP_LIST -join ',')"
        }
    }

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

    function date_prop_display {
    <#
    .SYNOPSIS
    Output a photo date property, possibly compared to a reference date property, as a string for display purpose
    .DESCRIPTION
    Output a photo date property, possibly compared to a reference date property, as a string for display purpose

    if $ref_date is provided then only this date is printed, fo the other date properties, the time span from the reference date is displayed.
    #>
    [CmdletBinding()]
        param (
            # Date property to convert to a string for display purpose
            $date,

            # Is this the reference property?
            [bool]$is_ref_prop,

            # Reference date property
            $ref_date = $null
        )
        process {
            if ( -not $date ) {
                # date property is $null
                return ''   
            }

            if ( $is_ref_prop -or (-not $ref_date) ) {
                # If this is the reference property or if there is no reference property, output the full datetime, formatted
                return $date.ToString($DEFAULT_DATE_FORMAT_PWSH)
            }

            # date identical to the reference date
            if ( are_identical_dates $date $ref_date ) {
                return '     =ref'
            }

            # There is a reference property and the date is not the reference property and they are not identical: output the datetime span from $ref_date, formatted
            $time_span = $date - $ref_date
            if ( $time_span -gt 0 ) {
                $signe = "+"
            }
            else {
                $signe = "-"
                $time_span = -$time_span
            }
            if ( $time_span.TotalDays -ge 1 ) { 
                # '+ 2d 10h03m59s'
                $result = "{0,1}{1,2}d {2,2}h{3,2}m{4,2}s" -f $signe, $time_span.Days, $time_span.Hours, $time_span.Minutes, $time_span.Seconds
            }
            elseif ( $time_span.TotalHours -ge 1 ) { 
                # '   + 10h03m59s'
                $result = "   {0,1} {1,2}h{2,2}m{3,2}s" -f $signe, $time_span.Hours, $time_span.Minutes, $time_span.Seconds
            }
            elseif ( $time_span.TotalMinutes -ge 1) { 
                # '      + 03m59s'
                $result = "      {0,1} {1,2}m{2,2}s" -f $signe, $time_span.Minutes, $time_span.Seconds
            }
            else {
                # '         + 59s'
                $result = "         {0,1} {1,2}s" -f $signe, $time_span.Seconds
            }
            
            return $result

        }

    }

}

process {
    # Process -Path_List argument
    if ( ($Path_List.Count -eq 1) -and $Do_comma_split_pathlist ) {
        $Path_List = $Path_List -split ','     
    }
    write-host "Count: $($Path_List.Count)"
    foreach ( $path in $Path_List ) {
        try {
            $file_entry = Get-Item $path
        }
        catch {
            throw "Non-existent path: '${path}'"
        }
        if ( $file_entry -is [System.IO.DirectoryInfo] ) {
            write-host "Directory: '${path}'"
        }
        elseif ( $file_entry -is [System.IO.FileInfo] ) {
            write-host "     File: '${path}'"
        }
        else {
            # Incorrect type
            throw "Invalid path type, not a file or directory: '${path}'"
        }
    }
    Exit 0



    # check the folder existence
    $main_folder = Get-Item $Photo_Folder
    if ( -not ($main_folder.PSIsContainer) ) {
        throw "Not a folder: '${Photo_Folder}'"
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

        # Get date data for all photo files contained in the photo folder
        $photo_list = [ArrayList]@()
        Get_PhotoDir_Data $photo_dir ([ref]$photo_list) -no_recurse -no_hash -Verbose:$false
        
        # Number of photo files in this folder
        $nb_photos = $photo_list.Count

        # Number of date-normalized photo file names in this folder
        $nb_datenormalized_filenames = @( $photo_list | Where-Object { Is_DateNormalized_FileName ($_.Name) } ).Count

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
            if ( $photo_list.Count -eq 0 ) {
                $nb_dates = 0
            }
            else {
                $sorted_dates = @( $photo_list.$date_prop | Sort-Object | ForEach-Object { $_.Date } )
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
                nb_dates_eq_ref             = -1                        # will be computed at step #3
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
            $ref_date_prop = $null
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
        }

        if ($null -ne $ref_date_prop ) {
            $prop_result[${ref_date_prop}].is_prop_ref = $true                                          # this is the reference property
            $prop_result[${ref_date_prop}].nb_dates_eq_ref  = $prop_result[${ref_date_prop}].nb_dates   # all the dates of this property, even out of folder range
        }


        # Compute property results, step #3
        foreach ( $date_prop in $PROP_LIST ) {

            # Nb dates of this property equal to the dates of the reference property (date difference is less than 1 minute)
            if ( $date_prop -ne $ref_date_prop ) {
                $prop_result[${date_prop}].nb_dates_eq_ref  = 0
                foreach ( $photo in $photo_list ) {
                    if ( ($null -ne $photo.$date_prop) -and ($null -ne $photo.$ref_date_prop) ) {
                        if ( are_identical_dates $photo.$date_prop $photo.$ref_date_prop ) {
                            $prop_result[${date_prop}].nb_dates_eq_ref  += 1
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
             if ( $null -ne $ref_date_prop ) {
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
            $level_3_subdir_list = @( Get-ChildItem -Directory -Recurse ($main_folder_fullname + '/*/*') )
            if ( $level_3_subdir_list.Count -ge 1 ) {
                display_warning "Warning: there are more than one level of subdirectories in the main folder. Ex: $($level_3_subdir_list[0].FullName.Substring($main_folder_fullname.Length))"
            }

            # No photos but subfolders into the main folder: do not display anything else. Next subfolder
            if ( ($nb_photos -eq 0) -and $global_main_has_subfolders ) {
                continue Next_subfolder
            }

            # Display a warning if there are sub-folders and some photos files not in sub-folders
            if ( ($nb_photos -gt 0)-and $global_main_has_subfolders ) {
                display_warning "Warning: there are photo files in the main folder that are not in subfolders.)'"
            }
        }
        
        # First line: general per-folder results
        $line = "  {0,-$($max_prop_length + 2)} : {1,4} photos" -f 'Folder', $nb_photos
        
        if ( $null -ne $min_date_folder  ) {
            $line += ", " + (date_range_string $min_date_folder $max_date_folder)
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
                display_ok $line
            }else {
                display_warning $line
            }
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
                $line = "    {0,-$($max_prop_length)} : {1,4} dates " -f $date_prop, $nb_dates
                if ( $min_date ) {
                    $line += ", " + (date_range_string $min_date $max_date)
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

                # display the property line
                if ( $is_prop_result_ok ) { 
                    display_ok $line 
                } 
                else { 
                    display_notok $line 
                }

            }


            # Display the list of the photo files data for the subfolder 
            if( $List_Files ) {

                if ( $ref_date_prop ) {
                    # Sort by reference property when it is provided
                    $sort_property = $ref_date_prop
                }
                else {
                    # Sort by filename when no reference property is provided
                    $sort_property = 'Name'
                }

                $photo_list | Sort-Object -Property $sort_property | 
                    Select-Object   Name, 
                                    @{ Name='CreateDateExif';   Expression={ date_prop_display $_.CreateDateExif   ($ref_date_prop -eq 'CreateDateExif')    $_.$ref_date_prop } },
                                    @{ Name='DateTimeOriginal'; Expression={ date_prop_display $_.DateTimeOriginal ($ref_date_prop -eq 'DateTimeOriginal')  $_.$ref_date_prop } },
                                    @{ Name='DateInFileName';   Expression={ date_prop_display $_.DateInFileName   ($ref_date_prop -eq 'DateInFileName')    $_.$ref_date_prop } },
                                    @{ Name='LastWriteTime';    Expression={ date_prop_display $_.LastWriteTime    ($ref_date_prop -eq 'LastWriteTime')     $_.$ref_date_prop } }
                    | Format-Table -AutoSize
            }
        }
        
    }   # foreach ( $photo_dir ...

    # End of photo_dir list
    if ( $global_main_has_subfolders ) {
        
        # Some subfolders: display a global result
        display_normal ""
        display_normal "============================"
        if ( $global_result_nb_folder_NOT_ok -eq 0 ) {
            display_ok "OK: all $($photo_subdir_list.Count) subfolders are ok."
        }
        else {
            display_notok "NOT ok: ${global_result_nb_folder_NOT_ok} / $($photo_subdir_list.Count) subfolders are NOT ok."
        }

    }
    else {

        # -List_Files and it is the main folder and it does not have subfolders and there is a reference property without out-of-range dates and files are not all date-normalized already
        if ( $List_Files -and $is_main_folder -and (-not $global_main_has_subfolders) -and $ref_date_prop -and ($prop_result[${ref_date_prop}].nb_OutOfRange_dates -le 0) -and ($prop_result[${ref_date_prop}].nb_dates -gt $nb_datenormalized_filenames) ) {

            Do {
                Write-Host ''
                $user_input = Read-Host "Do you want to rename files with date-normalized format '${DATE_NORMALIZED_FILENAME_FORMAT_PWSH}', using the property '${ref_date_prop}'?"
                $user_input = $user_input.ToUpper().Trim()
            }
            until ( $user_input -in ('Y','N') )

            if ( $user_input -eq 'Y' ) {

                # Rename files to the date-normalized format for all files having a date for the reference property
                $photo_list | Where-Object { $_.$ref_date_prop } | ForEach-Object { $new_name = FileName_DateNormalize $_.FullName $_.$ref_date_prop; if ($new_name) {"$($_.Name) ==> ${new_name}"} else {"$($_.Name) ==> ok already"} }

            }

        }

    }

} # process