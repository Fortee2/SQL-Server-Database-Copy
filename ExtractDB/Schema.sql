DECLARE
	--Variables for execution control
	@DropAndRecreate bit = 0,
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
	@ColIsComputed bit,
	@ColComputedDefintion varchar(max),
	@Seed int,
	@Increment int,
	@FirstColumn char(1) = ' ',
	--Variables for constraint
	@ConstraintName varchar(128),
	@ConstraintHold varchar(128),
	@ConstraintType varchar(2),
	--Variables for Indexes
	@IndexName  varchar(128),
	@IndexType  varchar(128),
	@IndexedColumns varchar(max),
	@IndexIncludedColumns varchar(max),
	--Variables for Data Migration
	@InsertCols varchar(max),
	@InsertSql nvarchar(max)

Declare @Scripts Table(
	Id int identity(1,1) primary key,
	ScriptType varchar(50),
	TableName varchar(128),
	SqlStatement varchar(max),
	SchemaName varchar(128)
)

DECLARE @Indices Table
(
	IndexName varchar(128),
	[IndexType] varchar(50),
	IndexedColumns varchar(Max),
	IncludedColumns varchar(max)
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
	ScriptType,
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
	SELECT TOP 1
		@TableObjectId = [object_id],
		@TableName = [Name],
		@SchemaName = [SchemaName]
		FROM #tables;

	SET @SQL = '';
	SET @InsertCols = '';

	IF OBJECT_ID('tempdb..#ColumnData') IS NOT NULL
	DROP TABLE #ColumnData;

	--Get a list of all the columns
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

	SET @FirstColumn = ' '; --This is used for toggling when to a comma in a series of fields

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
			,@ColIsComputed  = is_computed
		FROM #ColumnData
		Order by column_id

		SET @SQL = @SQL + @FirstColumn + ' ' + QUOTENAME( @ColumnName) + ' '

		if @ColIsComputed = 0
		BEGIN
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

				SET @SQL = @SQL +
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

			if NOT @ColDefault IS NULL
				SET @SQL = @SQL + ' DEFAULT' + @ColDefault

			if @ColNullable = 0
				SET @SQL = @SQL + ' NOT NULL '
		END
		ELSE
		BEGIN
			SELECT @ColComputedDefintion = [definition]
			from sys.computed_columns
			where [OBJECT_ID] = @TableObjectId
				and [column_id] = @ColId

			SET @SQL = @SQL + ' AS ' + @ColComputedDefintion
		END

		SET @FirstColumn = ',';

		DELETE FROM #ColumnData WHERE ColName = @ColumnName;
	END

	SET @SQL = @SQL +
	ISNULL((SELECT CHAR(9) + ', CONSTRAINT ' + QUOTENAME( k.name) + ' PRIMARY KEY (' +
		(SELECT STUFF((
			SELECT ', [' + c.name + '] ' + CASE WHEN ic.is_descending_key = 1 THEN 'DESC' ELSE 'ASC' END
			FROM sys.index_columns ic WITH (NOWAIT)
			JOIN sys.columns c WITH (NOWAIT) ON c.[object_id] = ic.[object_id] AND c.column_id = ic.column_id
			WHERE ic.is_included_column = 0
				AND ic.[object_id] = k.parent_object_id
				AND ic.index_id = k.unique_index_id
			FOR XML PATH(N''), TYPE).value('.', 'NVARCHAR(MAX)'), 1, 2, ''))
		+ ')' + CHAR(13)
		FROM sys.key_constraints k WITH (NOWAIT)
		WHERE k.parent_object_id = @TableObjectId
		AND k.[type] = 'PK'), '') + ')'  + CHAR(13)

	SET @SQL = 'CREATE TABLE ' + QUOTENAME( @SchemaName) + '.' + QUOTENAME( @TableName) + ' (' + @SQL ;

	IF @DropAndRecreate = 1
		INSERT INTO @Scripts
		(
			ScriptType,
			TableName,
			SqlStatement
		)
		VALUES(

			'Alter',
			@TableName,
			'IF object_id(''' + quotename(@SchemaName) + '.' + quotename(@TableName) + ''') IS NOT NULL  
				DROP TABLE ' + quotename(@SchemaName) + '.' + quotename(@TableName),
		)

	INSERT INTO @Scripts
	(
		ScriptType,
		TableName,
		SqlStatement,
		SchemaName
	)
	VALUES
	(
		'Table',
		@TableName,
		@SQL,
		@SchemaName
	)

	INSERT INTO @Scripts
	(
		ScriptType,
		TableName,
		SqlStatement,
		SchemaName
	)
	select 'Trigger',
		@TableName,
		m.definition,
		@SchemaName
	 from sys.sql_modules m
	inner join sys.objects o on m.object_id  = o.object_id
	WHERE o.parent_object_id = @TableObjectId
		and o.[Type] = 'TR'

	--Add in the indexes
	INSERT INTO @Indices
	(
		IndexName,
		[IndexType],
		IndexedColumns,
		IncludedColumns
	)
	SELECT
		 i.NAME AS 'IndexName'
		,LOWER(i.type_desc) + CASE
			WHEN i.is_unique = 1
				THEN ', unique'
			ELSE ''
			END + CASE
			WHEN i.is_primary_key = 1
				THEN ', primary key'
			ELSE ''
			END AS [IndexType]
		,STUFF((
				SELECT ', ' + quotename( sc.NAME )  AS "text()"
				FROM syscolumns AS sc
				INNER JOIN sys.index_columns AS ic ON ic.object_id = sc.id
					AND ic.column_id = sc.colid
				WHERE sc.id = so.object_id
					AND ic.index_id = i1.indid
					AND ic.is_included_column = 0
				ORDER BY key_ordinal
				FOR XML PATH('')
				), 1, 2, '') AS 'IndexedColumns'
		,STUFF((
				SELECT ', [' + sc.NAME + ']' AS "text()"
				FROM syscolumns AS sc
				INNER JOIN sys.index_columns AS ic ON ic.object_id = sc.id
					AND ic.column_id = sc.colid
				WHERE sc.id = so.object_id
					AND ic.index_id = i1.indid
					AND ic.is_included_column = 1
				FOR XML PATH('')
				), 1, 2, '') AS 'included_columns'
	FROM sysindexes AS i1
	INNER JOIN sys.indexes AS i ON i.object_id = i1.id
		AND i.index_id = i1.indid
	INNER JOIN sysobjects AS o ON o.id = i1.id
	INNER JOIN sys.objects AS so ON so.object_id = o.id
		AND is_ms_shipped = 0
	INNER JOIN sys.schemas AS s ON s.schema_id = so.schema_id
	WHERE so.type = 'U'
		AND i.is_primary_key = 0  --don't want the primary key and unique constraints
		AND i.is_unique = 0
		AND i1.indid < 255
		AND i1.STATUS & 64 = 0 --index with duplicates
		AND i1.STATUS & 8388608 = 0 --auto created index
		AND i1.STATUS & 16777216 = 0 --stats no recompute
		AND i.type_desc <> 'heap'
		AND so.NAME <> 'sysdiagrams'
		AND i.type_desc <> 'clustered'
		AND o.id = @TableObjectId

	WHILE Exists( SELECT top 1 IndexName FROM @Indices)
	BEGIN
		SELECT TOP 1
			@IndexName = IndexName,
			@IndexedColumns = IndexedColumns,
			@IndexType = IndexType,
			@IndexIncludedColumns = IncludedColumns
		FROM  @Indices

		SET @SQL =  'CREATE ' + @IndexType + ' INDEX ' + QUOTENAME(@IndexName) + ' ON ' + QUOTENAME(@SchemaName) + '.' + QUOTENAME(@TableName) + ' ( ' + @IndexedColumns + ') '

		if not @IndexIncludedColumns  is null
		BEGIN
			SET @SQL =   @SQL + 'INCLUDE (' + @IndexIncludedColumns + ')'
		END

		INSERT INTO @Scripts
		(
			ScriptType,
			TableName,
			SqlStatement,
			SchemaName
		)
		VALUES
		(
			'Index',
			@TableName,
			@SQL,
			@SchemaName
		)
		DELETE FROM @Indices WHERE IndexName = @IndexName
	END

	DELETE FROM #tables WHERE [object_id]  = @TableObjectId
END

	--Going to pull in the keys.  Not doing this with the table create in case this is being run with the bulk copy to ease the data in.
	INSERT INTO @Scripts
	(
		ScriptType,
		TableName,
		SqlStatement,
		SchemaName
	)
	SELECT
		'Foreign Keys',
		 ct.[name],
		'ALTER TABLE '
		   + QUOTENAME(cs.name) + '.' + QUOTENAME(ct.name)
		   + ' ADD CONSTRAINT ' + QUOTENAME(fk.name)
		   + ' FOREIGN KEY (' + STUFF((SELECT ', ' + QUOTENAME(c.name) + ' '
		   -- get all the columns in the constraint table
			FROM sys.columns AS c
			INNER JOIN sys.foreign_key_columns AS fkc
			ON fkc.parent_column_id = c.column_id
			AND fkc.parent_object_id = c.[object_id]
			WHERE fkc.constraint_object_id = fk.[object_id]
			ORDER BY fkc.constraint_column_id
			FOR XML PATH(N''), TYPE).value(N'.[1]', N'nvarchar(max)'), 1, 1, N'')
		  + ') REFERENCES ' + QUOTENAME(rs.name) + '.' + QUOTENAME(rt.name)
		  + '(' + STUFF((SELECT ',' + QUOTENAME(c.name)
		   -- get all the referenced columns
			FROM sys.columns AS c
			INNER JOIN sys.foreign_key_columns AS fkc
			ON fkc.referenced_column_id = c.column_id
			AND fkc.referenced_object_id = c.[object_id]
			WHERE fkc.constraint_object_id = fk.[object_id]
			ORDER BY fkc.constraint_column_id
			FOR XML PATH(N''), TYPE).value(N'.[1]', N'nvarchar(max)'), 1, 1, N'') + ');',
			cs.[Name]
		FROM sys.foreign_keys AS fk
		INNER JOIN sys.tables AS rt -- referenced table
		  ON fk.referenced_object_id = rt.[object_id]
		INNER JOIN sys.schemas AS rs
		  ON rt.[schema_id] = rs.[schema_id]
		INNER JOIN sys.tables AS ct -- constraint table
		  ON fk.parent_object_id = ct.[object_id]
		INNER JOIN sys.schemas AS cs
		  ON ct.[schema_id] = cs.[schema_id]
		WHERE rt.is_ms_shipped = 0 AND ct.is_ms_shipped = 0;

	--Functions
	INSERT INTO @Scripts
	(
		ScriptType,
		TableName,
		SqlStatement,
		SchemaName
	)
	select 'Functions',
		o.[Name],
		m.definition,
		@SchemaName
	 from sys.sql_modules m
	inner join sys.objects o on m.object_id  = o.object_id
	WHERE o.[Type] in ('FN', 'IF', 'TF')
	ORDER BY create_date asc

	--Grab Procedures
	INSERT INTO @Scripts
	(
		ScriptType,
		TableName,
		SqlStatement
	)
	select 'Procedures',
		p.name,
		m.definition
	from sys.procedures p
	inner join sys.sql_modules m on p.object_id = m.object_id
	ORDER BY create_date asc

	--Grab the Views
	INSERT INTO @Scripts
	(
		ScriptType,
		TableName,
		SqlStatement
	)
	select 'Views',
		p.name,
		m.definition
	from sys.views p
	inner join sys.sql_modules m on p.object_id = m.object_id
	ORDER BY create_date asc

	SELECT *, LEN(SqlStatement) AS StatementLength
	FROM @Scripts
