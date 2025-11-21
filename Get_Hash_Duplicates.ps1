<#
.SYNOPSIS
Compute the Hash of every file from 2 directories, then get the hash duplicates
.DESCRIPTION
Compute the Hash of every file from 2 directories, then get the hash duplicates
.EXAMPLE
$duplicates = . ./Get_Hash_Duplicates.ps1 '/home/denis/Documents/photo_sets/nostrucs/photo' '/home/denis/Documents/photo_sets/nostrucs/_ALBUMS' $true
#>
using namespace System.Collections
using namespace System.Collections.Generic
[CmdletBinding()]
    param (
        # The first directory
        [Parameter(Mandatory, Position = 0)]
        [string]$Dir1,

        # The first directory
        [Parameter(Position = 1)]
        [string]$Dir2,

        # Process the subdirectories
        [Parameter()]
        [bool]$Recurse = $true
    )

# top-level try-catch to display detailed error messages 
try {

    # Dir1
    $export_xml_file = join-path $Dir1 '.hash_export.xml'
    if ( Test-Path $export_xml_file ) {
        Write-Host "Importing Hash for files in '$Dir1'..."
        $files1 = Import-Clixml $export_xml_file
    }
    else {
        Write-Host "Computing Hash for files in '$Dir1' (recurse:${recurse})..."
        $dir_len = $Dir1.Length
        $files1 = gci -Recurse:$Recurse -file $Dir1 | Select-Object FullName, @{n='RelativeName';e={$_.FullName.Substring($dir_len)}}, @{n='Hash';e={(Get-FileHash $_).Hash}}
        $files1 | Export-Clixml $export_xml_file
    }
    Write-host " '$Dir1': $($files1.Count) computed hash"

    if ( $Dir2 ) {

        # Dir2
        $export_xml_file = join-path $Dir2 '.hash_export.xml'
        if ( Test-Path $export_xml_file ) {
            Write-Host "Importing Hash for files in '$Dir2'..."
            $files2 = Import-Clixml $export_xml_file
        }
        else {
            Write-Host "Computing Hash for files in '$Dir2' (recurse:${recurse})..."
            $dir_len = $Dir2.Length
            $files2 = gci -Recurse:$Recurse -file $Dir2 | Select-Object FullName, @{n='RelativeName';e={$_.FullName.Substring($dir_len)}}, @{n='Hash';e={(Get-FileHash $_).Hash}}
            $export_xml_file = join-path $Dir2 '.hash_export.xml'
            $files2 | Export-Clixml $export_xml_file
        }
        Write-host " '$Dir2': $($files2.Count) computed hash"

        # Compare
        Write-Host "Computing files having the same hash in both directories..."
        $result = @( compare-object $files2  $files1 -Property Hash -ExcludeDifferent -IncludeEqual -Passthru)
        Write-host "`$result = identical Hash: $($result.Count)"
    }

    write-host ""
    write-host "Then end."

}
catch {
    $err = $_
    write-host "$($err.Exception.Message)" -ForegroundColor Red

    $msg = ($err | Format-List *) | Out-String
    write-host $msg -ForegroundColor DarkRed
}
