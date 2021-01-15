<# ---------------------------------------------------------
For each sample directory not control extract the xml file 
formats
 ---------------------------------------------------------#>


Function ConvertIM3Cohort {
    param ( $root, $output_dir )
    $sample_all = Get-ChildItem -Path $root -Directory
    
    #
    foreach ($sub in $sample_all) {
        $IM3_fd = $root + "\" + $sub.Name + "\im3\"
        $ii = test-path -path $IM3_fd
        #
        IF (!$ii -or $sub.Name -like "Control*") {
            Continue
        }
        M:\Im3Shred\ConvertIM3Path.ps1 $root $output_dir $sub -s -xml
    }
    #
}

ConvertIM3Cohort '\\bki04\Clinical_Specimen_2' '\\bki04\flatw_2'


