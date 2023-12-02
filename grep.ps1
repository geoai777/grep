[string]$version = '1.0'
[string]$app_name = "Grep emulator for powershell"

function parseArguments {
    # parse arguments array
    # 1. filter out single char arguments
    # 2. filter out dual dash arguments
    # 3. filter out single dash multichar arguments and expand into list of single char arguments
    Param(
        [Parameter(Mandatory=$true)][array]$array
    )
    [array]$ret_arg = @()

    # special case for arguments that have numeric value
    if ($array.Contains('-m')){

        [int]$item_index = [array]::IndexOf($array, '-m')
        $ret_arg += "$($array[$item_index])=$($array[$item_index + 1])"
        $array = array_pop -array $array -to_remove $array[$item_index..($item_index + 1)]

    }
    
    # filter out mixed "-abc" type arguments
    # remove from initial array
    [String]$mixed_args = "^-[a-zA-Z]{2,16}"
    $mixed_arguments = $array | Where-Object {$_ -match $mixed_args}
    if ($mixed_arguments.Count -gt 0) {
        $array = $array | Where-Object {$_ -notmatch $mixed_args}

        [array]$argument_letters = $mixed_arguments.trimStart("-").toCharArray() | Sort-Object | Get-Unique

        $argument_letters = $argument_letters | Sort-Object | Get-Unique
        foreach($letter in $argument_letters){
            $ret_arg += "-$letter"
        }
    }

    # filter out "-C" and "--command" type arguments
    # remove from inital array to leave only pattern and filenames
    [String]$simple_args = "^-[a-zA-Z]?$|^--\w{1,16}$"
    $ret_arg += $array | Where-Object {$_ -match $simple_args}
    $array = $array | Where-Object {$_ -notmatch $simple_args}

    [hashtable]$ret = @{
        arg = ($ret_arg | Sort-Object | Get-Unique);
        pa_fi = $array;
    }

    return $ret
}

function array_pop{
    # remove elements from array
    Param(
        [Parameter(Mandatory=$true)][array]$array,
        [Parameter(Mandatory=$true)][array]$to_remove
    )
    
    [System.Collections.ArrayList]$temp = $array
    foreach($remove_me in $to_remove){
        $temp.Remove($remove_me)
    }
    return $temp
}

function testArgs{
    # test $run_args array to have arguments specified in $arg_list array
    Param(
        [Parameter(Mandatory=$true)][array]$arg_list,
        [Parameter(Mandatory=$false)][array]$arguments = $run_flags
    )
    foreach($this_argument in $arg_list){

        if ($arguments.Contains($this_argument)) {
                    return $true
        }

    }
    return $false
}

function loadRunner{
    # allow safe execution of code
    Param(
        [Parameter(Mandatory=$true)][string]$command,
        [Parameter(Mandatory=$false)][string[]]$allowed_commands = @(
            "Get-ChildItem", 
            "Select-String",
            "Where-Object",
            "Get-Member"
        ),
        [Parameter(Mandatory=$false)][string[]]$allowed_variables
    )

    try {
        $program = [scriptblock]::Create($command)
        $program.CheckRestrictedLanguage(
            $allowed_commands,
            $allowed_variables,
            $false
        )
        
        return (& $program)
    } catch {
        Write-Warning $_.Exception.Message
    }


}

function filter_files{
    Param(
        [Parameter(Mandatory=$true)][array]$array
    )
    [array]$ret = @()
    [string]$full_name = ''

    foreach($item in $array){
        $full_name = $item.FullName

        if (Test-Path -Path $full_name -PathType leaf){
            $ret += $full_name
        }
        Remove-Variable full_name
    }
    
    return $ret
}

function printAmount{
    # print specified amount of lines
    Param(
        [Parameter(Mandatory=$true)][array]$array,
        [Parameter(Mandatory=$false)][int]$print_amount = 0,
        [Parameter(Mandatory=$false)][bool]$line_number = $false,
        [Parameter(Mandatory=$false)][bool]$file_name = $false
    )

    if ($array.Count -le 0) { 
        Write-Warning "[printAmount] Array is empty, nothing to print"
        return 
    }
    # if no amount specified, print everything. If amount is greater than array size, print everything.
    if (($print_amount -le 0) -or ($print_amount -gt $array.Count)) { $print_amount = $array.Count }
    
    # for performance sake we do if outside loop
    if ($line_number -and $file_name) {

        for($counter = 0; $counter -lt $print_amount; $counter++){
            Write-Host $array[$counter]
        }
    } elseif ($line_number) {

        for($counter = 0; $counter -lt $print_amount; $counter++){
            Write-Host "$($array[$counter].LineNumber):$($array[$counter].Line)"
        }

    } elseif ($file_name) {

        for($counter = 0; $counter -lt $print_amount; $counter++){
            Write-Host "$($array[$counter].FileName):$($array[$counter].Line)"
        }

    } else {

        for($counter = 0; $counter -lt $print_amount; $counter++){
            Write-Host $($array[$counter].Line)
        }

    }

}

# --------------------------------------------- CUT HERE --------------------------------------------- #
# Diplay help if no argument given or run primary program
if ($args.Count -gt 0) {
    [hashtable]$control = parseArguments -array $args
    [array]$run_flags = $control.arg
    [array]$pattern_files = $control.pa_fi
    [array]$file_options = @()
    [array]$match_options = @('-CaseSensitive')
    [bool]$line_numbers = $false
    [bool]$file_names = $false
    [bool]$count_only = $false

    # consume all arguments
    if ($run_flags.Count -gt 0) {
        if (testArgs -arg_list ('-V', '--version')) {
            Write-Host @"
$app_name v.$version
License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.

Written by geoai777@gmail.com
"@
            Exit
        }

        # -[ file system operations ]--
        if (testArgs -arg_list ('-r', '--recursive')) {
            $file_options += '-Recurse'
        }

        # -[ pattern selection and interpretation ]--
        if (testArgs -arg_list ('-i', '--ignore-case')) {
            $match_options = array_pop -array $match_options -to_remove ('-CaseSensitive')
        }

        if (testArgs -arg_list ('-v', '--invert-match')) {
            $match_options += '-NotMatch'
        }

        # -[ output control ]--
        if (testArgs -arg_list ('-c', '--count')) {
            $count_only = $true
        } else {
            if (testArgs -arg_list ('-H', '--with-filename')) {
                $file_names = $true
            }

            # following two conditions should have exactly this order
            if (testArgs -arg_list ('-n', '--line-number')) {
                $line_numbers = $true
                $file_names = $true
            }
            if (testArgs -arg_list ('-h', '--no-filename')) {
                $file_names = $false
            }

            [int]$result_amount = 0
            if (testArgs -arg_list ('-m') -arguments $args) {
                $result_amount = ($run_flags -like '-m=?').Split('=')[1]
            }
        }
    }

    # check if no search pattern given
    if (($pattern_files.Count -le 0)) { 
        Write-Warning "Please specify pattern"
        Exit
    }
    [string]$pattern = $pattern_files[0]
    [array]$fs_items = @()

    # filter given files leaving only existing or get current dir list if none given
    if ($pattern_files.Count -gt 1){

        $given_paths = $pattern_files[1..$pattern_files.Count]

        foreach($this_path in $given_paths) {
    
            if(Test-Path $this_path){
                if($this_path.Contains(' ')){ $this_path = "`"$this_path`"" }
    
                $fs_items += loadRunner -command "Get-ChildItem $($file_options -join ' ') $this_path"
            }
    
        }
    
    } else {
        
        # if no argument given, search files in this folder
        $fs_items += loadRunner -command "Get-ChildItem $($file_options -join ' ')"

    }    
    
    [array]$files = @()
    $files = filter_files -array $fs_items

    ## match operations
    [array]$matches_found = @()

    $pattern = "`"$pattern`""
    [string]$option_string = ''
    if ($match_options.Count -gt 0) {
        $option_string = "$($match_options -join ' ') "
    }
    foreach($file in $files){

        $file = "`"$file`""
        $command_string = "Select-String $option_string-Path $file -Pattern $pattern"
        $matches_found += loadRunner -command $command_string
    
    }

    if ($matches_found.Count -le 0){
        Exit
    }

    if ($count_only) {
        Write-Host $matches_found.Count
        Exit
    }
    printAmount -array $matches_found `
        -print_amount $result_amount `
        -line_number $line_numbers `
        -file_name $file_names

} else {
    Clear-Host
    Write-Host @"
$app_name
Usage: grep [OPTION]... PATTERNS [FILE(s)]...
Search for PATTERNS in each FILE.
Example: grep -ir 'neddle' haystack.txt
PATTERNS can contain multiple patterns separated by newlines.

File selection options:
    -r, --recursive           recurse into subdirs

Pattern selection and interpretation:
    -i, --ignore-case         ignore case distinctions in patterns and data
                              matching is case sensitive by default
    -v, --invert-match        select non-matching lines

Output control:    
    -m, --max-count=NUM       stop after NUM selected lines
    -n, --line-number         print line number with output lines
    -H, --with-filename       print file name with output lines
    -h, --no-filename         suppress the file name prefix on output    
    -c, --count               print only a count of selected lines per FILE
                              overrides all other output options
Miscellaneous:
    -s, --no-messages         suppress error messages
    -V, --version             display version information and exit
    
"@

}