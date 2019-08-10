$ServerName = "Your Source Database Server"  
$DestinationServer = "Your Destintination Database Server"
$UserName = "Database User"
$Password = "Database User's Password"
$SourceDatabase = "Database to copy from"
$DestinationDB = "Database to copy to"
$fileName = "..\Schema.sql" #Path to the Schema.sql file included in this repo
$tempPath = "..\BCP\" #A temp directory on a drive with enough free space to save the bcp files during the export and import operations
$logPath = "C:\Script_Utility\log\"

#Get Schema Data from the database
$DS = Invoke-Sqlcmd -MaxCharLength 150000  -ServerInstance $ServerName -User $UserName -Password $Password -Database $SourceDatabase -InputFile $fileName -As DataSet

#For each row
foreach($sql in $DS.Tables[0].Rows){
    Write-Output $sql.TableName

    #Execute file on each database
    Invoke-Sqlcmd -ServerInstance $DestinationServer -Database $DestinationDB -Query $sql.SqlStatement -OutputSqlErrors $true -verbose
    
    if ($error.count -gt 0)
    {
        $error | Out-File -FilePath "$($logPath)$($sql.TableName) _sqlout.txt"
        $sql.SqlStatement | Out-File -FilePath "$($logPath)$($sql.TableName) _sqlout.txt"
        
        $error.Clear()
    }
    Write-Output $sql.SqlStatement    

    #If we just created the table, let's import the data before applying an constraints or indexes
    if($sql.ScriptType -eq "Table" )
    {
        #add code to create format file
        $bcp = "bcp $($sql.SchemaName).$($sql.TableName) format nul -n -f $($tempPath)$($sql.TableName).fmt -S $($ServerName) -d $($SourceDatabase) -U $($UserName) -P $($Password) -e $($logPath)$($sql.TableName)_fmt_err.txt"
        Invoke-Expression $bcp
        Write-Output $bcp

        $bcp = "bcp $($sql.SchemaName).$($sql.TableName) out $($tempPath)$($sql.TableName).bcp -S $($ServerName) -d $($SourceDatabase) -U $($UserName) -P $($Password) -E -n -t -e $($logPath)$($sql.TableName)_out_err.txt"
        Invoke-Expression $bcp
        Write-Output $bcp

        #add code to import in to use format file
        $bcp = "bcp $($sql.SchemaName).$($sql.TableName) in $($tempPath)$($sql.TableName).bcp -b 100 -S $($DestinationServer) -d $($DestinationDB) -T -t -E -f $($tempPath)$($sql.TableName).fmt -e $($logPath)$($sql.TableName)_in_err.txt"
        Invoke-Expression $bcp
        Write-Output $bcp

        #Remove temp data file before moving on
        remove-item -path "$($tempPath)$($sql.TableName).bcp"
        remove-item -path "$($tempPath)$($sql.TableName).fmt"

        #Clean up Logs
        if((Get-Item "$($logPath)$($sql.TableName)_out_err.txt").Length -eq 0 ){
            Remove-Item "$($logPath)$($sql.TableName)_out_err.txt"
        }

        if((Get-Item "$($logPath)$($sql.TableName)_in_err.txt").Length -eq 0 ){
            Remove-Item "$($logPath)$($sql.TableName)_in_err.txt"
        }

        if((Get-Item "$($logPath)$($sql.TableName)_fmt_err.txt").Length -eq 0 ){
            Remove-Item "$($logPath)$($sql.TableName)_fmt_err.txt"
        }
    }
} 