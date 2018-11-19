




$testfile = "E:\diskspd_benchio.dat"
$ResultFile = "diskspd_results_"+(Get-Date -format '_yyyyMMdd_HHmmss') + ".txt"

.\diskspd -b8K -d30 -h -L -o8 -t8 -r -w0 -c20G $testfile  > $ResultFile
Start-Sleep -Seconds 20
.\diskspd -b8K -d30 -h -L -o8 -t8 -r -w100 -c20G $testfile  >> $ResultFile
Start-Sleep -Seconds 20
.\diskspd -b8K -d30 -h -L -o8 -t8 -si -w0 -c20G $testfile  >> $ResultFile
Start-Sleep -Seconds 20
.\diskspd -b8K -d30 -h -L -o8 -t8 -si -w100 -c20G $testfile  >> $ResultFile
Start-Sleep -Seconds 20
.\diskspd -b64K -d30 -h -L -o8 -t8 -r -w0 -c20G $testfile  >> $ResultFile
Start-Sleep -Seconds 20
.\diskspd -b64K -d30 -h -L -o8 -t8 -r -w100 -c20G $testfile  >> $ResultFile
Start-Sleep -Seconds 20
.\diskspd -b64K -d30 -h -L -o8 -t8 -si -w0 -c20G $testfile  >> $ResultFile
Start-Sleep -Seconds 20
.\diskspd -b64K -d30 -h -L -o8 -t8 -si -w100 -c20G $testfile  >> $ResultFile
Start-Sleep -Seconds 20



cls
$total=$true
$lines = Get-Content $ResultFile 
write-host "Operation;Duration;IOSize;IOType;PendingIO;FileSize;MBs/Sec;IOPS;Avg_Lat(ms)"
foreach ($line in $lines) {

    if ($line -like "*block size*"){
        #write-host $line
        $BlockSize =$line.Replace("block size:","").Trim() / 1024
        $total=$true
    }

     
    if ($line -like "*performing*"){
        #write-host $line
        $Operation =$line.Replace("performing","").Replace("test","").Trim() 
    }

    if ($line -like "*duration*"){
        #write-host $line
        $duration =$line.Replace("duration:","").Replace("s","").Trim() 
    }

    if ($line -like "*outstanding*"){
        #write-host $line
        $Outstanding =$line.Replace("number of outstanding I/O operations:","").Trim() 
    }
    

    if ($line -like "Command Line*"){
        #write-host $line
        if ($line -match "-si"){
            $IOType = "Sequential"
        }
        else {
            $IOType = "Random"
        }
        
    }
    if ($line -like "* IO*"){
        #Total IO
        #Read IO
        #Write IO
        #write-host $line
    }
    if ($line -like "total:*"){
        #write-host $line
        $mbps = $line.Split("|")[2].Trim() 
        $iops = $line.Split("|")[3].Trim()
        $latency = $line.Split("|")[4].Trim()
        if ($total) {
            
            write-host ("$Operation;$duration;$BlockSize;$IOType;$Outstanding;FileSize;$mbps;$iops;$latency").replace(".",",")
            $total=$false
        }
    }

}
