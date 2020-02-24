
# https://claudioessilva.eu/2019/05/17/ups-i-have-deleted-some-data-can-you-put-it-back-dbatools-for-the-rescue/ 


# https://claudioessilva.eu/2019/05/17/ups-i-have-deleted-some-data-can-you-put-it-back-dbatools-for-the-rescue/ 

$SourceServer = "localhost\sql2019"
$DestinationServer = "localhost\sql2017"
$SourceDB = "performance"
$DestinationDB = "perf"
$tables = Get-DbaDbTable -SqlInstance $SourceServer -Database $SourceDB |select-object name,schema
$tables | Out-GridView

$options = New-DbaScriptingOption
    $options.DriPrimaryKey = $true
    $options.DriForeignKeys = $true
    $options.DriUniqueKeys = $true
    $options.DriClustered = $true
    $options.DriNonClustered = $true
    $options.DriChecks = $true
    $options.DriDefaults = $true
 
$tables | ForEach-Object {
    # Get the table definition from the source
    [string]$tableScript = Get-DbaDbTable -SqlInstance $SourceServer -Database $SourceDB -Table $_.Name | Export-DbaScript -ScriptingOptionsObject $options -Passthru;
 
    if (-not [string]::IsNullOrEmpty($tableScript)) {
        if ($null -eq (Get-DbaDbTable -SqlInstance $DestinationServer -Database $DestinationDB -Table $_.Name)) {
            # Run the script to create the table in the destination
            Invoke-DbaQuery -Query $tableScript -SqlInstance $DestinationServer -Database $DestinationDB;
        }
        else {
            Write-Warning "Table $_.Name already exists in detination database. Will continue and copy the data."
        }
 
        # Copy the data
        Copy-DbaDbTableData -SqlInstance $SourceServer -Database $SourceDB -Destination $DestinationServer -DestinationDatabase $DestinationDB -KeepIdentity -Truncate -Table $_.Name -DestinationTable $_.Name;
    }
    else {
        Write-Warning "Table $_.Name does not exists in source database."
    }
}


<#
foreach ($table in $tables) {
    $params = @{
        SqlInstance = $SourceServer 
        Destination = $DestinationServer
        Database = $SourceDB
        DestinationDatabase = $DestinationDB
        Table = $table.schema + "." + $table.name
        DestinationTable = "$table.schema`.$table.name"
        AutoCreateTable = $false
    }
    Copy-DbaDbTableData @params

}
#>