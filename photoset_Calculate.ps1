<#
.SYNOPSIS
Calculate data from a photo directory and return $photo_list, an ArrayList of data for each photo file, like FullName, Hash, CreateDateExif, DateInFileName,...
.DESCRIPTION
Calculate data from a photo directory and return $photo_list, an ArrayList of data for each photo file, like FullName, Hash, CreateDateExif, DateInFileName,...

The $photoset_name parameter is actually a subdirectory of "${Env:HOME}/Documents/photo_sets", the photo files being in "${Env:HOME}/Documents/photo_sets/${photoset_name}/photo".

Return:  A dot-sourced call must be done, so that the result is the following variables:
   [System.Collections.ArrayList]$photo_list
   $photo_list_ht[$photoset_name] = $photo_list

Main steps:

    EXTRACT STEP:
    If they exist, the zip files of "${Env:HOME}/Documents/photo_sets/${photoset_name}/zip" are extracted to the photos directory, unless it has been already done before.

    These zip files may be Google photo files, exported as .zip files using Google TakeOut. 

    CALCULATE AND EXPORT STEP:
        The data is calculated from each photo file, the result is [System.Collections.ArrayList]$photo_list.
        $photo_list is then exported to "${Env:HOME}/Documents/photo_sets/${photoset_name}/calculated_vars/photo_list.xml"

    OR 

    IMPORT STEP:
        If the data has been already calculated and exported in a previous execution, then it is imported, saving much time.
        The result is also [System.Collections.ArrayList]$photo_list
.EXAMPLE
. ./photoset_Calculate.ps1 gtest

Will calculate data for all the photos of the data set 'gtest', i.e. "${Env:HOME}/Documents/photo_sets/gtest"
The result is the variable [System.Collections.ArrayList]$photo_list
#>
using namespace System.Collections

[CmdletBinding()]
param (
    # The name of the photo data set, actually a subdirectory of "${Env:HOME}/Documents/photo_sets"
    [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
    [string]$photoset_name,

    # Force the photo files to be re-extracted from the zip files. Implies $Force_recalculation also. (if the zip files exist, else $Force_zip_extract is ignored.)
    [switch]$Force_zip_extract,

    # Force the photo file data to be re-calculated (and re-exported). Do not import pre-calculated data if it exists.
    [switch]$Force_recalculation,

    # Ensure that no collision is possible when extracting .zip files, even if the same file name/path is present in several .zip files.
    # This option produces more complex directory tree because the base name of the .zip is added as the first level destination subdirectory.
    # However, today 2025-02-10, this option is not required for Google TakeOut .zip files because they do not contain identical file names/paths in multiple zip files.
    [switch]$EnsureNoCollision
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$this_script_name = $MyInvocation.MyCommand.Name
Write-Verbose "${this_script_name}: Calculate data from a photo directory and return `$photo_list, an ArrayList of data for each photo file."

$isDotSourced = $MyInvocation.InvocationName -eq '.' -or $MyInvocation.Line -eq ''
if ( -not $isDotSourced ) {
    throw "${this_script_name} must be dot-sourced (i.e. should be called with '.  <script_path>')"
}

if ( -not $Is_SortPhotoDateTools_Loaded ) {
    . (Join-Path $PSScriptRoot "Sort-PhotoDateTools.ps1")
}

Write-Verbose "Data set name: '${photoset_name}' "


Write-Verbose ""
###### Possibly EXTRACT Google Takeout .ZIP files (skip if it is already done, or if no zip files) #############

# Photos directory: directory where are the photo files of the data set (possibly extracted from the zip directory)
# Do NOT create the Photos directory if it does not exist.
$photo_dir = get_photoset_dir $photoset_name 'photo_dir' -No_Existence_test  # Throw an exception if the data set BASE directory does not exist.(wrong data set name?)

$photo_count = Count_photo_dir $photo_dir

#  directory: directory where are the .zip files containing the photo files (possibly from exported from Google Photo with Google TakeOut)
# Do NOT create the zip directory if it does not exist.
$zip_dir = get_photoset_dir $photoset_name 'zip_dir' -No_Existence_test  # Throw an exception if the BASE directory of the data set does not exist

$zip_files = Get-ChildItem -File -Path (Join-Path $zip_dir *.zip) -ea SilentlyContinue
if ( -not $zip_files ) {
    $Force_zip_extract = $False   # no zip files: ignore -Force_zip_extract
    if ( $photo_count -eq 0 ) {
        throw "No photos and no TakeOut zip files for '${photoset_name}'."
    }
    else {
        Write-Verbose "No zip files in '${zip_dir}'."
    }
}
else {

    # Some zip files exist
    if ( $Force_zip_extract ) {
        Write-Verbose "-Force_zip_extract: zip files will be re-extracted to ${photo_dir} ..."
        $photo_count = 0
    }

    if ( ($photo_count -ne 0) ) {
        Write-Verbose "Assuming photo files have been already extracted from '${zip_dir}' to '${photo_dir}'."
    }
    else {
        
        # Empty the destination directory before extraction
        if ( Test-Path -LiteralPath $photo_dir ) {
            Write-Verbose "Deleting '${photo_dir}'..."
            Remove-Item -LiteralPath $photo_dir -Recurse -Force 1>$null
            New-Item $photo_dir -ItemType Directory 1>$null
        }
        
        Write-Verbose "Extracting zip files from '${zip_dir}' to '${photo_dir}'..."
        Foreach ( $zip_file in $zip_files ) {
            if ( $EnsureNoCollision ) {
                $dest_dir = Join-Path $photo_dir ($zip_file.BaseName)   # No collision is possible here, even if the same file path name is present in multiple .zip files
            }
            else {
                $dest_dir = $photo_dir                                  # There may be some collisions here, if the same file path name is present in multiple .zip files
            }
            Write-Verbose "  extracting from $($zip_file.Name) to ${dest_dir} ..."
            & 7zzs x "${zip_file}" -o"${dest_dir}"
            $EXIT_CODE = $LASTEXITCODE
            if ( $EXIT_CODE -ne 0 ) {
                throw "Extraction failure. Zzzs returned the exit code ${EXIT_CODE}."
            }
        }

        $photo_count = Count_photo_dir $photo_dir
        if ( $photo_count -eq 0 ) {
            throw "ERROR: no photo files extracted from zip files of '${zip_dir}'."
        }

        if ( $Force_zip_extract ) {
            Write-Verbose "-Force_zip_extract and zip files were actually re-extracted, so it implies -Force_recalculation "
            $Force_recalculation = $True
        }
    }
}


Write-Verbose ""
############# CALCULATE and export OR IMPORT pre-calculated data : $photo_list, ? #################
# Calculate the data and then export it?    
# ... or import the pre-calculated data that was calculated and exported in a prevous execution, to save time?

# calculated_dir: Directory for exporting variables, to avoid recalculating.
# Create this directory if needed, unless the data set base directory does not exist: in this case throw an exception.
$calculated_dir = get_photoset_dir $photoset_name 'calculated_dir'    # Throw an exception if the BASE directory of the data set does not exist


############ $photo_list ################
$export_file_name = 'photo_list.xml'
$exportClixml_photo_list_file = Join-Path $calculated_dir $export_file_name

$Do_calculate = $True   # Initially, the data is considered as to be calculated and to be then exported (so, not imported from a previous execution)

if ( $Force_recalculation ) {
    Write-Verbose "-Force_recalculation: `$photo_list will be re-calculated."
}
else {
    if ( -not (Test-Path $exportClixml_photo_list_file -PathType Leaf) ) {
        Write-Verbose "The import data file does not exist: data will be calculated and exported."
    }
    else {
        try {
            
            # Import from previous execution to save time
            [ArrayList]$photo_list = Import_Clixml_CalculatedData $photoset_name $export_file_name
            if ( $photo_list.Count -ne $photo_count ) {
                Write-Verbose "The imported photo count is not equal to the number of photos in the source directory"
                throw "The imported photo count is not equal to the number of photos in the source directory"
            }
            $Do_calculate = $False   # The data has already been calculated and exported before. Now it is imported and won't be re-calculated
        }
        catch {
            Write-Verbose "Import error: data will be re-calculated and re-exported."
        }
    }
}

if ( $Do_calculate ) {

    # Calculate photo file data
    Write-Verbose "Calculating `$photo_list = data for the ${photo_count} photo/video files...' "
    ### old ### $photo_list = [ArrayList]@()
    ### old ### Get_PhotoDir_Data $photo_dir ([ref]$photo_list)

    # Get [PhotoInfo] objects for all photo files in a photo directory.
    [List[PhotoInfo]]$photo_list = Get_Directory_PhotoInfo $photo_dir  -Recurse:$true -Compute_Hash:$true

    # Export photo file data, to save time for subsequent executions when data will be imported and not calculated again
    Export_Clixml_CalculatedData $photoset_name $export_file_name ([ref]$photo_list)

    # update the hash table photo_list_ht
    Write-Verbose "Update the hash table : `$photo_list_ht[`$photoset_name] = `$photo_list"
    if ( -not (Test-Path Variable:photo_list_ht) ) {
        $photo_list_ht = @{} 
    }
    $photo_list_ht[$photoset_name] = $photo_list
}

Write-Verbose "Result: [System.Collections.ArrayList]`$photo_list"
Write-Verbose " `$photo_list.count = $($photo_list.count) "

#}
#catch {
#    Write-Error "ERROR in photoset_Calculate.ps1: $($_| Format-List * | Out-String)"
#    [ArrayList]$photo_list = @()
#}
