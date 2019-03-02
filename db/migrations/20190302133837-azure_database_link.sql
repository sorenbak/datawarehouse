
-- +migrate Up
CREATE PROCEDURE [dbo].[azure_database_link] (
    @credname  NVARCHAR(100),
    @extname   NVARCHAR(100),
    @location  NVARCHAR(100),
    @database  NVARCHAR(100),
    @identity  NVARCHAR(100),
    @secret    NVARCHAR(100)
) AS
BEGIN 
    IF @credname IS NULL OR @extname IS NULL
    BEGIN
        UPDATE meta.[type] SET data_source = NULL, errorfile_data_source = NULL
        RETURN
    END 

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
    IF EXISTS (SELECT 1 FROM sys.external_data_sources WHERE name = @extname)
        SET @sql = 'ALTER EXTERNAL DATA SOURCE '+ @extname +' SET LOCATION = ''' + @location + ''', DATABASE_NAME = ''' + @database + ''', CREDENTIAL = '+ @credname
    ELSE
        SET @sql = 'CREATE EXTERNAL DATA SOURCE '+ @extname +' WITH (TYPE = RDBMS, LOCATION = ''' + @location + ''', DATABASE_NAME = ''' + @database + ''', CREDENTIAL = '+ @credname +')'
    EXEC sp_executesql @sql
END
;

-- +migrate Down
DROP PROCEDURE [dbo].[azure_database_link]
;
