<#
.SYNOPSIS
Analyse a photo data set. 
.DESCRIPTION
the $photo_list_ht hash table: the key is the data set name, the value is $photo_list, the ArrayList calculated by photo_calculate.ps1
The $photoset_name parameter is actually the key the $photo_list_ht hash table: the value is $photo_list, the ArrayList calculated by photo_Calculate.ps1

.EXAMPLE
. ./photoset_Analysis.ps1 gtest

This will set many result variables.
#>
[CmdletBinding()]
    param (
        # The name of the photo data set, actually the key for the hash table 
        [Parameter(Mandatory, Position = 0)]
        [string]$photoset_name 

    )

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$this_script_name = $MyInvocation.MyCommand.Name
Write-Verbose "${this_script_name}: Analyse a photo data set. "

$isDotSourced = $MyInvocation.InvocationName -eq '.' -or $MyInvocation.Line -eq ''
if ( -not $isDotSourced ) {
    throw "${this_script_name} must be dot-sourced (i.e. should be called with '.  <script_path>')"
}
    
if ( -not $Is_SortPhotoDateTools_Loaded ) {
    . (Join-Path $PSScriptRoot "Sort-PhotoDateTools.ps1")
}

# Check the $photoset_name argument:
# Photos directory: directory where are the photo files of the data set (possibly extracted from the zip directory)
# Do NOT create the Photos directory if it does not exist.
# Throw an exception if the data set BASE directory does not exist.(wrong data set name?)
$photo_dir = get_photoset_dir $photoset_name 'photo_dir' -No_Existence_test  

. (Join-Path $PSScriptRoot "photoset_Calculate.ps1") $photoset_name

Write-Verbose " `$photo_list.count = $($photo_list.count) "
if ( $photo_list.count -eq 0 ) {
    Throw "`$photo_list is empty."
}


############# ANALYSE #################


Write-Verbose ""
Write-Verbose "Data set ${photoset_name}: "


Write-Verbose "`$name_groups = list of unique file names (Group-Object)...' "
$name_groups = $photo_list | Group-Object -Property Name
Write-Verbose "   `$name_groups.count = $($name_groups.count) "

Write-Verbose "`$name_multiple_hash = list of the files having the same Name but different Hash...' "
$name_multiple_hash = $name_groups | ? { (($_.Group | select Hash -unique).count) -ge 2 }
Write-Verbose "   `$name_mu_listltiple_hash.count = $($name_multiple_hash.count) "

Write-Verbose "`$hash_groups = list of unique Hash values (Group-Object)...' "
$hash_groups = $photo_list | Group-Object -Property Hash
Write-Verbose "  `$hash_groups.count = $($hash_groups.count) "

Write-Verbose "`$hash_multiple_name = list of the files having the same Hash but different Names...' "
$hash_multiple_name = $hash_groups | ? { (($_.Group | select Name -unique).count) -ge 2 }
Write-Verbose "  `$hash_multiple_name.count = $($hash_multiple_name.count) "

Write-Verbose "`$untitled_photo_name_list = list of unique photo file names in '*Untitled*' or '*Sans titre*' subfolders...' "
$untitled_photo_name_list = $photo_list | Where-Object { ($_.FullName -like '*Untitled*') -or ($_.FullName -like '*Sans titre*') } | select -unique -ExpandProperty Name
Write-Verbose "  `$untitled_photo_name_list.count = $($untitled_photo_name_list.count) "

Write-Verbose "`$no_createdate_but_DateInFileName_list = list of photos files without CreateTagExif BUT with a valid DateInFileName...' "
$no_createdate_but_DateInFileName_list = $photo_list | ? { ($_.CreateDateExif -eq [DateTime]::MinValue) -and ($_.DateInFileName -ne [DateTime]::MinValue) }
Write-Verbose "  `$no_createdate_but_DateInFileName_list.count = $($no_createdate_but_DateInFileName_list.count) "

Write-Verbose "`$no_date_list = list of photos files without CreateTag or DateInFileName...' "
$no_date_list = $photo_list | ? { ($_.CreateDateExif -eq [DateTime]::MinValue) -and ($_.DateInFileName -eq [DateTime]::MinValue) }
Write-Verbose "  `$no_date_list.count = $($no_date_list.count) "

Write-Verbose "File Count by Extension + Is_Writable_By_ExifTool: "
$extension_groups = $photo_list | Group-Object -Property Extension -NoElement | Sort-Object -Property Count -Descending
$extension_groups | Select-Object Count,Name,@{l='ExifTool_writable';e={Is_Writable_By_ExifTool($_.Name)}} | ft -auto *

#Write-Verbose "File Count by FolderName: "
#$extension_groups = $photo_list | Group-Object -Property FolderName -NoElement
#$extension_groups | Select-Object Count,Name | ft -auto *
