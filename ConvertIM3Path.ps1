<#--------------------------------------------------------------------------------------------
ConvertIm3Path.ps1

"shred" or "inject" the im3 files for a whole sample depending on options provided. This code
is part of the flat fielding work flow for the JHU astropath pipeline. 

Created by: Alex Szalay, Benjamin Green - JHU - 04/14/2020

Usage:
 To "shred" a directory of im3s in the CS format use:
    ConvertIm3Path <dataroot> <fwroot> <sample> -shred [-all -dat -xml -xmlfull] [-interactive] [-images <paths>]
    Reads the im3s from <dataroot>\<sample>\im3\Scan<highest number>\MSI and writes to <fwroot>\<sample>
    Optional arguments (pass at least one of -all, -dat, -xml, -xmlfull):
	-all: do everything below (-dat and -xml)
	-dat: only extract the binary bitmap for each image into the output directory
	-xml: extract the xml information only for each image, xml information includes:
		1) one <sample>.Parameters.xml: sample location, shape, and scale
		2) one <sample>.Full.xml: the full xml of an im3 without the bitmap
		3) an .SpectralBasisInfo.Exposure.xml for each image containing the
			exposure times of the image
	-xmlfull: only the <sample>.Parameters.xml and <sample>.Full.xml from (-xml)
	-interactive: write each image name to the host as it is processed
	-images: only process these im3 files (full paths) instead of the whole MSI folder
 To "inject" a directory of .Data.dat binary blobs for each image back into the directory of im3s use:
    ConvertIm3Path <dataroot> <fwroot> <sample> -inject
    Reads the .Data.dat files from <fwroot>\<sample>
    Exports the new '.im3s' into <dataroot>\<sample>\im3\flatw (the injected files are 
    renamed from <name>.injected.im3 to <name>.im3)
    Each .Data.dat in <fwroot>\<sample> is renamed to <name>.fw once it has been injected
#--------------------------------------------------------------------------------------------#>
function ConvertIm3Path{ 
    #
    param ([Parameter(Position=0)][string] $root1 = '',
           [Parameter(Position=1)][string] $root2 = '', 
           [Parameter(Position=2)][string] $sample = '',
           [Parameter(Position=3)][switch] $interactive = $false,
           [Parameter()][array] $images,
           [Parameter()][switch]$inject,
           [Parameter()][switch]$shred, 
           [Parameter()][switch]$all,
           [Parameter()][switch]$xml,
           [Parameter()][switch]$xmlfull,
           [Parameter()][switch]$dat)
    #
    test-convertim3params $PSBoundParameters
    test-convertim3exe
    $scan = search-scan $root1 $sample
    $IM3 = search-im3 $scan
    $flatw = search-flatw $root2 $sample -inject:$inject
    #
    write-convertim3log -myparams $PSBoundParameters -IM3_fd $IM3 -Start 
    #
    if (!($PSBoundParameters.ContainsKey('images'))){
        $pattern = Join-Path $IM3 "*"
        $images = (get-childitem $pattern '*.im3').FullName
    }
    #
    if ($images.Count -eq 0){
         write-convertim3log -myparams $PSBoundParameters -IM3_fd $IM3 -Finish 
         return
    }
    #
    if ($shred) {
        #
        # for shred: extract the bit map and xml for each image. 
        # then extract the full xml and rename to 'Full.xml' and 
        # extract additional sample information like shape, etc
        # optional inputs are applied
        #
        if ($all -or $dat) { 
            Invoke-IM3Convert -images $images -dest $flatw $interactive -BIN 
            }
        #
        if ($all -or $xml) {
            Invoke-IM3Convert $images $flatw $interactive -XML
        }
        #
        if ($all -or $xml -or $xmlfull) {
            Invoke-IM3Convert $images $flatw $interactive -FULL
            Invoke-IM3Convert $images $flatw $interactive -PARMS
        }
        #
    } elseif ($inject) {
        #
        # for inject check for '.dat' files then inject
        # back to im3 into the flatw folder
        #
        $pattern = Join-Path $flatw "*"
        $dats = get-childitem $pattern '*.dat'
        if (!($dats.Count -eq $images.Count)) { 
            Write-Verbose ("WARNING: " + $dats.Count + " .dat file(s) in $flatw but " +
                $images.Count + " .im3 file(s) to inject from $IM3")
        }
        #
        $dest = Join-Path $root1 "$sample\im3\flatw"
        if (!(test-path $dest)) {
            new-item $dest -itemtype directory | Out-Null
        }
        Invoke-IM3Convert $images $dest $interactive -inject -IM3 $IM3 -flatw $flatw
        # 
    } 
    #
    write-convertim3log -myparams $PSBoundParameters -IM3_fd $IM3 -Finish 
    #
}
#
function test-convertim3params{
    #
    param ([Parameter(Position=0)][hashtable] $myparams)
    #
    if (
        !($myparams.ContainsKey('root1')) -OR 
        !($myparams.ContainsKey('root2')) -OR 
        !($myparams.ContainsKey('sample')) -OR
        (!($myparams.inject) -AND !($myparams.shred))
    ) {
        Throw "Usage: ConvertIm3Path dataroot dest sample -inject -shred:[-all -dat -xml -xmlfull]"
    }
    #
    # shred and inject are exclusive, shred would otherwise run and inject be silently ignored
    #
    if ($myparams.inject -and $myparams.shred) {
        Throw "-shred and -inject cannot be used together, run ConvertIm3Path once for each"
    }
    #
    # set default to all for shred if no other value given
    #
    if ($myparams.shred -and !$myparams.all -and !$myparams.dat -and !$myparams.xml -and !$myparams.xmlfull) { $myparams.all = $true }
    #
    # if option is set for inject send a warning message as the option params are not valid
    #
    if ($myparams.inject) {
        #
        if ($myparams.all) {
            Write-Verbose "WARNING: '-all' not valid for inject. IGNORING"
        } elseif ($myparams.dat) {
            Write-Verbose "WARNING: '-dat' not valid for option inject. IGNORING"
        } elseif ($myparams.xml) {
            Write-Verbose "WARNING: '-xml' not valid for option inject. IGNORING"
        } elseif ($myparams.xmlfull) {
            Write-Verbose "WARNING: '-xmlfull' not valid for option inject. IGNORING"
        }
        #
    }
    #
}
#
function test-convertim3exe {
    #
    # check that ConvertIM3.exe, and mono on non-windows, are available before
    # any folders are created or any images are processed
    #
    $code = Join-Path $PSScriptRoot "ConvertIM3.exe"
    if (!(test-path -LiteralPath $code)) {
        Throw "ConvertIM3.exe not found at $code; it must be in the same folder as ConvertIM3Path.ps1"
    }
    #
    if (!($env:OS -eq 'Windows_NT') -and !(get-command mono -ErrorAction SilentlyContinue)) {
        Throw "'mono' is required to run ConvertIM3.exe on this platform but was not found on the PATH"
    }
    #
}
#
function search-scan {
    #
    param ([Parameter(Position=0)][string] $root1 = '',
        [Parameter(Position=2)][string] $sample = '')
    #
    # find highest scan folder, exit if im3 directory not found
    #
    $IM3 = Join-Path $root1 "$sample\im3"
    if (!(test-path $IM3)) {
        #
        # say which level is missing: dataroot, sample folder, or im3 folder
        #
        $samplepath = Join-Path $root1 $sample
        if (!(test-path -LiteralPath $root1)) {
            Throw "IM3 root path $IM3 not found: data root '$root1' does not exist"
        } elseif (!(test-path -LiteralPath $samplepath)) {
            Throw ("IM3 root path $IM3 not found: sample folder '$samplepath' does not exist")
        }
        Throw ("IM3 root path $IM3 not found: sample folder '$samplepath' has no 'im3' folder")
    }
    #
    # only folders named exactly Scan<number> are valid.
    #
    $sub = get-childitem -LiteralPath $IM3 -Directory |
        where-object {$_.Name -like "Scan*"}
    foreach ($sub1 in $sub) {
        if ($sub1.Name -notmatch '^Scan\d+$') {
            Write-Verbose ("WARNING: ignoring folder '" + $sub1.Name + 
                "' in $IM3; scan folders must be named Scan<number> (e.g. Scan1)")
        }
    }
    #
    $valid = $sub | where-object {$_.Name -match '^Scan\d+$'}
    if (!$valid) {
        Throw ("No valid scan folder (Scan<number>) found in $IM3. " + 
            "Folders found: " + ((get-childitem -LiteralPath $IM3 -Directory).Name -join ', '))
    }
    #
    $scanname = ($valid |
        sort-object {[int]$_.Name.substring(4)} |
        select-object -last 1).Name
    $scan = Join-Path $IM3 $scanname
    #
    return $scan
    #
}
#
function search-im3 {
    #
    param ([Parameter(Position=0)][string] $scan = '')
    #
    # build full im3 path, exit if not found
    #
    $IM3 = Join-Path $scan "MSI"
    if (!(test-path $IM3)) {
        Throw "IM3 subpath $IM3 not found: the highest scan folder '$scan' has no 'MSI' folder"
    }
    #
    return $IM3
    #
}
#
function search-flatw {
    #
    param ([Parameter(Position=0)][string] $root2 = '',
        [Parameter(Position=2)][string] $sample = '',
        [parameter(Mandatory=$false)][Switch]$inject)
    #
    # build flatw path, and create folders if they do not exist for shred
    # exit if not found on inject
    #
    $flatw = Join-Path $root2 $sample
    if (!(test-path $flatw) -and !$inject) {
        Write-Verbose "output folder $flatw not found, creating it"
        new-item $flatw -itemtype directory | Out-Null
    } elseif (!(test-path $flatw) -and $inject){
        Throw "flatw path $flatw not found"
    }
    #
    return $flatw
    #
}
#
function write-convertim3log {
    <# ----------------------------------------------------- 
     Part of the shredPath workflow. This function
     writes to the log using either a -Start or -Finish Switch
    -----------------------------------------------------
     Usage: Write-Log -Start OR Write-Log -Finish
    # ----------------------------------------------------- #>
    [CmdletBinding(PositionalBinding=$false)]
    #
    param([parameter(Mandatory=$false)][hashtable]$myparams,
          [parameter(Mandatory=$false)][String]$IM3_fd,
          [parameter(Mandatory=$false)][Switch]$Start,
          [parameter(Mandatory=$false)][Switch]$Finish)
    #
    $s = $myparams.shred
    $i = $myparams.inject
    $d = $myparams.dat
    $xml = $myparams.xml
    $xmlfull = $myparams.xmlfull
    $a = $myparams.all
    $root1 = $myparams.root1
    $root2 = $myparams.root2
    $sample = $myparams.sample
    #
    # if Start switch is active write the start error messaging for shred
    #
    if ($Start) {
        #
        Write-Verbose ". `r"
        #
        if ($s) {
            #
            $appendargs = @()
            #
            if ($d){
                $appendargs += '-dat'
            }
            #
            if ($xml){
                $appendargs += '-xml'
            }
            #
            if ($xmlfull){
                $appendargs += '-xmlfull'
            }
            #
            if ($all){
                $appendargs += '-all'
            }
            #
            $appendargs = ($appendargs -join ' ')
            Write-Verbose "shredPath $root1 $root2 $sample $appendargs `r"
            $logpath = Join-Path $root2 "$sample\doShred.log"
            If (test-path $logpath) {
                 Remove-Item $logpath -Force
                 }
            #
        } else {
            #
            Write-Verbose "injectPath $root1 $root2 $sample `r"
            $logpath = Join-Path $root1 "$sample\im3\flatw\doInject.log"
            If (test-path $logpath) {
                 Remove-Item $logpath -Force
                 }
            #
        }
        #
        Write-Verbose (" "+(get-date).ToString('T')+"`r")
        #
        if (!$s) {
            $sampledir = Join-Path $root2 $sample
            Write-Verbose "  src path $sampledir `r"
            $pattern = Join-Path $sampledir "*"
            $stats = get-childitem $pattern '*.dat' | Measure-Object Length -sum
            Write-Verbose ('     '+$stats.Count+' File(s) '+$stats.Sum+' byte(s)'+"`r")
        }
        #
        Write-Verbose "  im3 path $IM3_fd `r"
        $pattern = Join-Path $IM3_fd "*"
        $stats = get-childitem $pattern '*.im3' | Measure-Object Length -sum
        Write-Verbose ('     '+$stats.Count+' File(s) '+$stats.Sum+' byte(s)'+"`r")
        #
    }
    #
    # if finish switch is active write the finish error messaging for 
    #    
    if ($Finish){
        #
        if ($s) { $dest = Join-Path $root2 $sample
        } else { $dest = Join-Path $root1 "$sample\im3\flatw" }
        #
        Write-Verbose "  dst path $dest `r"
        #
        $pattern = Join-Path $dest "*"
        if ($s) {
            #
            if($a -or $d) {
                $stats = get-childitem $pattern '*.dat' | Measure-Object Length -sum
                Write-Verbose ('     '+$stats.Count+' File(s) '+$stats.Sum+' byte(s)'+"`r")
            }
            #
            if ($a -or $xml -or $xmlFull){
                $stats = get-childitem $pattern '*.xml' | Measure-Object Length -sum
                Write-Verbose ('     '+$stats.Count+' File(s) '+$stats.Sum+' byte(s)'+"`r")
            }
            #
        } else {
            $stats = get-childitem $pattern '*.im3' | Measure-Object Length -sum
            Write-Verbose ('     '+$stats.Count+' File(s) '+$stats.Sum+' byte(s)'+"`r")
            #
        }
        #
        Write-Verbose (" "+(get-date).ToString('T')+"`r")
        # 
    }
    #
}
#
function Get-IM3Exception {
    #
    # ConvertIM3 reports a failure by printing 'Exception: <message>' to the output
    # and exiting 0, so the exit code cannot be used to tell that it failed
    #
    param([parameter(Position=0)][array]$output)
    #
    $line = $output | Where-Object {$_ -like 'Exception: *'} | Select-Object -First 1
    if ($line) { return "ConvertIM3 error: " + $line.Substring(11) }
    #
}
#
function Write-IM3Results {
    #
    # write the ConvertIM3 output to the log, and for each image that failed use
    # the exception ConvertIM3 reported, if any, as the reason
    #
    param([parameter(Position=0)][array]$results,
          [parameter(Position=1)][String]$log,
          [parameter(Position=2)][array]$failed,
          [parameter(Position=3)][hashtable]$reasons)
    #
    $results | foreach-object { $_.Output } | Out-File -append $log
    $failed = @($failed | where-object {$_})
    foreach ($result in $results) {
        $exception = Get-IM3Exception $result.Output
        if ($exception) {
            $reasons[$result.Image] = $exception
            if ($failed -notcontains $result.Image) { $failed += $result.Image }
        }
    }
    return $failed
    #
}
#
function Write-IM3AttemptFailure {
    #
    # verbose message for a failed attempt, with the reason for each failed image
    #
    param([parameter(Position=0)][int]$attempt,
          [parameter(Position=1)][String]$summary,
          [parameter(Position=2)][array]$images,
          [parameter(Position=3)][hashtable]$reasons)
    #
    Write-Verbose "    Attempt $attempt - Error $summary"
    foreach ($image in $images) {
        Write-Verbose "    $image - $($reasons[$image])"
    }
    #
}
#
function Stop-IM3Convert {
    #
    # throw for images that still failed after the last attempt, also written to the log
    #
    param([parameter(Position=0)][String]$step,
          [parameter(Position=1)][array]$failed,
          [parameter(Position=2)][hashtable]$reasons,
          [parameter(Position=3)][String]$log)
    #
    # one line per distinct reason, with an example image
    #
    $groups = @($failed | group-object {$reasons[$_]})
    $lines = $groups | select-object -first 10 | foreach-object {
        $line = "    " + [IO.Path]::GetFileName($_.Group[0]) + " - " + $_.Name
        if ($_.Count -gt 1) { $line += " (and " + ($_.Count - 1) + " more)" }
        $line
    }
    if ($groups.Count -gt 10) { $lines += "    ... and " + ($groups.Count - 10) + " more reasons" }
    $msg = ("ConvertIM3 $step failed for " + $failed.Count + " image(s) after 5 attempts:`n" +
        ($lines -join "`n") + "`nSee $log for the ConvertIM3 output.")
    #
    (get-date).ToString('T') + " $msg" | Out-File $log -Append
    Throw $msg
    #
}
#
function Invoke-IM3Convert {
    <# ----------------------------------------------------- 
    # Part of the shredPath workflow. This function
    # runs the IM3Convert utility for each of the different
    # instances desired
    #
    # ----------------------------------------------------- #>
    param([parameter(Position=0)][array]$images,
          [parameter(Position=1)][String]$dest,
          [parameter(Position=2)][Switch]$interactive,
          [parameter(Mandatory=$false)][Switch]$BIN,
          [parameter(Mandatory=$false)][Switch]$XML,
          [parameter(Mandatory=$false)][Switch]$FULL,
          [parameter(Mandatory=$false)][Switch]$PARMS, 
          [parameter(Mandatory=$false)][Switch]$inject,
          [parameter(Mandatory=$false)][String[]]$IM3,
          [parameter(Mandatory=$false)][String[]]$flatw)
    #
    # Set up variables
    #
    $code = Join-Path $PSScriptRoot "ConvertIM3.exe"
    $dat = ".//D[@name='Data']/text()"
    $exp = ".//G[@name='SpectralBasisInfo']//D[@name='Exposure']" #| " + 
            # "(.//G[@name='Protocol']//G[@name='DarkCurrentSettings'])" + '"'
    $glb_prms =  "//D[@name='Shape']  | " +
                 "//D[@name='SampleLocation'] | " +
                 "//D[@name='MillimetersPerPixel'] | " +
                 "(.//G[@name='Protocol']//G[@name='CameraState'])[1]"
    $injecttxt = ".//D[@name='Data']/text()"
    #
    # extracts the binary bit map
    #
    if ($BIN) {
        #
        $log = Join-Path $dest "doShred.log"
        $cnt = 0
        $reasons = @{}
        #
        while($images -and ($cnt -lt 5)){
            #
            Write-Debug ('       attempt:' + $cnt)
            #
            $results = $images | foreach-object -Parallel {
                if ($using:interactive){
                    write-host $_
                }                     
                if ($env:OS -contains 'Windows_NT'){
                    $out = & $using:code $_ DAT -x $using:dat -o $using:dest 2>&1
                } else {
                    $command = "mono $using:code $_ DAT -x "+'"'+$using:dat+'"'+" -o $using:dest"
                    $out = iex $command 2>&1
                }
                [pscustomobject]@{Image = $_; Output = @($out | Out-String -Stream)}
            } -ThrottleLimit 5
            #
            Start-Sleep 2
            #
            $images = SEARCH-FAILED $images $dest '.Data.dat' $reasons
            $images = Write-IM3Results $results $log $images $reasons
            if ($images) {
                Write-IM3AttemptFailure ($cnt + 1) "extracting $(@($images).Count) BIN images" $images $reasons
            }
            $cnt += 1
        }
        #
        # images left after the last attempt failed.
        #
        if ($images) {
            Stop-IM3Convert 'BIN extraction' $images $reasons $log
        }
        #
    }
    #
    # extracts the xml file for the exposure times
    #
    if ($XML) {
        #
        $log = Join-Path $dest "doShred.log"
        $cnt = 0
        $reasons = @{}
        #
        while($images -and ($cnt -lt 5)){
            #
            Write-Debug ('       attempt:' + $cnt)
            #
            $results = $images | foreach-object -Parallel {
                if ($using:interactive){
                    Write-Host $_
                }             
                if ($env:OS -contains 'Windows_NT'){
                    $out = & $using:code $_ XML -x $using:exp -o $using:dest 2>&1
                } else {
                    $command = "mono $using:code $_ XML -x "+'"'+$using:exp+'"'+" -o $using:dest"
                    $out = iex $command 2>&1
                }
                [pscustomobject]@{Image = $_; Output = @($out | Out-String -Stream)}
            } -ThrottleLimit 5
            #
            Start-Sleep 2
            #
            $images = SEARCH-FAILED $images $dest '.SpectralBasisInfo.Exposure.xml' $reasons
            $images = Write-IM3Results $results $log $images $reasons
            if ($images) {
                Write-IM3AttemptFailure ($cnt + 1) "extracting $(@($images).Count) XML images" $images $reasons
            }
            $cnt += 1
        }
        #
        if ($images) {
            Stop-IM3Convert 'XML extraction' $images $reasons $log
        }
        #
    }
    #
    # for full switch extract the full xml from the first IM3 
    # in the directory
    #
    if ($FULL){
        #
        $im1 = $images[0]
        $shredlog = Join-Path $dest "doShred.log"
        if ($interactive){
            write-host $im1
        }     
        if ($env:OS -contains 'Windows_NT'){
            & $code $im1 XML -t 64 -o $dest 2>&1>> $shredlog
        } else {
            $command = "mono $code $im1 XML -t 64 -o $dest"
            iex $command 2>&1>> $shredlog
        }
        #
        $pattern = Join-Path $dest "*].xml"
        $f = (get-childitem $pattern)[0].Name
        $f2 = Join-Path $dest "$sample.Full.xml"
        if (test-path $f2) {Remove-Item $f2 -Force}
        Rename-Item $pattern $f2 -Force
        "$f Renamed to $sample.Full.xml" | Out-File $shredlog -Append
        #
    }
    #
    # for parms switch extract the global parameters from the first IM3
    # in the directory
    #
    if ($PARMS) {
        #
        $im1 = $images[0]
        $shredlog = Join-Path $dest "doShred.log"
        if ($interactive){
            write-host $im1
        }        
        if ($env:OS -contains 'Windows_NT'){
            & $code $im1 XML -x $glb_prms -o $dest 2>&1>> $shredlog
        } else {
            $command = "mono $code $im1 XML -x "+'"'+$glb_prms+'"'+" -o $dest"
            iex $command 2>&1>> $shredlog
        }
        # 
        $pattern = Join-Path $dest "*State.xml"
        $f = (get-childitem $pattern)[0].Name
        $f2 = Join-Path $dest "$sample.Parameters.xml"
        if (test-path $f2) {Remove-Item $f2 -Force}
        Rename-Item $pattern $f2 -Force
        "$f Renamed to $sample.Parameters.xml" | Out-File $shredlog -Append
        #
    }
    #
    # for inject switch inject the .dat back into the flatw files
    # 
    if ($inject) {
        #
        $log = Join-Path $dest "doInject.log"
        $cnt = 0
        #
        $savedimagenames = $images
        $reasons = @{}
        #
        while($images -and ($cnt -lt 5)){
            #
            Write-Debug ('       attempt:' + $cnt)
            #
            $results = $images | foreach-object -Parallel {
                if ($using:interactive){
                    write-host $_
                }
                #
                $in = $_.Replace($using:IM3, $using:flatw)
                $in = $in.Replace('.im3', '.Data.dat')
                #
                if ($env:OS -contains 'Windows_NT'){
                    $out = & $using:code $_ IM3 -x $using:injecttxt -i $in -o $using:dest 2>&1
                } else {
                    $command = "mono $using:code $_ IM3 -x "+'"'+$using:injecttxt+'"'+" -i $in -o $using:dest"
                    $out = iex $command 2>&1
                }
                [pscustomobject]@{Image = $_; Output = @($out | Out-String -Stream)}
            } -ThrottleLimit 5
            #
            Start-Sleep 2
            #
            $images = SEARCH-FAILED $images $dest '.injected.im3' $reasons
            $images = Write-IM3Results $results $log $images $reasons
            if ($images) {
                Write-IM3AttemptFailure ($cnt + 1) "injecting $(@($images).Count) images" $images $reasons
            }
            $cnt += 1
        }
        #
        $savedimagenames | foreach-object {
            #
            # renamed injected.im3s to im3s
            #    
            $f2 = $_.replace($IM3, $dest)
            $f = $f2.replace('.im3', '.injected.im3')
            $pattern = Join-Path $dest ""
            $f2log = $f2.replace($pattern, '') 
            if (test-path -LiteralPath $f2) {Remove-Item -LiteralPath $f2 -Force}
            Rename-Item -LiteralPath $f $f2 -Force
            "$f Renamed to $f2log" | Out-File $log -Append
            #
            # renamed Data.dat to .fw
            #    
            $f2 = $_.replace($IM3, $flatw)
            $f = $f2.replace('.im3', '.Data.dat')
            $f2 = $f2.replace('.im3', '.fw')
            #
            $pattern = Join-Path $flatw ""
            $f2log = $f2.replace($pattern, '') 
            if (test-path -LiteralPath $f2) {Remove-Item -LiteralPath $f2 -Force}
            Rename-Item -LiteralPath $f $f2 -Force
            "$f Renamed to $f2log" | Out-File $log -Append
            #
        }
        #
        if ($images) {
            Stop-IM3Convert 'injection' $images $reasons $log
        }
        #
    }
}
#
function SEARCH-FAILED {
    #
    param([parameter(Position=0)][array]$images,
    [parameter(Position=1)][String]$dest,
    [parameter(Position=2)][String]$filespec,
    [parameter(Position=3)][hashtable]$reasons = @{})
    #
    # find images that did not extract at all. $reasons is filled in with
    # why each image that is returned was considered failed
    #
    $pattern = Join-Path $dest "*"
    $output = Get-ChildItem ($pattern) ('*' + $filespec)
    if (!$output){
        foreach ($image in $images) {
            $reasons[$image] = "no '*$filespec' output files found"
        }
        return $images
    }
    #
    write-debug '       search failed'
    #
    $outputnames = [array]($output.Name)
    $compareimagenames = (Split-Path $images -Leaf) -replace ([regex]::escape('.im3') + '$'), $filespec
    $imagepath = Split-Path $images[0]
    #
    write-debug ('        filespec: ' + $filespec)
    write-debug ('        comparename ex: ' + $compareimagenames[0])
    write-debug ('        expected ex: ' + $outputnames[0])
    #
    $comparison = Compare-Object -ReferenceObject $compareimagenames `
        -DifferenceObject $outputnames |
        Where-Object -FilterScript {$_.SideIndicator -eq '<='}
    #
    [array]$outimages = @()
    #
    if ($comparison.InputObject){
        ($comparison.InputObject) | foreach-Object{
            $missing = Join-Path $imagepath ($_  -replace ([regex]::escape($filespec) + '$'), '.im3')
            $outimages += $missing
            $reasons[$missing] = "output file '$_' not found"
        }
    }
    #
    write-debug ('        n files after not found file check: ' + $outimages.Length)
    #
    # Find potential corrupt files. The minimum sizes are fixed thresholds, so a
    # legitimately smaller image is reported as failed here
    #
    if ($filespec -match '.Data.dat'){
        #
        if (($output | measure-object length  -maximum).maximum -gt 200000kb){
            $min = 220000kb
        } else {
            $min = 90000kb
        }
    } elseif ($filespec -match '.SpectralBasisInfo.Exposure.xml') {
        $min = 500
    } else {
        $min = 90000kb
    }
    #
    Write-Debug ('        min size filter: ' + $min)
    Write-Debug ('        min file size: ' + ($output | measure-object length  -Minimum).Minimum)
    #
    $filteredoutput = $output | Where-Object {$_.Length -lt $min}
    foreach ($small in $filteredoutput) {
        $smallimage = Join-Path $imagepath ($small.Name -replace ([regex]::escape($filespec) + '$'), '.im3')
        $outimages += $smallimage
        $reasons[$smallimage] = "output file below the expected minimum of " + ('{0:N0}' -f $min) + " bytes"
    }
    #
    write-debug ('        n files after wrong file size check: ' + $outimages.Length)
    #
    return $outimages
    #
}
