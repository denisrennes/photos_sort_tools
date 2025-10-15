<#
.SYNOPSIS
Defines functions for sorting photo and video files based on the file's EXIF date tags or a date that may be specified in the file name.
.DESCRIPTION
Defines functions for sorting photo and video files based on the file's EXIF date tags or a date that may be specified in the file name.

This script will ensure that ExifTool by Phil Harvey (https://exiftool.org/) is installed and its directory is added into the PATH environment variable.
.EXAMPLE
. ~/Documents/photos_sort_tools/Sort-PhotoDateTools.ps1 -Verbose
Dot-sourcing call of Sort-PhotoDateTools.ps1, to install ExifTool, or verify if it is already installed, and define functions to help sorting photo and video files.

#>
using namespace System.Collections
using namespace System.Collections.Generic

[CmdletBinding()]
    param (
        # Force the re-installation of ExifTool
        [Parameter()]
        [switch]$Force_ExifTool_Install
    )

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Is_SortPhotoDateTools_Loaded = $False

$this_script_name = $MyInvocation.MyCommand.Name
Write-Verbose "${this_script_name}: Install or verify ExifTool and define functions to help classify photo and video files."

$isDotSourced = $MyInvocation.InvocationName -eq '.' -or $MyInvocation.Line -eq ''
if ( -not $isDotSourced ) {
    throw "${this_script_name} must be dot-sourced (i.e. should be called with '.  <script_path>')"
}

# ExifTool access via $env:PATH (install exitool with git clone if necessary)
$exiftool_path = Join-Path $Env:HOME '/bin/exiftool'
$exiftool = Join-Path $exiftool_path 'exiftool'
$exiftool_version = $null

# Remove ExifTool directory if $Force_ExifTool_Install or if it is not correctly installed
if ( Test-Path $exiftool_path ) {
    try {
        [Version]$exiftool_version = & $exiftool -ver
    }
    catch {
        $exiftool_version = $null
    }
    if ( $exiftool_version ) {
        if ( $Force_ExifTool_Install ) {
            Write-Verbose "Removing ExifTool version ${exiftool_version} from '${exiftool_path}' because -Force_ExifTool_Install is used..."
            $exiftool_version = $null
            Remove-Item $exiftool_path -Recurse -Force
        }
    }
    else {
        Write-Verbose "Removing '${exiftool_path}' because ExifTool is not correctly installed..."
        $exiftool_version = $null
        Remove-Item $exiftool_path -Recurse -Force
    }
}

# Install ExifTool if it is not installed
if ( -not $exiftool_version ) {
    Write-Host -NoNewline "Installing ExifTool by Phil Harvey to '${exiftool_path}' ... "
    & git clone --quiet  https://github.com/exiftool/exiftool.git $exiftool_path 
    # Verify that ExifTool is correctly installed
    try {
        [Version]$exiftool_version = & $exiftool -ver
    }
    catch {
        $exiftool_version = $null
    }
    if ( $exiftool_version ) { 
        Write-Host "ok"
    }
    else {
        Write-Host "Error!"
        Throw "Exiftool is not correctly installed in '${exiftool_path}'"
    }
}
# Add ExifTool path to the environment variable PATH
$env:PATH = ( (($env:PATH -split ':') | Where-Object { $_ -ne $exiftool_path}  ) -join ':' ) + ':' + $exiftool_path
Write-Verbose "ok, ExifTool version ${exiftool_version} is available in '${exiftool_path}' and added to `$Env:PATH : just type '& exiftool'."

# List of file extensions that can be written by ExifTool
$EXIFTOOL_WRITABLE_EXTENSION_LIST = ('.360','.3g2','.3gp','.aax','.ai','.arq','.arw','.avif','.cr2','.cr3','.crm','.crw','.cs1','.dcp','.dng','.dr4','.dvb','.eps','.erf','.exif','.exv','.f4a','.f4v','.fff','.flif','.gif','.glv','.gpr','.hdp','.heic','.heif','.icc','.iiq','.ind','.insp','.jng','.jp2','.jpeg','.jpg','.jxl','.lrv','.m4a','.m4v','.mef','.mie','.mng','.mos','.mov','.mp4','.mpo','.mqv','.mrw','.nef','.nksc','.nrw','.orf','.ori','.pbm','.pdf','.pef','.pgm','.png','.ppm','.ps','.psb','.psd','.qtif','.raf','.raw','.rw2','.rwl','.sr2','.srw','.thm','.tiff','.vrd','.wdp','.webp','.x3f','.xmp')

# Defaut date format for ExifTool
$DEFAULT_DATE_FORMAT_EXIFTOOL = '%Y-%m-%d %H:%M:%S'

# Defaut date format for Powershell [DateTime] conversion to/from ExitTool
$DEFAULT_DATE_FORMAT_PWSH = 'yyyy-MM-dd HH:mm:ss'

# Powershell date-normalized file name format
$DATE_NORMALIZED_FILENAME_FORMAT_PWSH = 'yyyy-MM-dd_HH-mm-ss'
$DATE_NORMALIZED_FILENAME_FORMAT_PWSH_LEN = 19      # There could be escape characters into the format, so we do not use .Length


function IsWritableByExifTool {
<#
.SYNOPSIS
Return $True if the given file extension can be written by ExifTool.
.DESCRIPTION
This function returns $True if the given file extension belongs to a file type that can be written by ExifTool by Phil Harvey.

ExifTool by Phil Harvey can write file tags only for certain file types, generally recognized by their extension.

Return $True/$False
.NOTES
The variable $EXIFTOOL_WRITABLE_EXTENSION_LIST must contain the list of the file extensions that ExifTool can write to.
.EXAMPLE
if ( -not IsWritableByExifTool($File.Extension) ) {
    throw "This file type cannot be written by ExifTool"
}
#>
[CmdletBinding()]
    param (
        # The file extension to check
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string]$Extension
    )
    process {
        if ( $Extension -in $EXIFTOOL_WRITABLE_EXTENSION_LIST ) {
            return $True
        }
        else {
            return $False
        }
    }
}
Write-Verbose "ok, IsWritableByExifTool is available."


function Get_DateInFileName {
<#
.SYNOPSIS
Return the Date that may appear in the file base name.
.DESCRIPTION
Return a [DateTime] object computed from the date or date and time that may appear in the file name.

Filenames supported: any name containing a date like "YYYYMMdd HHmmss" or "YYYYMMdd" with various separator characters and possibly a text prefix and/or a text suffix.

Optional separator character for date (the same for the whole date string):                 - . : _ <space>
Optional separator character for time (the same for the whole time string):                 - . : _ <space>
Optional separator character between date and time:                                         - . : _ T <space>

Supported dates have a 4 digits year '19xx' or '20xx' (So noMiddle Ages dates or Star Trek dates ;-)

Supported file base name examples: '2015-07-06 18:21:32','IMG_20150706_182132_1','PIC_20150706_001', etc.

Return $null if no date and time could be retrieved from the file name.
.NOTES
The file existence is not verified.
.EXAMPLE
$photo_DateInFileName = Get_DateInFileName ~/Documents/test_photos/IMG_20150706_182132_1.jpg

Set $photo_DateInFileName with the [DateTime]"2015-07-06 18:21:32" that was retrieved from the file name 'IMG_20150706_182132_1' .
.EXAMPLE
$photo_list = Get-ChildItem ~/Documents/test_photos -File -Recurse | Select-Object FullName,Directory,Name,BaseName,Extension,@{label="DateInFileName";expression={Get_DateInFileName $_}}

Set $photo_list with the list of custom objects from the files into ~/Documents/test_photos . Each custom objet has the properties FullName,Directory,Name,BaseName,Extension,DateInFileName .
#>
[CmdletBinding()]
    param (
        # The literal path of the file whose base name may contain the date to be retrieved.
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string]$LiteralPath
    )
    begin {
        $date_regex = '^(?<prefix>.*)(?<Year>(19|20)\d\d)(?<d_separ>[-.:_ ]?)(?<Month>(01|02|03|04|05|06|07|08|09|10|11|12))\k<d_separ>(?<Day>[0123]\d)([_ -.T:]?(?<Hour>[012345]\d)((?<t_separ>[-.:_ ]?)|[hH])(?<Minute>[012345]\d)(\k<t_separ>|[mM])(?<Second>[012345]\d))?(?<suffix>.*)$'
    }
    process {
        # Get the file base name. Example 'IMG_2022-11-29 13-48-59_001'
        $File = [System.IO.FileInfo]::new( $LiteralPath )       # The file existence is not verified here
        $file_base_name = $File.BaseName

        if ( $file_base_name -match $date_regex ) {
            try {
                $date_in_filename_s = $Matches.Year + '-' + $Matches.Month + '-' + $Matches.Day + ' ' + $Matches.Hour + ':' + $Matches.Minute + ':' + $Matches.Second
                if ( ($Matches.Hour) -and ($Matches.Minute) -and ($Matches.Second) ) {
                    $date_in_filename_s = $Matches.Year + '-' + $Matches.Month + '-' + $Matches.Day + ' ' + $Matches.Hour + ':' + $Matches.Minute + ':' + $Matches.Second
                    $date_in_filename = [DateTime]::ParseExact($date_in_filename_s, 'yyyy-MM-dd HH:mm:ss', $null)
                }
                else {
                    $date_in_filename_s = $Matches.Year + '-' + $Matches.Month + '-' + $Matches.Day
                    $date_in_filename = [DateTime]::ParseExact($date_in_filename_s, 'yyyy-MM-dd', $null)
                }
            }
            catch {
                throw "date conversion error for '${$date_in_filename_s}' in Get_DateInFileName( '${LiteralPath}' ) "   
            }
        }
        else {
            # no date found in the file name
            $date_in_filename = $null
        }

        return $date_in_filename
    }
}  
Write-Verbose "ok, Get_DateInFileName is available."


function Is_DateNormalized_FileName {
<#
.SYNOPSIS
Is a file name a date-normalized file name?
.DESCRIPTION
Returns $true if the file name is a date-normalized filename:

The date-normalized filename pattern is  YYYY-MM-dd_HH-mm-ss[-n].<ext> where '-n' is an optionnal integer to avoid identical file names and '.<ext>' is the file name extension part.

.NOTES
The file existence is not verified.
.EXAMPLE
Is_DateNormalized_FileName ~/Documents/test_photos/IMG_20150706_182132_1.jpg

Return $false
.EXAMPLE
Is_DateNormalized_FileName ~/Documents/test_photos/2015-07-06_18-21-32.jpg

Return $true

#>
[CmdletBinding()]
    param (
        # The literal path of the file.
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string]$LiteralPath
    )
    begin {
    }
    process {
        # Get the file base name. Example 'IMG_2022-11-29 13-48-59_001'
        $File = [System.IO.FileInfo]::new( $LiteralPath )       # The file existence is not verified here
        $file_base_name = $File.BaseName

        $file_base_name_datetime = $file_base_name.SubString(0, $DATE_NORMALIZED_FILENAME_FORMAT_PWSH_LEN)
        
        try { 
            $filename_datetime = [DateTime]::ParseExact($file_base_name_datetime, $DATE_NORMALIZED_FILENAME_FORMAT_PWSH, $null)
        
            $result = $true

            # check possible trailing '-n', an optionnal integer to avoid identical file names: only '-1', '-2', etc. are allowed 
            if ( $file_base_name.Length -gt $file_base_name_datetime.Length ) {
                $file_base_name_tail = $file_base_name.SubString($DATE_NORMALIZED_FILENAME_FORMAT_PWSH_LEN)
                if ( $file_base_name_tail -notmatch '^-\d+$' ) {
                    
                    # the left datetime part of the filename is correct but the right part after that is not '-1' or '-2', etc., so not correct
                    $result = $false
                }
            }
        }
        catch { 
            $result = $false 
        }

        return $result
    }
}
Write-Verbose "ok, Is_FileName_DateNormalized is available."



# Type of a date-normalized folder name 
enum PhotoFolderType {
    none        # not date-normalized
    Year        # “2025 blabla”
    Month       # “2025-11 blabla”
    Day         # “2025-11-29 blabla”
    DayRange    # “2025-11-29(2d) blabla”  
}
function Get_DateRange_From_Normalized_Folder_Name {
<#
.SYNOPSIS
Return the minimum and maximun dates of photo files that may be in a folder name, based on the normalized name of the folder.
.DESCRIPTION
Return the minimum and maximun dates of photo files that may be in a folder name, based on the normalized name of the folder.

Normalized folder names supported ("blabla" is an optional text following the date pattern):
* “2025 blabla” : Min_date = "2025-01-01 00:00:00" (included), Max_date = "2026-01-01 00:00:00" (excluded).
* “2025-11 blabla” : Min_date = "2025-11-01 00:00:00" (included), Max_date = "2025-12-01 00:00:00" (excluded).
* “2025-11-29 blabla” : Min_date = "2025-12-29 00:00:00" (included), Max_date = "2025-12-30 00:00:00" (excluded).
* “2025-11-29(2d) blabla” ("2j" is supported, for French "jour") :  Min_date ="2025-12-29 00:00:00" (included), Max_date = "2025-12-31 00:00:00" (excluded).

Supported dates have a 4 digits year '19xx' or '20xx' (So Middle Ages dates or Star Trek dates are not supported ;-)

Return an ordered hash table: 
        [ordered]@{ 
            Min_date = [DateTime]$value     # [ included
            Max_date = [DateTime]$value     #    excluded [
            Folder_Type = [PhotoFolderType]$value
        } 
Throw an exception if the folder does not exist.

.NOTES
The folder existence is verified.
.EXAMPLE
$minmax_dates = Get_DateRange_From_Normalized_Folder_Name '~/Documents/2015/2015-12 Christmas'

Result:  $minmax_dates.Min_date = [DateTime]"2015-12-01 00:00:00" and $minmax_dates.Max_date = [DateTime]"2016-01-01 00:00:00" (excluded).
.EXAMPLE
$minmax_dates = Get_DateRange_From_Normalized_Folder_Name '~/Documents/2015'

Result:  $minmax_dates.Min_date = [DateTime]"2015-01-01 00:00:00" and $minmax_dates.Max_date = [DateTime]"2016-01-01 00:00:00" (excluded).
#>
[CmdletBinding()]
    param (
        # Literal path of the folder whose base name may contain the date to be retrieved, or literal path of a file contained in the folder to be examined.
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string]$LiteralPath
    )
    begin {
        $date_regex = '^(?<Year>(19|20)\d\d)((?<d_separ>[-])(?<Month>(01|02|03|04|05|06|07|08|09|10|11|12)))?(\k<d_separ>(?<Day>[0123]\d)(\((?<nb_days>\d+)[jd]\))?)?(?<suffix>.*)?$'
    }
    process {
        # Get the folder base name. Example '2015-12 Christmas'
        $path = Get-Item $LiteralPath -ErrorAction SilentlyContinue
        if ( (-not $Path) -or (-not $path.PSIsContainer) ) {
            throw "Get_DateRange_From_Normalized_Folder_Name: This path does not exist or is not a folder: '${LiteralPath}') "
        }
        $folder_base_name = $Path.BaseName

        $min_date = $null
        $max_date = $null
        $Folder_Type = [PhotoFolderType]::none

        try {
            if ( $folder_base_name -match $date_regex ) {   
                if ( $Matches.nb_days ) {
                    if ( -not ( ($Matches.Day) -and ($Matches.Month) -and ($Matches.Year) ) ) {
                        throw "Folder name not date-normalized. (xd) or (xj) is only allowed after a YYYY-MM-dd date: '${folder_base_name}'"
                    }
                    # “2025-11-29(2d) blabla”
                    $Folder_Type = [PhotoFolderType]::DayRange  
                    $nb_days = $Matches.nb_days
                    $min_date = [DateTime]($Matches.Year + '-' + $Matches.Month + '-' + $Matches.Day)  # YYYY-MM-dd 00:00:00
                    $max_date = $min_date.AddDays($nb_days)   # $nb_days after at 00:00:00 (excluded)
                }
                elseif ( ($Matches.Year) -and ($Matches.Month) -and ($Matches.Day) ) {
                    # “2025-11-29 blabla”
                    $Folder_Type = [PhotoFolderType]::Day
                    $min_date = [DateTime]($Matches.Year + '-' + $Matches.Month + '-' + $Matches.Day)  # YYYY-MM-dd 00:00:00
                    $max_date = $min_date.AddDays(1)   # 1 after at 00:00:00 (excluded)
                }
                elseif ( ($Matches.Year) -and ($Matches.Month) ) {
                    # “2025-11 blabla”
                    $Folder_Type = [PhotoFolderType]::Month
                    $min_date = [DateTime]($Matches.Year + '-' + $Matches.Month + '-01')    # YYYY-MM-01 00:00:00
                    $max_date = $min_date.AddMonths(1)      # the 1st of the month after, at 00:00:00 (excluded)
                }
                elseif ( $Matches.Year ) {
                    # YYYY
                    $Folder_Type = [PhotoFolderType]::Year
                    $min_date = [DateTime]($Matches.Year + '-01-01')        # YYYY-01-01
                    $max_date = $min_date.AddYears(1)   # # the 1st of January of the year after, at 00:00:00 (excluded)
                }
                else {
                    throw "Folder name not date-normalized (yet it matches the regex...): '${folder_base_name}'"
                }
            }
            else {
                throw "Folder name not date-normalized: '${folder_base_name}'"
            }
        }
        catch {
            # No correct date pattern found in the folder name ${folder_base_name}.
            $min_date = $null
            $max_date = $null
            $Folder_Type = [PhotoFolderType]::none
        }

        return [ordered]@{ 
                min_date = $min_date
                max_date = $max_date
                Folder_Type = $Folder_Type
            }
    }
}  
Write-Verbose "ok, Get_DateRange_From_Normalized_Folder_Name is available."

   

$gci_photo_dir_ScriptBlock = { 
# Script Block to get the photo files from a directory, excluding some file names and path.
Param(
        [string]$photo_dir
    )
    # .json and .html files are excluded because they are present in Google Takeout photo exports but they are not photo files.
    # *@SynoEAStream files are excluded because they are present in Synology photo shares but they are not photo files.
    Get-ChildItem -LiteralPath $photo_dir -Recurse -File -Exclude ('*.json','*.html','*@SynoEAStream','*.db','*.jbf') | Where-Object { $_FullName -notlike '*@eaDir*' }
}
Write-Verbose "ok, gci_photo_dir_ScriptBlock (ScriptBlock) is available."

function Count_photo_dir {
<#
.SYNOPSIS
Count the photo/video files in a directory.
.DESCRIPTION
Count the photo/video files in a directory.
Return 0 if the directory does not exist.
.NOTES
Uses the script block $gci_photo_dir_ScriptBlock
.EXAMPLE
$photo_dir_count = Count_photo_dir $photo_dir
#>
[CmdletBinding()]
    param (
        # The directory to check, where the photo files should be
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string]$photo_dir
    )
    process {
        Write-Verbose "Counting photo  files in '${photo_dir}'..."
        $photo_dir_count = 0
        if ( Test-Path $photo_dir -PathType Container ) {
            $photo_dir_count = (& $gci_photo_dir_ScriptBlock $photo_dir).Count
        }
        Write-Verbose "... ${photo_dir_count} photo files."
        return $photo_dir_count
    }
}
Write-Verbose "ok, Count_photo_dir is available."


function get_photoset_dir {
<#
.SYNOPSIS
Get the 'base_dir','zip_dir', 'photo_dir' or 'calculated_dir' directory for a given data set name.
.DESCRIPTION
Get the 'base_dir','zip_dir', 'photo_dir' or 'calculated_dir' directory for a given data set name.

Without -No_Existence_test, create the result subdirectory if it does not exist.
With -No_Existence_test, just check that is is a valid path, do not check that this subdirectory actually exists, do not create it.

Throw an exception for any directory type, if the data set BASE directory does not exist ('base_dir' existence is verified every time).
.EXAMPLE
$dataset_export_dir = get_photoset_dir 'nostrucs' 'calculated_dir'
#>
[CmdletBinding()]
param (
    # The name of the photo data set, actually a subdirectory of "${Env:HOME}/Documents/photo_sets"
    [Parameter(Mandatory, Position = 0)]
    [string]$photoset_name,

    # The type of directory
    [Parameter(Mandatory, Position = 1)]
    [ValidateSet('base_dir','zip_dir','photo_dir','calculated_dir', IgnoreCase=$true)]
    [string]$dir_type,

    # Just check that is is a valid path, do not check that this directory actually exists, do not create it.
    [switch]$No_Existence_test
)

begin {
    $subdir_names = [ordered]@{
        'base_dir' = $null
        'zip_dir' = 'zip'
        'photo_dir' = 'photo'
        'calculated_dir' = 'exportClixml'
    }
}

process {
    if ( $dir_type -eq 'base_dir' ) {
        $result_dir = "${Env:HOME}/Documents/photo_sets/${photoset_name}"
    }
    else {
        $dataset_basedir = get_photoset_dir $photoset_name  'base_dir'       # an exception is raised if the data set base directory does not exist
        $result_dir = Join-Path $dataset_basedir $subdir_names[$dir_type]
    }

    if ( $No_Existence_test ) {
        # Just check that is is a valid path, do not check that this directory actually exists, do not create it.
        if ( -not (Test-Path $result_dir -PathType Container -Isvalid ) ) {
            throw "The directory '${result_dir}' is not a valid path."
        }
    }
    else {
        if ( -not (Test-Path $result_dir -PathType Container ) ) {
            if ( $dir_type -eq 'base_dir' ) {
                # throw an exception if the base directory does not exist
                throw "The data set '${photoset_name}' does not exist: the base directory '${dataset_basedir}' does not exist."
            }
            else {
                # Create the directory if it does not exist
                New-Item $result_dir -ItemType Directory 1>$null
                Write-Verbose "The directory '${result_dir} has been created."
            }
        }
    }

    $result_dir
}
}
Write-Verbose "ok, get_photoset_dir is available."


function Export_Clixml_CalculatedData {
<#
.SYNOPSIS
Export photo file data, to save time for subsequent executions when data will be imported and not calculated again.
.DESCRIPTION
Export photo file data, to save time for subsequent executions when data will be imported and not calculated again.

Throw an exception if the data set BASE directory does not exist.
.EXAMPLE
Export_Clixml_CalculatedData 'nostrucs' 'photo_list.xml' ([ref]$photo_list)
#>
[CmdletBinding()]
    param (
        # The name of the photo data set
        [Parameter(Mandatory, Position = 0)]
        [string]$photoset_name,

        # The name of the export file. Any path is ignored in this parameter, only the file name is kept. Ex: '~/Documents/photo_list.xml' is changed to 'photo_list.xml'
        [Parameter(Mandatory, Position = 1)]
        [string]$export_file_name,
        
        # Calculated data to export
        [Parameter(Mandatory, Position = 2)]
        [ref]$data_to_export

    )

    # Ignore any path from the export_file_name argument
    $export_file_name = [System.IO.FileInfo]::New($export_file_name).Name

    # Directory for exporting variables, to avoid recalculating.
    # Create it if needed, unless the data set base directory does not exist: in this case throw an exception.
    $calculated_dir = get_photoset_dir $photoset_name 'calculated_dir'

    $exportXML_file = Join-Path $calculated_dir $export_file_name
    if ( -not (Test-Path $exportXML_file -IsValid) ) {
        Throw "Invalid path '${exportXML_file}'"
    }

    Write-Verbose "Exporting calculated data to '${exportXML_file}'... "
    if ( Test-Path $exportXML_file ) {
        Remove-Item -LiteralPath $exportXML_file
    }

    $data_to_export.Value | Export-Clixml $exportXML_file
}
Write-Verbose "ok, Export_Clixml_CalculatedData is available."

function Import_Clixml_CalculatedData {
<#
.SYNOPSIS
Import photo file data, that was calculated and exported previously, to save time. (not calculated again.)
.DESCRIPTION
Import photo file data, that was calculated and exported previously, to save time. (not calculated again.)

Return the imported data, output of Import-Clixml.
Return $null if the data file to import does not exist.

Throw an exception if the data set BASE directory does not exist.
.EXAMPLE
$photos_list = Import_Clixml_CalculatedData 'nostrucs' 
#>
[CmdletBinding()]
    param (
        # The name of the photo data set
        [Parameter(Mandatory, Position = 0)]
        [string]$photoset_name,
        
        # The name of the file to import. Any path is ignored in this parameter, only the file name is kept. Ex: '~/Documents/photo_list.xml' is changed to 'photo_list.xml'
        [Parameter(Mandatory, Position = 1)]
        [string]$import_file_name

    )

    # Ignore any path from the import_file_name argument
    $import_file_name = [System.IO.FileInfo]::New($import_file_name).Name

    # Directory for exporting variables, to avoid recalculating.
    # Create it if needed, unless the data set base directory does not exist: in this case throw an exception.
    $calculated_dir = get_photoset_dir $photoset_name 'calculated_dir'

    $importXML_file = Join-Path $calculated_dir $import_file_name

    if ( -not (Test-Path $importXML_file -PathType Leaf) ) {
        return $null
    }

    $date_export = (Get-ChildItem -LiteralPath $importXML_file).LastWriteTime.ToSTring($DEFAULT_DATE_FORMAT_PWSH)
    Write-Verbose "Importing from '${importXML_file}' ${date_export} ... "
    Import-Clixml $importXML_file
}
Write-Verbose "ok, Import_Clixml_CalculatedData is available."

 
function Get_PhotoDir_Data {
<#
.SYNOPSIS
Get some data for every photo files in a photo directory.
.DESCRIPTION
Get some data for every photo files in a directory.

Return an [ArrayList] of 
    [PSCustomObject]@{
        FullName          = [string]...          # full path of the file
        FolderName        = [string]...          # Parent directory Name
        Name              = [string]...          # file name
        Extension         = [string]...          # Extension of the file name
        Hash              = [string]...          # Hash of the file 
        CreateDateExif    = [DateTime]...        # 'CreateDate exif tag if it exists,
        DateTimeOriginal  = [DateTime]...        # 'DateTimeOriginal exif tag if it exists,
        DateInFileName    = [DateTime]...        # The date that may appear in the file base name. See function Get_DateInFileName
        LastWriteTime     = [DateTime]...        # The last write time (a.k.a. last modify date) of the file . See function Get-FileLastWriteTime
    }

Throw an exception if the photo directory does not exist.
.NOTES
PREREQUISITE: 
ExifTool by Phil Harvey (https://exiftool.org/) must be installed and its directory must be in the PATH environment variable.
.EXAMPLE
$photo_list = [ArrayList]@()
Get_PhotoDir_Data $photo_dir ([ref]$photo_list)
#>
[CmdletBinding()]
    param (
        # The directory to scan, where are the photo files
        [Parameter(Mandatory, Position = 0)]
        [string]$photo_dir,

        # Calculated data to export
        [Parameter(Mandatory, Position = 1)]
        [ref][ArrayList]$Result_list,

        # Do no process the subdirectories
        [switch]$no_recurse,
        
        # Do not compute the file hash
        [switch]$no_hash
        
    )
    begin {

        # Script block to add to the result ArrayList the new [PSCustomObject] for the current file
        $Add_photo_data_entry_script_block = {
            $DateInFileName = Get_DateInFileName $FullName
            $file = Get-Item $FullName 
            $new_photo_dates_obj = [PSCustomObject]@{
                FullName            = $FullName
                FolderName          = $file.Directory.Name
                Name                = $file.Name
                Extension           = $file.Extension
                Hash                = if ( $no_hash ) { $null } else { (Get-FileHash $FullName).Hash }
                CreateDateExif      = $CreateDateExif
                DateTimeOriginal    = $DateTimeOriginal
                DateInFileName      = $DateInFileName
                LastWriteTime       = $file.LastWriteTime
            }
            $Result_list.value.Add( $new_photo_dates_obj ) 1>$null
        }
    }
    process {

        Write-Verbose "Getting photo files data from '${photo_dir}'..."
        if ( -not (Test-Path $photo_dir -PathType Container) ) {
            Throw "Get_PhotoDir_Data: the photo directory does not exist or is not a directory: '${photo_dir}' "
        }

        $Result_list.Value = [ArrayList]@() 

        # Base variables to store the values parsed from the output lines of ExitTool command
        $FullName = ''
        $CreateDateExif = $null
        $DateTimeOriginal = $null

        # ExifTool command to get the file full path, CreateDate and DateTimeOriginal for every photo file of $photo_dir
        # This is 16 times much faster than using Get-ChildItem and callin ExifTool for each file
        if ( $no_recurse ) {
            $arg_recurse = $false
        }
        else {
            $arg_recurse = $true
        }
        & exiftool -recurse:${arg_recurse} -s2 -d "${DEFAULT_DATE_FORMAT_EXIFTOOL}" -CreateDate -DateTimeOriginal $photo_dir  --ext json --ext html --ext db --ext jbf --ext 'db@SynoEAStream' --ext 'jpg@SynoEAStream'  --ext 'pdf@SynoEAStream' | Foreach-Object {

            $line = $_

            <#  output lines example:
            ...
            ======== /home/denis/Documents/photo_sets/nostrucs/photo/2006/2006-04 Pâque + Ilan/P1070163.JPG
            CreateDate: 2006-04-19 19:34:23
            DateTimeOriginal: 2006-04-19 19:34:23
            ======== /home/denis/Documents/photo_sets/nostrucs/photo/2006/2006-04 Pâque/100_1662.JPG
            ======== /home/denis/Documents/photo_sets/nostrucs/photo/2006/2006-04 Pâque/P1070162.JPG
            DateTimeOriginal: 2006-04-19 19:33:52
                1 directories scanned
               71 image files read
            #>

            if ( $line -like '======== *') {
                
                # File Path line

                # Add the previous file data to the result list
                if ( $FullName -ne '' ) {
                    & $Add_photo_data_entry_script_block

                    # reset current file values of ExifTool output lines parsing
                    $FullName = ''
                    $CreateDateExif = $null
                    $DateTimeOriginal = $null
                }
                
                # New file
                $FullName = $line.substring(9)

            }
            elseif ( $line -like 'CreateDate: *') {
                try {
                    $CreateDateExif = [dateTime]::ParseExact( $line.substring(12), ${DEFAULT_DATE_FORMAT_PWSH}, $null)
                }
                catch {
                    $CreateDateExif = $null
                }
            }
            elseif ( $line -like 'DateTimeOriginal: *') {
                try {
                    $DateTimeOriginal = [dateTime]::ParseExact( $line.substring(18), ${DEFAULT_DATE_FORMAT_PWSH}, $null)
                }
                catch {
                    $DateTimeOriginal = $null
                }
            }
            else {
                # 2 final lines: "    x directories scanned" then "   y image files read"
                if ( ($line -notmatch '^[ ]*\d+ directories scanned$') -and ($line -notmatch '^[ ]*\d+ image files read$') ) {
                    throw "Unexpected ExifTool output line: '$line'"
                }
                # Add the previous file data to the result list
                if ( $FullName -ne '' ) {
                    & $Add_photo_data_entry_script_block

                    # reset current file values of ExifTool output lines parsing
                    $FullName = ''
                    $CreateDateExif = $null
                    $DateTimeOriginal = $null
                }
            }
        }
        Write-Verbose "... $($result_list.Value.Count) photo files."
    }
}
Write-Verbose "ok, Get_PhotoDir_Data is available."


$Is_SortPhotoDateTools_Loaded = $True