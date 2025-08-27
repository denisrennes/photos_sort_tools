<#
.SYNOPSIS
Define functions to help classify photo and video files, based on the file's date exif tags or a possible date found in the file name.
.DESCRIPTION
Define functions to help classify photo and video files, based on the file's date exif tags or a possible date found in the file name.

This script will ensure that ExifTool by Phil Harvey (https://exiftool.org/) is installed and its directory is added into the PATH environment variable.
.EXAMPLE
. ~/Documents/photos_sort_tools/Sort-PhotoDateTools.ps1 -Verbose
Dot-sourcing call of Sort-PhotoDateTools.ps1, to install ExifTool, or verify if it is already installed, and define functions to help sorting photo and video files.

#>
using namespace System.Collections

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
    Write-Verbose "Installing ExifTool by Phil Harvey to '${exiftool_path}' ..."
    & git clone https://github.com/exiftool/exiftool.git $exiftool_path
    # Verify that ExifTool is correctly installed
    try {
        [Version]$exiftool_version = & $exiftool -ver
    }
    catch {
        $exiftool_version = $null
    }
}
if ( -not $exiftool_version ) { 
    Throw "Exiftool is not correctly installed in '${exiftool_path}'"
}
# Add ExifTool path to the environment variable PATH
$env:PATH = ( (($env:PATH -split ':') | Where-Object { $_ -ne $exiftool_path}  ) -join ':' ) + ':' + $exiftool_path
Write-Verbose "ok, ExifTool version ${exiftool_version} is available in '${exiftool_path}' and added to `$Env:PATH : just type '& exiftool'."

# List of file extensions that can be written by ExifTool
$EXIFTOOL_WRITABLE_EXTENSION_LIST = ('.360','.3g2','.3gp','.aax','.ai','.arq','.arw','.avif','.cr2','.cr3','.crm','.crw','.cs1','.dcp','.dng','.dr4','.dvb','.eps','.erf','.exif','.exv','.f4a','.f4v','.fff','.flif','.gif','.glv','.gpr','.hdp','.heic','.heif','.icc','.iiq','.ind','.insp','.jng','.jp2','.jpeg','.jpg','.jxl','.lrv','.m4a','.m4v','.mef','.mie','.mng','.mos','.mov','.mp4','.mpo','.mqv','.mrw','.nef','.nksc','.nrw','.orf','.ori','.pbm','.pdf','.pef','.pgm','.png','.ppm','.ps','.psb','.psd','.qtif','.raf','.raw','.rw2','.rwl','.sr2','.srw','.thm','.tiff','.vrd','.wdp','.webp','.x3f','.xmp')

# Defaut date format for ExifTool
$DEFAULT_DATE_FORMAT_EXIFTOOL = '%Y-%m-%d %H:%M:%S'

# Defaut date format for Powershell [DateTime] conversion
$DEFAULT_DATE_FORMAT_PWSH = 'yyyy-MM-dd HH:mm:ss'

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


function Get-DateInFileName {
<#
.SYNOPSIS
Return the Date that may appear in the file base name.
.DESCRIPTION
Return a [DateTime] object computed from the date or date and time that may appear in the file name.

Filenames supported: any name containing a date like "YYYYMMdd HHmmss" or "YYYYMMdd" with various separator characters and possibly a text prefix and/or a text suffix.

Separator character possible for date (only one or none):                 - . : _ <space>
Separator character possible for time (only one or none):                 - . : _ <space>
Separator character possible between date and time (only one or none):    - . : _ T <space>

Supported dates have a 4 digits year '19xx' or '20xx' (so no dates from the Middle Ages or Star Trek ;-)

Supported file base name examples: '2015-07-06 18:21:32','IMG_20150706_182132_1','PIC_20150706_001', etc.

Return [DateTime]::MinValue if no date and time could be retrieved into the file name.
.NOTES
The file existence is not verified.
.EXAMPLE
$photo_DateInFileName = Get-DateInFileName ~/Documents/test_photos/IMG_20150706_182132_1.jpg

Set $photo_DateInFileName with the [DateTime]"2015-07-06 18:21:32" that was retrieved from the file name 'IMG_20150706_182132_1' .
.EXAMPLE
$photo_list = Get-ChildItem ~/Documents/test_photos -File -Recurse | Select-Object FullName,Directory,Name,BaseName,Extension,@{label="DateInFileName";expression={Get-DateInFileName $_}}

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
                throw "date conversion error for '${$date_in_filename_s}' in Get-DateInFileName( '${LiteralPath}' ) "   
            }
        }
        else {
            # no date found in the file name
            $date_in_filename = [DateTime]::MinValue
        }

        return $date_in_filename
    }
}  
Write-Verbose "ok, Get-DateInFileName is available."

function Get-DateMinMaxInFolderName {
<#
.SYNOPSIS
Return the minimum and maximun dates of photo files that may be in a folder name, based on the date that may be in the folder name.
.DESCRIPTION
Return the minimum and maximun dates of photo files that may be in a folder name, based on the date that may be in the folder name.

Return an ordered hash table: 
        [ordered]@{ 
            Min_date = [DateTime]$value     # [ included, ...
            Max_date = [DateTime]$value     #              ...  excluded [
        } 

To be in the folder date range, a date $date must verify Min_date <= $date < Max_date, so this expression must be True: ( ($date -ge $minmaxVar.Min_date) -and ($date -lt $minmaxVar.Max_date) )
To be OUT OF the folder date range, a date $date must verify (($date < Min_date) or ($date >= Max_date)), so this expression must be True: ( ($date -lt $minmaxVar.Min_date) -or ($date -ge $minmaxVar.Max_date) )

Folder names supported: any name starting with a date like (all below patterns can possibly be followed by a space and some text, as folder description or title):
* “2025” :                    Min_date=>"2025-01-01 00:00:00" (included), Max-date=Min_date.AddYears(1)  => "2026-01-01 00:00:00" (excluded).
* “2025-11” :                 Min_date=>"2025-11-01 00:00:00" (included), Max-date=Min_date.AddMonths(1) => "2025-12-01 00:00:00" (excluded).
* “2025-11-29” :              Min_date=>"2025-12-29 00:00:00" (included), Max-date=Min_date.AddDays(1)   => "2025-12-30 00:00:00" (excluded).
* “2025-11-29(2j)” (or (2d))  Min_date=>"2025-12-29 00:00:00" (included), Max-date=Min_date.AddDays(2)   => "2025-12-31 00:00:00" (excluded).

Supported dates have a 4 digits year '19xx' or '20xx' (so no dates from the Middle Ages or Star Trek dates ;-)

if a file is given as argument then its parent directory is processed, the file is ignored.
.NOTES
The folder existence is verified, and the file existence too, if a file has been given.
.EXAMPLE
$minmax_dates = Get-DateMinMaxInFolderName '~/Documents/2015/2015-12 Christmas'

Result:  $minmax_dates.Min_date = [DateTime]"2015-12-01 00:00:00" and $minmax_dates.Max_date = [DateTime]"2016-01-01 00:00:00". They were calculated from the directory name '/2015-12 Christmas/'.
.EXAMPLE
$minmax_dates = Get-DateMinMaxInFolderName '~/Documents/2015/2015-12-25 Christmas/IMG_20151225_202132_1.jpg'

Result:  $minmax_dates.Min_date = [DateTime]"2015-12-25 00:00:00" and $minmax_dates.Max_date = [DateTime]"2015-12-26 00:00:00". They were calculated from the PARENT directory name '/2015-12 Christmas/'.
.EXAMPLE
$minmax_dates = Get-DateMinMaxInFolderName '~/Documents/2015'

Result:  $minmax_dates.Min_date = [DateTime]"2015-01-01 00:00:00" and $minmax_dates.Max_date = [DateTime]"2016-01-01 00:00:00". They were calculated from the directory name '/2015/'.
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
        if ( -not $Path ) {
            throw "Get-DateMinMaxInFolderName: This file or folder path does not exist: '${LiteralPath}') "
        }
        if ( $path -is [System.IO.FileInfo] ) {
            # $LiteralPath is a file, so get its parent directory
            $path = $path.Directory
        }
        if ( -not ($path -is [System.IO.DirectoryInfo]) ) {
            throw "Get-DateMinMaxInFolderName: This path is not a file or a directory: '${LiteralPath}') "
        }
        $folder_base_name = $Path.BaseName

        try {
            if ( $folder_base_name -match $date_regex ) {
                if ( $Matches.nb_days ) {
                    if ( -not $Matches.Day ) {
                        Write-Warning "Incorrect folder date '${folder_base_name}': (xd) or (xj) is only allowed after a YYYY-MM-dd date. Ignored for this folder."
                    }
                    # (2j) or (2d) after the date ==> numbers of days of the folder date range
                    $nb_days = $Matches.nb_days
                }
                else {
                    # No (2j) or (2d) after the date ==> the folder date range is 1 day
                    $nb_days = 1
                }
                if ( $Matches.Day ) {
                    # YYYY-MM-DD or YYYY-MM-DD(xd) or YYYY-MM-DD(xj)
                    $min_date = [DateTime]($Matches.Year + '-' + $Matches.Month + '-' + $Matches.Day)  # YYYY-MM-dd 00:00:00
                    $max_date = $min_date.AddDays($nb_days)   # $nb_days after at 00:00:00 (excluded)
                }
                elseif ( $Matches.Month ) {
                    # YYYY-MM
                    $min_date = [DateTime]($Matches.Year + '-' + $Matches.Month + '-01')    # YYYY-MM-01 00:00:00
                    $max_date = $min_date.AddMonths(1)      # the 1st of the month after, at 00:00:00 (excluded)
                }
                else {
                    # YYYY
                    $min_date = [DateTime]($Matches.Year + '-01-01')        # YYYY-01-01
                    $max_date = $min_date.AddYears(1)   # # the 1st of January of the year after, at 00:00:00 (excluded)
                }
            }
            else {
                throw "No date found in the folder name ${folder_base_name}."
            }
        }
        catch {
            $min_date = [DateTime]::MinValue
            $max_date = [DateTime]::MinValue
        }

        return [ordered]@{ 
                min_date = $min_date
                max_date = $max_date
            }
    }
}  
Write-Verbose "ok, Get-DateMinMaxInFolderName is available."

   

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

 
function Get-PhotoDir_Data {
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
        DateInFileName    = [DateTime]...        # The date that may appear in the file base name. See function Get-DateInFileName
        LastWriteTime     = [DateTime]...        # The last write time (a.k.a. last modify date) of the file . See function Get-FileLastWriteTime
    }

Throw an exception if the photo directory does not exist.
.NOTES
PREREQUISITE: 
ExifTool by Phil Harvey (https://exiftool.org/) must be installed and its directory must be in the PATH environment variable.
.EXAMPLE
$photo_list = [ArrayList]@()
Get-PhotoDir_Data $photo_dir ([ref]$photo_list)
#>
[CmdletBinding()]
    param (
        # The directory to scan, where are the photo files
        [Parameter(Mandatory, Position = 0)]
        [string]$photo_dir,

        # Calculated data to export
        [Parameter(Mandatory, Position = 1)]
        [ref][ArrayList]$Result_list
    )
    begin {

        # Script block to add to the result ArrayList the new [PSCustomObject] for the current file
        $Add_photo_data_entry_script_block = {
            $DateInFileName = Get-DateInFileName $FullName
            $file = Get-Item $FullName 
            $new_photo_dates_obj = [PSCustomObject]@{
                FullName            = $FullName
                FolderName          = $file.Directory.Name
                Name                = $file.Name
                Extension           = $file.Extension
                Hash                = (Get-FileHash $FullName).Hash
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
            Throw "Get-PhotoDir_Data: the photo directory does not exist or is not a directory: '${photo_dir}' "
        }

        $Result_list.Value = [ArrayList]@() 

        # Base variables to store the values parsed from the output lines of ExitTool command
        $FullName = ''
        $CreateDateExif = [dateTime]::MinValue
        $DateTimeOriginal = [dateTime]::MinValue

        # ExifTool command to get the file full path, CreateDate and DateTimeOriginal for every photo file of $photo_dir
        # This is 16 times much faster than using Get-ChildItem and callin ExifTool for each file
        & exiftool -recurse -s2 -d "${DEFAULT_DATE_FORMAT_EXIFTOOL}" -CreateDate -DateTimeOriginal $photo_dir  --ext json --ext html --ext db --ext jbf --ext 'db@SynoEAStream' --ext 'jpg@SynoEAStream'  --ext 'pdf@SynoEAStream' | Foreach-Object {

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
                    $CreateDateExif = [dateTime]::MinValue
                    $DateTimeOriginal = [dateTime]::MinValue
                }
                
                # New file
                $FullName = $line.substring(9)

            }
            elseif ( $line -like 'CreateDate: *') {
                try {
                    $CreateDateExif = [dateTime]::ParseExact( $line.substring(12), ${DEFAULT_DATE_FORMAT_PWSH}, $null)
                }
                catch {
                    $CreateDateExif = [dateTime]::MinValue
                }
            }
            elseif ( $line -like 'DateTimeOriginal: *') {
                try {
                    $DateTimeOriginal = [dateTime]::ParseExact( $line.substring(18), ${DEFAULT_DATE_FORMAT_PWSH}, $null)
                }
                catch {
                    $DateTimeOriginal = [dateTime]::MinValue
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
                    $CreateDateExif = [dateTime]::MinValue
                    $DateTimeOriginal = [dateTime]::MinValue
                }
            }
        }
        Write-Verbose "... $($result_list.Value.Count) photo files."
    }
}
Write-Verbose "ok, Get-PhotoDir_Data is available."


$Is_SortPhotoDateTools_Loaded = $True