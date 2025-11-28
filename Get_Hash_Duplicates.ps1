<#
.SYNOPSIS
Calculate the hash of each photo file in two directories, retrieve the duplicate hashes between the two directories, then request that they be deleted from the second directory.
If only one directory argument then compute the hash fo its photo files and return the duplicates by subfolders list where they are.
.DESCRIPTION
With two directory arguments, $Dir1 and $Dir2:
- Get the hash of every photo file in $Dir1 and $Dir2
- if -Only_Hash argument: then return the [HashInfo] list for the files in $Dir1 and Dir2, then exit.
- if NO -Only_Hash argument:
- Get the photo files from $Dir2 having the same hash than a file in $Dir1
- Ask the user to delete them from $Dir2
- Return the [HashInfo] list of the photo files from $Dir2 having the same hash than a file in $Dir1 (they were deleed or not, depending on the user answer)

With one directory arguments, $Dir1:
- Get the hash of every photo file from $Dir1
- if -Only_Hash argument: then return the [HashInfo] list for the files in $Dir1, then exit.
- if NO -Only_Hash argument:
- Return the duplicates by the subfolder list where they are. Ex:  "42 subfolder1,subfolder2" means there are 42 hash duplicates between subfolder1 and subfolder2

For the first call for a directory, the [HashInfo] list is computed and exported (Export-Clixml) with Export-Clixml, as a '.photo_hash.Cli.xml' file in this directory (-Recurse: '.photo_hash_recurse.Cli.xml').
For the next calls for the same directory, the [HashInfo] list is not computed, it is directly imported (Import-Clixml), unless the content of the directory was changed.
For more details, see the function Get_Directory_Photo_Hash_Export of Sort-PhotoDateTools.ps1 .

.EXAMPLE
$duplicates = ./Get_Hash_Duplicates.ps1 '/home/denis/Documents/photo_sets/nostrucs/photo' '/home/denis/Documents/photo_sets/gdegau35/photo/Takeout/Google Photos' -Recurse
.EXAMPLE
$folder_with_duplicates = ./Get_Hash_Duplicates.ps1 '/home/denis/Documents/photo_sets/gdegau35/photo/Takeout/Google Photos' -Recurse
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
        [switch]$Recurse,

        # Get only the [HashInfo], do not search for duplicate hashes
        [switch]$Only_Hash
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


# Check Dir1
$file_o = Get-Item $Dir1
if ( $file_o -isnot [System.IO.DirectoryInfo] ) {
    throw "This directory does not exist: '${Dir1}'"
}
$Dir1 = $file_o.FullName

if ( $Dir2 ) {
    # Check Dir2
    $file_o = Get-Item $Dir2
    if ( $file_o -isnot [System.IO.DirectoryInfo] ) {
        throw "This directory does not exist: '${Dir2}'"
    }
    $Dir2 = $file_o.FullName

    if ( $Dir1 -eq $Dir2 ) {
        Throw "Same Directory argument provided twice."
    }
}

# Get [HashInfo] list for $Dir1
[List[HashInfo]]$dir1_hashinfo_list = @( Get_Directory_Photo_Hash_Export $Dir1 -Recurse:${Recurse} )
Out normal " '$Dir1': $($dir1_hashinfo_list.Count) computed hash"

if ( -not $Dir2 ) {

    if ( $Only_Hash ) {
        # Only $Dir1 directory argument and -Only_Hash argument: return the [HashInfo] list
        return $dir1_hashinfo_list
    }

    # Only $Dir1 directory argument (and no -Only_Hash argument): return the duplicates by subfolders list where they are

    # Add Subfolder and Name to the hash info list
    [List[System.Object]]$hashinfo_b_list = $dir1_hashinfo_list | select-object Hash, RelativePath, @{n='Subfolder'; e={($_.RelativePath -split '/')[1]}}, @{n='Name'; e={($_.RelativePath -split '/')[2]}}

    # Get the has duplicates
    $hash_group_list = $hashinfo_b_list | group-object Hash | Where-Object { $_.Count -ge 2 }

    # Group the duplicates by the subfolder list where they are. Ex:  "42 subfolder1,subfolder2" means there are 42 hash duplicates between subfolder1 and subfolder2
    $folder_with_duplicates = $hash_group_list | ForEach-Object { ($_.group.Subfolder | Sort-Object) -join ',' } | Group-Object | sort-object Name

    return $folder_with_duplicates

}
else {

    # $Dir1 and $Dir2 directory arguments: return the duplicates between the two directories
    
    # Check Dir2
    $file_o = Get-Item $Dir2
    if ( $file_o -isnot [System.IO.DirectoryInfo] ) {
        throw "This directory does not exist: '${Dir2}'"
    }
    $Dir2 = $file_o.FullName

    # Get [HashInfo] list for $Dir2
    [List[HashInfo]]$dir2_hashinfo_list = @( Get_Directory_Photo_Hash_Export $Dir2 -Recurse:${Recurse} )
    Out normal " '$Dir2': $($dir2_hashinfo_list.Count) computed hash"

    if ( $Only_Hash ) {
         # $Dir1 and $Dir2 directory arguments and -Only_Hash argument: return the [HashInfo] list of both directories
        $dir1_hashinfo_list
        return $dir2_hashinfo_list
    }

    # $Dir1 and $Dir2 directory arguments (and no -Only_Hash argument): return the duplicates between the two directories

    # Get files from $Dir2 having a Hash already existing in $Dir1 (Compare-Object does not work here because the same hash value appears multiple times.)
    Out normal -NoNewLine "Searching files from `"${Dir2}`" having a Hash existing in `"${Dir1}`"... " -Highlight_Text $Dir2
    $dir1_hash_hashset = [HashSet[string]]::new()
    $dir1_hashinfo_list.Hash | ForEach-Object { $null = $dir1_hash_hashset.Add($_) }
    [List[HashInfo]]$dir2_same_hash_hashinfo_list = @( $dir2_hashinfo_list | Where-Object { $dir1_hash_hashset.Contains($_.Hash) } )
    Out normal ": $($dir2_same_hash_hashinfo_list.Count)"

    # Delete files in $Dir2 having the same hash than a file in $Dir1?
    if ( $dir2_same_hash_hashinfo_list.Count -ne 0 ) {

        # Display the files from $Dir2 having the same hash than a file in $Dir1
        Out normal ''
        Out normal "Files from `"${Dir2}`" having the same hash than a file in `"${Dir1}`":"
        $dir2_same_hash_hashinfo_list.RelativePath | Out normal
        
        # User input: Confirm deleting files in $Dir2 having the same hash than a file in $Dir1?
        $input_default = 'n'
        Do {
            Out normal -NoNewLine "Confirm to delete the above $($dir2_same_hash_hashinfo_list.Count) files from `"${Dir2}`" having the same hash than a file in `"${Dir1}`" [y/n(default)]: " -Highlight_Text $Dir2
            $user_input = Read-Host
            if (-not $user_input ) { $user_input = $input_default }
        } Until ( $user_input -in ('y','n') ) 

        if ( $user_input -eq 'n' ) {
            Out normal "The user chose not to delete the files."
        }
        else {
            # Delete the files from Dir2
            $dir2_same_hash_hashinfo_list.RelativePath | ForEach-Object {
                $file_fullname = Join-Path $Dir2 $_
                Out normal -NoNewLine "Deleting `"${file_fullname}`"... " -Highlight_Text ${file_fullname}
                Remove-Item $file_fullname -ErrorAction Stop
                Out normal "Done."
            }
        }

    }

    # Return the files from $Dir2 having a Hash already existing in $Dir1 
    Return $dir2_same_hash_hashinfo_list

}

Out normal ""
Out normal "END OK."

}
catch {
    $err = $_
    write-host "$($err.Exception.Message)" -ForegroundColor Red

    $msg = ($err | Format-List *) | Out-String
    write-host $msg -ForegroundColor DarkRed
}
