
-- +migrate Up
CREATE PROCEDURE [dbo].[azure_database_link] (@linkname VARCHAR(50), @connectionstring VARCHAR(1024)) AS
BEGIN
    -- Delete link and revert to local files
    IF @linkname IS NULL
    BEGIN
        UPDATE meta.[type] SET data_source = NULL, errorfile_data_source = NULL
        RETURN
    END 

    DECLARE @credname  VARCHAR(100) = @linkname + '_cred'
    DECLARE @location  VARCHAR(100) = (SELECT SUBSTRING(value, CHARINDEX('=', value) + 1, LEN(value))
                                         FROM STRING_SPLIT(@connectionstring, ';') WHERE VALUE LIKE 'server=%')
    DECLARE @database  VARCHAR(100) = (SELECT SUBSTRING(value, CHARINDEX('=', value) + 1, LEN(value))
                                         FROM string_split(@connectionstring, ';') WHERE VALUE LIKE 'database=%')
    DECLARE @identity  VARCHAR(100) = (SELECT SUBSTRING(value, CHARINDEX('=', value) + 1, LEN(value))
                                         FROM string_split(@connectionstring, ';') WHERE VALUE LIKE 'user id=%')
    DECLARE @secret    VARCHAR(100) = (SELECT SUBSTRING(value, CHARINDEX('=', value) + 1, LEN(value))
                                         FROM string_split(@connectionstring, ';') WHERE VALUE LIKE 'password=%')

    -- TODO: Master password - a little reckless here?
    IF NOT EXISTS (SELECT * FROM sys.symmetric_keys WHERE name LIKE '%DatabaseMasterKey%')
        CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'F00Bar&Baz'

    -- Create database scoped credentials for accessing remote location/database
    DECLARE @sql NVARCHAR(MAX) = 'DATABASE SCOPED CREDENTIAL ' + @credname + ' WITH IDENTITY = ''' + @identity + ''', SECRET = ''' + @secret + ''''
    IF EXISTS (SELECT 1 FROM sys.database_scoped_credentials WHERE name = @credname)
        SET @sql = 'ALTER ' + @sql
    ELSE
        SET @sql = 'CREATE ' + @sql
    EXEC sp_executesql @sql

    -- ALSO Need to be dynamic SQL - even more stupid WITH/SET syntax (sigh-sigh)
    IF EXISTS (SELECT 1 FROM sys.external_data_sources WHERE name = @linkname)
        SET @sql = 'ALTER EXTERNAL DATA SOURCE '+ @linkname +' SET LOCATION = ''' + @location + ''', DATABASE_NAME = ''' + @database + ''', CREDENTIAL = '+ @credname
    ELSE
        SET @sql = 'CREATE EXTERNAL DATA SOURCE '+ @linkname +' WITH (TYPE = RDBMS, LOCATION = ''' + @location + ''', DATABASE_NAME = ''' + @database + ''', CREDENTIAL = '+ @credname +')'
    EXEC sp_executesql @sql
END
;

-- +migrate Down
DROP PROCEDURE [dbo].[azure_database_link]
;
