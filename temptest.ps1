
<#
.SYNOPSIS
.DESCRIPTION
.NOTES
ExifTool by Phil Harvey (https://exiftool.org/) may be automatically installed and its directory put in the PATH environment variable.
#>
using namespace System.Collections
using namespace System.Collections.Generic

[CmdletBinding()]
param (
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Load Sort-PhotoDateTools.ps1 (dot-sourcing call allows the 'module' to be in the same directory)
. (Join-Path $PSScriptRoot "Sort-PhotoDateTools.ps1") -Verbose:$false


[List[PhotoInfo]]$photo_list = @( Get_Directory_PhotoInfo '/home/denis/Documents/photo_sets/gdegau35/photo/Takeout/Google Photos/Photos from 2018' -Recurse:$false -Compute_Hash:$false )
$photo_list.Count

[List[PhotoInfo]]$photo_list = @( Get_Directory_PhotoInfo '/home/denis/Documents/photo_sets/nostrucs/photo/2006' -Recurse:$false -Compute_Hash:$false )
$photo_list.Count

