<#
.SYNOPSIS
Calculate data from all photo data set names, calling photoset_Calculate.ps1 .

returns the $photo_list_ht hash table: the key is the data set name, the value is $photo_list, the ArrayList calculated by photo_Calculate.ps1
.EXAMPLE
. ./batch_calculate.ps1
.EXAMPLE
. ./batch_Calculate.ps1 -Force_zip_extract -Force_recalculation
#>
[CmdletBinding()]
    param (

        # Force the photo files to be re-extracted from the zip files. Implies $Force_recalculation also. (if the zip files exist, else $Force_zip_extract is ignored.)
        [switch]$Force_zip_extract,

        # Force the photo file data to be recomputed and so exported as pre-calculated data.. Do not import pre-calculated data if it exists.
        [switch]$Force_recalculation,

        # Ensure that no collision is possible when extracting .zip files, even if the same file name/path is present in several .zip files.
        # This option produces more complex directory tree (the base name of the .zip is added as the first level destination subdirectory.)
        # However, today 2025-02-10, Google TakeOut .zip files for photos do not have identical file names/paths present in multiple .zip .
        [switch]$EnsureNoCollision
    )

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$this_script_name = $MyInvocation.MyCommand.Name
Write-Verbose "${this_script_name}: Calculate data from all photo data set names, calling photoset_Calculate.ps1."

$isDotSourced = $MyInvocation.InvocationName -eq '.' -or $MyInvocation.Line -eq ''
if ( -not $isDotSourced ) {
    throw "${this_script_name} must be dot-sourced (i.e. should be called with '.  <script_path>')"
}
    
if ( -not $Is_SortPhotoDateTools_Loaded ) {
    . (Join-Path $PSScriptRoot "Sort-PhotoDateTools.ps1")
}

$photoset_name_list = ('gtest', 'gdegau35', 'gscrapcath', 'nostrucs')
Write-Verbose "`$photoset_name_list = (${photoset_name_list})"

# hastable for the photo list data of each data set
# key: the data set name: 'gtest', 'gdegau35', 'gscrapcath', 'nostrucs'
# value: $photo_list data 
$photo_list_ht = @{} 
foreach ( $photoset_name in $photoset_name_list ) {
    Write-Verbose ""
    Write-Verbose ". ./photoset_Calculate.ps1 $photoset_name -Force_zip_extract:$Force_zip_extract -Force_recalculation:$Force_recalculation"
    . ./photoset_Calculate.ps1 $photoset_name -Force_zip_extract:$Force_zip_extract -Force_recalculation:$Force_recalculation -EnsureNoCollision:$EnsureNoCollision
    $photo_list_ht[$photoset_name] = $photo_list
    Write-Verbose "`$photo_list_ht[${photoset_name}]: $($photo_list_ht[$photoset_name].Count) photos "
}

Write-Host ""
Write-Host "`$photo_list_ht : "
$photo_list_ht
