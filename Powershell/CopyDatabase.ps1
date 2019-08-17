function copy-database{
    param(
        $ServerName = "Localhost\sqlexpress",  
        $DestinationServer = "localhost\sqlexpress",
        $SourceUser = "Database User",
        $SourcePassword = "Database User's Password",
        $DestinationUser = "Database User",
        $DestinationPassword = "Database User's Password",
        $SourceDatabase = "websearch", #name of the databse to copy too
        $DestinationDB = "websearchSchema", #name of the destination database
        $CopyData = $false, #flag to trigger bulk copy of data to destination database
        $fileName = ".\ExtractDB\Schema.sql", #Path to the Schema.sql file included in this repo
        $tempPath = ".\BCP\", #A temp directory on a drive with enough free space to save the bcp files during the export and import operations
        $logPath = ".\log\" #directory to write error logs too
    )
    #Get Schema Data from the database
    $DS = Invoke-Sqlcmd -MaxCharLength 150000  -ServerInstance $ServerName  -Database $SourceDatabase -InputFile $fileName -As DataSet

    #For each row
    foreach($sql in $DS.Tables[0].Rows){
        Write-Output $sql.TableName

        #Create a variable for our log file name
        $errLog = "$($logPath)$($sql.TableName)_sqlout.txt"

        copy-schema -Sql $sql.SqlStatement -DestinationDatabase $DestinationDB -DestinationServer $DestinationServer -ErrorFile $errLog

        #If we just created the table, let's import the data before applying an constraints or indexes
        if($sql.ScriptType -eq "Table" -and $CopyData -eq $true){
            copy-data -SchemaName $sql.SchemaName -TableName $sql.TableName -SourceServer $ServerName -DestinationServer $DestinationServer -SourceDatabase $SourceDatabase -DestinationDatabase $DestinationDB -WorkingFolder $tempPath

            #Remove temp data file before moving on
            remove-item -path "$($tempPath)$($sql.TableName).bcp"
            remove-item -path "$($tempPath)$($sql.TableName).fmt"

            if ($error.count -gt 0){
                $error | Out-File -FilePath "$($errLog)"
                $sql.SqlStatement | Out-File -Append -FilePath "$($errLog)"

                $error.Clear()
            }
        }
    }
}

function copy-schema {
    param(
        [string] $Sql,
        [string] $DestinationDatabase,
        [string] $DestinationServer,
        [string] $ErrorFile
    )
        #Execute file on destination database
        Invoke-Sqlcmd -ServerInstance $DestinationServer -Database $DestinationDB -Query $Sql -OutputSqlErrors $true -verbose
        if ($error.count -gt 0)
        {
            $error | Out-File -FilePath "$($ErrorFile)"
            $sql.SqlStatement | Out-File -Append -FilePath "$($ErrorFile)"
    
            $error.Clear()
        }
        Write-Output $Sql
}

#TODO: Breakup into extract and import
function copy-data{ 
    param(
        [string] $SchemaName,
        [string] $TableName,
        [string] $SourceDatabase,
        [string] $DestinationDatabase,
        [string] $SourceServer,
        [string] $DestinationServer,
        [string] $WorkingFolder,
        [string] $SourceUser,
        [string] $DestinationUser,
        [string] $SourcePassword,
        [string] $DestinationPassword
    )

    $sourceAuth = " -T "
    $destAuth = " -T "

    if($SourceUser -ne "" -and $SourcePassword -ne ""){
        $sourceAuth = " -U $($SourceUser) -P $($SourcePassword) "
    }

    if($DestinationUser -ne "" -and $DestinationPassword -ne ""){
        $destAuth = " -U $($DestinationUser) -P $($DestinationPassword) "
    }

    #add code to create format file
    $bcp = "bcp $($SchemaName).$($TableName) format nul -n -f $($WorkingFolder)$($TableName).fmt -S $($SourceServer) -d $($SourceDatabase) $($sourceAuth) "
    Invoke-Expression $bcp
    Write-Output $bcp

    $bcp = "bcp $($SchemaName).$($TableName) out $($WorkingFolder)$($TableName).bcp -b 100 -S $($SourceServer) -d $($SourceDatabase) $($sourceAuth) -E -n -t "
    Invoke-Expression $bcp
    Write-Output $bcp

    #add code to import in to use format file
    $bcp = "bcp $($SchemaName).$($TableName) in $($WorkingFolder)$($TableName).bcp -b 100 -S $($DestinationServer) -d $($DestinationDatabase) $($destAuth) -t -E -f $($WorkingFolder)$($TableName).fmt"
    Invoke-Expression $bcp
    Write-Output $bcp
}
