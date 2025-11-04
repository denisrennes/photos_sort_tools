<#
.SYNOPSIS
Rename files with a lowercase extension.
.DESCRIPTION
Rename files with a lowercase extension.

Some photo files thus become compliant with the normalized date-based file name model without changing their base name.
This is because the date-normalized filename pattern is  "YYYY-MM-dd_HH-mm-ss[-n].<ext>", with .<ext> in lowercase.

.NOTES
ExifTool by Phil Harvey (https://exiftool.org/) may be automatically installed and its directory put in the PATH environment variable.
.EXAMPLE
ren_normalized.ps1 '/home/denis/Documents/photo_sets/nostrucs/photo/2006/2006-04 Pâque + Ilan'
#>
using namespace System.Collections
using namespace System.Collections.Generic
[CmdletBinding()]
    param (
        # The directory to scan, where are the photo files
        [Parameter(Mandatory, Position = 0)]
        [string]$Directory,

        # Process the subdirectories
        [Parameter(Mandatory)]
        [switch]$Recurse
    )

# top-level try-catch to display detailed error messages 
try {

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Load Sort-PhotoDateTools.ps1 (dot-sourcing call allows the 'module' to be in the same directory)
if ( (-not (Test-Path variable:Is_SortPhotoDateTools_Loaded)) -or (-not $Is_SortPhotoDateTools_Loaded) ) {
    . (Join-Path $PSScriptRoot "Sort-PhotoDateTools.ps1")
}

# Check the directory existence
$Dir_o = Get-Item $Directory
if ( $Dir_o -isnot [System.IO.DirectoryInfo] ) {
    throw "Not a directory: '${Directory}'"
}
$Directory = $Dir_o.FullName

if ( $Recurse ) {
    Out normal "Scanning the directory '${Directory}' and its subdirectories for non-lowercase file name extensions..."
}
else {
    Out normal "Scanning the directory '${Directory}', NOT its subdirectories, for non-lowercase file name extensions..."
}

# Files having a non-lowercase extension
$file_to_rename_list = @( Get-ChildItem -File -Recurse:${Recurse} -LiteralPath $Directory | Where-Object { $_.Extension -cne $_.Extension.ToLower()} )

# End here if no file is to be renamed: all extensions already are lowercase
if ( $file_to_rename_list.Count -eq 0 ) {
    Out success "ok all files already have a lowercase extension."
    return
}

# Display the non-lowercase extensions with their file count 
Out normal 
Out normal  "Number of files to be renamed with lowercase extension:"
$file_to_rename_list | Group-Object Extension | Select-Object @{n='Extension';e={$_.Name}}, Count | Out-String | Out normal 

# User input to confirm renaming
Do {
    $user_input = Read-Host "Confirm to rename with lowercase extension? (y/n)"
} Until ( $user_input -in ('y','n') ) 

# End here if the user canceled
if ( $user_input -eq 'n' ) {
    Out warning "Canceled by the user."
    return
}

# Rename
Out normal "Renaming..."
foreach ($file in $file_to_rename_list ) {
    $new_name = $file.BaseName + $file.Extension.ToLower()
    try { 
        Rename-Item $file -NewName $new_name -ErrorAction Stop 
    }
    catch {
        $exception = $_
        if (Test-Path (Join-Path $file.Directory $new_name)) {
            Out error "Failed to rename '$($file.FullName)' because a file named '${new_name}' already exists."
        }
        else {
            Out error "Failed to rename '$($file.FullName)':"
            Out error (($exception|Format-List *) | Out-String)
        }
    }
}

# Check the result: any file still having a non-lowercase extension?
$file_to_rename_list = @( Get-ChildItem -File -Recurse:${Recurse} -LiteralPath $Directory | Where-Object { $_.Extension -cne $_.Extension.ToLower()} )

# End here if no file is to be renamed: all extensions already are lowercase
if ( $file_to_rename_list.Count -eq 0 ) {
    Out success "ok all files now have a lowercase extension."
    return
}

Out error "Some files could not be renamed:"
$file_to_rename_list | Group-Object Extension | Select-Object @{n='Extension';e={$_.Name}}, Count | Out-String | Out error

Return



# top-level try-catch to display detailed error messages 
}
catch {
    $err = $_
    write-host "$($err.Exception.Message)" -ForegroundColor Red

    $msg = ($err | Format-List *) | Out-String
    write-host $msg -ForegroundColor DarkRed
}
