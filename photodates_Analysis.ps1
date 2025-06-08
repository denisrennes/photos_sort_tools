<#
.SYNOPSIS
Analyse the photo dates of a photo folder, compares the dates with the folder date range (computed from its name).
The folder date range is computed from its coventional naming. See the function Get-DateMinMaxInFolderName.
.DESCRIPTION
The computed results are for the folder and for the photo dates CreateDateExif, DateInFileName and LastWriteTime.
(CreateDateExif = CreateDate exif tag if it exists, or else DateTimeOriginal exif tag.)

Computed for the folder:
* $nb_photos                              : Number of photo files.
* [$min_date_folder, $max_date_folder[    : Folder Date Range (date part only, no time). Date range of the folder, computed from its name. $max_date_folder is excluded. See function Get-DateMinMaxInFolderName.

Computed for each property CreateDateExif, DateInFileName and LastWriteTime:
* $nb_dates                  : Number of photo files having a valid date for this property.
* $nb_OutOfRange_dates       : Number of photo files having a date out of the Folder Date Range.
* [$min_date, $max_date]     : Date range for this property. (date part only, no time). $max_date is included.
* $nb_days_missing           : Number of days missing in the property date range, to be equal to the folder's Date Range. (Only if the property date range is included in the folder date range.)

The analyse result of the photo folder is ok ($true) if, for one property:
* all photo have this property date and all dates are within the folder date range: ( ( $nb_dates -eq $nb_photos ) -and ( $nb_OutOfRange_dates -eq 0 ) )
* AND the date range of these dates is the same as the folder range: ( $nb_days_missing -eq 0 )
  Exception: for a YYYY-MM folder, $nb_days_missing is ignored because these folders often contain only a few day-to-day photos, not taken from the first to the last day of the month.

Throw an exception if the directory does not exist or if it is not a valid format ('YYYY' or 'YYYY-MM[-DD[(xj)]][ title]' )
.NOTES
PREREQUISITE: 
ExifTool by Phil Harvey (https://exiftool.org/) must be installed and its directory must be in the PATH environment variable.
.EXAMPLE
photo_dates_Analysis.ps1 -Detailed '/home/denis/Documents/photo_sets/nostrucs/photo/2006/2006-04 Pâque + Ilan'
#>
[CmdletBinding()]
param (
    # The directory to be scanned. If it is a year-level, YYYY, then each sub-directory is analyzed one after the other.
    [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
    [string]$photo_folder,

    # Detailed analysis: the folder global result line is followed by 1 detailed line for the folder and 1 detailed line per date property
    [switch]$Detailed
)
begin {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    if ( -not $Is_SortPhotoDateTools_Loaded ) {
        . (Join-Path $PSScriptRoot "Sort-PhotoDateTools.ps1" -Verbose:$false)
    }
}
process {

    if ( $photo_folder -match '^(.*/)(?<year>(19|20)\d\d)$' ) {
        # Year folder: '.../YYYY/'
        $photo_dir_list = Get-ChildItem -Directory $photo_folder | Sort-Object -Property Name
        $Is_Year_Folder = $True
    }
    elseif ( $photo_folder -match '^(.*/)(?<year>(19|20)\d\d)/\k<year>-(?<month>01|02|03|04|05|06|07|08|09|10|11|12)(.*)?$' ) {
        # Month or Day folder: '.../YYYY/YYYY-MM[-DD[(xj)]][ title]'
        # the list is only 1 folder
        $photo_dir_list = @( $photo_folder )
        $Is_Year_Folder = $False
    }
    else {
        Throw "The folder name does not have a valid format: '.../YYYY/' or 'YYYY-MM[-DD[(xj)]][ title]'."
    }


    # Process each folder
    $global_result_nb_folder_NOT_ok = 0

    foreach ( $photo_dir in $photo_dir_list ) {


        # Final result for the folder analysis
        $result_ok = $false 
        $result_ok_property_list = @()        # Names of the properties that are compliant with the folder date range

        $date_data = [ordered]@{}
        # Date results Hash table for this folder. The key is the property name 'CreateDateExif','DateInFileName','LastWriteTime'), the value is a [PSCustomObject], one per date property name:
        # [PSCustomObject]@{
        #     nb_dates                  = [int32]...           # number of dates for this property (valid dates: -ne [DateTime]::MinValue ) 
        #     nb_OutOfRange_dates       = [int32]...           # number of dates, out of the the folder date range 
        #     nb_days_missing           = [int32]...           # Number of days missing in the property date range, to be equal to the folder's Date Range. (Only if the property date range is included in the folder date range.)
        #     min_date                  = [DateTime]...        # earliest date (date-only, no time)
        #     max_date                  = [DateTime]...        # latest date (date-only, no time)
        # }

        ###### COMPUTE ######

        # Get some file and date data for all photo files contained in the photo folder
        $photo_list = [ArrayList]@()
        Get-PhotoDir_Data $photo_dir ([ref]$photo_list)  -Verbose:$false
        
        # Number of phto files in this folder
        $nb_photos = $photo_list.Count

        # Folder date range, computed from the folder name: incorrect name if ($min_date_folder -eq [DateTime]::MinValue)
        $minmax_folder_dates = Get-DateMinMaxInFolderName $photo_dir
        $min_date_folder = $minmax_folder_dates.Min_date
        $max_date_folder = $minmax_folder_dates.Max_date

        # Is this folder a month range folder, i.e named like 'YYYY-MM ....'?  (for the exception to ignore $nb_days_missing)
        $Is_Folder_YYYYMM = ( $photo_dir -match '^(.*/)(?<year>(19|20)\d\d)/\k<year>-(?<month>01|02|03|04|05|06|07|08|09|10|11|12)( .*)?$' )


        foreach ( $date_prop in ('CreateDateExif','DateInFileName','LastWriteTime') ) {
            
            $is_prop_compliant = $false
            $nb_dates = -1
            $nb_OutOfRange_dates = -1
            $nb_days_missing = -1
            $min_date = [DateTime]::MinValue
            $max_date = [DateTime]::MinValue

            # sorted list of the dates of this property (date-only, the time part is discarded)
            $sorted_dates = $photo_list.$date_prop | Where-Object { ( $_ -ne [DateTime]::MinValue ) } | Sort-Object | ForEach-Object { $_.Date }
            $nb_dates = $sorted_dates.Count

            if ( $nb_dates -ne 0 ) {
                # Dates out of folder date range
                if ($min_date_folder -ne [DateTime]::MinValue) {
                    $OutOfRange_date_list = $sorted_dates | Where-Object { ( $_ -lt $min_date_folder ) -or ( $_ -ge $max_date_folder ) }
                    $nb_OutOfRange_dates = $OutOfRange_date_list.Count
                }
                
                # Date range for this property
                $min_date = $sorted_dates[0]
                $max_date = $sorted_dates[-1]

                # Number of days missing in the property date range, to be equal to the folder's Date Range. (Only if the property date range is included in the folder date range.)
                if ($min_date_folder -ne [DateTime]::MinValue) {
                    if ( ($min_date_folder -ge $min_date_folder) -and ($max_date -lt $max_date_folder) ) {
                        $nb_days_missing = ($min_date - $min_date_folder).TotalDays + ($max_date_folder.AddDays(-1) - $max_date).TotalDays
                    }
                }
            }

            # The analyse final result of the photo folder is ok ($true) for the first property meeting the following conditions:
            # 1) All photos have this property date and all dates are within the folder date range: ( ( $nb_dates -eq $nb_photos ) -and ( $nb_OutOfRange_dates -eq 0 ) )
            # 2) AND the date range of the property dates is the same as the folder date range: ( $nb_days_missing -eq 0 )
            #    Exception: for a YYYY-MM folder, $nb_days_missing is ignored because these folders often contain only a few day-to-day photos, not taken from the first to the last day of the month.
            if ( ( $nb_dates -eq $nb_photos ) -and ( $nb_OutOfRange_dates -eq 0 ) ) {
                # Here all photos have this property date and all dates are within the folder date range: the analyse result of the folder may be ok
                if ( $Is_Folder_YYYYMM ) {
                    $is_prop_compliant = $true
                    # month range folder: the date range of the photos can be smaller than the folder date range. We ignore $nb_days_missing, the folder is ok.
                    $Result_Ok = $true
                    $result_ok_property_list += $date_prop    # Names of the properties that are compliant with the folder date range
                }
                else {
                    if ( $nb_days_missing -eq 0 ) {
                        $is_prop_compliant = $true
                        # the date range of the photos is the same as the folder date range, no excess days in the folder date range. The folder is ok.
                        $Result_Ok = $true
                        $result_ok_property_list += $date_prop    # Names of the properties that are compliant with the folder date range
                    }
                    # else the folder date range is too big: the folder is not ok because the date range of the photos is smaller than the folder date range
                }
            }


            # Add the result custom object for the dates of this property
            $date_data[${date_prop}] = [PSCustomObject]@{
                is_prop_compliant         = $is_prop_compliant
                nb_dates                  = $nb_dates
                nb_OutOfRange_dates       = $nb_OutOfRange_dates
                nb_days_missing           = $nb_days_missing
                min_date                  = $min_date
                max_date                  = $max_date
            }
            
        }


        ###### OUTPUT RESULTS ######

        # 1st line: global result for the folder

        $photo_relative_dir = ($photo_dir -split '/')[-2,-1] -join '/'
        
        if ( $result_ok ) {
            Write-Host "'${photo_relative_dir}': OK. " -ForegroundColor Green  -NoNewline
            Write-Host "Compliant date properties: $($result_ok_property_list -join ', ')" -ForegroundColor DarkGreen
        }
        else {
            if ( $min_date_folder -eq [datetime]::MinValue ) {
                Write-Host "'./${photo_relative_dir}/': NOT ok. " -ForegroundColor Red  -NoNewline
                Write-Host "Bad folder name. (No date range found in the folder name.)" -ForegroundColor DarkRed
            }
            else {
                Write-Host "'${photo_relative_dir}': NOT ok. " -ForegroundColor Red  -NoNewline
                Write-Host "No compliant date property." -ForegroundColor DarkRed
            }
        }

        # Detailed lines: the folder global result line is followed by 1 detailed line for the folder and 1 detailed line per date property
        if ( $Detailed ) {
            
            # Folder Detailed line
            if ( $result_ok ) { $color = 'DarkGreen' } else { $color = 'DarkRed' }
            Write-Host -ForegroundColor $color "       Folder      : ${nb_photos} photos. Range [$($min_date_folder.ToString('yyyy-MM-dd')), $($max_date_folder.ToString('yyyy-MM-dd'))[ ."

            foreach ( $date_prop in ('CreateDateExif','DateInFileName','LastWriteTime') ) {

                $is_prop_compliant        = $date_data[${date_prop}].is_prop_compliant
                $nb_dates                 = $date_data[${date_prop}].nb_dates
                $nb_OutOfRange_dates      = $date_data[${date_prop}].nb_OutOfRange_dates
                $nb_days_missing          = $date_data[${date_prop}].nb_days_missing
                $min_date                 = $date_data[${date_prop}].min_date
                $max_date                 = $date_data[${date_prop}].max_date
        
                # Detail line for 1 date property
                $line = "    ${date_prop}$(' ' * ('CreateDateExif'.Length - $date_prop.Length)) : ${nb_dates} dates.  "
                if ( ${min_date} -ne [DateTime]::MinValue ) {
                    $line += "Range [$($min_date.ToString('yyyy-MM-dd')), $($max_date.ToString('yyyy-MM-dd'))]. "
                }
                if ( ${nb_OutOfRange_dates} -ne -1 ) {
                    $line += "${nb_OutOfRange_dates} out of folder range. "
                }
                if ( ${nb_days_missing} -ne -1 ) {
                    $line += "${nb_days_missing} missing days. "
                }
                if ( $is_prop_compliant ) { $color = 'DarkGreen' } else { $color = 'DarkRed' }
                Write-Host -ForegroundColor $color $line
            }
        }
        
        # update the global number of folders not ok
        if ( -not $result_ok ) {
            $global_result_nb_folder_NOT_ok += 1
        }

    }   # foreach ( $photo_dir ...

    if ( $Is_Year_Folder ) {
        Write-Host "============================"
        if ( $global_result_nb_folder_NOT_ok -eq 0 ) {
            Write-Host -ForegroundColor Green "OK: all $($photo_dir_list.Count) subfolders are ok."
        }
        else {
            Write-Host -ForegroundColor Red "NOT ok: ${global_result_nb_folder_NOT_ok} subfolders are NOT ok. (Out of $($photo_dir_list.Count))"
        }
    }
}