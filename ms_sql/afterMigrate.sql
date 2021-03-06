/*
Panko
Copyright (c) 2020 John McCall

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Source: https://github.com/LowlyDBA/Panko
*/

/* Set schema where Flyway stores its data*/
DECLARE @flywaySchema sysname = N'dbo';

/* Set name flyway configured table and new changelog table */
DECLARE @changelogTable sysname = N'schema_changelog';
DECLARE @versionTable sysname = N'schema_version';

--========================--
-- Do not edit below here --
--========================--

DECLARE @sqlEndVersion NVARCHAR(MAX) = N''; 
DECLARE @parmDefinitionEndVersion NVARCHAR(MAX) = N'';

DECLARE @sqlLogInsert NVARCHAR(MAX) = N''; 

DECLARE @migrationEnd DATETIME2 = GETDATE();
DECLARE @migrationStart DATETIME2 = NULL;

DECLARE @endVersionID INT = NULL;
DECLARE @startVersionID INT = NULL;

CREATE TABLE #changelog (
	   [start_version_id] [int] NOT NULL,
	   [end_version_id] [int] NOT NULL,
	   [migration_start] DATETIME2 NOT NULL,
	   [migration_end] DATETIME2 NOT NULL,
	   [schema] [sysname] NULL,
	   [name] [sysname] NULL,
	   [type_desc] [nvarchar](60) NULL,
	   [change] [nvarchar](50) NULL
	   );

/* Get last version ID of migration */
SELECT @sqlEndVersion = N'
SELECT  @endversionID_out = MAX([installed_rank])
FROM  ' + QUOTENAME(@flywaySchema) + '.' + QUOTENAME(@versionTable) + ';'
SELECT @parmDefinitionEndVersion = N'@endVersionID_out INT OUTPUT';
EXEC sp_executesql @sqlEndVersion, @parmDefinitionEndVersion,  @endversionID_out = @endVersionID OUTPUT;

/* Grab start version and start time of the migration */
SELECT @startVersionID = [start_version_id]
	 ,@migrationStart = [migration_start]
FROM ##changelog_start;

/* Store all logged changes into temp table for dynamic SQL construction: */

--Objects modified/created during migration
INSERT INTO #changelog
SELECT @startVersionID
	 ,@endVersionID
	 ,@migrationStart
	 ,@migrationEnd
	 ,SCHEMA_NAME([ao].[schema_id])
	 ,[ao].[name]
	 ,[ao].[type_desc]
	 ,CASE
           WHEN [ao].[create_date] >= @migrationStart
                AND [ao].[create_date] <= @migrationEnd
              THEN 'created'
           ELSE 'modified'
       END
FROM [sys].[all_objects] AS [ao] 
WHERE (([ao].[create_date] >= @migrationStart AND [ao].[create_date] <= @migrationEnd)
    OR ([ao].[modify_date] >= @migrationStart AND [ao].[modify_date] <= @migrationEnd));

--Objects that no longer exist but did before
INSERT INTO #changelog
SELECT @startVersionID
	 ,@endVersionID
	 ,@migrationStart
	 ,@migrationEnd
	 ,[sao].[schema_name]
	 ,[sao].[name]
	 ,[sao].[type_desc]
	 ,'dropped'
FROM [##start_all_objects] AS [sao]
    LEFT JOIN [sys].[all_objects] AS [ao] ON [ao].[object_id] = [sao].[object_id]
WHERE [ao].[object_id] IS NULL;

/* Add all created, modified, and dropped objects to the log */
SELECT @sqlLogInsert = N'
INSERT INTO ' + QUOTENAME(@flywaySchema) + '.' + QUOTENAME(@changelogTable) + '(
					    [start_version_id]
					   ,[end_version_id]
					   ,[migration_start]
					   ,[migration_end]
					   ,[schema]
					   ,[name]
					   ,[type_desc]
					   ,[change])
SELECT [start_version_id] 
	 ,[end_version_id]
	 ,[migration_start] 
	 ,[migration_end] 
	 ,[schema]
	 ,[name]
	 ,[type_desc]
	 ,[change]
FROM #changelog';

EXEC sp_executesql @sqlLogInsert;
