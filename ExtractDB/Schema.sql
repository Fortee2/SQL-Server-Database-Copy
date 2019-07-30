DECLARE 
	--Variables for execution control
	@DropAndRecreate bit = 1,
	@SQL varchar(max),
	--Variables for Schemas
	@SchemaName varchar(128),
	--Variables for table defintion
	@TableObjectId int,
	@TableName varchar(100),
	--Variables for column definition
	@ColumnName varchar(500),
	@dataType  varchar(50),
	@ColId int,
	@ColObject int,
	@ColNullable bit,
	@ColIdentity bit,
	@ColDefault varchar(100),
	@ColMaxLength int,
	@ColPrecision int,
	@ColScale int,
	@ColTextLength varchar(5),
	@Seed int,
	@Increment int, 
	@FirstColumn char(1) = ' ',
	--Variables for Data Migration
	@InsertCols varchar(max),
	@InsertSql nvarchar(max)

Declare @Scripts Table(
	Id int identity(1,1) primary key,
	TableName varchar(128),
	SqlStatement varchar(max),
	SchemaName varchar(128)
)

--Base line everything by dropping any temp tables that are still around
IF OBJECT_ID('tempdb..#tables') IS NOT NULL		
DROP TABLE #tables

IF OBJECT_ID('tempdb..#ColumnData') IS NOT NULL		
DROP TABLE #ColumnData

IF OBJECT_ID('tempdb..#SchemaData') IS NOT NULL		
DROP TABLE #SchemaData

--First thing is to create the schemas.   We are not going to import users or add authorizations, just create the schemas
SELECT s.[name], s.[schema_id]
INTO #SchemaData
from sys.schemas s 
	inner join sys.server_principals sp on s.principal_id = sp.principal_id
where type_desc = 'SQL_LOGIN'
	and s.Name <> 'dbo'

INSERT INTO @Scripts 
(
	TableName, 
	SqlStatement, 
	SchemaName
)
SELECT 'Schema', 'CREATE SCHEMA ' + [Name], null
FROM #SchemaData

--Create a table list to
SELECT t.[Name], [object_id], isnull(sd.[name], 'dbo') as [SchemaName]
INTO #tables
FROM sys.tables t
	Left JOIN #SchemaData sd on t.schema_id = sd.schema_id
	WHERE type = 'U'
	--and t.name = 'TBL_Recovery'
order by create_date asc

While EXISTS (SELECT [Name] FROM #Tables)
BEGIN
	SELECT @TableObjectId = [object_id], 
		@TableName = [Name],
		@SchemaName = [SchemaName]
		FROM #tables;

	SET @SQL = '';
	SET @InsertCols = '';

	IF OBJECT_ID('tempdb..#ColumnData') IS NOT NULL		
	DROP TABLE #ColumnData;

	select 
		col.[Name] As ColName, 
		types.[name] as TypeName, 
		col.[object_id],
		Col.[column_id],
		col.is_nullable, 
		is_identity, 
		is_computed, 
		is_rowguidcol, 
		col.max_length, 
		col.[precision], 
		col.scale
	INTO #ColumnData 
	from sys.columns col
	inner join sys.types types on col.user_type_id = types.user_type_id
	WHERE [object_id] = @TableObjectId
	order by Column_id

	SET @FirstColumn = ' ';

	While EXISTS (SELECT TOP 1 [ColName] FROM #ColumnData)
	BEGIN
		--Reset Flags
		SELECT @ColNullable = 0,
			@ColIdentity = 0,
			@ColDefault = null

		SELECT TOP 1 @ColumnName = ColName
			,@dataType = TypeName
			,@ColNullable = is_nullable
			,@ColIdentity = is_identity
			,@ColId = column_id
			,@ColObject = [object_id]
			,@colMaxLength = max_length
			,@colprecision = precision
			,@colScale = scale
		FROM #ColumnData
		Order by column_id
		
		--For text fields length is the number of bytes.  for nvarchar and nchar it takes two bytes to store a character that is why we divide by 2
		SELECT @ColTextLength = CASE @ColMaxLength
			 WHEN -1 THEN 'max' 
			 ELSE 
				CASE WHEN @dataType = 'nvarchar' OR @dataType = 'nchar' THEN
					CONVERT(varchar(4),@ColMaxLength /2)
				ELSE 
					CONVERT(varchar(4),@ColMaxLength) 
				END
			 END

		SET @SQL = @SQL + @FirstColumn + ' ' + @ColumnName + ' ' + 
			CASE @dataType  
				WHEN 'varchar' THEN 'varchar(' + @ColTextLength  + ')'
				WHEN 'char' THEN 'char(' + @ColTextLength + ')'
				WHEN 'nvarchar' THEN 'nvarchar(' + @ColTextLength + ')'
				WHEN 'nchar' THEN 'nchar(' + @ColTextLength + ')'
				WHEN 'decimal' then 'decimal(' + CONVERT(varchar(3), @colPrecision) + ',' +  CONVERT(varchar(3), @colScale) + ')'
				WHEN 'numeric' then 'numeric(' + CONVERT(varchar(3), @colPrecision) + ',' +  CONVERT(varchar(3), @colScale) + ')'
				ELSE @dataType
			END

		if @ColIdentity = 1
		BEGIN
			SELECT @Seed = Convert(int, seed_value),  @Increment = convert(int, increment_value)
			FROM sys.identity_columns
			WHERE [object_id] = @TableObjectId AND [name] = @ColumnName

			SET @SQL = @SQL + ' IDENTITY(' + CONVERT(varchar(3), @Seed) + ',' +  CONVERT(varchar(3),@Increment) + ') '
		END

		SELECT @ColDefault = d.definition   
		FROM sys.default_constraints AS d  
		WHERE d.parent_object_id = @ColObject
		AND d.parent_column_id = @ColId 

		if NOT @ColDefault IS NULL
			SET @SQL = @SQL + ' DEFAULT' + @ColDefault

		if @ColNullable = 0
			SET @SQL = @SQL + ' NOT NULL '

		-- This code is for generating an insert statement		
		SET @InsertCols = @InsertCols + @FirstColumn + ' ' + @ColumnName + ' ';

		SET @FirstColumn = ',';
		
		DELETE FROM #ColumnData WHERE ColName = @ColumnName;
	END

	SET @SQL = 'CREATE TABLE ' + @SchemaName + '.' + @TableName + ' (' + @SQL + ')';

	IF @DropAndRecreate = 1
		INSERT INTO @Scripts	(TableName, SqlStatement)
		VALUES(

			'Alter',
			'DROP TABLE ' + @SchemaName + '.' + @TableName
		)	

	INSERT INTO @Scripts	
		(
			TableName, 
			SqlStatement, 
			SchemaName
		)
	VALUES
	(
		@TableName,
		@SQL,
		@SchemaName
	)

	DELETE FROM #tables WHERE [object_id]  = @TableObjectId
END

	SELECT * FROM @Scripts;