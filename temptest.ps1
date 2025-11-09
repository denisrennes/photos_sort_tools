
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

Out normal 'ceci est un test.'

Out normal 'ceci est un test.' -Highlight_Text 'est'

$color_list = ('Black','DarkGray','Cyan','Blue','DarkBlue','DarkCyan','Green','DarkGreen','Red','DarkRed','DarkMagenta','DarkYellow','Gray','White','Magenta','Yellow')

foreach ( $color in $color_list ) {
    write-host "${color}, " -ForegroundColor $color -NoNewline
}

