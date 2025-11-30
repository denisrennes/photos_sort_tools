<#
.SYNOPSIS
Move the photo files of a directory, based on their date-normalized file name, to the date-normalized folders <Destination_Parent_Directory>/YYYY/YYYY-MM
.DESCRIPTION
Move the photo files of a directory, based on their date-normalized file name, to the date-normalized folders <Destination_Parent_Directory>/YYYY/YYYY-MM

Only the date-normalized photo files will be moved.

If <Destination_Parent_Directory> is not provided as argument then it is the '../Photos' sibling of the photos files directory

.NOTES
ExifTool by Phil Harvey (https://exiftool.org/) may be automatically installed and its directory put in the PATH environment variable.
.EXAMPLE
If the photo file names in '/home/denis/Documents/photo_sets/gdegau35/photo/Takeout/Google Photos/Photos from 2006' are date-normalized, then this command will move them to 
'/home/denis/Documents/photo_sets/gdegau35/photo/Takeout/Google Photos/Photos/2006/2066-01', '.../2006/2006-02', '.../2006/2006-04' and '.../2006/2006-05' :

move_normalized.ps1 '/home/denis/Documents/photo_sets/gdegau35/photo/Takeout/Google Photos/Photos from 2006'
#>
using namespace System.Collections
using namespace System.Collections.Generic
[CmdletBinding()]
    param (
        # The date-normalized photo files to be moved. All files must belong to the same Directory.
        # The list can be provided as a single comma-separated string to handle Nemo file manager actions with multiple selections.
        # A single directory can also be given: its date-normalized contained files will be processed
        [Parameter(Mandatory, Position = 0)]
        [string[]]$Photo_File_List,

        # Destination parent directy. If not given then it will be the '../Photos/' sibling of the photos files directory
        [Parameter(Position = 1)]
        [string]$Destination_Parent_Directory

    )

# top-level try-catch to display detailed error messages 
try {


Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'


function New_Destination_Directory {
<#
.SYNOPSIS
Compute the new directory path where to move the photo file, based on its date-normalized name and the destination parent directory.
.DESCRIPTION
Compute the new directory path where to move the photo file, based on its date-normalized name and the destination parent directory.

return: The new destination directory 
.EXAMPLE
$new_dest_dir = New_Destination_Directory $photo_info '/home/denis/Documents/photo_sets/gdegau35/photo/Takeout/Google Photos/Photos'

$photo_info is the [PhotoInfo] object for '/home/denis/Documents/photo_sets/gdegau35/photo/Takeout/Google Photos/Photos from 2006/2006-01-07_16-36-02.jpg'

This will return '/home/denis/Documents/photo_sets/gdegau35/photo/Takeout/Google Photos/Photos/2006/2006-01'

#>
[CmdletBinding()]
    param (
        # The photo file to move, based on its date-normalized file name.
        [Parameter(Mandatory, Position = 0)]
        [PhotoInfo]$Photo_Info,

        # The destination parent directory where to move the file (into './yyyy/yyyy-MM/' )
        [Parameter(Mandatory, Position =1)]
        [string]$Destination_Parent_Directory

    )

    [DateTime]$date_in_filename = Get_DateInFileName $Photo_Info.FullName
    $new_dest_dir = Join-Path $Destination_Parent_Directory $date_in_filename.ToString('yyyy/yyyy-MM')

    return $new_dest_dir
}



function Compute_Planned_Move {
<#
.SYNOPSIS
Compute the skip or move status of a photo file.
.DESCRIPTION
Compute the skip or move status of a photo file, based on its [PhotoInfo], the reference property name and the $Force_Already_Normalized argument.

return:
    ' skip: not Date-normalized'    ==> Do not move because the file name is not date-normalized
    ' skip: already exists'         ==> Do not move because the file name already exists into the destination directory
    'TO MOVE'                       ==> Move the file, based on its date-normalized name
#>
[CmdletBinding()]
    param (
        # The photo file to move, based on its date-normalized file name.
        [Parameter(Mandatory, Position = 0)]
        [PhotoInfo]$Photo_Info,

        # The destination parent directory where to move the file (into './yyyy/yyyy-MM/' )
        [Parameter(Mandatory, Position =1)]
        [string]$Destination_Parent_Directory

    )

    # If not date-normalized then it will not be moved
    if ( -not (Is_DateNormalized_FileName $Photo_Info.FullName) ) {
        return ' skip: not Date-normalized'
    }
    else {
        $new_dest_path = Join-Path (New_Destination_Directory $Photo_Info $Destination_Parent_Directory) $Photo_Info.Name

        if ( Test-Path $new_dest_path ) {
            return ' skip: already exists'
        }
        else {
            return 'TO MOVE'
        }
    }

}


# Load Sort-PhotoDateTools.ps1 (dot-sourcing call allows the 'module' to be in the same directory)
if ( (-not (Test-Path variable:Is_SortPhotoDateTools_Loaded)) -or (-not $Is_SortPhotoDateTools_Loaded) ) {
    . (Join-Path $PSScriptRoot "Sort-PhotoDateTools.ps1")
}

# Check the argument $Photo_File_List

# The list can be provided as a single semicolon-separated string to handle Nemo file manager actions with multiple selections.
if ( $Photo_File_List.Count -eq 1 ) {
    $Photo_File_List = $Photo_File_List -split ';'
}

# If this is a single directory argument, then get [PhotoInfo] objects for its files
$PhotoInfo_List = $null
if ( $Photo_File_List.Count -eq 1 ) {
    $directory = $Photo_File_List[0]
    try { $file = Get-Item $directory -ErrorAction Stop }
    catch { throw "This file does not exist: '${directory}'" }
    if ( $file -is [System.IO.DirectoryInfo] ) {

        # One single directory: get [PhotoInfo] objects for its files. Non-photo file extensions and directories are excluded.
        [List[PhotoInfo]]$PhotoInfo_List = @( Get_Directory_PhotoInfo $directory -Recurse:$false -Compute_Hash:$false | Sort-Object -Property Name )
    }
}

if ( $null -eq $PhotoInfo_List ) {

    # NOT a single directory, so list of files: get [PhotoInfo] objects for them. Non-photo file extensions and directories are excluded.
    [List[PhotoInfo]]$PhotoInfo_List = @( Get_Files_PhotoInfo $Photo_File_List -Compute_Hash:$false | Sort-Object -Property Name )

    # All photo files must belong to the same directory
    $dir_list = @( $PhotoInfo_List | Group-Object Directory -NoElement )
    if ( $dir_list.Count -ge 2 ) {
        throw "All the files must belong to the same directory."
    }
}

if ( $PhotoInfo_List.count -eq 0 ) {
    throw "No photo files."
}


# Source directory: the photo files parent Directory (all belong to the same directory)
$source_directory = $PhotoInfo_List[0].Directory


# Destination parent directory: provided as argument or the '../Photo' sibling of the photo files parent Directory
if ( $Destination_Parent_Directory ) {
    # the destination parent directory is given as argument
    $dest_parent_dir = $Destination_Parent_Directory
}
else {
    # the destination parent directory is not given as argument: default is the '../Photo' sibling of the photo files parent Directory
    $dest_parent_dir = [system.IO.Path]::GetFullPath( '../Photos', $source_directory )
}
if ( -not (test-Path $dest_parent_dir -PathType Container) ) {
    
    # user input: Confirm the creation of the destination directory? y/n
    Do {
        $input_default = 'n'
        Out normal -NoNewLine "Confirm to create the destination directory '${dest_parent_dir}'? [y/n(default)]: " -Highlight_Text $dest_parent_dir
        $user_input = Read-Host
        if (-not $user_input ) { $user_input = $input_default }
    } Until ( $user_input -in ('y','n') ) 

    if ( $user_input -eq 'n' ) {
        # End/Exit
        Out warning "Canceled by the user."
        return
    }
    else {
        $null = New-Item -Type Directory $dest_parent_dir -ErrorAction Stop
        Out normal "ok, the destination directory has been created: '${dest_parent_dir}'" -Highlight_Text $dest_parent_dir
    }

}


# Display the file data, confirm moving or End/exit
  
Out normal ''

# Display the list of the photo files data, sorted by Directory and Name: dates are displayed compared to the reference date property
Out normal ''
Out normal "${source_directory}:"

$ref_date_prop = 'DateInFileName'
$formatted_table = $PhotoInfo_List | 
    Select-Object   Name, 
                    @{ Name='CreateDateExif';   Expression={ date_diff_ref_tostring $_.CreateDateExif   ($ref_date_prop -eq 'CreateDateExif')    ($ref_date_prop ? $_.$ref_date_prop : $null) } },
                    @{ Name='DateTimeOriginal'; Expression={ date_diff_ref_tostring $_.DateTimeOriginal ($ref_date_prop -eq 'DateTimeOriginal')  ($ref_date_prop ? $_.$ref_date_prop : $null) } },
                    @{ Name='DateInFileName';   Expression={ date_diff_ref_tostring $_.DateInFileName   ($ref_date_prop -eq 'DateInFileName')    ($ref_date_prop ? $_.$ref_date_prop : $null) } },
                    @{ Name='LastWriteTime';    Expression={ date_diff_ref_tostring $_.LastWriteTime    ($ref_date_prop -eq 'LastWriteTime')     ($ref_date_prop ? $_.$ref_date_prop : $null) } },
                    CamModel,
                    @{ Name='MOVE_Or_Skip';   Expression={ Compute_Planned_Move $_ $dest_parent_dir } }
    | Format-Table -AutoSize | Out-String -Stream 
    
$formatted_table[0..2] | Out normal -Highlight_Text $ref_date_prop
$formatted_table[3..($formatted_table.Count -1)] | Out normal -Highlight_Text 'TO MOVE'

# user input: Confirm? y/n
Do {
    $input_default = 'n'
    Out normal -NoNewLine "Confirm to move the files to '${dest_parent_dir}/yyyy/yyyy-MM'? [y/n(default)]: " -Highlight_Text $dest_parent_dir
    $user_input = Read-Host
    if (-not $user_input ) { $user_input = $input_default }
} Until ( $user_input -in ('y','n') ) 

if ( $user_input -eq 'n' ) {
    # End/Exit
    Out warning "Canceled by the user."
    return
}
        
# Move the files
Out normal
Out normal "Moving the files to '${dest_parent_dir}/yyyy/yyyy-MM' ..." -Highlight_Text $dest_parent_dir


$number_moved_success = 0           # Number of successfully moved files
$number_moved_error = 0             # Number of failed file moving
$number_skip_not_normalized = 0     # Number of files not moved because their names were not date-normalized
$number_skip_already_exist = 0      # Number of files not moved because they already exist in destination

:Loop_File_Moving Foreach ( $photoinfo in $PhotoInfo_List ) {

    $file_full_name = $photoinfo.FullName
    $file_name = $photoinfo.Name

    # If not date-normalized then it will not be moved
    if ( -not (Is_DateNormalized_FileName $file_full_name) ) {
        $number_skip_not_normalized += 1
        continue :Loop_File_Moving
    }
    else {
        $new_dest_dir = New_Destination_Directory $photoinfo $dest_parent_dir
        if ( -not (Test-Path -PathType Container $new_dest_dir) ) {
            $null = New-Item -ItemType Directory $new_dest_dir -ErrorAction Stop
        }

        if ( Test-Path (Join-Path $new_dest_dir $file_name) ) {
            $number_skip_already_exist += 1
            continue :Loop_File_Moving
        }
        else {

            # Move the file
            try { 
                Move-Item $file_full_name -Destination $new_dest_dir -ErrorAction Stop
                Out success "ok: '${file_name}' was successfully moved to '${new_dest_dir}'"
                $number_moved_success += 1
            }
            catch {
                $err = $_
                $err_message = "ERROR trying to move '${file_name}' to '${new_dest_dir}':"
                $err_message += "${NL}[$($err.Exception.Message)]" 
                Out error $err_message
                $number_moved_error += 1
            }

        }
    }

}

Out normal   ''
Out normal   '===== Renaming results ====='
Out normal   ("{0,4} files were selected" -f $PhotoInfo_List.Count)
Out success  ("{0,4} files were successfully moved" -f $number_moved_success)
if ( $number_skip_not_normalized -ne 0) {
    Out success  ("{0,4} files were not moved because their name was not date-normalized" -f $number_skip_not_normalized) -Highlight_Text 'not date-normalized'
}
if ( $number_skip_already_exist -ne 0) {
    Out warning  ("{0,4} files were not moved because their name already exist in their destination directory" -f $number_skip_already_exist)
}
if ( $number_moved_error -ne 0) {
    Out error  ("{0,4} files failed to be moved due to some error" -f $number_moved_error)
}



# top-level try-catch to display detailed error messages 
}
catch {
    $err = $_
    write-host "$($err.Exception.Message)" -ForegroundColor Red

    $msg = ($err | Format-List *) | Out-String
    write-host $msg -ForegroundColor DarkRed
}
