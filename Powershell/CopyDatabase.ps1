$ServerName = "Your Source Database Server"  
$DestinationServer = "Your Destintination Database Server"
$UserName = "Database User"
$Password = "Database User's Password"
$SourceDatabase = "Database to copy from"
$DestinationDB = "Database to copy to"
$fileName = "..\Schema.sql" #Path to the Schema.sql file included in this repo
$tempPath = "..\BCP\" #A temp directory on a drive with enough free space to save the bcp files during the export and import operations

#Run the Schema.sql file againist the source database to get the metadata for the import
$DS = Invoke-Sqlcmd -ServerInstance $ServerName -User $UserName -Password $Password -Database $SourceDatabase -InputFile $fileName -As DataSet

#For each row
foreach($sql in $DS.Tables[0].Rows){
    Write-Output $sql.TableName

    #Execute file on each database
    Invoke-Sqlcmd -ServerInstance $DestinationServer -Database $DestinationDB -MaxCharLength 8000 -Query $sql.SqlStatement 
    Write-Output $sql.SqlStatement    

    if($sql.TableName -ne "Schema" -and $sql.TableName -ne "Alter" )
    {
        #add code to create format file
        $bcp = "bcp $($sql.SchemaName).$($sql.TableName) format nul -n -f $($tempPath)$($sql.TableName).fmt -S $($ServerName) -d $($SourceDatabase) -U $($UserName) -P $($Password) "
        Invoke-Expression $bcp
        Write-Output $bcp

        $bcp = "bcp $($sql.SchemaName).$($sql.TableName) out $($tempPath)$($sql.TableName).bcp -S $($ServerName) -d $($SourceDatabase) -U $($UserName) -P $($Password) -E -n -t"
        Invoke-Expression $bcp
        Write-Output $bcp

        #add code to import in to use format file
        $bcp = "bcp $($sql.SchemaName).$($sql.TableName) in $($tempPath)$($sql.TableName).bcp -S $($DestinationServer) -d $($DestinationDB) -T -t -E -f $($tempPath)$($sql.TableName).fmt"
        Invoke-Expression $bcp
        Write-Output $bcp

        #Remove temp data file before moving on
        remove-item -path "$($tempPath)$($sql.TableName).bcp"
        remove-item -path "$($tempPath)$($sql.TableName).fmt"
    }
} 