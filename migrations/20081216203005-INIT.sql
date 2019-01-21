-- ----------------------------------------------------------------------------------------------------------------------------------
-- +migrate Up
-- ----------------------------------------------------------------------------------------------------------------------------------
CREATE SCHEMA [meta]
;
CREATE SCHEMA [init]
;
CREATE SCHEMA [temp]
;
CREATE SCHEMA [stag]
;
CREATE SCHEMA [repo]
;
SET ANSI_NULLS ON
;
SET QUOTED_IDENTIFIER ON
;
CREATE
PROCEDURE[meta].[debug]-- |
--| ==========================================================================================
--| Description: Provide common debug output throughout API - also for handling error messages
--| consistently as the procedure tries to automatically determine the current
--| state
--| Arguments:
(
    @pid   BIGINT = @@PROCID, --| @@PROCID of the calling SP - has to be provided
    @msg   NVARCHAR(4000)-- | Message to log to loggin output stream
)
AS
-- | ------------------------------------------------------------------------------------------
BEGIN
    PRINT '[' + CONVERT(NVARCHAR(20), GETDATE(), 120) + '] [' + OBJECT_SCHEMA_NAME(@pid) + '.' + OBJECT_NAME(@pid) + ']: ' + @msg

    -- | Check for error state and outermost nesting level(besides the call to this procedure)
    IF ERROR_NUMBER() IS NOT NULL AND @@NESTLEVEL <= 2
    BEGIN
        SET @msg = 'ERROR [' + CAST(ERROR_NUMBER() AS NVARCHAR) + '] in [' + COALESCE(ERROR_PROCEDURE(), '<sql>') + '] line [' + CAST(ERROR_LINE() AS NVARCHAR) + ']: ' + ERROR_MESSAGE()
        RAISERROR(@msg, 11, 1)
    END

    -- | Return whatever ERROR_NUMBER() of the current state
    RETURN COALESCE(ERROR_NUMBER(), 0)
END
-- | ==========================================================================================
;
CREATE
FUNCTION [meta].[check_date] --|
--| ==========================================================================================
--| Description: Provide a common function for validating date values
--|              0    => OK
--|              <> 0 => ERROR
--| Arguments:
(
    @value   NVARCHAR(50),       --| Value to check
    @format  INT                 --| Date format to check
                                 --| (http://msdn.microsoft.com/en-us/library/ms187928.aspx)
)
RETURNS TINYINT
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    --| Handle special NULL case => OK
    IF @value IS NULL RETURN 0 --+ OK (Special NULL)

    --| Set default DD/MM/YYYY
    SET @format = COALESCE(@format, 103)

    --| Case on date format code
    RETURN
        CASE @format
            --| 102 => YYYY.MM.DD
            WHEN 102 THEN
                CASE WHEN @value LIKE '%[^0-9.]%'                                      THEN 10 --+ Contains other than 0-9 or . characters
                     WHEN @value NOT LIKE '[1-3][0-9][0-9][0-9].[0-1][0-9].[0-3][0-9]' THEN 20 --+ Invalid format
                     ELSE 0
                END
            --| 103 => DD/MM/YYYY (default)
            WHEN 103 THEN
                CASE WHEN @value LIKE '%[^0-9/]%'                                      THEN 10 --+ Contains other than 0-9 or / characters
                     WHEN @value NOT LIKE '[0-3][0-9]/[0-1][0-9]/[1-3][0-9][0-9][0-9]' THEN 20 --+ Invalid format
                     ELSE 0
                END
            --| 104 => DD.MM.YYYY
            WHEN 104 THEN
                CASE WHEN @value LIKE '%[^0-9.]%'                                      THEN 10 --+ Contains other than 0-9 or . characters
                     WHEN @value NOT LIKE '[0-3][0-9].[0-1][0-9].[1-3][0-9][0-9][0-9]' THEN 20 --+ Invalid format
                     ELSE 0
                END
            --| 105 => DD-MM-YYYY
            WHEN 105 THEN
                CASE WHEN @value LIKE '%[^0-9\-]%'                                     THEN 10 --+ Contains other than 0-9 or - characters
                     WHEN @value NOT LIKE '[0-3][0-9]-[0-1][0-9]-[1-3][0-9][0-9][0-9]' THEN 20 --+ Invalid format
                     ELSE 0
                END
            --| 111 => YYYY/MM/DD
            WHEN 111 THEN
                CASE WHEN @value LIKE '%[^0-9/]%'                                      THEN 10 --+ Contains other than 0-9 or 7 characters
                     WHEN @value NOT LIKE '[1-3][0-9][0-9][0-9]/[0-1][0-9]/[0-3][0-9]' THEN 20 --+ Invalid format
                     ELSE 0
                END
            --| 102 => YYYY.MM.DD
            WHEN 102 THEN
                CASE WHEN @value LIKE '%[^0-9.]%'                                      THEN 10 --+ Contains other than 0-9 or 7 characters
                     WHEN @value NOT LIKE '[1-3][0-9][0-9][0-9].[0-1][0-9].[0-3][0-9]' THEN 20 --+ Invalid format
                     ELSE 0
                END
            --| 120 => YYYY-MM-DD
            WHEN 120 THEN
                CASE WHEN @value LIKE '%[^0-9\-]%'                                     THEN 10 --+ Contains other than 0-9 or 7 characters
                     WHEN @value NOT LIKE '[1-3][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]' THEN 20 --+ Invalid format
                     ELSE 0
                END
            --| Otherwise OK
            ELSE 0
        END
END
--| ==========================================================================================
;
CREATE
FUNCTION [meta].[check_numeric] --|
--| ==========================================================================================
--| Description: Provide a common function for validating numeric values
--|              0    => OK
--|              <> 0 => ERROR
--| Arguments:
(
    @value      NVARCHAR(50),       --| Value to check
    @precision  INT,                --| Precision of value to check
    @scale      INT                 --| Scale of value to check
)
RETURNS TINYINT
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    --| Handle special NULL case
    IF NULLIF(@value, '') IS NULL RETURN  0 --+ OK (Special NULL)

    --| Handle special Non NUMERIC case
    SET @value = REPLACE(@value, ',', '.')
    IF @value NOT LIKE '%[0-9]%'  RETURN  5 --+ Case when not containing any digits (-/+)
    IF ISNUMERIC(@value) = 0      RETURN 10 --+ Invalid number

    --| Check for precision and scale
    DECLARE @floor BIGINT
    SET @floor = ABS(FLOOR(@value))
    RETURN
        CASE
            WHEN @floor > 0 AND @precision - @scale = 0                     THEN 20 --+ Special case (e.g NUMERIC(3,3))
            WHEN LEN(@floor) > @precision - @scale                          THEN 30 --+ Too big value for precision
            WHEN LEN(ABS(ABS(@value) - CAST(@floor AS FLOAT))) - 2 > @scale THEN 40 --+ Too many decimals
            ELSE                                                                  0 --+ OK
        END
END
--| ==========================================================================================

;
CREATE FUNCTION [meta].[get_status_date] --|
--| ==========================================================================================
--| Description: Extract a valid status date from a delivery name according to file formats:
--|                [filename prefix]_YYYY-MM-DD.[extension]
--|                [filename prefix]_YYYY.MM.DD.[extension]
--|                [filename prefix]_YYYY/MM/DD.[extension]
--|                [filename prefix]_YYYYMMDD.[extension]
--|              If neither date format is found in the filename, NULL is returned
--| Arguments:
(
    @name    NVARCHAR(500)      --| Full filename to extract status date from
)
RETURNS DATE
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    --| Handle special NULL case => GETDATE()
    IF NULLIF(@name, '') IS NULL RETURN NULL

    DECLARE @date_c NVARCHAR(20)
    --| Get the date pattern (last '_' separated section before extension '.')
    DECLARE @pos_1 INT
    DECLARE @pos_2 INT
    --+ Get position 1 (of last '_')
    SET @pos_1 = LEN(@name) - CHARINDEX('_', REVERSE(@name)) + 2
    IF @pos_1 < 0 RETURN NULL

    --+ Get position 2 (of last '.')
    SET @pos_2 = LEN(@name) - CHARINDEX('.', REVERSE(@name)) + 1
    IF @pos_2 < @pos_1 RETURN NULL

    --+ Extract date part between position 1 and 2
    SET @date_c = SUBSTRING(@name, @pos_1, @pos_2 - @pos_1)
    
    --| Return date according to order of precense
    --+ Return if date format 120 (YYYY-MM-DD)
    IF meta.check_date(@date_c, 120) = 0 RETURN CONVERT(DATE, @date_c, 120)
    --+ Return if date format 102 (YYYY.MM.DD)
    IF meta.check_date(@date_c, 102) = 0 RETURN CONVERT(DATE, @date_c, 102)
    --+ Return if date format 111 (YYYY/MM/DD)
    IF meta.check_date(@date_c, 111) = 0 RETURN CONVERT(DATE, @date_c, 111)

    --+ Last attempt of date format (YYYYMMDD)
    SET @date_c = SUBSTRING(@date_c, 1, 4) + '-' + SUBSTRING(@date_c, 5, 2) + '-' + SUBSTRING(@date_c, 7, 2)
    IF meta.check_date(@date_c, 120) = 0 RETURN CONVERT(DATE, @date_c, 120)

    --+ Otherwise return NULL
    RETURN NULL
END
--| ==========================================================================================

;
CREATE FUNCTION [meta].[in_group] --|
--| ==========================================================================================
--| Description: Check if a user is in a specific group
--|              0 => not member
--|              1 => member
--| Arguments:
(
    @username      NVARCHAR(50),       --| Username to check
    @groupname     NVARCHAR(50)        --| Group to check membership of
)
RETURNS TINYINT
AS 
BEGIN
--| ------------------------------------------------------------------------------------------
    --| Lookup the membership in meta data
    RETURN COALESCE((
    SELECT CASE WHEN createdtm IS NULL THEN 0 ELSE 1 END
      FROM meta.user_group_v
     WHERE username   = @username
       AND group_name = @groupname), 0)
--| ==========================================================================================
END
;
CREATE FUNCTION [meta].[split]() RETURNS INT AS BEGIN RETURN 1 END
;
CREATE
FUNCTION [meta].[table_row_len] --|
--| ==========================================================================================
--| Description: Calculate the length in bytes for a specific table in temp 
--|              Used for determining the MS SQL hard 8060/4000 bytes limit for a table row
--| Arguments:
(
    @table_name     NVARCHAR(128)  --| Table name
)
RETURNS INT
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    --| Return case on length of datatype in init schema
    RETURN
        (SELECT SUM(CASE 
                        WHEN character_maximum_length = -1    THEN 10
                        WHEN character_maximum_length IS NULL THEN 50
                        ELSE character_maximum_length
                    END)
           FROM meta.column_mapping_v
          WHERE table_schema = 'init'
            AND table_name   = @table_name)
END
--| ==========================================================================================

;
CREATE FUNCTION [meta].[user_access] --|
--| ==========================================================================================
--| Description: Check if a user has specific access to an agreement
--|              0    => not access to agreement
--|              <> 0 => userid is returned as 'true' value
--| Arguments:
(
    @username      NVARCHAR(50), --| Username to check
    @agreement_id  BIGINT, --| Agreement to check access against
    @accessname    NVARCHAR(50)-- | Access to check
)
RETURNS TINYINT
AS
BEGIN
--| ------------------------------------------------------------------------------------------
    --| Return value of lookup in meta data
    RETURN COALESCE((
    SELECT TOP 1 user_id
      FROM meta.user_access_v
     WHERE UPPER(username) = UPPER(@username)
       AND agreement_id = @agreement_id
       AND accessname = @accessname), 0)
--| ==========================================================================================
END
;
CREATE TABLE[meta].[agreement]
        (

   [id][bigint] IDENTITY(1,1) NOT NULL,

  [type_id] [bigint]
        NOT NULL,

  [group_id] [bigint]
        NOT NULL,

  [user_id] [bigint]
        NOT NULL,

  [name] [nvarchar] (100) NOT NULL,

   [pattern] [nvarchar] (250) NOT NULL,

    [createdtm] [datetime]
        NOT NULL,

    [modifydtm] [datetime]
        NOT NULL,

    [frequency] [int] NOT NULL,

    [description] [nvarchar] (1000) NOT NULL,
 
     [file2temp] [nvarchar] (250) NOT NULL,
  
      [temp2stag] [nvarchar] (250) NOT NULL,
   
       [stag2repo] [nvarchar] (250) NOT NULL,
     CONSTRAINT[PK_meta.delivery] PRIMARY KEY CLUSTERED
   (
       [id] ASC
   )WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON[PRIMARY]
) ON[PRIMARY]
;
SET ANSI_NULLS ON
;
SET QUOTED_IDENTIFIER ON
;
CREATE TABLE[meta].[agreement_attribute]
        (

   [id][bigint] IDENTITY(1,1) NOT NULL,

  [agreement_id] [bigint]
        NOT NULL,

  [attribute_id] [bigint]
        NOT NULL,

  [value] [nvarchar] (1000) NOT NULL,

   [createdtm] [datetime]
        NOT NULL,
CONSTRAINT[PK_agreement_attribute] PRIMARY KEY CLUSTERED
(
  [id] ASC
)WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON[PRIMARY]
) ON[PRIMARY]
;
CREATE TABLE[meta].[attribute]
        (

   [id][bigint] IDENTITY(1,1) NOT NULL,

  [name] [nvarchar] (100) NOT NULL,

   [description] [nvarchar] (1000) NULL,
	[default_value] [nvarchar] (1000) NULL,
	[options] [nvarchar] (2000) NULL,
	[createdtm]
        [datetime]
        NOT NULL,
 CONSTRAINT[PK_attribute] PRIMARY KEY CLUSTERED
(
   [id] ASC
)WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON[PRIMARY]
) ON[PRIMARY]
;
CREATE
VIEW[meta].[agreement_attribute_v] --|
--| ==========================================================================================
--| Description: Agreement attributes with default values if not set
--| ==========================================================================================
AS
SELECT a.id AS agreement_id,
       a.name AS agreement_name,
       u.id AS attribute_id,
       u.name AS attribute_name,
       u.options AS attribute_options,
       u.description AS attribute_description,
       COALESCE(au.value, u.default_value) AS value,
       au.createdtm
  FROM meta.agreement a
       FULL OUTER JOIN
       meta.attribute u ON (1 = 1)
       FULL OUTER JOIN
       meta.agreement_attribute au ON (a.id = au.agreement_id AND u.id = au.attribute_id)
;
CREATE TABLE[meta].[audit]
        (

   [id][bigint] IDENTITY(1,1) NOT NULL,

  [stage_id] [bigint]
        NOT NULL,

  [delivery_id] [bigint]
        NOT NULL,

  [table_id] [bigint]
        NOT NULL,

  [createdtm] [datetime]
        NOT NULL,

  [description] [nvarchar] (250) NULL,
 CONSTRAINT[PK_audit] PRIMARY KEY CLUSTERED
(
   [id] ASC
)WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON[PRIMARY]
) ON[PRIMARY]
;
CREATE TABLE[meta].[delivery]
        (

   [id][bigint] IDENTITY(1,1) NOT NULL,

  [agreement_id] [bigint]
        NOT NULL,

  [user_id] [bigint]
        NOT NULL,

  [name] [nvarchar] (250) NOT NULL,

   [createdtm] [datetime]
        NOT NULL,

   [size] [bigint]
        NOT NULL,

   [status_date] [date] NULL,
 CONSTRAINT[PK_delivery] PRIMARY KEY CLUSTERED
(
   [id] ASC
)WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON[PRIMARY]
) ON[PRIMARY]
;
CREATE TABLE[meta].[group]
        (

   [id][bigint] IDENTITY(1,1) NOT NULL,

  [name] [nvarchar] (50) NOT NULL,

   [description] [nvarchar] (1000) NULL,
	[createdtm]
        [datetime]
        NOT NULL,
 CONSTRAINT[PK_group] PRIMARY KEY CLUSTERED
(
   [id] ASC
)WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON[PRIMARY]
) ON[PRIMARY]
;
CREATE TABLE[meta].[type]
        (

   [id][bigint] IDENTITY(1,1) NOT NULL,

  [name] [nvarchar] (50) NOT NULL,

   [batchsize] [int] NULL,
	[check_constraints] [bit] NULL,
	[codepage] [nvarchar] (10) NULL,
	[datafiletype] [nvarchar] (10) NULL,
	[fieldterminator] [nvarchar] (10) NULL,
	[firstrow] [int] NULL,
	[fire_triggers] [bit] NULL,
	[format_file] [nvarchar] (250) NULL,
	[keepidentity] [bit] NULL,
	[keepnulls] [bit] NULL,
	[kilobytes_per_batch] [int] NULL,
	[lastrow] [int] NULL,
	[maxerrors] [int] NULL,
	[order] [varchar] (500) NULL,
	[rows_per_batch] [int] NULL,
	[rowterminator] [nvarchar] (10) NULL,
	[tablock] [bit] NULL,
	[errorfile] [nvarchar] (250) NULL,
 CONSTRAINT[PK_type] PRIMARY KEY CLUSTERED
(
   [id] ASC
)WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON[PRIMARY]
) ON[PRIMARY]
;
CREATE TABLE[meta].[user]
        (

   [id][bigint] IDENTITY(1,1) NOT NULL,

  [username] [nvarchar] (50) NOT NULL,

   [realname] [nvarchar] (100) NULL,
	[description] [nvarchar] (1000) NULL,
	[createdtm]
        [datetime]
        NOT NULL,
 CONSTRAINT[PK_user] PRIMARY KEY CLUSTERED
(
   [id] ASC
)WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON[PRIMARY]
) ON[PRIMARY]
;
CREATE
VIEW[meta].[agreement_delivery_count_v] --|
--| ==========================================================================================
--| Description: Agreement details combined with delivery count in each stage
--| ==========================================================================================
AS
SELECT a.id, 
       a.name, 
       a.description,
       a.pattern,
       a.createdtm,
       a.modifydtm,
       a.frequency,
       a.file2temp,
       a.temp2stag,
       a.stag2repo,
       t.id AS type_id,
       t.name AS type_name,
       g.id AS group_id,
       g.name AS group_name, 
       u.id AS user_id,
       u.username AS user_name,
       u.realname AS user_realname,
       COALESCE(temp.cnt, 0) AS temp_count,
       COALESCE(stag.cnt, 0) AS stag_count,
       COALESCE(repo.cnt, 0) AS repo_count
  FROM meta.agreement a
       LEFT OUTER JOIN
       --+ Agreement ID, # deliveries in stage TEMP
       (SELECT d.agreement_id, COUNT(*) AS cnt
          FROM meta.delivery d,
               (SELECT delivery_id,
                       MAX(stage_id) AS stage_id
                  FROM meta.audit
                 GROUP BY delivery_id) u
         WHERE d.id       = u.delivery_id
           AND u.stage_id = 1 -- temp
         GROUP by d.agreement_id) temp ON a.id = temp.agreement_id
       LEFT OUTER JOIN
       --+ Agreement ID, # deliveries in stage STAG
       (SELECT d.agreement_id, COUNT(*) AS cnt
          FROM meta.delivery d,
               (SELECT delivery_id,
                       MAX(stage_id) AS stage_id
                  FROM meta.audit
                 GROUP BY delivery_id) u
         WHERE d.id       = u.delivery_id
           AND u.stage_id = 2 -- stag
         GROUP by d.agreement_id) stag ON a.id = stag.agreement_id
       LEFT OUTER JOIN
       --+ Agreement ID, # deliveries in stage REPO
       (SELECT d.agreement_id, COUNT(*) AS cnt
          FROM meta.delivery d,
               (SELECT delivery_id,
                       MAX(stage_id) AS stage_id
                  FROM meta.audit
                 GROUP BY delivery_id) u
         WHERE d.id       = u.delivery_id
           AND u.stage_id = 3 --repo
         GROUP by d.agreement_id) repo ON a.id = repo.agreement_id,       
       meta.[type] t,
       meta.[group] g,
       meta.[user] u
 WHERE t.id = a.type_id
   AND g.id = a.group_id
   AND u.id = a.user_id
;
CREATE TABLE[meta].[operation](

    [id] [bigint] IDENTITY(1,1) NOT NULL,

    [audit_id] [bigint]
        NOT NULL,

    [status_id] [bigint]
        NOT NULL,

    [createdtm] [datetime]
        NOT NULL,

    [name] [nvarchar] (50) NOT NULL,
 
     [description] [nvarchar] (250) NULL,
 CONSTRAINT[PK_operation] PRIMARY KEY CLUSTERED
(
   [id] ASC
)WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON[PRIMARY]
) ON[PRIMARY]
;
CREATE TABLE[meta].[stage]
        (

   [id][bigint] IDENTITY(1,1) NOT NULL,

  [name] [nvarchar] (50) NOT NULL,

   [description] [nvarchar] (1000) NOT NULL,
 CONSTRAINT[PK_stage] PRIMARY KEY CLUSTERED
(
   [id] ASC
)WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON[PRIMARY]
) ON[PRIMARY]
;
CREATE
VIEW[meta].[agreement_delivery_max_audit_v] --|
--| ==========================================================================================
--| Description: Repeat agreement details for every delivery made along with the latest(MAX)
--|              audit stage of the delivery
--| ==========================================================================================
AS
SELECT a.name AS agreement_name, 
       a.id AS agreement_id,
       g.name AS agreement_group, 
       a.description AS agreement_description, 
       a.pattern AS agreement_pattern, 
       d.name AS delivery_name, 
       d.id AS delivery_id,
       s.realname AS delivery_owner, 
       d.createdtm AS delivery_createdtm, 
       d.size AS delivery_size, 
       d.status_date AS delivery_status_date,
       u.name AS stage_name, 
       u.createdtm AS audit_createdtm,
       u.description AS audit_description,
       u.status_id AS status_id,
       d.user_id AS user_id
FROM meta.agreement a,
 meta.[group] g,
       meta.[user] s,
       meta.delivery d,
       (SELECT u.*, s.name, p.*
          FROM meta.audit u,
               meta.stage s,
               (SELECT MAX(o.status_id) AS status_id, audit_id
                  FROM meta.operation o
                 GROUP BY audit_id) p
         WHERE u.stage_id = s.id
           AND p.audit_id = u.id) u
 WHERE g.id = a.group_id
   AND s.id = d.user_id
   AND a.id = d.agreement_id
   AND u.id = (SELECT MAX(id)
                 FROM meta.audit u2
                WHERE u2.delivery_id = d.id)

;
CREATE TABLE[meta].[table]
        (

   [id][bigint] IDENTITY(1,1) NOT NULL,

  [name] [nvarchar] (100) NOT NULL,

   [schema] [nvarchar] (50) NOT NULL,

    [createdtm] [datetime]
        NOT NULL,

    [temporary] [bit]
        NOT NULL,

    [permanent] [bit]
        NOT NULL,
 CONSTRAINT[PK_table] PRIMARY KEY CLUSTERED
(
   [id] ASC
)WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON[PRIMARY]
) ON[PRIMARY]
;
CREATE
VIEW[meta].[agreement_stage_table_v] --|
--| ==========================================================================================
--| Description: Map agreement to stage table for easy lookup via audit.
--| ==========================================================================================
AS
SELECT a.id AS agreement_id,
       u.id AS audit_id_init,
       g.name AS table_schema,
       t.name +
       CASE
           WHEN g.id       <=   2 THEN ''  -- stage_id <= init, temp, stag
           WHEN a.frequency = 1 THEN '_' + CAST(YEAR(GETDATE()) AS NVARCHAR) + RIGHT('0' + CAST(MONTH(GETDATE()) AS NVARCHAR), 2) + RIGHT('0' + CAST(DAY(GETDATE()) AS NVARCHAR), 2)

           WHEN a.frequency =  30 THEN '_' + CAST(YEAR(GETDATE()) AS NVARCHAR) + RIGHT('0' + CAST(MONTH(GETDATE()) AS NVARCHAR), 2)

           WHEN a.frequency = 365 THEN '_' + CAST(YEAR(GETDATE()) AS NVARCHAR)

           ELSE ''
	   END AS table_name,
       (SELECT id
          FROM meta.[table]
         WHERE[schema] = g.name
           AND name = t.name
                    + CASE

                          WHEN g.id       <=   2 THEN '' -- stage_id <= init, temp, stag
                          WHEN a.frequency = 1 THEN '_' + CAST(YEAR(GETDATE()) AS NVARCHAR) + RIGHT('0' + CAST(MONTH(GETDATE()) AS NVARCHAR), 2) + RIGHT('0' + CAST(DAY(GETDATE()) AS NVARCHAR), 2)

                          WHEN a.frequency =  30 THEN '_' + CAST(YEAR(GETDATE()) AS NVARCHAR) + RIGHT('0' + CAST(MONTH(GETDATE()) AS NVARCHAR), 2)

                          WHEN a.frequency = 365 THEN '_' + CAST(YEAR(GETDATE()) AS NVARCHAR)

                          ELSE ''
					  END)
				   AS table_id,
       g.id AS stage_id
FROM meta.agreement a,
meta.delivery d,
meta.audit u,
meta.[table] t,
       meta.stage g,
       meta.stage i
 WHERE a.id = d.agreement_id
   AND d.id = u.delivery_id
   AND t.id = u.table_id
   AND i.id = u.stage_id
   AND i.id = 0-- INIT delivery
;
CREATE TABLE[meta].[type_map](

    [id] [int] IDENTITY(1,1) NOT NULL,

    [data_type] [nvarchar] (128) NULL,
	[mapping] [nvarchar] (4000) NULL,
	[agreement_id] [bigint] NULL,
	[column_name] [nvarchar] (128) NULL
) ON[PRIMARY]
;
CREATE
VIEW[meta].[column_mapping_v] --|
--| ==========================================================================================
--| Description: Map agreement tables to columns for each stage
--| ==========================================================================================
AS
SELECT c.agreement_id,
       c.table_schema,
       c.table_name,
       CASE
           WHEN c.table_schema = 'temp' THEN 'CAST([' + c.column_name + '] AS NVARCHAR(' + CAST(COALESCE(c.character_maximum_length, 50) AS NVARCHAR) + '))'
           WHEN c.table_schema = 'repo' THEN '[' + c.column_name + ']'
           WHEN m.column_name IS NOT NULL THEN REPLACE(REPLACE(REPLACE(REPLACE(COALESCE(m.mapping, '[' + m.column_name + ']'), '{column}', '[' + c.COLUMN_NAME + ']'), '{precision}', COALESCE(c.NUMERIC_PRECISION, '')), '{scale}', COALESCE(c.NUMERIC_SCALE, '')), '{length}', COALESCE(c.CHARACTER_MAXIMUM_LENGTH, '')) 
           WHEN n.column_name IS NOT NULL THEN REPLACE(REPLACE(REPLACE(REPLACE(COALESCE(n.mapping, '[' + n.column_name + ']'), '{column}', '[' + c.COLUMN_NAME + ']'), '{precision}', COALESCE(c.NUMERIC_PRECISION, '')), '{scale}', COALESCE(c.NUMERIC_SCALE, '')), '{length}', COALESCE(c.CHARACTER_MAXIMUM_LENGTH, '')) 
           WHEN o.data_type   IS NOT NULL THEN REPLACE(REPLACE(REPLACE(REPLACE(COALESCE(o.mapping, '[' + c.column_name + ']'), '{column}', '[' + c.COLUMN_NAME + ']'), '{precision}', COALESCE(c.NUMERIC_PRECISION, '')), '{scale}', COALESCE(c.NUMERIC_SCALE, '')), '{length}', COALESCE(c.CHARACTER_MAXIMUM_LENGTH, '')) 
           ELSE '[' + c.column_name + ']'
       END AS mapping, 
       CASE
           WHEN m.mapping IS NOT NULL THEN 'Agreement'
           WHEN n.mapping IS NOT NULL THEN 'Name'
           WHEN o.mapping IS NOT NULL THEN 'Default'
           ELSE                            ''
       END AS mapping_type,
       '[' + c.column_name + ']' AS column_name,
       c.data_type,
       c.character_maximum_length,
       c.numeric_precision,
       c.numeric_scale,
       c.ordinal_position
  FROM (SELECT a.agreement_id, b.*
          FROM meta.agreement_stage_table_v a,
               INFORMATION_SCHEMA.COLUMNS b
         WHERE a.table_name   = b.table_name
           AND a.table_schema = b.table_schema) c
        LEFT OUTER JOIN
        meta.type_map m ON(UPPER(c.column_name) = UPPER(m.column_name) AND m.agreement_id = c.agreement_id)
        LEFT OUTER JOIN
        meta.type_map n ON (UPPER(c.column_name) = UPPER(n.column_name) AND n.agreement_id IS NULL)
        LEFT OUTER JOIN
        meta.type_map o ON (UPPER(c.data_type)   = UPPER(o.data_type)   AND o.agreement_id IS NULL)


--select* from meta.column_mapping_v where agreement_id = 166
;
CREATE TABLE[meta].[status]
        (

   [id][bigint] IDENTITY(1,1) NOT NULL,

  [description] [nvarchar] (250) NULL,
 CONSTRAINT[PK_status] PRIMARY KEY CLUSTERED
(
   [id] ASC
)WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON[PRIMARY]
) ON[PRIMARY]
;
CREATE
VIEW[meta].[delivery_id_audit_operation_v] --|
--| ==========================================================================================
--| Description: Repeat delivery_id for every audit stage operation performed on the delivery
--| ==========================================================================================
AS
SELECT d.agreement_id AS agreement_id,
       u.delivery_id AS delivery_id, 
       u.id AS audit_id,
       u.createdtm AS audit_createdtm,
       u.description AS audit_description,
       g.id AS stage_id,
       g.name AS stage_name, 
       t.id AS table_id,
       t.[schema] AS table_schema,
       t.name AS table_name, 
       t.createdtm AS table_createdtm,
       o.id AS operation_id,
       o.createdtm AS operation_createdtm,
       o.name AS operation_name,
       o.description AS operation_description,
       s.id AS status_id,
       s.description AS status_description
FROM meta.delivery d,
     meta.audit u,
     meta.[table] t,
       meta.stage g,
       meta.operation o,
       meta.status s
 WHERE d.id = u.delivery_id
   AND t.id = u.table_id
   AND g.id = u.stage_id
   AND u.id = o.audit_id
   AND s.id = o.status_id

;
CREATE TABLE[meta].[access](

    [id] [bigint] IDENTITY(1,1) NOT NULL,

    [name] [nvarchar] (50) NOT NULL,
 
     [description] [nvarchar] (1000) NULL,
 CONSTRAINT[PK_access] PRIMARY KEY CLUSTERED
(
   [id] ASC
)WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON[PRIMARY]
) ON[PRIMARY]
;
CREATE TABLE[meta].[group_agreement]
        (

   [group_id][bigint] NOT NULL,

   [agreement_id] [bigint]
        NOT NULL,

   [access_id] [bigint]
        NOT NULL,

   [createdtm] [datetime]
        NOT NULL
) ON[PRIMARY]
;
CREATE
VIEW[meta].[group_access_v] --|
--| ==========================================================================================
--| Description: Group access to agreements 
--| ==========================================================================================
AS
SELECT ga.group_id,     g.name AS groupname, 
       ga.agreement_id, a.name AS agreementname, 
       ga.access_id,    c.name AS accessname
  FROM meta.[group] g,
       meta.[agreement] a,
       meta.[access] c,
       meta.group_agreement ga
 WHERE g.id = ga.group_id
   and a.id = ga.agreement_id
   and c.id = ga.access_id
UNION
SELECT g.id, g.name AS groupname,
       a.id, a.name AS agreementname,
       c.id, c.name AS accessname
  FROM meta.[group] g,
       meta.[agreement] a,
       meta.[access] c
 WHERE g.name = 'ADMIN'
   AND NOT EXISTS (SELECT 1
                     FROM meta.group_agreement ga
                    WHERE a.id = ga.agreement_id
                      AND c.id = ga.access_id
                      AND g.id = ga.group_id)
                      
                      
--select agreementname, groupname, count(*) from[meta].[group_access_v] group by agreementname, groupname
;
CREATE TABLE[meta].[link]
        (

   [id][bigint] IDENTITY(1,1) NOT NULL,

  [external_id] [bigint] NULL,
	[dw_delivery_id] [bigint] NULL,
	[createdtm]
        [datetime]
        NOT NULL,

    [user_id] [bigint] NULL,
	[status_id]
        [bigint]
        NOT NULL
) ON[PRIMARY]
;
CREATE
VIEW[meta].[link_v] --|
--| ==========================================================================================
--| Description: External link details of deliveries
--| ==========================================================================================
AS
SELECT l.id,
       l.external_id,
       l.dw_delivery_id,
       l.user_id,
       l.status_id,
       l.createdtm,
       COALESCE(d.agreement_id, -1) AS agreement_id,
       COALESCE(u.username, 'N/A')  AS user_username,
       COALESCE(u.realname, 'N/A')  AS user_realname,
       COALESCE(d.name, 'N/A')  AS delivery_name
  FROM meta.link l
       LEFT OUTER JOIN
       meta.delivery d
       ON (d.id = l.dw_delivery_id)
       LEFT OUTER JOIN
       meta.[user] u
       ON (u.id = l.user_id)
;
CREATE TABLE[meta].[usage_log]
        (

   [id][bigint] IDENTITY(1,1) NOT NULL,

  [user_id] [bigint]
        NOT NULL,

  [path] [nvarchar] (250) NULL,
	[query] [nvarchar] (1000) NULL,
	[createdtm]
        [datetime]
        NOT NULL,
 CONSTRAINT[PK_usage_log] PRIMARY KEY CLUSTERED
(
   [id] ASC
)WITH(PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON[PRIMARY]
) ON[PRIMARY]
;
CREATE
VIEW[meta].[usage_v] --|
--| ==========================================================================================
--| Description: User activity
--| ==========================================================================================
AS
SELECT l.user_id, 
       COALESCE(u.username, 'N/A') AS username,
       COALESCE(u.realname, 'N/A') AS realname,
       l.createdtm, l.path, l.query
  FROM meta.usage_log l
       LEFT OUTER JOIN
       meta.[user] u ON (l.user_id = u.id)
;
CREATE TABLE[meta].[user_group]
        (

   [user_id][bigint] NOT NULL,

   [group_id] [bigint]
        NOT NULL,

   [createdtm] [datetime]
        NOT NULL
) ON[PRIMARY]
;
CREATE
VIEW[meta].[user_access_v] --|
--| ==========================================================================================
--| Description: User access to agreements via group memberships
--| ==========================================================================================
AS
SELECT ug.user_id,      u.username, u.realname,
       ug.group_id,     g.name AS groupname, 
       ga.agreement_id, a.name AS agreementname, 
       ga.access_id,    c.name AS accessname
  FROM meta.[user] u,
       meta.[group] g,
       meta.[agreement] a,
       meta.[access] c,
       meta.user_group ug,
       meta.group_agreement ga
 WHERE u.id = ug.user_id
   and g.id = ug.group_id
   and g.id = ga.group_id
   and a.id = ga.agreement_id
   and c.id = ga.access_id
UNION
SELECT u.id, u.username, u.realname,
       g.id, g.name AS groupname,
       a.id, a.name AS agreementname,
       c.id, c.name AS accessname
  FROM meta.[user] u,
       meta.[group] g,
       meta.[agreement] a,
       meta.[access] c
 WHERE g.name = 'ADMIN'
   AND EXISTS (SELECT 1
                 FROM user_group ug
                WHERE u.id = ug.user_id
                  AND g.id = ug.group_id)
;
CREATE
VIEW[meta].[user_group_v] --|
--| ==========================================================================================
--| Description: User group memberships
--| ==========================================================================================
AS
SELECT uxg.*, ug.createdtm
  FROM(SELECT u.id as user_id, u.username, u.realname, u.description AS user_description,
               g.id as group_id, g.name AS group_name, g.description AS group_description
          FROM meta.[user] u,
               meta.[group] g) uxg
       LEFT OUTER JOIN
       meta.user_group ug ON uxg.user_id = ug.user_id AND uxg.group_id = ug.group_id
;
CREATE
VIEW[meta].[user_v] --|
--| ==========================================================================================
--| Description: User details
--| ==========================================================================================
AS
SELECT u.id,
       u.username,
       u.realname,
       u.description,
       u.createdtm,
       COALESCE(d.cnt, 0) AS delivery_count
  FROM meta.[user]    u
       LEFT OUTER JOIN
       (SELECT user_id, COUNT(*) AS cnt
          FROM meta.delivery
         GROUP BY user_id) d
       ON(u.id = d.user_id)

;
CREATE
FUNCTION[meta].[get_agreements] --|
--| ==========================================================================================
--| Description: Return the agreements and relevant fields based on status date
--| Arguments:
(
    @date NVARCHAR(10) --| Status date to filter on(YYYY-MM-DD)
)
RETURNS TABLE
AS        
--| ------------------------------------------------------------------------------------------
RETURN
SELECT a.*,
       t.name AS type_name, 
       u.realname AS user_realname,
       g.name AS group_name, 
       e.err, 
       COALESCE(o.ok, 0) AS ok,
       s.status_date, 
       s.diff_pct
  FROM meta.agreement a
       JOIN
       meta.[group] g
       ON (g.id = a.group_id)
       JOIN
       meta.[user] u
       ON (u.id = a.user_id)
       JOIN
       meta.[type] t
       ON (t.id = a.type_id)
       LEFT OUTER JOIN
       --+ Failed deliveries
       (SELECT agreement_id, COUNT(*) AS err
          FROM meta.agreement_delivery_max_audit_v
         WHERE status_id<> 1
         GROUP by agreement_id) e
       ON(a.id = e.agreement_id)
       LEFT OUTER JOIN
       --+ OK deliveries
       (SELECT agreement_id, COUNT(*) AS ok
          FROM meta.agreement_delivery_max_audit_v
         WHERE status_id = 1
           AND stage_name = 'repo'
         GROUP by agreement_id) o
       ON(a.id = o.agreement_id)
       LEFT OUTER JOIN
       (SELECT d.agreement_id,
               MAX(d.status_date) AS status_date,
               CAST(CAST(t.value - DATEDIFF(day, MAX(d.status_date), CONVERT(datetime, @date, 120)) AS NUMERIC(10,2))
                    / CAST(NULLIF(t.value, 0) AS NUMERIC(10,2)) AS NUMERIC(4,2)) AS diff_pct
          FROM meta.delivery d
               JOIN
               meta.agreement_attribute_v t
               ON (d.agreement_id = t.agreement_id AND t.attribute_name = 'MAX_AGE_DAYS')
         WHERE d.status_date BETWEEN CONVERT(datetime, @date, 120) - CAST(t.value AS INT)
                                 AND CONVERT(datetime, @date, 120)
         GROUP BY d.agreement_id, t.value) s
       ON(a.id = s.agreement_id)

--| ------------------------------------------------------------------------------------------
;
CREATE TABLE[meta].[agreement_rule]
        (

   [id][bigint] IDENTITY(1,1) NOT NULL,

  [agreement_id] [bigint]
        NOT NULL,

  [rule_id] [int] NOT NULL,

  [rule_text] [nvarchar] (4000) NOT NULL
) ON[PRIMARY]
;
ALTER TABLE[meta].[agreement] ADD CONSTRAINT[DF_agreement_type_id]  DEFAULT((0)) FOR[type_id]
;
ALTER TABLE[meta].[agreement] ADD CONSTRAINT[DF_agreement_createdtm]  DEFAULT(getdate()) FOR[createdtm]
;
ALTER TABLE[meta].[agreement] ADD CONSTRAINT[DF_agreement_modifydtm]  DEFAULT(getdate()) FOR[modifydtm]
;
ALTER TABLE[meta].[agreement] ADD CONSTRAINT[DF_agreement_frequency]  DEFAULT((0)) FOR[frequency]
;
ALTER TABLE[meta].[agreement_attribute] ADD CONSTRAINT[DF_agreement_attribute_createdtm]  DEFAULT(getdate()) FOR[createdtm]
;
ALTER TABLE[meta].[attribute] ADD CONSTRAINT[DF_attribute_createdtm]  DEFAULT(getdate()) FOR[createdtm]
;
ALTER TABLE[meta].[audit] ADD CONSTRAINT[DF_audit_createdtm]  DEFAULT(getdate()) FOR[createdtm]
;
ALTER TABLE[meta].[delivery] ADD CONSTRAINT[DF_file_createdtm]  DEFAULT(getdate()) FOR[createdtm]
;
ALTER TABLE[meta].[group] ADD DEFAULT(getdate()) FOR[createdtm]
;
ALTER TABLE[meta].[group_agreement] ADD DEFAULT(getdate()) FOR[createdtm]
;
ALTER TABLE[meta].[link] ADD CONSTRAINT[DF_link_createdtm]  DEFAULT(getdate()) FOR[createdtm]
;
ALTER TABLE[meta].[operation] ADD CONSTRAINT[DF_operation_createdtm]  DEFAULT(getdate()) FOR[createdtm]
;
ALTER TABLE[meta].[table] ADD CONSTRAINT[DF_table_createdtm]  DEFAULT(getdate()) FOR[createdtm]
;
ALTER TABLE[meta].[table] ADD CONSTRAINT[DF_table_temporary]  DEFAULT((0)) FOR[temporary]
;
ALTER TABLE[meta].[table] ADD CONSTRAINT[DF_table_permanent]  DEFAULT((1)) FOR[permanent]
;
ALTER TABLE[meta].[usage_log] ADD DEFAULT(getdate()) FOR[createdtm]
;
ALTER TABLE[meta].[user] ADD DEFAULT(getdate()) FOR[createdtm]
;
ALTER TABLE[meta].[user_group] ADD DEFAULT(getdate()) FOR[createdtm]
;
ALTER TABLE[meta].[agreement] WITH CHECK ADD CONSTRAINT[FK_agreement_group] FOREIGN KEY([group_id])
REFERENCES[meta].[group]
        ([id])
;
ALTER TABLE[meta].[agreement]
        CHECK CONSTRAINT[FK_agreement_group]
;
ALTER TABLE[meta].[agreement] WITH CHECK ADD CONSTRAINT[FK_agreement_type] FOREIGN KEY([type_id])
REFERENCES[meta].[type]
        ([id])
;
ALTER TABLE[meta].[agreement]
        CHECK CONSTRAINT[FK_agreement_type]
;
ALTER TABLE[meta].[agreement] WITH CHECK ADD CONSTRAINT[FK_agreement_user] FOREIGN KEY([user_id])
REFERENCES[meta].[user]
        ([id])
;
ALTER TABLE[meta].[agreement]
        CHECK CONSTRAINT[FK_agreement_user]
;
ALTER TABLE[meta].[agreement_attribute] WITH CHECK ADD CONSTRAINT[FK_agreement_attribute_agreement] FOREIGN KEY([agreement_id])
REFERENCES[meta].[agreement]
        ([id])
;
ALTER TABLE[meta].[agreement_attribute]
        CHECK CONSTRAINT[FK_agreement_attribute_agreement]
;
ALTER TABLE[meta].[agreement_attribute] WITH CHECK ADD CONSTRAINT[FK_agreement_attribute_attribute] FOREIGN KEY([attribute_id])
REFERENCES[meta].[attribute]
        ([id])
;
ALTER TABLE[meta].[agreement_attribute]
        CHECK CONSTRAINT[FK_agreement_attribute_attribute]
;
ALTER TABLE[meta].[agreement_rule] WITH CHECK ADD CONSTRAINT[FK_agreement_rule_agreement] FOREIGN KEY([agreement_id])
REFERENCES[meta].[agreement]
        ([id])
;
ALTER TABLE[meta].[agreement_rule]
        CHECK CONSTRAINT[FK_agreement_rule_agreement]
;
ALTER TABLE[meta].[audit] WITH CHECK ADD CONSTRAINT[FK_audit_delivery] FOREIGN KEY([delivery_id])
REFERENCES[meta].[delivery]
        ([id])
;
ALTER TABLE[meta].[audit]
        CHECK CONSTRAINT[FK_audit_delivery]
;
ALTER TABLE[meta].[audit] WITH CHECK ADD CONSTRAINT[FK_audit_stage] FOREIGN KEY([stage_id])
REFERENCES[meta].[stage]
        ([id])
;
ALTER TABLE[meta].[audit]
        CHECK CONSTRAINT[FK_audit_stage]
;
ALTER TABLE[meta].[audit] WITH CHECK ADD CONSTRAINT[FK_audit_table] FOREIGN KEY([table_id])
REFERENCES[meta].[table]
        ([id])
;
ALTER TABLE[meta].[audit]
        CHECK CONSTRAINT[FK_audit_table]
;
ALTER TABLE[meta].[delivery] WITH CHECK ADD CONSTRAINT[FK_delivery_agreement] FOREIGN KEY([agreement_id])
REFERENCES[meta].[agreement]
        ([id])
;
ALTER TABLE[meta].[delivery]
        CHECK CONSTRAINT[FK_delivery_agreement]
;
ALTER TABLE[meta].[delivery] WITH CHECK ADD CONSTRAINT[FK_delivery_user] FOREIGN KEY([user_id])
REFERENCES[meta].[user]
        ([id])
;
ALTER TABLE[meta].[delivery]
        CHECK CONSTRAINT[FK_delivery_user]
;
ALTER TABLE[meta].[group_agreement] WITH CHECK ADD CONSTRAINT[FK_group_agreement_access] FOREIGN KEY([access_id])
REFERENCES[meta].[access]
        ([id])
;
ALTER TABLE[meta].[group_agreement]
        CHECK CONSTRAINT[FK_group_agreement_access]
;
ALTER TABLE[meta].[group_agreement] WITH CHECK ADD CONSTRAINT[FK_group_agreement_agreement] FOREIGN KEY([agreement_id])
REFERENCES[meta].[agreement]
        ([id])
;
ALTER TABLE[meta].[group_agreement]
        CHECK CONSTRAINT[FK_group_agreement_agreement]
;
ALTER TABLE[meta].[group_agreement] WITH CHECK ADD CONSTRAINT[FK_group_agreement_group] FOREIGN KEY([group_id])
REFERENCES[meta].[group]
        ([id])
;
ALTER TABLE[meta].[group_agreement]
        CHECK CONSTRAINT[FK_group_agreement_group]
;
ALTER TABLE[meta].[link] WITH CHECK ADD CONSTRAINT[FK_link_status] FOREIGN KEY([status_id])
REFERENCES[meta].[status]
        ([id])
;
ALTER TABLE[meta].[link]
        CHECK CONSTRAINT[FK_link_status]
;
ALTER TABLE[meta].[operation] WITH CHECK ADD CONSTRAINT[FK_operation_audit] FOREIGN KEY([audit_id])
REFERENCES[meta].[audit]
        ([id])
;
ALTER TABLE[meta].[operation]
        CHECK CONSTRAINT[FK_operation_audit]
;
ALTER TABLE[meta].[operation] WITH CHECK ADD CONSTRAINT[FK_operation_status] FOREIGN KEY([status_id])
REFERENCES[meta].[status]
        ([id])
;
ALTER TABLE[meta].[operation]
        CHECK CONSTRAINT[FK_operation_status]
;
ALTER TABLE[meta].[user_group] WITH CHECK ADD CONSTRAINT[FK_user_group_group] FOREIGN KEY([group_id])
REFERENCES[meta].[group]
        ([id])
;
ALTER TABLE[meta].[user_group]
        CHECK CONSTRAINT[FK_user_group_group]
;
ALTER TABLE[meta].[user_group] WITH CHECK ADD CONSTRAINT[FK_user_group_user] FOREIGN KEY([user_id])
REFERENCES[meta].[user]
        ([id])
;
ALTER TABLE[meta].[user_group]
        CHECK CONSTRAINT[FK_user_group_user]
;
CREATE PROCEDURE[dbo].[define] --|
--| ==========================================================================================
--| Description: Management procedure for defining a template procedure, function or view.
--|              The reason for this is to use the ALTER xxx statement in the remaining scripts
--|              creating the API procedures - instead of an initial DROP xxx statement,
--|              which would remove all grants and ownership.
--|              Unfortunately SQL Server does not support CREATE OR REPLACE

--| NOTE:        Bootstrap procedure to be created before loading the remainder of the API
--| ==========================================================================================
(
    @type NVARCHAR(25), -- PROCEDURE, FUNCTION or VIEW
  @obj    NVARCHAR(200)
)
AS
BEGIN
    DECLARE @sql NVARCHAR(250)

	--+ Define procedure

    IF UPPER(@type) = 'PROCEDURE'
		IF NOT EXISTS(SELECT* FROM sys.procedures WHERE object_id = OBJECT_ID(@obj))

            SET @sql = 'CREATE PROCEDURE ' + @obj + ' AS SELECT 1'

    -- + Define function
     IF UPPER(@type) = 'FUNCTION'
		IF NOT EXISTS(SELECT* FROM sys.objects WHERE object_id = OBJECT_ID(@obj))

            SET @sql = 'CREATE FUNCTION ' + @obj + '() RETURNS INT AS BEGIN RETURN 1 END'

    -- + Define view
     IF UPPER(@type) = 'VIEW'
		IF NOT EXISTS(SELECT* FROM sys.views WHERE object_id = OBJECT_ID(@obj))

            SET @sql = 'CREATE VIEW ' + @obj + ' AS SELECT 1 AS dummy'

    -- + Execute the SQL statement
     IF LEN(@sql) > 0 EXEC sp_executesql @sql
 END
;
CREATE
PROCEDURE[meta].[operation_add] --|
--| ==========================================================================================
--| Description: Add a new operation log entry
--| NOTE:        Used for logging to the system and therefore assumed to always succeed.If
--|              this does not hold true, the return value need to be checked which would
--|              render the code too complex.
--| Arguments:
(
    @audit_id BIGINT,        --| ID of audit entry to log operation for
    @status_id BIGINT,        --| ID of status of entry to log
    @pid           BIGINT,        --| @@PROCID of calling procedure
    @description NVARCHAR(250)  --| Human readable message to log
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    --| Add operation to log by looking up the PID
    EXEC meta.debug @@PROCID, 'Insert into operation table'

    INSERT INTO meta.operation
           (audit_id, status_id, name, description)
    VALUES(@audit_id, @status_id, OBJECT_SCHEMA_NAME(@pid) + '.' + OBJECT_NAME(@pid), COALESCE(@description, ERROR_MESSAGE(), ''))

    EXEC meta.debug @@PROCID, 'DONE'

    --| Return success
    RETURN
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[group_agreement_add] --|
--| ==========================================================================================
--| Description: Add an access for a group to an agreement - checking for doublets
--| Arguments:
(
    @group_id BIGINT,        --| ID of the group
    @agreement_id BIGINT,        --| ID of the agreement
    @access_id BIGINT         --| ID of the access
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @exists BIGINT

    --| Check if group_agreement entry already exists
    EXEC meta.debug @@PROCID, 'Check if entry already exists'
    SELECT @exists = 1
      FROM meta.group_agreement
     WHERE group_id     = @group_id
       AND agreement_id = @agreement_id
       AND access_id = @access_id

    IF @exists IS NULL
    BEGIN
        --| Insert new entry if not existing
        INSERT INTO meta.group_agreement
               (group_id, agreement_id, access_id)
        VALUES(@group_id, @agreement_id, @access_id)

        EXEC meta.debug @@PROCID, 'group_agreement entry inserted'
    END

    EXEC meta.debug @@PROCID, 'DONE'
    --| Return success
    RETURN
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[generic_file2temp] --|
--| ==========================================================================================
--| Description: Load the data from the delivery file into the load table in temp.
--|              Use the provided name to lookup the agreement and other information from meta
--|              data and make sure the temp schema table is created and populated from the
--|              specified file name.
--| Arguments:             
(
    @delivery_id BIGINT,
    @path NVARCHAR(250)
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN

    DECLARE @count INT
    DECLARE @agreement_id  BIGINT
    DECLARE @name NVARCHAR(250)
    DECLARE @size          BIGINT

    --| Lookup the essential arguments from the delivery
    SELECT @agreement_id = agreement_id, @name = name, @size = size
      FROM meta.delivery
     WHERE id = @delivery_id

    --| Lookup the type details from the delivery_id via the agreement
    EXEC meta.debug @@PROCID, 'Lookup type details name in meta data via agreement'
    DECLARE @schema              NVARCHAR(50)
    DECLARE @table               NVARCHAR(128)
    -- BULK INSERT arguments
    DECLARE @batchsize INT
    DECLARE @check_constraints   BIT
    DECLARE @codepage NVARCHAR(10)
    DECLARE @datafiletype        NVARCHAR(10)
    DECLARE @fieldterminator     NVARCHAR(10)
    DECLARE @firstrow            INT
    DECLARE @fire_triggers BIT
    DECLARE @format_file         NVARCHAR(250)
    DECLARE @keepidentity        BIT
    DECLARE @keepnulls BIT
    DECLARE @kilobytes_per_batch INT
    DECLARE @lastrow INT
    DECLARE @maxerrors           INT
    DECLARE @order NVARCHAR(500)
    DECLARE @rows_per_batch      INT
    DECLARE @rowterminator NVARCHAR(10)
    DECLARE @tablock             BIT
    DECLARE @errorfile NVARCHAR(250)
    DECLARE @nvarchar_max_load   NVARCHAR(1000)

    SELECT @schema = t.table_schema,
           @table = t.table_name,
           @nvarchar_max_load = u.value,
           -- BULK INSERT arguments
           @batchsize = y.[batchsize],
           @check_constraints = y.[check_constraints],
           @codepage = y.[codepage],
           @datafiletype = y.[datafiletype],
           @fieldterminator = y.[fieldterminator],
           @firstrow = y.[firstrow],
           @fire_triggers = y.[fire_triggers],
           @format_file = y.[format_file],
           @keepidentity = y.[keepidentity],
           @keepnulls = y.[keepnulls],
           @kilobytes_per_batch = y.[kilobytes_per_batch],
           @lastrow = y.[lastrow],
           @maxerrors = y.[maxerrors],
           @order = y.[order],
           @rows_per_batch = y.[rows_per_batch],
           @rowterminator = y.[rowterminator],
           @tablock = y.[tablock],
           @errorfile = y.[errorfile]
      FROM meta.[type]                  y,
           meta.agreement a,
           meta.agreement_stage_table_v t,
           meta.agreement_attribute_v u
     WHERE a.id = t.agreement_id
       AND a.id = u.agreement_id
       AND y.id = a.type_id
       AND a.id = @agreement_id
       AND t.table_schema   = 'temp'
       AND u.attribute_name = 'NVARCHAR_MAX_LOAD'

    -- + Prepend path to form the full name of the delivery
    SET @name = @path + '\' + @name

    -- + Set the field limiter to \0 if row size of target table exceeds 4000 (NVARCHAR) due to
    --+ hard limit of 8060 in MS SQL. This is optional as some data deliveries manages - others
    --+ dont - and changing the behavior has a great performance impact.
    --+ The attribute NVARCHAR_MAX_LOAD controls the setting.
    IF @nvarchar_max_load = 'YES' SET @fieldterminator = '\0'

    -- | Prepare BULK INSERT statement from retrieved parameters (meta.type)
    DECLARE @sql NVARCHAR(4000)
    EXEC meta.debug @@PROCID, 'Prepare BULK INSERT statement'   
    SET @sql = 'BULK INSERT [' + @schema + '].[' + @table + '] FROM ''' + @name + ''' WITH ('
    
    --+ Replace dynamic parameters
    SET @errorfile   = REPLACE(@errorfile, '{datafile}', @name)
    SET @format_file = REPLACE(@format_file, '{datafile}', @name)

    IF @batchsize           IS NOT NULL SET @sql = @sql + 'BATCHSIZE='''         + @batchsize           + ''','
    IF @codepage            IS NOT NULL SET @sql = @sql + 'CODEPAGE='''          + @codepage            + ''','
    IF @datafiletype        IS NOT NULL SET @sql = @sql + 'DATAFILETYPE='''      + @datafiletype        + ''','
    IF @fieldterminator     IS NOT NULL SET @sql = @sql + 'FIELDTERMINATOR='''   + @fieldterminator     + ''','
    IF @format_file         IS NOT NULL SET @sql = @sql + 'FORMAT_FILE='''       + @format_file         + ''','
    IF @order               IS NOT NULL SET @sql = @sql + 'ORDER='''             + @order               + ''','
    IF @rowterminator       IS NOT NULL SET @sql = @sql + 'ROWTERMINATOR='''     + @rowterminator       + ''','
    IF @errorfile           IS NOT NULL SET @sql = @sql + 'ERRORFILE='''         + @errorfile           + ''','

    IF @firstrow            IS NOT NULL SET @sql = @sql + 'FIRSTROW=' + CAST(@firstrow            AS NVARCHAR) + ','
    IF @kilobytes_per_batch IS NOT NULL SET @sql = @sql + 'KILOBYTES_PER_BATCH=' + CAST(@kilobytes_per_batch AS NVARCHAR) + ','
    IF @lastrow             IS NOT NULL SET @sql = @sql + 'LASTROW=' + CAST(@lastrow             AS NVARCHAR) + ','
    IF @maxerrors           IS NOT NULL SET @sql = @sql + 'MAXERRORS=' + CAST(@maxerrors           AS NVARCHAR) + ','
    IF @rows_per_batch      IS NOT NULL SET @sql = @sql + 'ROWS_PER_BATCH=' + CAST(@rows_per_batch      AS NVARCHAR) + ','

    IF @check_constraints = 1         SET @sql = @sql + 'CHECKCONSTRAINTS,'
    IF @fire_triggers = 1         SET @sql = @sql + 'FIRE_TRIGGERS,'
    IF @keepidentity = 1         SET @sql = @sql + 'KEEPIDENTITY,'
    IF @keepnulls = 1         SET @sql = @sql + 'KEEPNULLS,'
    IF @tablock = 1         SET @sql = @sql + 'TABLOCK,'

    SET @sql = LEFT(@sql, LEN(@sql) - 1) + ')'

    -- + Execute the BULK INSERT statement
    DECLARE @bulk_count INT
    EXEC meta.debug @@PROCID, @sql
    EXEC sp_executesql @sql

    --+ Get the number of rows reported by BULK INSERT
    SET @bulk_count = @@ROWCOUNT
    EXEC meta.debug @@PROCID, 'Rows affected by BULK INSERT'
    EXEC meta.debug @@PROCID, @bulk_count

    --! --------------------------------------------------------------------------------------------------
    --! NOTE: For some reason the number of errors encountered during BULK INSERT is impossible to
    --!       identify using any best practices published by the vendor.So in order to break properly
    --!       when encountering errors, the.Error.Txt file must be inspected manually
    --! NOTE: The xp_fileexist extended (and undocumented) procedure suggested by many parties does not 
    --!       work with network paths
    --! NOTE: Apparently the only way to properly determine if any error rows were skipped is to try
    --!       to load the.error file and break if it exists
    --! --------------------------------------------------------------------------------------------------
    
    --| Inspect the .error files to retrieve (possible) errors and break properly if so
    --+ Checking for errors is triggered by the @errorfile parameter
    IF @errorfile IS NOT NULL
    BEGIN
        EXEC meta.debug @@PROCID, 'Performing error check of BULK LOAD'
        
        --+ Check if the.error file exists by trying to load it with no tolerance
        --+ First prepare new BULK LOAD statement which will break no matter what - and handle the error
        --+ code accordingly
        SET @sql = REPLACE(@sql, ' FROM ''' + @name + ''' WITH', ' FROM ''' + @errorfile + ''' WITH')
        SET @sql = REPLACE(@sql, 'ERRORFILE=''' + @errorfile + '''', 'ERRORFILE=''' + @errorfile + '.check''')
        SET @sql = CASE WHEN @maxerrors IS NULL THEN REPLACE(@sql, 'WITH (', ' WITH (MAXERRORS=0,')
                        ELSE REPLACE(@sql, 'MAXERRORS=' + CAST(@maxerrors AS NVARCHAR), 'MAXERRORS=0')
                   END
        SET @sql = CASE WHEN @firstrow IS NULL THEN REPLACE(@sql, 'WITH (', ' WITH (FIRSTROW=1,')
                        ELSE REPLACE(@sql, 'FIRSTROW=' + CAST(@firstrow AS NVARCHAR), 'FIRSTROW=1')
                   END
        --+ Execute the error check in a nested TRY/CATCH block
        BEGIN TRY
            EXEC meta.debug @@PROCID, @sql
            EXEC sp_executesql @sql
        END TRY
        BEGIN CATCH
            --+ Handle the 7330 (Cannot fetch row from OLE DB provider) - meaning error file exists
            IF ERROR_NUMBER() = 7330 RAISERROR('Errors encountered in BULK LOAD - see [%s]', 11, 1, @errorfile)
        END CATCH
    END

    --| Compare the number of rows inserted with rows read
    --+ Get number of rows inserted
    EXEC meta.debug @@PROCID, 'Get number of rows inserted into temp table'
    SET @sql = N'SELECT @rows = COUNT(*) FROM [' + @schema + '].[' + @table + ']'
    EXEC sp_executesql @sql, N'@rows BIGINT OUTPUT', @count OUTPUT
    EXEC meta.debug @@PROCID, @count

    --+ Error if the two counts do not match
    IF @bulk_count <> @count
        RAISERROR('Count mismatch, BULK INSERT [%d] and SELECT COUNT(*) [%d]', 11, 1, @bulk_count, @count)

    --| Update the delivery meta data
    EXEC meta.debug @@PROCID, 'Update meta.delivery'
    UPDATE meta.delivery
       SET size = @count
     WHERE id = @delivery_id


    RETURN
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[table_add] --|
--| ==========================================================================================
--| Description: Add a new table to the meta data.No checks or validation performed.
--| Arguments:
(
    @name NVARCHAR(250), --| Name of new table
@schema        NVARCHAR(50),  --| Schema of new table
@temporary     BIT,           --| (not used) Flag for temporary tables
    @permanent BIT,           --| (not used) Flag for permanent tables
    @table_id BIGINT OUTPUT  --| Returned table ID
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    --| Insert the new table entry
    INSERT INTO meta.[table]
           (name,  [schema], temporary, permanent)
    VALUES(@name, @schema, @temporary, @permanent)

    SET @table_id = IDENT_CURRENT('meta.table')

    -- | Return success
     RETURN
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[table_create] --|
--| ==========================================================================================
--| Description: Management procedure for creating table related to a stage
--|              * stage = 0: [init] table is created as part of the agreement in order to
--|                provide the base column names and types properly - thus just added to the
--|                meta data(bootstrap)
--|              * stage = 1: [temp] load table based on the definition in the init schema 
--|                - i.e.all columns are typed NVARCHAR to load without format errors
--|              * stage = 2: [stag] table should be a copy of the init table extended with 
--|                rowid, timestamps etc. for proper validation of data from temp
--|              * stage = 3: [repo] table should be a copy of the stag table extended with
--|                validation checkmarks etc.
--| Arguments:
(
    @agreement_id BIGINT,        --| ID of agreement to link table
    @stage_id BIGINT,        --| ID of stage of table
    @table_id        BIGINT OUTPUT  --| Returned ID of table
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    --| Handle init stage table
    IF @stage_id = 0
    BEGIN
        --| Lookup the proper table(base) name
       DECLARE @name NVARCHAR(128)
        SELECT @name = COALESCE(t.table_name, a.name), @table_id = t.table_id
          FROM meta.agreement a
               LEFT OUTER JOIN
               meta.agreement_stage_table_v t
               ON (a.id = t.agreement_id AND t.stage_id = @stage_id)
         WHERE a.id = @agreement_id

        --| If init table exists then return here
        IF @table_id IS NOT NULL
        BEGIN
            EXEC meta.debug @@PROCID, 'DONE'
            RETURN
        END


        BEGIN TRANSACTION

        BEGIN TRY
            --+ Add init table to meta (bootstrap)
            EXEC meta.debug @@PROCID, 'Add the init table to meta'
            EXEC meta.table_add @name, 'init', 0, 1, @table_id OUT
        END TRY
        BEGIN CATCH
            ROLLBACK TRANSACTION
            RAISERROR ('Creating table [%s] failed', 10, 1, @name)
            RETURN 1    
        END CATCH

        --| Return here as table is already created as part of the agreement
        EXEC meta.debug @@PROCID, 'DONE'
        COMMIT TRANSACTION
        RETURN
    END

    --| Handle other stage tables
    --+ Get table schema, name and delivery frequency from agreement
    DECLARE @schema       NVARCHAR(50)
    DECLARE @table        NVARCHAR(128)
    DECLARE @init_table   NVARCHAR(128)

    EXEC meta.debug @@PROCID, 'Lookup table definition from init schema'
    --+ Current stage table
    SELECT @table     = table_name,
           @schema    = table_schema,
           @table_id  = table_id
      FROM meta.agreement_stage_table_v
     WHERE agreement_id = @agreement_id
       AND stage_id = @stage_id

    -- + Init table
    SELECT @init_table  = table_name
      FROM meta.agreement_stage_table_v
     WHERE agreement_id = @agreement_id
       AND table_schema = 'init'

    -- + Error + exit if table not found
    IF @table IS NULL OR @init_table IS NULL
    BEGIN
        RAISERROR ('Table for agreement_id [%I64d], stage_id [%I64d] not found', 11, 1, @agreement_id, @stage_id)
        RETURN 2
    END

    DECLARE @msg NVARCHAR(300)
    SET @msg = 'INIT [init].[' + @init_table + '] => [' + @schema + '].[' + @table + ']'
    EXEC meta.debug @@PROCID, @msg

    --| Check if the required table already exist - then just return the table_id
    EXEC meta.debug @@PROCID, 'Check if table exists already'

    IF @table_id IS NOT NULL
    BEGIN
        --| Return here as table is already created as part of the agreement
        SET @msg = 'Existing table [' + CAST(@table_id AS NVARCHAR) + '] found for stage [' + CAST(@stage_id AS NVARCHAR) + '] - OK'
        EXEC meta.debug @@PROCID, @msg
        EXEC meta.debug @@PROCID, 'DONE'
        RETURN
    END

    --| BEGIN controlled transaction
    BEGIN TRANSACTION

    BEGIN TRY
        DECLARE @sql NVARCHAR(MAX)

        --| Prepare SQL for creating the table as copy from init
        SET @sql = 'SELECT * INTO [' + @schema + '].[' + @table + '] FROM [init].[' + @init_table + '] WHERE 1=2'
        EXEC meta.debug @@PROCID, 'Create base table'

        --| Special case is the temp table where columns are type 'indifferent' (NVARCHAR)
        IF @schema = 'temp'
        BEGIN
            --+ Override the default SQL
            SET @sql = ''

            -- + Check if @len_sum< 4000 (MS SQL hardcoded max length for NVARCHAR data rows)
            --+ Controlled by the NVARCHAR_MAX_LOAD attribute
            DECLARE @nvarchar_max_load NVARCHAR(1000)
            SELECT @nvarchar_max_load = value
              FROM meta.agreement_attribute_v
             WHERE agreement_id = @agreement_id
               AND attribute_name = 'NVARCHAR_MAX_LOAD'


            IF @nvarchar_max_load = 'YES'
                SET @sql = 'data NVARCHAR(MAX)'
            ELSE
            BEGIN
                DECLARE @col NVARCHAR(128)
                DECLARE @len INT
                DECLARE @type NVARCHAR(8)

                --| Lookoup datatype for temp table
                EXEC meta.debug @@PROCID, 'Lookup VARCHAR or NVARCHAR from agreement.type_id'
                SELECT @type = CASE WHEN UPPER(t.datafiletype) = 'CHAR' THEN '' ELSE 'N' END + 'VARCHAR'
                  FROM meta.agreement a,
                       meta.[type] t
                 WHERE a.id = @agreement_id
                   AND t.id = a.type_id


                EXEC meta.debug @@PROCID, @type

                EXEC meta.debug @@PROCID, 'Prepare SQL for mapping columns to proper (N)VARCHARs'
                DECLARE rec CURSOR FOR
                SELECT column_name, character_maximum_length
                  FROM meta.column_mapping_v
                 WHERE agreement_id = @agreement_id
                   AND table_schema = 'init'
                 ORDER BY ordinal_position

                --+ Open cursor
                OPEN rec

                --+ Prepare (daft MS SQL) loop
                FETCH NEXT FROM rec INTO @col, @len

                WHILE @@FETCH_STATUS = 0
                BEGIN
                    EXEC meta.debug @@PROCID, @col

                    --+ All datatypes are mapped to maximum length NVARCHAR
                    SET @sql = @sql + CAST(@col + ' ' + @type + '(' + CASE @len WHEN - 1 THEN 'MAX' ELSE CAST(COALESCE(@len, 50) AS NVARCHAR) END + ')' AS NVARCHAR(MAX))


                    FETCH NEXT FROM rec INTO @col, @len
                    IF @@FETCH_STATUS = 0 SET @sql = @sql + CAST(',' AS NVARCHAR(MAX))
                END
                CLOSE rec
                DEALLOCATE rec
            END

            --+ Prepare create table statement
            SET @sql = CAST('CREATE TABLE [' + @schema + '].[' + @table + '](' AS NVARCHAR(MAX))
                     + @sql
                     + CAST(')' AS NVARCHAR(MAX))
        END

        --+ Execute the statement
        EXEC meta.debug @@PROCID, @sql
        EXEC sp_executesql @sql

        --| Handle each schema/stage differently(adding columns)
        --+ Append columns for both stag and repo
        IF @schema IN('stag', 'repo')
        BEGIN
            SET @sql = 'ALTER TABLE [' + @schema + '].[' + @table + '] ADD dw_delivery_id BIGINT'
            EXEC meta.debug @@PROCID, 'Append [dw_delivery_id] column'
            EXEC meta.debug @@PROCID, @sql
            EXEC sp_executesql @sql
        END
        IF @schema IN ('repo')
        BEGIN
            SET @sql = 'ALTER TABLE [' + @schema + '].[' + @table + '] ADD dw_row_id BIGINT IDENTITY(1,1)'
            EXEC meta.debug @@PROCID, 'Append [dw_row_id] column'
            EXEC meta.debug @@PROCID, @sql
            EXEC sp_executesql @sql
        END

        --+ Add the table to meta
        EXEC meta.debug @@PROCID, 'Add the table to meta'
        EXEC meta.table_add @table, @schema, 0, 1, @table_id OUT
    END TRY
    BEGIN CATCH
        --| Log in audit and rollback transaction
        EXEC meta.debug @@PROCID, 'Creating table failed'
        --| Return error code
        RETURN 10
    END CATCH

    --| SUCCESS handling
    EXEC meta.debug @@PROCID, 'DONE'
        --| COMMIT controlled transaction
    COMMIT TRANSACTION
        --| Return success
    RETURN
    --| END
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[audit_add]-- |
--| ==========================================================================================
-- | Description: Add a new audit to meta data - check foreign keys to make sure doublets
-- | are not inserted - return any existing row with matching IDs
-- | Arguments:
(
    @stage_id BIGINT, --| ID of the stage of audit trail
    @delivery_id   BIGINT, --| ID of the delivery to add audit trail for
    @table_id      BIGINT, --| ID of table created / updated as part of stage
    @description   NVARCHAR(250), --| Description of audit trail change
    @audit_id      BIGINT OUTPUT-- | Returned audit_id of created entry
)
AS
-- | ------------------------------------------------------------------------------------------
BEGIN
    -- | Check if audit entry already exists
    EXEC meta.debug @@PROCID, 'Check audit foreign keys'
    SELECT @audit_id = u.id
      FROM meta.audit u
     WHERE u.stage_id = @stage_id
       AND u.delivery_id = @delivery_id
       AND u.table_id = @table_id

    IF @audit_id IS NULL
    BEGIN
        -- | Insert new audit entry if not existing
        INSERT INTO meta.audit
               (stage_id, delivery_id, table_id, description)
        VALUES(@stage_id, @delivery_id, @table_id, @description)

        SET @audit_id = IDENT_CURRENT('meta.audit')

        -- | Add to operation log
        EXEC meta.operation_add @audit_id, 1, @@PROCID, 'Audit inserted'
    END


    EXEC meta.debug @@PROCID, 'DONE'
    -- | Return success
    RETURN
END
-- | ==========================================================================================
;
CREATE
PROCEDURE[meta].[delivery_add]-- |
--| ==========================================================================================
--| Description: Add or promote a delivery into meta data.
--| A delivery undergoes several stages and this SP adds an audit trail per
--| stage in the audit and operation tables - respectively.This procedure does
--| not update the delivery itself unless when adding, instead the audit trail
--|              is appended, i.e.every call add another audit record.
--| Arguments:
(
    @agreement_id BIGINT, --| ID of agreement to which the delivery belongs
    @stage_id      BIGINT, --| ID of stage to add / promote delivery
    @name          NVARCHAR(250), --| Name of the delivery
    @username      NVARCHAR(50), --| Owner of the delivery file(only valid when adding)
    @size          BIGINT, --| Size of the delivery file(only valid when adding)
    @description   NVARCHAR(250), --| Human readable description of the delivery
    @delivery_id   BIGINT OUTPUT, --| Returned delivery ID added or audit appended
    @audit_id      BIGINT OUTPUT, --| Returned audit ID added
    @table_id      BIGINT OUTPUT-- | Returned table ID linked
)
AS
-- | ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @msg       NVARCHAR(50)
    DECLARE @user_id   BIGINT
    DECLARE @max_stage BIGINT

    -- | Check user if init or temp stage(CREATE AGREEMENT or UPLOAD)
    -- | -only stage we have a username anyway!
    IF @stage_id <= 1
    BEGIN
        EXEC meta.debug @@PROCID, 'Check user UPLOAD permission'
        SET @user_id = meta.user_access(@username, @agreement_id, 'UPLOAD')

        IF @user_id = 0
        BEGIN
            RAISERROR('User [%s] does not have UPLOAD permissions', 11, 1, @username)
            RETURN 20
        END
        EXEC meta.debug @@PROCID, 'User checked successfully'
    END

    -- | Check if delivery with same name already exists
    EXEC meta.debug @@PROCID, 'Lookup delivery name in meta data - in order not to create doublets'
    SELECT @delivery_id = d.id, @user_id = d.user_id, @max_stage = u.max_stage
      FROM meta.delivery d
           LEFT OUTER JOIN
           (SELECT delivery_id, MAX(stage_id) AS max_stage
              FROM meta.audit
             GROUP BY delivery_id) u ON d.id = u.delivery_id
     WHERE d.agreement_id = @agreement_id
       AND d.name = @name

    -- | Check if either delivery exists
    IF @delivery_id IS NOT NULL
        EXEC meta.debug @@PROCID, 'Delivery exists'

    -- | Check if delivery is in a stage higher than than current
    SET @msg = 'MAX stage [' + CAST(COALESCE(@max_stage, @stage_id) AS NVARCHAR) + '] current [' + CAST(@stage_id AS NVARCHAR) + ']'
    EXEC meta.debug @@PROCID, 'Check if MAX stage is higher than current '
    EXEC meta.debug @@PROCID, @msg

    -- + Compare stage for the delivery
    IF @stage_id < @max_stage
    BEGIN
        -- + Check the ALLOW_DELIVERY_REPLACE attribute to see if previous delivery should be replaced
        DECLARE @allow_delivery_replace  NVARCHAR(1000)
        SELECT @allow_delivery_replace = value
          FROM meta.agreement_attribute_v
         WHERE agreement_id = @agreement_id
           AND attribute_name = 'ALLOW_DELIVERY_REPLACE'

        -- + If not allowed or stage > init then break with error
        IF @allow_delivery_replace = 'NO' OR @stage_id > 1
        BEGIN
            RAISERROR('Current stage is smaller than MAX for delivery [%I64d] < [%I64d]', 11, 1, @stage_id, @max_stage)
            RETURN 20
        END

        -- + Otherwise perform a cleanup by renaming previous delivery
        UPDATE meta.delivery
           SET name = name + ' (replaced ' + CONVERT(NVARCHAR(20), getdate(), 120) + ')'
         WHERE id = @delivery_id

        -- + Set @delivery_id to NULL
        SET @delivery_id = NULL
    END

    -- + Assign proper audit message based on stage_id
    SET @msg = CASE
                   WHEN @stage_id = 0 THEN 'Agreement initialization'
                   WHEN @stage_id = 1 THEN 'Delivery ready for load'
                   WHEN @stage_id = 2 THEN 'Delivery ready for staging area'
                   WHEN @stage_id = 3 THEN 'Delivery ready for exposure'
                   ELSE 'Unknown stage_id [' + CAST(@stage_id AS NVARCHAR) + ']'
               END

    -- | BEGIN controlled transaction
    -- + Validity checks complete - update meta data
    BEGIN TRANSACTION

    BEGIN TRY
        -- | Error if delivery is 'promoted' and it does not exist
        IF @delivery_id IS NULL AND @stage_id > 1 RAISERROR('Delivery does not exist [%s]', 11, 1, @name)

        -- | Create delivery entry if it does not exist(stage 0 only)
        IF @delivery_id IS NULL
        BEGIN
            -- + If not - insert delivery
            EXEC meta.debug @@PROCID, 'Insert the delivery'
            INSERT INTO meta.delivery
                   (agreement_id, name, user_id, size, status_date)
            VALUES(@agreement_id, @name, @user_id, @size, meta.get_status_date(@name))


            SET @delivery_id = IDENT_CURRENT('meta.delivery')
        END

        -- | Create the table for the stage
        EXEC meta.debug @@PROCID, 'Add table for stage'
        EXEC meta.table_create @agreement_id, @stage_id, @table_id OUT

        -- | Add to the audit log
        EXEC meta.debug @@PROCID, 'Add audit'
        EXEC meta.audit_add @stage_id, @delivery_id, @table_id, @description, @audit_id OUT

        -- | Log the current operation
        EXEC meta.debug @@PROCID, 'Add operation'
        EXEC meta.operation_add @audit_id, 1, @@PROCID, @msg
    END TRY
    -- | ERROR handling
    BEGIN CATCH
        -- | Rollback transaction
        ROLLBACK TRANSACTION
        EXEC meta.debug @@PROCID, 'Adding delivery failed'
        -- | Return error code
        RETURN 10
    END CATCH

    -- | SUCCESS handling
    EXEC meta.debug @@PROCID, 'DONE'
        -- | COMMIT controlled transaction
    COMMIT TRANSACTION
        -- | Return success
    RETURN
    -- | END
END
-- | ==========================================================================================
;
CREATE
PROCEDURE[meta].[agreement_add] --|
--| ==========================================================================================
--| Description: Add a new agreement to the meta data.
--|              The agreement has a reference to a init table(delivery stage 0), which 
--|              contains the column definitions(name and type) used as template for tables 
--|              in other stages.
--|              The agreement file is considered to be a delivery to 'itself' in the sense
--|              that a virtual delivery is registered during the creation, specifying itself
--|              as input.All future deliveries are treated similarly, except the agreement
--| Arguments:
(
    @name NVARCHAR(250),  --| Name of agreement(tables inherits this so unique!)
    @username NVARCHAR(50),   --| User adding the agreement - must be member of ADMIN group
    @group NVARCHAR(50),   --| Group owning the agreement
    @pattern NVARCHAR(250),  --| Unique pattern for recognizing delivery files
@type          NVARCHAR(25),   --| Name of predefined type(for BULK INSERT)
    @description NVARCHAR(1000), --| Human readable description of the agreement
    @frequency INT,            --| Frequency of deliveries - determines table name postfix
    @file2temp NVARCHAR(250),  --| (optional) Name of custom file --> temp procedure(load)
    @temp2stag NVARCHAR(250),  --| (optional) Name of custom temp --> stag procedure
    @stag2repo NVARCHAR(250),  --| (optional) Name of custom stag --> repo procedure
    @agreement_id BIGINT OUTPUT   --| Returned agreement_id when inserted
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    IF meta.in_group(@username, 'ADMIN') <> 1
    BEGIN
        RAISERROR('User [%s] not member of ADMIN group', 11, 1, @username)
        RETURN 20
    END

    --+ Default data move procedures
    SET @file2temp = COALESCE(@file2temp, 'meta.generic_file2temp @delivery_id, @path')
    SET @temp2stag = COALESCE(@temp2stag, 'meta.generic_temp2stag @delivery_id, @o_sql OUT')
    SET @stag2repo = COALESCE(@stag2repo, 'meta.generic_stag2repo @delivery_id, @o_sql OUT')

    -- + Local variables
     DECLARE @type_id BIGINT
    DECLARE @group_id    BIGINT
    DECLARE @user_id BIGINT
    DECLARE @audit_id    BIGINT
    DECLARE @table_id BIGINT
    DECLARE @delivery_id BIGINT
    DECLARE @upload_id BIGINT
    DECLARE @view_id     BIGINT
    
    --| Lookup the UPLOAD and VIEW permission IDs
    SELECT @upload_id = id FROM meta.access WHERE name = 'UPLOAD'
    SELECT @view_id = id FROM meta.access WHERE name = 'VIEW'

  -- | Lookup user
  EXEC meta.debug @@PROCID, 'Lookup user in meta data'

  SELECT @user_id = id

    FROM meta.[user]
     WHERE UPPER(username) = UPPER(@username)

  -- | Check if group exist

  EXEC meta.debug @@PROCID, 'Lookup owner group in meta data'

  SELECT @group_id = id

    FROM meta.[group]
     WHERE UPPER(name) = UPPER(@group)

  -- + Error + exit if group does not exist

  IF @group IS NOT NULL AND @group_id IS NULL
  BEGIN

      RAISERROR ('Group [%s] does not exist in meta data', 11, 1, @group)
        RETURN 2
    END

    --| Check if delivery type is available
    EXEC meta.debug @@PROCID, 'Lookup delivery type in meta data'
    SELECT @type_id = t.id
      FROM meta.type t
     WHERE UPPER(t.name) = UPPER(@type)

    -- + Error + exit if invalid type at this point
    IF @type IS NOT NULL AND @type_id IS NULL
    BEGIN
        RAISERROR ('Type [%s] does not exist in meta data', 11, 1, @type)
        RETURN 2
    END

    --| Check if agreement with same name already exists
    EXEC meta.debug @@PROCID, 'Lookup agreement name in meta data - in order not to create doublets'
    SELECT @agreement_id = a.id
      FROM meta.agreement a
     WHERE a.name = @name

    -- | Update + exit if agreement already exists
    IF @agreement_id IS NOT NULL
    BEGIN
        --| BEGIN controlled transaction
        EXEC meta.debug @@PROCID, 'Agreement exists - updating attributes'
        BEGIN TRANSACTION
        BEGIN TRY
            --| Update agreement
            UPDATE meta.agreement
               SET pattern     = COALESCE(@pattern, pattern),
                   description = COALESCE(@description, description),
                   type_id     = COALESCE(@type_id, type_id),
                   user_id     = COALESCE(@user_id, user_id),
                   group_id    = COALESCE(@group_id, group_id),
                   file2temp   = COALESCE(@file2temp, file2temp),
                   temp2stag   = COALESCE(@temp2stag, temp2stag),
                   stag2repo   = COALESCE(@stag2repo, stag2repo)
             WHERE id = @agreement_id

            -- | Add the UPLOAD access to the group
            EXEC meta.debug @@PROCID, 'Add group UPLOAD ownership'
            EXEC meta.group_agreement_add @group_id, @agreement_id, @upload_id
            EXEC meta.group_agreement_add @group_id, @agreement_id, @view_id

            --| Log the operation
            SELECT @audit_id = audit_id_init
              FROM meta.agreement_stage_table_v
             WHERE agreement_id = @agreement_id
               AND stage_id = 0

            EXEC meta.debug @@PROCID, 'Add operation'
            EXEC meta.operation_add @audit_id, 1, @@PROCID, 'Updated agreement'
            
            --| Commit and return here as remainder is assumed up to date
            COMMIT TRANSACTION
            RETURN
        END TRY
        --| ERROR handling
        BEGIN CATCH
            --| Rollback transaction
            ROLLBACK TRANSACTION
            PRINT ERROR_MESSAGE()
            EXEC meta.debug @@PROCID, 'Updating agreement failed'
            --| Return error code
            RETURN 10
        END CATCH
    END

    --| Check all existing agreement if pattern will conflict
    --| NOTE: This is not complete in any sense as the patterns can overlap in many ways
    --|       using both %, ? and character classes([a-z])
    EXEC meta.debug @@PROCID, 'Check if other agreement matching pattern exists'
    DECLARE @msg               NVARCHAR(300)
    DECLARE @pattern_check     NVARCHAR(250)
    SET @pattern_check = REPLACE(@pattern, '%', '')
    SELECT @agreement_id = id, @msg = 'ID [' + CAST(id AS NVARCHAR) + '] pattern [' + pattern + ']'
      FROM meta.agreement
     WHERE @pattern_check LIKE pattern
    
    --+ Error + exit if agreement found
    IF @agreement_id IS NOT NULL
    BEGIN
        RAISERROR ('Agreement %s conflicts with [%s]', 11, 1, @msg, @pattern)
        CLOSE rec
        DEALLOCATE rec
        RETURN 3
    END

    --+ Check the other way around by looping over existing agreements
    DECLARE @id_check  BIGINT
    DECLARE rec CURSOR FOR
    SELECT id, pattern
      FROM meta.agreement

    --+ Open cursor
    OPEN rec

    --+ Prepare(daft MS SQL) loop
   FETCH NEXT FROM rec INTO @id_check, @pattern_check

   WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @msg = 'ID [' + CAST(@id_check AS NVARCHAR) + '] pattern [' + @pattern_check + ']'
        SET @pattern_check = REPLACE(@pattern_check, '%', '')

        EXEC meta.debug @@PROCID, @msg

        --+ Check pattern of current agreement with new one about to be created
        SELECT @agreement_id = @id_check
         WHERE @pattern_check LIKE @pattern

        --+ Error + exit if agreement found
        IF @agreement_id IS NOT NULL
        BEGIN
            RAISERROR('Agreement %s conflicts with [%s]', 11, 1, @msg, @pattern)
            CLOSE rec
            DEALLOCATE rec
            RETURN 3
        END

        FETCH NEXT FROM rec INTO @id_check, @pattern_check
    END

    CLOSE rec
    DEALLOCATE rec
   
    --| Check that the load table(containing the field definitions) exists
   EXEC meta.debug @@PROCID, 'Check if load table exists'
    IF NOT EXISTS(SELECT 1 
                     FROM INFORMATION_SCHEMA.TABLES
                    WHERE LOWER(TABLE_SCHEMA) = 'init'
                      AND LOWER(TABLE_NAME)   = LOWER(LTRIM(RTRIM(@name))))
    BEGIN
        RAISERROR('Agreement table [init.%s] does not exist - must be created before adding agreement', 11, 1, @name)
        RETURN 4
    END
    
    --| BEGIN controlled transaction
    BEGIN TRANSACTION

    BEGIN TRY
        --| Create the agreement
        EXEC meta.debug @@PROCID, 'Insert new agreement and link to table via delivery'
        INSERT INTO meta.agreement
               (type_id, group_id, user_id, name, pattern, frequency, description, file2temp, temp2stag, stag2repo)
        VALUES(@type_id, @group_id, @user_id, @name, @pattern, @frequency, @description, @file2temp, @temp2stag, @stag2repo)


        SET @agreement_id = IDENT_CURRENT('meta.agreement')

        -- | Add the UPLOAD access to the group
        EXEC meta.debug @@PROCID, 'Add group UPLOAD/VIEW permissions'
        EXEC meta.group_agreement_add @group_id, @agreement_id, @upload_id
        EXEC meta.group_agreement_add @group_id, @agreement_id, @view_id

        --| Create the initial delivery to the agreement (bootstrap)
        EXEC meta.delivery_add @agreement_id, 0, @name, @username, 0, 'AGREEMENT', @delivery_id OUT, @audit_id OUT, @table_id OUT
    END TRY
    --| ERROR handling
    BEGIN CATCH
        --| Rollback transaction
        ROLLBACK TRANSACTION
        PRINT ERROR_MESSAGE()
        EXEC meta.debug @@PROCID, 'Adding agreement failed'
        --| Return error code
        RETURN 10
    END CATCH

    --| SUCCESS handling
    EXEC meta.debug @@PROCID, 'DONE'
        --| COMMIT controlled transaction
    COMMIT TRANSACTION
        --| Return success
    RETURN
    --| END
END
--| ==========================================================================================
;
CREATE PROCEDURE[meta].[agreement_attribute_add] --|
--| ==========================================================================================
--| Author:      Soren Bak Larsen
--| Create date: 2012-07-11
--| Description: Add a customized attribute for agreement
--| Arguments:
(
    @agreement_id BIGINT,        --| ID of meta.agreement the attribute should be linked to
    @name         NVARCHAR(50),  --| Attribute name
    @value        NVARCHAR(1000) --| Validation SQL to be inserted into WHERE clause
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @msg NVARCHAR(4000)
    DECLARE @ok_id         BIGINT
    DECLARE @attribute_id BIGINT
    DECLARE @options       NVARCHAR(2000)
    DECLARE @link_id       BIGINT

    --| Look up the agreement_id
    SELECT @ok_id = id
      FROM meta.agreement
     WHERE id = @agreement_id

    IF @ok_id IS NULL
    BEGIN
        RAISERROR ('Agreement [%I64d] does not exist', 11, 1, @agreement_id)
        RETURN 2
    END

    --| Look up the attribute_id
    SELECT @attribute_id = id,
           @options = options
      FROM meta.attribute
     WHERE name = @name

    IF @attribute_id IS NULL
    BEGIN
        RAISERROR ('Attribute [%s] does not exist', 11, 1, @name)
        RETURN 2
    END

    --+ Check if value is valid
    IF NOT(@options IS NULL OR @options LIKE '%,' + @value + ',%' OR @options LIKE @value + ',%' OR @options LIKE '%,' + @value)
    BEGIN
        RAISERROR('Attribute [%s] not in options list [%s]', 11, 1, @value, @options)
        RETURN 2
    END
    
    --+ Check if insert or update
    SELECT @link_id = id
      FROM meta.agreement_attribute
     WHERE agreement_id = @agreement_id
       AND attribute_id = @attribute_id

    IF @link_id IS NULL
    BEGIN
        SET @msg = 'Inserting attribute [' + @name + ']=[' + @value + ']'
        EXEC meta.debug @@PROCID, @msg
        INSERT INTO meta.agreement_attribute
                    (agreement_id, attribute_id, value)
             VALUES (@agreement_id, @attribute_id, @value)
    END
    ELSE
    BEGIN 
        --+ Check if delete (value is NULL)
        IF @value IS NULL
        BEGIN
            SET @msg = 'DELETE attribute [' + @name + ']'
            EXEC meta.debug @@PROCID, @msg
            DELETE FROM meta.agreement_attribute
             WHERE id = @link_id
        END
        ELSE
        BEGIN
            SET @msg = 'Update attribute [' + @name + ']=[' + @value + ']'
            EXEC meta.debug @@PROCID, @msg
            UPDATE meta.agreement_attribute
               SET value = @value
             WHERE id = @link_id
        END
    END
    
    --| Return Success
    EXEC meta.debug @@PROCID, 'DONE'
    RETURN
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[delivery_delete]-- |
--| ==========================================================================================
--| Description: Delete a delivery from the meta data
--| This is a very destructive procedure and should be called by authorities only
--| Arguments:             
(
    @delivery_id   BIGINT-- | ID of delivery to delete / flush from database
)
AS
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @msg NVARCHAR(1000)

    --| Ckeck the agreement_id
    EXEC meta.debug @@PROCID, 'Check delivery ID'
    SELECT @delivery_id = id
      FROM meta.agreement
     WHERE @delivery_id = id

    IF @delivery_id IS NULL
    BEGIN
        RAISERROR ('Delivery ID [%I64d] does not exist', 11, 1, @delivery_id)
        RETURN 2
    END
     
    --| BEGIN controlled transaction
    BEGIN TRANSACTION

    BEGIN TRY
        --| Delete operations
        EXEC meta.debug @@PROCID, 'Delete operations'
        DELETE FROM meta.operation
         WHERE audit_id IN (SELECT id
                              FROM meta.audit
                             WHERE delivery_id = @delivery_id)

        --+ Prepare delete audit trail
        DECLARE @audit_id    BIGINT
        DECLARE @stage_id BIGINT
        DECLARE @table_id    BIGINT
        DECLARE @count INT
        DECLARE @type        NVARCHAR(15)
        DECLARE @table_name  NVARCHAR(200)
        DECLARE @sql         NVARCHAR(300)
        DECLARE rec CURSOR FOR
        SELECT u.id, u.stage_id, u.table_id, '[' + t.[schema] + '].[' + t.[name] + ']' AS table_name
          FROM meta.audit u,
               meta.[table] t
         WHERE u.delivery_id = @delivery_id
           AND u.table_id    = t.id
         ORDER BY u.stage_id DESC

        --+ Open cursor
        OPEN rec

        --+ Prepare (daft MS SQL) loop
        FETCH NEXT FROM rec INTO @audit_id, @stage_id, @table_id, @table_name

        --| Loop over audit and delete tables/views and meta data one by one
        EXEC meta.debug @@PROCID, 'Loop over audit'
        WHILE @@FETCH_STATUS = 0
        BEGIN
            --+ Delete delivery from repo
            IF @stage_id = 3
            BEGIN
                SET @sql = 'DELETE FROM ' + @table_name + ' WHERE dw_delivery_id = ' + CAST(@delivery_id AS NVARCHAR)
                EXEC sp_executesql @sql
            END

            --+ Check if any other audit trail on the table exists
            SELECT @count = COUNT(*)
              FROM meta.audit
             WHERE table_id = @table_id
               AND id <> @audit_id

            DELETE FROM meta.audit
             WHERE id = @audit_id

            -- + If count is 0 
            IF @count = 0
            BEGIN
                --+ Drop table
                IF OBJECT_ID(@table_name) IS NOT NULL
                BEGIN
                    --+ Determine if view or table
                    SELECT @type = TABLE_TYPE
                      FROM INFORMATION_SCHEMA.TABLES
                     WHERE UPPER(@table_name) = UPPER('[' + TABLE_SCHEMA + '].[' + TABLE_NAME + ']')


                    SET @sql = 'DROP ' + CASE @type WHEN 'VIEW' THEN 'VIEW' ELSE 'TABLE' END + ' ' + @table_name
                    EXEC meta.debug @@PROCID, @sql
                    EXEC sp_executesql @sql
                END
                
                --+ Delete table meta data
                DELETE FROM meta.[table]
                 WHERE id = @table_id
            END
                                            
            --+ Repeat (daft MS SQL) loop
            FETCH NEXT FROM rec INTO @audit_id, @stage_id, @table_id, @table_name
        END
        CLOSE rec
        DEALLOCATE rec

        --| Delete the delivery entry
        EXEC meta.debug @@PROCID, 'Delete delivery'
        DELETE FROM meta.delivery
         WHERE id = @delivery_id

    END TRY
    --| ERROR handling
    BEGIN CATCH
        --| Rollback transaction
        ROLLBACK TRANSACTION
        PRINT ERROR_MESSAGE()
        EXEC meta.debug @@PROCID, 'Deleting delivery failed'
        --| Return error code
        RETURN 10
    END CATCH

    --| SUCCESS handling
    EXEC meta.debug @@PROCID, 'DONE'
        --| COMMIT controlled transaction
    COMMIT TRANSACTION
        --| Return success
    RETURN
    --| END
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[agreement_delete] --|
--| ==========================================================================================
--| Description: Delete an agreement from the meta data - including deliveries
--|              This is a very destructive procedure and should be called by authorities only
--| Arguments:             
(
    @agreement_id BIGINT --| ID of agreement to delete/flush from database
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @delivery_id BIGINT
    DECLARE @temp2stag      NVARCHAR(1000)
    DECLARE @stag2repo      NVARCHAR(1000)
    DECLARE @msg            NVARCHAR(1000)

    --| Ckeck the agreement_id
    EXEC meta.debug @@PROCID, 'Check agreement ID'
    SELECT @agreement_id = id,
           @temp2stag = temp2stag,
           @stag2repo = stag2repo
      FROM meta.agreement
     WHERE @agreement_id = id

    IF @agreement_id IS NULL
    BEGIN
        RAISERROR ('Agreement ID [%I64d] does not exist', 11, 1, @agreement_id)
        RETURN 2
    END
     
    --| BEGIN controlled transaction
    BEGIN TRANSACTION

    BEGIN TRY
        --| Find all deliveries made to the agreement
        DECLARE a_rec CURSOR FOR
        SELECT id,
               '  [' + CAST(id AS NVARCHAR) + '] [' + name + ']'
          FROM meta.delivery
         WHERE agreement_id = @agreement_id

        -- + Open cursor
        OPEN a_rec

        --+ Prepare (daft MS SQL) loop
        FETCH NEXT FROM a_rec INTO @delivery_id, @msg

        --+ Loop over deliveries and delete one by one calling meta.delivery_delete
        EXEC meta.debug @@PROCID, 'Loop over deliveries'
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC meta.debug @@PROCID, @msg
            EXEC meta.delivery_delete @delivery_id

            --+ Repeat (daft MS SQL) loop
            FETCH NEXT FROM a_rec INTO @delivery_id, @msg
        END
        CLOSE a_rec
        DEALLOCATE a_rec
        
        --| Delete validation rules
        EXEC meta.debug @@PROCID, 'Deleting validation rules'
        DELETE FROM meta.agreement_rule
         WHERE agreement_id = @agreement_id

        --| Delete type maps
        EXEC meta.debug @@PROCID, 'Deleting mapping rules'
        DELETE FROM meta.type_map
         WHERE agreement_id = @agreement_id

        --| Delete group access
        EXEC meta.debug @@PROCID, 'Deleting group permissions'
        DELETE FROM meta.group_agreement
         WHERE agreement_id = @agreement_id

        --| Delete agreement attributes
        EXEC meta.debug @@PROCID, 'Deleting agreement attributes'
        DELETE FROM meta.agreement_attribute
         WHERE agreement_id = @agreement_id

        --| Delete the agreement entry
        EXEC meta.debug @@PROCID, 'Deleting agreement'
        DELETE FROM meta.agreement
         WHERE id = @agreement_id

    END TRY
    --| ERROR handling
    BEGIN CATCH
        --| Rollback transaction
        ROLLBACK TRANSACTION
        PRINT ERROR_MESSAGE()
        EXEC meta.debug @@PROCID, 'Deleting agreement failed'
        --| Return error code
        RETURN 10
    END CATCH

    --| SUCCESS handling
    EXEC meta.debug @@PROCID, 'DONE'
        --| COMMIT controlled transaction
    COMMIT TRANSACTION
        --| Return success
    RETURN
    --| END
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[agreement_dump] --|
--| ==========================================================================================
--| Description: Dump agreement as rows to be exported, displayed or otherwise processed
--|
--| TODO:        This stored procedure outputs autogenerated code, which may be subject to
--|              changes and thus it should be based on a template with insertion points/
--|              patterns instead of hardcoded insert statements in order to ensure easy 
--|              maintenance
--| Arguments:
(
    @agreement_id BIGINT              --| ID of agreement to dump
)
AS 
SET ANSI_WARNINGS OFF
SET NOCOUNT ON
--| ------------------------------------------------------------------------------------------
BEGIN
    --| Lookup the agreement and table
    EXEC meta.debug @@PROCID, 'Lookup agreement details from agreement_id'
    DECLARE @name          NVARCHAR(100)
    DECLARE @user          NVARCHAR(50)
    DECLARE @group         NVARCHAR(50)
    DECLARE @pattern       NVARCHAR(50)
    DECLARE @type          NVARCHAR(25)
    DECLARE @description   NVARCHAR(1000)
    DECLARE @file2temp     NVARCHAR(250)
    DECLARE @temp2stag     NVARCHAR(250)
    DECLARE @stag2repo     NVARCHAR(250)
    DECLARE @frequency     INT

    SELECT @name        = name,
           @user        = user_name,
           @group       = group_name,
           @pattern     = pattern,
           @type        = type_name,
           @description = description,
           @file2temp   = file2temp,
           @temp2stag   = temp2stag,
           @stag2repo   = stag2repo,
           @frequency   = frequency
      FROM meta.agreement_delivery_count_v
     WHERE id = @agreement_id

    --+ Error + exit if invalid agreement_id
    IF @name IS NULL
    BEGIN
        RAISERROR('Agreement [%I64d] does not exist in meta data', 11, 1, @agreement_id)
        RETURN 2
    END

    --| Create the result table with resulting agreement definition
    CREATE TABLE #agreement
    (
        id BIGINT IDENTITY(1,1) PRIMARY KEY,
data        NVARCHAR(4000)
    )

    DECLARE @maxpos INT
    DECLARE @maxlen INT
    SELECT @maxlen = MAX(LEN(column_name)) + 1,
           @maxpos = MAX(ordinal_position)
      FROM meta.column_mapping_v
     WHERE agreement_id = @agreement_id
       AND table_schema = 'init'
    IF @maxlen < 6 SET @maxlen = 6

    -- | POPULATE AGREEMENT
    --+ Definitions
    INSERT INTO #agreement (data) VALUES('BEGIN TRY')
    INSERT INTO #agreement (data) VALUES('BEGIN TRANSACTION')
    INSERT INTO #agreement (data) VALUES('DECLARE @name          NVARCHAR(100)')
    INSERT INTO #agreement (data) VALUES('DECLARE @user          NVARCHAR(50)')
    INSERT INTO #agreement (data) VALUES('DECLARE @group         NVARCHAR(50)')
    INSERT INTO #agreement (data) VALUES('DECLARE @pattern       NVARCHAR(50)')
    INSERT INTO #agreement (data) VALUES('DECLARE @type          NVARCHAR(25)')
    INSERT INTO #agreement (data) VALUES('DECLARE @description   NVARCHAR(1000)')
    INSERT INTO #agreement (data) VALUES('DECLARE @file2temp     NVARCHAR(250)')
    INSERT INTO #agreement (data) VALUES('DECLARE @temp2stag     NVARCHAR(250)')
    INSERT INTO #agreement (data) VALUES('DECLARE @stag2repo     NVARCHAR(250)')
    INSERT INTO #agreement (data) VALUES('DECLARE @frequency     INT')
    INSERT INTO #agreement (data) VALUES('DECLARE @table         NVARCHAR(200)')
    INSERT INTO #agreement (data) VALUES('DECLARE @agreement_id  BIGINT')
    INSERT INTO #agreement (data) VALUES('DECLARE @sql           NVARCHAR(MAX)')
    --+ Pretty header
    INSERT INTO #agreement (data) VALUES('--|-------' + REPLICATE('-', @maxlen + 20) + '|')
    INSERT INTO #agreement (data) VALUES('--| AGREEMENT DEFINITION' + REPLICATE(' ', @maxlen + 6) + '|')
    INSERT INTO #agreement (data) VALUES('--|-------' + REPLICATE('-', @maxlen + 20) + '|')
    --+ Agreement details
    INSERT INTO #agreement (data) VALUES('SET @name         = ''' + @name        + ''' --|')
    INSERT INTO #agreement (data) VALUES('SET @table        = ''[init].['' + @name + '']''')
    INSERT INTO #agreement (data) VALUES('SET @user         = ''' + @user        + ''' --|')
    INSERT INTO #agreement (data) VALUES('SET @group        = ''' + @group       + ''' --|')
    INSERT INTO #agreement (data) VALUES('SET @pattern      = ''' + @pattern     + ''' --|')
    INSERT INTO #agreement (data) VALUES('SET @type         = ''' + @type        + ''' --|')
    INSERT INTO #agreement (data) VALUES('SET @description  = ''' + @description + ''' --|')
    INSERT INTO #agreement (data) VALUES('SET @frequency    = '   + CAST(@frequency AS NVARCHAR))
    INSERT INTO #agreement (data) VALUES('/* 0 = single, 1 = daily (YYYYMMDD), 30 = monthly (YYYYMM), 365 = yearly (YYYY) */')
    INSERT INTO #agreement (data) VALUES('SET @file2temp    = ''' + REPLACE(@file2temp, '''', '''''') + '''')
    INSERT INTO #agreement (data) VALUES('/* NULL => Generic file->temp load procedure, otherwise name of custom procedure */')
    INSERT INTO #agreement (data) VALUES('SET @temp2stag    = ''' + REPLACE(@temp2stag, '''', '''''') + '''')
    INSERT INTO #agreement (data) VALUES('/* NULL => Generic temp->stag move procedure, Otherwise name of custom procedure*/')
    INSERT INTO #agreement (data) VALUES('SET @stag2repo    = ''' + REPLACE(@stag2repo, '''', '''''') + '''')
    INSERT INTO #agreement (data) VALUES('/* NULL => Generic stag->repo move procedure, Otherwise name of custom procedure*/')
    INSERT INTO #agreement (data) VALUES('--|                                                                   --|')

    --| TABLE/VIEW Field definitions
    --+ Pretty header
    INSERT INTO #agreement (data) VALUES ('--|-------' + REPLICATE('-', @maxlen + 20) + '|')
    INSERT INTO #agreement (data) VALUES ('--| FIELDS' + REPLICATE(' ', @maxlen + 20) + '|')
    INSERT INTO #agreement (data) VALUES ('--| Name  ' + REPLICATE(' ', @maxlen -  6) + 'Type' + REPLICATE(' ', 22) + '|')
    INSERT INTO #agreement (data) VALUES ('--|-------' + REPLICATE('-', @maxlen + 20) + '|')
    
    INSERT INTO #agreement (data) VALUES ('SET @sql = CAST(''')
    --| Check if agreement use database link or not (type LIKE '%LINK')
    IF UPPER(@type) LIKE '%LINK'
    BEGIN 
        --| DATABASE LINK Field definitions(based on view)
        --+ Table + field definitions
        INSERT INTO #agreement (data) 
        SELECT REPLACE(text, '''', '''''')
          FROM dbo.syscomments
         WHERE id = OBJECT_ID('[init].[' + @name + ']', 'V')
         ORDER BY colid
        INSERT INTO #agreement (data) VALUES (')'' AS NVARCHAR(MAX))')
    END ELSE BEGIN
        INSERT INTO #agreement (data) VALUES ('CREATE TABLE '' + @table + '' (')
        --| TABLE field definitions (based on table)
        --+ Table + field definitions
        INSERT INTO #agreement (data)
        SELECT '    ' + column_name + REPLICATE(' ', @maxlen - LEN(column_name)) +
               CASE data_type
                    WHEN 'numeric'          THEN 'NUMERIC(' + CAST(numeric_precision AS NVARCHAR) + ',' + CAST(numeric_scale AS NVARCHAR) + ')'
                    WHEN 'varchar'          THEN 'VARCHAR('  + CAST(character_maximum_length AS NVARCHAR) + ')'
                    WHEN 'nvarchar'         THEN 'NVARCHAR(' + CAST(character_maximum_length AS NVARCHAR) + ')'
                    ELSE UPPER(data_type) 
               END + CASE WHEN ordinal_position<CAST(@maxpos AS NVARCHAR) THEN ',' ELSE '' END + ' --|'
          FROM meta.column_mapping_v
         WHERE agreement_id = @agreement_id
           AND table_schema = 'init'
         ORDER BY ordinal_position
        INSERT INTO #agreement (data) VALUES (')'' AS NVARCHAR(MAX))')
    END
    --+ Agreement creation call
    INSERT INTO #agreement (data) VALUES ('/* Execute the table create statement and add the agreement to meta data')
    INSERT INTO #agreement (data) VALUES ('   Table cannot be modified as deliveries might have been made already */')
    INSERT INTO #agreement (data) VALUES ('IF OBJECT_ID( @table ) IS NULL EXEC sp_executesql @sql')
    INSERT INTO #agreement (data) VALUES ('EXEC [meta].[agreement_add] @name, @user, @group, @pattern, @type, @description, @frequency, @file2temp, @temp2stag, @stag2repo, @agreement_id OUT')
    --| Attributes
    --+ Pretty header
    INSERT INTO #agreement (data) VALUES ('--|------------------------------' + REPLICATE('-', @maxlen - 3) + '|')
    INSERT INTO #agreement (data) VALUES ('--| ATTRIBUTES                   ' + REPLICATE(' ', @maxlen - 3) + '|')
    INSERT INTO #agreement (data) VALUES ('--| Name                    Value' + REPLICATE(' ', @maxlen - 3) + '|')
    INSERT INTO #agreement (data) VALUES ('--|------------------------------' + REPLICATE('-', @maxlen - 3) + '|')
    --+ Value definitions
    INSERT INTO #agreement (data)
    SELECT CASE s.def
                WHEN 1 THEN 'EXEC meta.agreement_attribute_add @agreement_id,'
                WHEN 2 THEN '   ''' + u.attribute_name + ''',' + REPLICATE(' ', 23 - LEN(u.attribute_name))
                          + '''' + REPLACE(u.value, '''', '''''') + ''' --|'
           END
      FROM meta.agreement_attribute_v u,
           (SELECT 1 AS def UNION ALL SELECT 2) s
     WHERE u.agreement_id = @agreement_id
       AND u.createdtm IS NOT NULL
     ORDER BY u.attribute_name
    --| Validation rules for sensitive types
    --+ Pretty header
    INSERT INTO #agreement (data) VALUES ('--|-----------------' + REPLICATE('-', @maxlen + 10) + '|')
    INSERT INTO #agreement (data) VALUES ('--| VALIDATION RULES' + REPLICATE(' ', @maxlen + 10) + '|')
    INSERT INTO #agreement (data) VALUES ('--| ID    Rule      ' + REPLICATE(' ', @maxlen + 10) + '|')
    INSERT INTO #agreement (data) VALUES ('--|-----------------' + REPLICATE('-', @maxlen + 10) + '|')
    --+ Rule definitions
    INSERT INTO #agreement (data)
    SELECT CASE s.def
                WHEN 1 THEN 'EXEC meta.agreement_rule_add @agreement_id,'
                WHEN 2 THEN '    ' + REPLICATE(' ', 4 - LEN(CAST(r.rule_id AS NVARCHAR))) + CAST(r.rule_id AS NVARCHAR)
                          + ', ''' + REPLACE(r.rule_text, '''', '''''') + ''' --|'
           END
      FROM meta.agreement_rule r,
           (SELECT 1 AS def UNION ALL SELECT 2) s
     WHERE r.agreement_id = @agreement_id
     ORDER BY r.rule_id, s.def
    --| Mapping rules for sensitive types
    --+ Pretty header
    INSERT INTO #agreement (data) VALUES ('--|-----------------' + REPLICATE('-', @maxlen + 10) + '|')
    INSERT INTO #agreement (data) VALUES ('--| MAPPING RULES   ' + REPLICATE(' ', @maxlen + 10) + '|')
    INSERT INTO #agreement (data) VALUES ('--| Field ' + REPLICATE(' ', @maxlen -  4) + 'Rule' + REPLICATE(' ', 20) + '|')
    INSERT INTO #agreement (data) VALUES ('--|-------' + REPLICATE('-', @maxlen + 20) + '|')
    --+ Rule definitions
    INSERT INTO #agreement (data)
    SELECT CASE s.def
                WHEN 1 THEN 'EXEC meta.type_map_add @agreement_id,'
                WHEN 2 THEN '   ''' + t.column_name + ''',' + REPLICATE(' ', @maxlen - LEN(t.column_name))
                          + '''' + REPLACE(t.mapping, '''', '''''') + ''' --|'
           END
      FROM meta.type_map t,
           (SELECT 1 AS def UNION ALL SELECT 2) s
     WHERE t.agreement_id = @agreement_id
     ORDER BY t.id, s.def
    INSERT INTO #agreement (data) VALUES ('--|-----------------' + REPLICATE('-', @maxlen + 10) + '|')
    INSERT INTO #agreement (data) VALUES ('COMMIT TRANSACTION')
    INSERT INTO #agreement (data) VALUES ('END TRY')
    INSERT INTO #agreement (data) VALUES ('BEGIN CATCH')
    INSERT INTO #agreement (data) VALUES ('    ROLLBACK TRANSACTION')
    INSERT INTO #agreement (data) VALUES ('    PRINT ERROR_MESSAGE()')
    INSERT INTO #agreement (data) VALUES ('    RAISERROR(''Failed to create agreement [%s]'', 18, 1, @name)')
    INSERT INTO #agreement (data) VALUES ('    RETURN')
    INSERT INTO #agreement (data) VALUES ('END CATCH')
    
    SELECT id, data
      FROM #agreement 
     ORDER BY id

    RETURN 0
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[agreement_find] --|
--| ==========================================================================================
--| Description: Lookup the agreement from pattern with error handling if several found
--| Arguments:             
(
    @name NVARCHAR(250),      --| Name of file to match against the agreement pattern
@stage_id     BIGINT,             --| Flag for procedure(2 = temp2stag, 3 = stag2repo)
    @agreement_id BIGINT         OUT, --| Return found ID
    @procedure    NVARCHAR(1000) OUT  --| Return found procedure
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @count INT

    --| Based on name pattern, lookup the agreement from meta.agreement table
    EXEC meta.debug @@PROCID, @name
    SELECT @agreement_id = MAX(a.id),
           @procedure    = MAX(CASE WHEN @stage_id = 1 THEN a.file2temp
                                    WHEN @stage_id = 2 THEN a.temp2stag
                                    WHEN @stage_id = 3 THEN a.stag2repo
                                    ELSE ''
                               END),
           @count        = COUNT(*)
      FROM meta.agreement a
     WHERE @name LIKE a.pattern
     
    --+ Error + exit if no or several agreement found
    IF @count > 1 
    BEGIN
        RAISERROR ('Several agreements [%I64d] matching [%s]', 10, 1, @count, @name)
        RETURN 2
    END

    RETURN
END
--| ==========================================================================================
;
CREATE PROCEDURE[meta].[agreement_rule_add] --|
--| ==========================================================================================
--| Description: Add a customized validation rule to a specific agreement
--| Arguments:
(
    @agreement_id BIGINT,        --| ID of meta.agreement the rule should be linked to
@rule_id           INT,           --| Agreement specific rule id(for log in error table)
    @rule_text NVARCHAR(4000) --| Validation SQL to be inserted into WHERE clause
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @msg NVARCHAR(4000)
    DECLARE @table  NVARCHAR(200)

    --| Look up the init table from agreement_id
    SELECT @table = '[' + table_schema + '].[' + table_name + ']'
      FROM meta.agreement_stage_table_v
     WHERE agreement_id = @agreement_id
       AND stage_id = 0

    IF @table IS NULL
    BEGIN
        RAISERROR ('Agreement [%I64d] does not exist', 11, 1, @agreement_id)
        RETURN 2
    END

    SET @msg = 'Rule [' + CAST(@rule_id AS NVARCHAR) + ']=[' + @rule_text + ']'
    EXEC meta.debug @@PROCID, @msg

    --| Check the validation rule against the table definition
    SET @msg = 'SELECT TOP 1 1 FROM ' + @table + ' WHERE ' + @rule_text
    BEGIN TRY
        EXEC sp_executesql @msg
    END TRY
    BEGIN CATCH
        SET @msg = 'Validation [' + @rule_text + '] error [' + CAST(ERROR_NUMBER() AS NVARCHAR) + '] [' + ERROR_MESSAGE() + ']'
        EXEC meta.debug @@PROCID, @msg
        RETURN 3
    END CATCH

    --| Determine update or insert rule
    DECLARE @count INT
    SELECT @count = COUNT(*)
      FROM meta.agreement_rule
     WHERE agreement_id = @agreement_id
       AND rule_id = @rule_id

    IF @count = 0
        INSERT INTO meta.agreement_rule
               (agreement_id, rule_id, rule_text)
        VALUES (@agreement_id, @rule_id, @rule_text)
    ELSE
        UPDATE meta.agreement_rule
           SET rule_text = @rule_text
         WHERE agreement_id = @agreement_id
           AND rule_id = @rule_id

    -- | Return Success
    EXEC meta.debug @@PROCID, 'DONE'
    RETURN
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[agreement_rule_add_all] --|
--| ==========================================================================================
--| Description: Add deduced validation rules from data types for all fields in agreement
--| Arguments:
(
    @agreement_id BIGINT,        --| ID of meta.agreement to add rules
    @date_format INT            --| Optional common date format specification
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    EXEC meta.debug @@PROCID, 'Adding deduced validation rules for agreement'
    --| Set default date format
    SET @date_format = COALESCE(@date_format, 103)
    EXEC meta.debug @@PROCID, 'Date format used'
    EXEC meta.debug @@PROCID, @date_format
    
    --+ Prepare to loop over all columns in agreement
    DECLARE @column_name NVARCHAR(128)
    DECLARE @rule_id                  INT
    DECLARE @data_type NVARCHAR(128)
    DECLARE @character_maximum_length INT
    DECLARE @numeric_precision TINYINT
    DECLARE @numeric_scale            INT
    DECLARE rec CURSOR FOR
    SELECT column_name,
           data_type,
           character_maximum_length,
           numeric_precision,
           numeric_scale
      FROM meta.column_mapping_v
     WHERE agreement_id = @agreement_id
       AND table_schema = 'init'
     ORDER BY ordinal_position

    OPEN rec

    FETCH rec INTO @column_name, @data_type, @character_maximum_length, @numeric_precision, @numeric_scale
    
    --| Loop over all fields(name, type, precision, scale and size) in init schema
    DECLARE @rule_text  NVARCHAR(1000)
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @rule_id = NULL

        --| Determine validation rule based on type
        SET @rule_text =
            CASE UPPER(@data_type)
                --| INT       => meta.check_numeric(x, 10, 0)
                WHEN 'INT'      THEN 'meta.check_numeric(' + @column_name + ', 10, 0) = 0'
                --| BIGINT    => meta.check_numeric(x, 18, 0)
                WHEN 'BIGINT'   THEN 'meta.check_numeric(' + @column_name + ', 18, 0) = 0'
                --| NUMERIC   => meta.check_numeric(x, precision, scale)
                WHEN 'NUMERIC'  THEN 'meta.check_numeric(' + @column_name + ',' + CAST(@numeric_precision AS NVARCHAR) + ',' + CAST(@numeric_scale AS NVARCHAR) + ') = 0'
                --| DATE      => meta.check_date(x, format)
                WHEN 'DATE'     THEN 'meta.check_date('    + @column_name + ',' + CAST(@date_format AS NVARCHAR) + ') = 0'
                --| NVARCHAR  => LEN(x) <= size
                WHEN 'NVARCHAR' THEN 'LEN(' + @column_name + ') <= ' + CAST(@character_maximum_length AS NVARCHAR)
                ELSE ''
            END

        SELECT @rule_id = rule_id
           FROM meta.agreement_rule
          WHERE agreement_id = @agreement_id
            AND rule_text = @rule_text
            
        --+ Check if rule already exists
        IF @rule_id IS NULL
            SELECT @rule_id = MAX(rule_id) + 1 
              FROM meta.agreement_rule
             WHERE agreement_id = @agreement_id


        SET @rule_id = COALESCE(@rule_id, 1)

        EXEC meta.agreement_rule_add @agreement_id, @rule_id, @rule_text

        FETCH rec INTO @column_name, @data_type, @character_maximum_length, @numeric_precision, @numeric_scale
    END
    CLOSE rec
    DEALLOCATE rec

    --| Return Success
    EXEC meta.debug @@PROCID, 'DONE'
    RETURN
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[analysis_file2temp] --|
--| ==========================================================================================
--| Description: Load the data from the delivery file into the load table in temp.
--|              Serves as alternative to generic_file2temp for doing analysis of a file in
--|              order to auto generate an agreement - details and field types - from data.
--|
--|              Load the first row as header and mark it <header>..</header> in order to 
--|              identify it. This approach is necessary in order to probe on all lines in
--|              the file as the line order cannot be relied on when loading into table
--| Arguments:             
(
    @delivery_id BIGINT,
    @path NVARCHAR(250)
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @type_id BIGINT
    DECLARE @firstrow  INT
    DECLARE @lastrow INT
    DECLARE @column    NVARCHAR(128)
    DECLARE @table     NVARCHAR(128)
    DECLARE @line      NVARCHAR(MAX)
    DECLARE @sql       NVARCHAR(MAX)

    --| Enter transction in order to perform rollback in case of errors
    BEGIN TRY
        --| Get meta data from ANALYSIS agreement
        --+ Get the type id in order to temporarily update it
        EXEC meta.debug @@PROCID, 'Get header line from data file'
        SELECT @type_id = y.id,
               @firstrow = y.firstrow,
               @lastrow = y.lastrow,
               @column = c.column_name,
               @table = c.table_name
          FROM meta.[type] y,
               meta.agreement a,
               meta.column_mapping_v c,
               meta.delivery d
         WHERE a.id = d.agreement_id
           AND y.id = a.type_id
           AND a.id = c.agreement_id
           AND c.table_schema = 'init'
           AND c.ordinal_position = 1
           AND d.id = @delivery_id

        -- + Temporarily update the first and last row to 1 (header)
        UPDATE meta.[type]
           SET firstrow = 1,
               lastrow  = 1
         WHERE id = @type_id

        -- | Load the file header (first row)
        EXEC meta.debug @@PROCID, 'Loading single header line'
        EXEC meta.generic_file2temp @delivery_id, @path

        --| Load the row into variable
        EXEC meta.debug @@PROCID, 'Retrieve line into local variable'
        SET @sql = 'SELECT @data = ' + @column + ' FROM [temp].[' + @table + ']'
        EXEC sp_executesql @sql, N'@data NVARCHAR(MAX) OUTPUT', @line OUTPUT
        EXEC meta.debug @@PROCID, @line
    END TRY
    BEGIN CATCH
        UPDATE meta.[type]
           SET firstrow = @firstrow,
               lastrow  = @lastrow
         WHERE id = @type_id


        RAISERROR ('Error loading header column [%s] into table [%s]', 11, 1, @column, @table)
        RETURN 10
    END CATCH

    --+ Truncate the temp table
    EXEC meta.debug @@PROCID, 'Truncate the temp table for loading the data rows'
    SET @sql = 'TRUNCATE TABLE [temp].[' + @table + ']'
    EXEC sp_executesql @sql

    --+ Return the values to type
    EXEC meta.debug @@PROCID, 'Rollback changes to type in order to load remaining data'
    UPDATE meta.[type]
       SET firstrow = @firstrow,
           lastrow  = @lastrow
     WHERE id = @type_id

    -- | Load the file properly
    EXEC meta.generic_file2temp @delivery_id, @path
    
    --+ Insert the header with markup for identification
    EXEC meta.debug @@PROCID, 'Get header line from data file'
    SET @sql = CAST('INSERT INTO [temp].[' + @table + '] (' + @column + ') ' AS NVARCHAR(MAX))
             + CAST('VALUES (''<header/>' AS NVARCHAR(MAX)) + CAST(REPLACE(@line, '''', '''''') AS NVARCHAR(MAX))
             + CAST(''')' AS NVARCHAR(MAX))
    EXEC sp_executesql @sql

    --+ Update the delivery meta data
    EXEC meta.debug @@PROCID, 'Update meta.delivery'
    UPDATE meta.delivery
       SET size = size + 1
     WHERE id = @delivery_id


    RETURN
    --| END
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[analysis_stag2repo] --|
--| ==========================================================================================
--| Description: Analysis of data loaded into a column - return the SQL to pull the generated
--|              meta data (column names, types, size, precision and scale) into the stag 
--|              table
--| Arguments:
(
    @separator NVARCHAR(1),         --| Separator of data file loaded
@delivery_id     BIGINT,              --| ID of delivery to move data for
    @sql NVARCHAR(MAX) OUTPUT --| Generated SQL string for doing the move
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    --+ TODO: Error handling!!!!!

    --| Lookup the agreement and table
    EXEC meta.debug @@PROCID, 'Lookup agreement_id from delivery_id'
    DECLARE @agreement_id    BIGINT
    DECLARE @user NVARCHAR(50)
    DECLARE @name            NVARCHAR(250)
    DECLARE @pattern         NVARCHAR(250)
    DECLARE @stag_name       NVARCHAR(128)
    DECLARE @repo_name       NVARCHAR(128)
    DECLARE @column          NVARCHAR(128)

    SELECT @agreement_id = d.agreement_id,
           @name = d.name,
           @user = u.username,
           @stag_name = '[' + s.table_schema + '].[' + s.table_name + ']',
           @repo_name = '[' + r.table_schema + '].[' + r.table_name + ']',
           @column = c.column_name
      FROM meta.delivery  d,
           meta.[user] u,
           meta.agreement_stage_table_v s,
           meta.agreement_stage_table_v r,
           meta.column_mapping_v c
     WHERE u.id           = d.user_id
       AND d.agreement_id = s.agreement_id
       AND d.agreement_id = r.agreement_id
       AND d.agreement_id = c.agreement_id
       AND d.id           = @delivery_id
       AND s.table_schema = 'stag'
       AND r.table_schema = 'repo'
       AND c.table_schema = 'init'
       AND c.ordinal_position = 1

    -- | Deduce the new agreement name from delivery name:
    EXEC meta.debug @@PROCID, 'Determine new agreement name from delivery name'

    --+ Find the split position in the pattern (based on first wildcard % in analysis pattern)
    DECLARE @prelen          INT
    DECLARE @poslen INT
    SELECT @prelen = CHARINDEX('%', pattern),
           @poslen = LEN(pattern) - CHARINDEX('%', pattern)
      FROM meta.agreement
     WHERE id = @agreement_id

    -- + Remove the pre- and post-fix from surrounding analysis agreement
    SET @name = SUBSTRING(@name, @prelen, LEN(@name) - @poslen - @prelen + 1)
    -- + Replace '-' with '\' for path
    SET @name = REPLACE(@name, '-', '\')
    SET @pattern = @name + '%.csv'
    SET @name = SUBSTRING(@name, CHARINDEX('\', @name) + 1, LEN(@name))
    EXEC meta.debug @@PROCID, 'New agreement name'
    EXEC meta.debug @@PROCID, @name

    -- | Prepare table for column types and weight for determining best match
    IF OBJECT_ID('#analysis') IS NOT NULL DROP TABLE #analysis
    CREATE TABLE #analysis 
    (
        row         INT,
        position    INT,
        weight      INT,
        name        NVARCHAR(128),
        type        NVARCHAR(128),
        length      INT,
        digits      INT,
        scale       INT
    )

    -- | Loop over columns separated by separator
    -- | Determine the column names(default is field_n)
    -- | Prepare SQL for determining types
    -- | INT      rated  0
    -- | BIGINT   rated 10
    -- | NUMERIC  rated 20
    -- | DATE     rated 30
    -- | NVARCHAR rated 50

    -- | Get the cursor reading from dataset
     EXEC meta.debug @@PROCID, 'Get the cursor reading from dataset (potential header as first line)'
    DECLARE @data       NVARCHAR(MAX)
    DECLARE @col        NVARCHAR(MAX)
    DECLARE @n_col      NVARCHAR(MAX)
    DECLARE @cursql     NVARCHAR(2000)
    DECLARE @type       NVARCHAR(25)
    DECLARE @length     INT
    DECLARE @n_length   INT
    DECLARE @digits     INT
    DECLARE @scale      INT
    DECLARE @weight     INT
    DECLARE @i          BIGINT
    DECLARE @j          BIGINT
    DECLARE @pos        BIGINT
    DECLARE @len        INT
    DECLARE @maxpos_hdr BIGINT
    DECLARE @row        BIGINT
    DECLARE @msg        NVARCHAR(500)

    -- + Prepare dynamic cursor
    SET @cursql = 'DECLARE rec CURSOR FOR '
                + 'SELECT ' + @column + ' '
                + '  FROM '
                + '    ('
                + '     SELECT 1 AS _o, REPLACE(' + @column + ', ''<header/>'', '''') AS ' + @column + ' FROM ' + @stag_name + ' WHERE ' + @column + ' LIKE ''<header/>%'' '
                + '      UNION ALL '
                + '     SELECT 2 AS _o, ' + @column + ' FROM ' + @stag_name + ' WHERE ' + @column + ' NOT LIKE ''<header/>%'' '
                + '    ) a '
                + ' ORDER BY _o ASC'
    EXEC meta.debug @@PROCID, @cursql
    EXEC meta.debug @@PROCID, @separator


    EXEC sp_executesql @cursql

    -- + Open cursor
    OPEN rec


    FETCH NEXT FROM rec INTO @data

    -- | Loop over rows in dataset
    SET @row = 1
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- | Loop over columns separated by separator
        -- | j and i are one - based string pointers:
        --|
        --| j        i
        -- | ..   / --------\  ..
        --| .. , fieldvalue,  ..   < --data - string with separators(,)
        SET @j = 1
        SET @pos = 1
        SET @len = LEN(@data)

        -- + Loop while j is not pointing at the end of the string
        WHILE(@j <= @len)
        BEGIN
            SET @i = COALESCE(NULLIF(CHARINDEX(@separator, @data, @j), 0), @len + 1)

            -- + Find fieldvalue based on j and i
            SET @col = SUBSTRING(@data, @j, @i - @j)
            SET @n_col = CASE WHEN SUBSTRING(@col, 1, 1) = '-' THEN SUBSTRING(@col, 2, LEN(@col)) ELSE @col END

            -- | Evaluate type based on patterns in 'ascending order of chaos'
            SET @type = CASE WHEN @n_col NOT LIKE '%[^0-9]%' AND LEN(@col) < 5 THEN 'INT'
                               WHEN @n_col NOT LIKE '%[^0-9]%'                   THEN 'BIGINT'
                               WHEN ISNUMERIC(@n_col) = 1                        THEN 'NUMERIC'
                               WHEN(meta.check_date(@col, 102) = 0
                                     OR meta.check_date(@col, 103) = 0
                                     OR meta.check_date(@col, 104) = 0
                                     OR meta.check_date(@col, 111) = 0)          THEN 'DATE'
                               ELSE                                                   'NVARCHAR'
                          END
            -- | Calculate length of NVARCHAR types
            SET @length = LEN(@col)
            SET @n_length = LEN(@n_col)
            -- + Calculate number of digits before punctuation
            SET @digits = CASE WHEN CHARINDEX('.', @n_col) = 0 THEN @n_length
                               ELSE CHARINDEX('.', @n_col) - 1 END
            -- | Set scale as number of decimals after punctuation
            SET @scale = CASE WHEN @type = 'NUMERIC'  THEN @n_length - @digits - 1
                               ELSE 0 END
            -- | Set weight according to 'ascending order of chaos'
            -- | (INT, BIGINT, NUMERIC, DATE, NVARCHAR)
            SET @weight = CASE @type
                               WHEN 'INT'      THEN 0
                               WHEN 'BIGINT'   THEN 10
                               WHEN 'NUMERIC'  THEN 20
                               WHEN 'DATE'     THEN 30
                               WHEN 'NVARCHAR' THEN 50
                          END

            -- + Insert the meta data(column + datatype) in #temp table
            INSERT INTO #analysis 
                       (row, position, name, weight, type, length, digits, scale)
                VALUES(@row, @pos, @col, @weight, @type, @length, @digits, @scale)


            SET @pos = @pos + 1
            SET @j = @i + 1-- Skip separator
        END
        -- + Store the number of cols from header line
 
         IF @row = 1 SET @maxpos_hdr = @pos

        -- | Check number of columns in row with header row
        IF @row > 1 AND @pos <> @maxpos_hdr
        BEGIN
            SET @msg = 'Row [' + CAST(@row AS NVARCHAR) + '] has [' + CAST(@pos AS NVARCHAR) + '] columns <> header [' + CAST(@maxpos_hdr AS NVARCHAR) + ']'
            EXEC meta.debug @@PROCID, @msg
        END
        SET @row = @row + 1
        FETCH NEXT FROM rec INTO @data
    END


    CLOSE rec
    DEALLOCATE rec

    EXEC meta.debug @@PROCID, 'Create agreement'
    -- | ----------------------------------------
    --| Create the agreement
    -- + TODO: Some of the arguments here should be parameters or deduced differently
    -- | -Create the table
    DECLARE rec CURSOR FOR
    SELECT '[' + COALESCE(NULLIF(REPLACE(LTRIM(RTRIM(h.name)), ' ', '_'), ''), 'FIELD' + CAST(w.position AS NVARCHAR)) + '] ' +
           CASE weight
                WHEN 0  THEN 'INT'
                WHEN 10 THEN 'BIGINT'
                WHEN 20 THEN 'NUMERIC(' + CAST(w.digits + w.scale AS NVARCHAR) + ',' + CAST(w.scale AS NVARCHAR) + ')'
                WHEN 30 THEN 'DATE'
                WHEN 50 THEN 'NVARCHAR(' + CAST(w.length AS NVARCHAR) + ')'
           END
      FROM(SELECT name, position FROM #analysis WHERE row = 1) h,
           (SELECT position,
                   MAX(weight) AS weight,
                   CASE WHEN MAX(digits + scale + 1) > MAX(length) THEN MAX(digits + scale + 1) ELSE MAX(length) END AS length,
                   MAX(digits) AS digits,
                   MAX(scale)  AS scale
              FROM #analysis 
             WHERE row > 1
             GROUP BY position) w
     WHERE h.position = w.position
     ORDER BY h.position

    -- + TODO: Check if table exists already
    OPEN rec
    DECLARE @line  NVARCHAR(250)
    SET @sql = 'CREATE TABLE [init].[' + @name + '] ('


    FETCH rec INTO @line


    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = @sql + CAST(@line AS NVARCHAR(MAX))
        FETCH rec INTO @line
        IF @@FETCH_STATUS = 0 SET @sql = @sql + CAST(',' AS NVARCHAR(MAX))
    END
    CLOSE rec
    DEALLOCATE REC

    SET @sql = @sql + CAST(')' AS NVARCHAR(MAX))
    EXEC meta.debug @@PROCID, 'Execute SQL for creating table'
    EXEC meta.debug @@PROCID, @sql


    EXEC sp_executesql @sql

    -- + Determine load type(DEFAULT_CSV_HEADER) based on separator
    SET @type = CASE @separator
                    WHEN ',' THEN 'COMMA_CSV_HEADER'
                    ELSE          'DEFAULT_CSV_HEADER'
                END
    -- | -Add the agreement
    DECLARE @new_agreement_id BIGINT
    DECLARE @description      NVARCHAR(200)
    SET @description = 'Autogenerated from dataset in delivery [' + CAST(@delivery_id AS NVARCHAR) + ']'
    EXEC[meta].[agreement_add] @name, @user, 'ADMIN', @pattern, @type, @description, 0, NULL, NULL, NULL, @new_agreement_id OUT

    -- | -Add validation rules
    EXEC[meta].[agreement_rule_add_all] @new_agreement_id, NULL

    CREATE TABLE #result (id BIGINT, data NVARCHAR(MAX))

    -- | ----------------------------------------
    --| Perform agreement_dump and store computed code lines as repo data
    INSERT INTO #result 
      EXEC meta.agreement_dump  @new_agreement_id

    SET @sql = 'INSERT INTO ' + @repo_name + ' (dw_delivery_id, ' + @column + ') '
             + 'SELECT ' + CAST(@delivery_id AS NVARCHAR) + ', data FROM #result ORDER BY id'
    EXEC meta.debug @@PROCID, @sql
    EXEC sp_executesql @sql

    -- | Truncate stag table
    SET @sql = 'TRUNCATE TABLE ' + @stag_name
    EXEC meta.debug @@PROCID, @sql
    EXEC sp_executesql @sql

    RETURN 0
END
-- | ==========================================================================================
;
CREATE
PROCEDURE[meta].[delivery_find] --|
--| ==========================================================================================
--| Description: Lookup the delivery from filename.Mainly used for cleanup batch scripts
--| Arguments:             
(
    @name NVARCHAR(250),      --| Name of file to match against the deliveries
    @delivery_id BIGINT         OUT, --| Return found ID
   @count        BIGINT OUT  --| Number of found matches
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN

    --| Based on filename
--    EXEC meta.debug @@PROCID, @name
    SELECT @delivery_id = MAX(d.id),
           @count       = COUNT(*)
      FROM meta.delivery d
     WHERE name LIKE @name


    RETURN
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[delivery_load] --|
--| ==========================================================================================
--| Description: Load the data from the delivery file into the load table in temp.
--|              Use the provided name to lookup the agreement and other information from meta
--|              data and make sure the temp schema table is created and populated from the
--|              specified file name.
--|              The agreement to which the delivery belongs specifies the file2temp procedure
--|              call, which again is a dynamic code 'stub'. This allows customized procedures
--|              to be implemented and called instead of the default generic_file2temp().
--|              
--| Arguments:             
(
    @path NVARCHAR(250), --| Path to physical file
    @name NVARCHAR(250), --| Name of file to match against the agreement pattern
  @owner  NVARCHAR(50),  --| Owner of the physical file
  @size   BIGINT         --| Size in bytes of the physical file
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    --- --------------------------------------------------------------------------------------
    --- NOTE: More intelligent handling of previous load attempts could be made here such as 
    --- skipping already inserted rows. But the assumption for now (2012-01-30) is that all
    --- loads are performed from scratch every time until further performance requirements are
    --- set for the solution
    --- --------------------------------------------------------------------------------------
    --- NOTE: More intelligent handling of errors could be implemented here - such as checking
    --- error tables and other logs
    --- --------------------------------------------------------------------------------------
    
    DECLARE @count         INT
    DECLARE @agreement_id BIGINT
    DECLARE @delivery_id   BIGINT
    DECLARE @table_id BIGINT
    DECLARE @audit_id      BIGINT
    DECLARE @file2temp NVARCHAR(250)

    --| Based on name pattern, lookup the agreement from meta.agreement table
    EXEC meta.debug @@PROCID, 'Lookup active agreement from delivery.name LIKE agreement.pattern'
    EXEC meta.agreement_find @name, 1, @agreement_id OUT, @file2temp OUT

    IF @agreement_id IS NULL
    BEGIN
        RAISERROR ('Error looking up agreement [%s]', 11, 1, @name)
        RETURN 2
    END
   
    --| Add delivery to meta data in stage temp(ID 1)
    EXEC meta.delivery_add @agreement_id, 1, @name, @owner, @size, 'BULK INSERT', @delivery_id OUT, @audit_id OUT, @table_id OUT

    --| BEGIN controlled transaction
    --+ From here we take over error handling in order to log failed attempts
    BEGIN TRANSACTION

    BEGIN TRY
        --| Lookup agreement attributes
        DECLARE @auto_truncate_temp NVARCHAR(10)
        DECLARE @table_name         NVARCHAR(128)
        SELECT @auto_truncate_temp = u.value,
               @table_name = t.table_name
          FROM meta.agreement_attribute_v   u,
               meta.agreement_stage_table_v t
         WHERE u.agreement_id   = @agreement_id
           AND t.agreement_id   = @agreement_id
           AND t.table_schema   = 'temp'
           AND u.attribute_name = 'AUTO_TRUNCATE_TEMP'

        -- | Check if temp load table is ready (empty) - otherwise complain and break
        EXEC meta.debug @@PROCID, 'Check if temp table exists'
        DECLARE @sql    NVARCHAR(2000)

        --+ Check if load table exists
        IF NOT EXISTS(SELECT* FROM sys.tables WHERE object_id = OBJECT_ID('[temp].[' + @table_name + ']'))
            RAISERROR('Temp table [temp].[%s] does not exist', 10, 1, @table_name)
        
        --| Truncate table if AUTO_TRUNCATE_TEMP is YES
        EXEC meta.debug @@PROCID, 'Check AUTO_TRUNCATE_TEMP attribute'
        EXEC meta.debug @@PROCID, @auto_truncate_temp
        IF @auto_truncate_temp = 'YES'
        BEGIN
            EXEC meta.debug @@PROCID, 'Truncate temp table'
            SET @sql = 'TRUNCATE TABLE [temp].[' + @table_name + ']'
            EXEC meta.debug @@PROCID, @sql
            EXEC sp_executesql @sql
        END

        --+ Get the number of rows in table
        EXEC meta.debug @@PROCID, 'Check if temp table is empty'
        SET @sql = 'SELECT @out = COUNT(*) FROM [temp].[' + @table_name + ']'
        EXEC meta.debug @@PROCID, @sql
        EXEC sp_executesql @sql, N'@out BIGINT OUTPUT', @count OUT

        --+ Error + exit if not empty
        EXEC meta.debug @@PROCID, 'Count from temp table'
        EXEC meta.debug @@PROCID, @count
        IF @count > 0 
            RAISERROR ('Query returned non-zero count [%s] - bulk load table is in invalid state and need manual check + cleanup', 11, 1, @sql)

        --| Get the stored procedure call for loading data(source --> repo)
        --| Replace the available parameters in quotes in the dynamic query(file2temp)
        EXEC meta.debug @@PROCID, 'Prepare stored procedure for loading temp table'
        --|  @delivery_id:  Current delivery_id just generated
        SET @file2temp = REPLACE(@file2temp, '@delivery_id', CAST(@delivery_id AS NVARCHAR))
        -- | @path:         Directory path of the file being loaded
        SET @file2temp = REPLACE(@file2temp, '@path', '''' + @path + '''')
        -- | @name:         Name of file (including extension)
        SET @file2temp = REPLACE(@file2temp, '@name', '''' + @name + '''')
        -- | @owner:        File system owner of the file being loaded
        SET @file2temp = REPLACE(@file2temp, '@owner', '''' + @owner + '''')
        -- | @size:         File system size of the file being loaded
        SET @file2temp = REPLACE(@file2temp, '@size', CAST(@size AS NVARCHAR))
        EXEC meta.debug @@PROCID, @file2temp
        --| Execute the stub
        EXEC sp_executesql @file2temp

        EXEC meta.operation_add @audit_id, 1, @@PROCID, 'Delivery loaded'
    END TRY
    --| ERROR handling
    BEGIN CATCH
        --| Log in audit and rollback transaction
        ROLLBACK TRANSACTION
        EXEC meta.operation_add @audit_id, 3, @@PROCID, NULL
        EXEC meta.debug @@PROCID, 'Loading delivery failed'
        --| Return error code
        RETURN 10
    END CATCH
    
    --| SUCCESS handling
    EXEC meta.debug @@PROCID, 'DONE'
        --| COMMIT controlled transaction
    COMMIT TRANSACTION
        --| Return success
    RETURN
    --| END
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[delivery_publish] --|
--| ==========================================================================================
--| Description: Publish the data from the staging area to repository for external usage
--|              The agreement to which the delivery belongs specifies the stag2repo procedure
--|              for publishing the data to the repo schema.This allows customized publishing 
--|              procedures to be implemented for deliveries requiring special treatment as an
--|              alternative to the standard generic_stag2repo() procedure.
--| Arguments:             
(
    @name NVARCHAR(250)  --| Name of file to match against the agreement pattern
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @msg NVARCHAR(4000)
    DECLARE @stag2repo     NVARCHAR(1000)
    DECLARE @count         INT
    DECLARE @agreement_id BIGINT
    DECLARE @delivery_id   BIGINT
    DECLARE @table_id BIGINT
    DECLARE @audit_id      BIGINT

    --| Based on name pattern, lookup the agreement from meta.agreement table
    EXEC meta.debug @@PROCID, 'Lookup active agreement from delivery.name LIKE agreement.pattern'
    EXEC meta.agreement_find @name, 3, @agreement_id OUT, @stag2repo OUT
    IF @agreement_id IS NULL
    BEGIN
        RAISERROR ('Error looking up agreement [%s]', 11, 1, @name)
        RETURN 2
    END

    --| Promote delivery to stag(ID 2)
    EXEC meta.delivery_add @agreement_id, 3, @name, NULL, 0, 'PUBLISH', @delivery_id OUT, @audit_id OUT, @table_id OUT

    IF @delivery_id IS NULL
    BEGIN
        RAISERROR('Delivery [%s] for repository not available', 11, 1, @name)
        RETURN 4
    END

    --+ Get the temp and stag schema and table names
    DECLARE @stag_schema NVARCHAR(50)
    DECLARE @stag_name    NVARCHAR(100)
    DECLARE @repo_schema  NVARCHAR(50)
    DECLARE @repo_name    NVARCHAR(100)

    --+ Stag table
    SELECT @stag_name = table_name,
           @stag_schema = table_schema
      FROM meta.agreement_stage_table_v
     WHERE agreement_id = @agreement_id
       AND table_schema = 'stag'

    -- + Repo table
    SELECT @repo_name   = table_name,
           @repo_schema = table_schema
      FROM meta.agreement_stage_table_v
     WHERE agreement_id = @agreement_id
       AND table_schema = 'repo'

    -- + Check if table names were found
    IF @stag_name IS NULL
    BEGIN
        RAISERROR('Stag table not found for delivery [%s]', 11, 1, @name)
        RETURN 5
    END
    IF @repo_name IS NULL
    BEGIN
        RAISERROR('Repo table not found for delivery [%s]', 11, 1, @name)
        RETURN 6
    END

    --| Check if delivery has already been loaded once
    DECLARE @sql    NVARCHAR(MAX)
    SET @sql = 'SELECT @o_count = COUNT(*) '
             + '  FROM [' + @repo_schema + '].[' + @repo_name + ']'
             + ' WHERE dw_delivery_id = ' + CAST(@delivery_id AS NVARCHAR)
    EXEC sp_executesql @sql, N'@o_count INT OUT', @o_count = @count OUT

    IF COALESCE(@count, 0) > 0 
    BEGIN
        EXEC meta.operation_add @audit_id, 3, @@PROCID, 'Delivery has already promoted'
        RAISERROR('Delivery [%s] has already been promoted to [repo] ([%d] rows)', 11, 1, @name, @count)
        RETURN 7
    END
    
    --| BEGIN controlled transaction
    --+ From here we take over error handling in order to log failed attempts
    BEGIN TRANSACTION

    BEGIN TRY
        --| Get the stored procedure call for moving data(stag --> repo)
        EXEC meta.debug @@PROCID, 'Prepare SQL for mapping stag table to repo'
        --| Replace available parameters in quotes in the dynamic query (temp2stag)
        --|  @delivery_id
        SET @stag2repo = REPLACE(@stag2repo, '@delivery_id', CAST(@delivery_id AS NVARCHAR))
        EXEC meta.debug @@PROCID, @stag2repo
        EXEC sp_executesql @stag2repo, N'@o_sql NVARCHAR(MAX) OUT', @o_sql = @sql OUT
        EXEC meta.debug @@PROCID, @sql

        IF LEN(@sql) = 0 RAISERROR('Stag-> procedure [%s] returned empty SQL', 11, 1, @stag2repo)
        
        --| Execute the SQL insert into repo statement
        EXEC sp_executesql @sql

        --+ Prepare cleanup of stag statement(TRUNCATE)
        EXEC meta.debug @@PROCID, 'Truncate stag table'
        SET @sql = 'TRUNCATE TABLE [' + @stag_schema + '].[' + @stag_name + ']'

        -- | Execute the cleanup of stag table
        EXEC sp_executesql @sql


    END TRY
    --| ERROR handling
    BEGIN CATCH
        --| Log in audit and rollback transaction
        IF @@trancount > 0 ROLLBACK TRANSACTION
        IF @audit_id IS NOT NULL EXEC meta.operation_add @audit_id, 3, @@PROCID, NULL
        EXEC meta.debug @@PROCID, 'Publishing delivery failed'
        --| Return error code
        RETURN 10
    END CATCH
    
    --| SUCCESS handling
    EXEC meta.debug @@PROCID, 'DONE'
        --| COMMIT controlled transaction
    COMMIT TRANSACTION
        --| Return success
    RETURN
    --| END
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[delivery_validate] --|
--| ==========================================================================================
--| Description: Validate the data loaded into the database from file and move to staging area
--|              The agreement to which the delivery belongs specifies the temp2stag procedure
--|              for moving the data to stag after validation using generic rules.This allows
--|              customized validation procedures to be implemented for deliveries requiring
--|              special treatment on top of the standard rule system.Such procedures must
--|              implement the moving of data from temp to stag schema - or call the default
--|              generic_temp2stag() procedure in the end.
--| Arguments:             
(
    @name NVARCHAR(250)  --| Name of file to match against the agreement pattern
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @msg NVARCHAR(4000)
    DECLARE @temp2stag     NVARCHAR(1000)
    DECLARE @count         INT
    DECLARE @agreement_id BIGINT
    DECLARE @delivery_id   BIGINT
    DECLARE @table_id BIGINT
    DECLARE @audit_id      BIGINT

    --| Based on name pattern, lookup the agreement from meta.agreement table
    EXEC meta.debug @@PROCID, 'Lookup active agreement from delivery.name LIKE agreement.pattern'
    EXEC meta.agreement_find @name, 2, @agreement_id OUT, @temp2stag OUT
    IF @agreement_id IS NULL
    BEGIN
        RAISERROR ('Error looking up agreement [%s]', 11, 1, @name)
        RETURN 2
    END

    --| Promote delivery to stag(ID 2)
    EXEC meta.delivery_add @agreement_id, 2, @name, NULL, 0, 'VALIDATE', @delivery_id OUT, @audit_id OUT, @table_id OUT

    --+ Error if valid delivery_id is not returned
    IF @delivery_id IS NULL
    BEGIN
        RAISERROR('Delivery [%s] for staging not available', 11, 1, @name)
        RETURN 4
    END

    --+ Get the temp and stag schema and table names
    DECLARE @temp_schema NVARCHAR(50)
    DECLARE @temp_name    NVARCHAR(100)
    DECLARE @stag_schema  NVARCHAR(50)
    DECLARE @stag_name    NVARCHAR(100)

    --+ Temp table
    SELECT @temp_name = table_name,
           @temp_schema = table_schema
      FROM meta.agreement_stage_table_v
     WHERE agreement_id = @agreement_id
       AND table_schema = 'temp'

    -- + Stag table
    SELECT @stag_name   = table_name,
           @stag_schema = table_schema
      FROM meta.agreement_stage_table_v
     WHERE agreement_id = @agreement_id
       AND table_schema = 'stag'

    -- + Check if table names were found
    IF @temp_name IS NULL
    BEGIN
        RAISERROR('Temp table not found for delivery [%s]', 11, 1, @name)
        RETURN 5
    END
    IF @stag_name IS NULL
    BEGIN
        RAISERROR('Stag table not found for delivery [%s]', 11, 1, @name)
        RETURN 6
    END

    --| Check if delivery has already been loaded once
    DECLARE @sql    NVARCHAR(MAX)
    SET @sql = 'SELECT @o_count = COUNT(*) '
             + '  FROM [' + @stag_schema + '].[' + @stag_name + ']'
             + ' WHERE dw_delivery_id = ' + CAST(@delivery_id AS NVARCHAR)
    EXEC sp_executesql @sql, N'@o_count INT OUT', @o_count = @count OUT

	--+ Error + break if delivery_id is present in stag table
    IF COALESCE(@count, 0) > 0 
    BEGIN
        EXEC meta.operation_add @audit_id, 3, @@PROCID, 'Delivery has already promoted'
        RAISERROR('Delivery [%s] has already been promoted to [stag] ([%d] rows)', 11, 1, @name, @count)
        RETURN 7
    END
    
    --| Load validation rules if any
    SELECT @count = COUNT(*)
      FROM meta.agreement_rule
     WHERE agreement_id = @agreement_id


    IF @count > 0
    BEGIN
        DECLARE @rule_id INT
        DECLARE @rule_text   NVARCHAR(MAX)
        DECLARE @rule_count INT
        DECLARE @err_table   NVARCHAR(110)
        SET @err_table = '[' + @temp_schema + '].[' + @temp_name + '_errors]'

        -- + Drop the error table if it exists
        IF OBJECT_ID(@err_table) IS NOT NULL
        BEGIN
            SET @sql = 'DROP TABLE ' + @err_table
            EXEC meta.debug @@PROCID, @sql
            EXEC sp_executesql @sql
        END
        
        --| Loop over rules specific for the agreement
        DECLARE rul CURSOR FOR
        SELECT rule_id, rule_text
          FROM meta.agreement_rule
         WHERE agreement_id = @agreement_id


        OPEN rul

        --+ Prepare (daft MS SQL) loop
        FETCH NEXT FROM rul INTO @rule_id, @rule_text

        SET @sql = CAST('SELECT * INTO ' + @err_table + ' FROM (' AS NVARCHAR(MAX))
        SET @rule_count = 0

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @rule_count = @rule_count + 1
            SET @msg = '  RULE [' + CAST(@rule_id AS NVARCHAR) + ']: [' + @rule_text + ']'
            EXEC meta.debug @@PROCID, @msg

            --| Append validation SQL
            SET @sql = @sql
                     + CAST('SELECT *,'  AS NVARCHAR(MAX))
                     + CAST(@rule_id     AS NVARCHAR(MAX)) + CAST(' AS rule_id, '    AS NVARCHAR(MAX))
                     + CAST(@delivery_id AS NVARCHAR(MAX)) + CAST(' AS delivery_id ' AS NVARCHAR(MAX))
                     + CAST('  FROM [' + @temp_schema + '].[' + @temp_name + ']'     AS NVARCHAR(MAX))
                     + CAST(' WHERE NOT(' + @rule_text + ')' AS NVARCHAR(MAX))

            FETCH NEXT FROM rul INTO @rule_id, @rule_text
            IF @@FETCH_STATUS = 0 SET @sql = @sql + CAST(' UNION ALL ' AS NVARCHAR(MAX))
        END

        --| Set dummy validation statement if no rules applied
        IF @rule_count = 0 SET @sql = @sql + 'SELECT CAST(0 AS INT) AS dummy_with_no_rows WHERE 1=0'
        SET @sql = @sql + CAST(') a' AS NVARCHAR(MAX))

        -- | Execute the final validation SQL statement built from rules
        EXEC meta.debug @@PROCID, 'Loaded rules into SQL'
        EXEC meta.debug @@PROCID, @rule_count
        EXEC meta.debug @@PROCID, @sql
        EXEC sp_executesql @sql
        
        --| Perform error checking after rules have been applied
        --+ Check if rows are found in the temp error table
        SET @sql = 'SELECT @o_count = COUNT(*) FROM ' + @err_table + ' WHERE delivery_id = ' + CAST(@delivery_id AS NVARCHAR(MAX))
        EXEC meta.debug @@PROCID, @sql
        EXEC sp_executesql @sql, N'@o_count INT OUT', @o_count = @count OUT

        IF @count > 0 
        BEGIN
            EXEC meta.operation_add @audit_id, 3, @@PROCID, 'Validation failed'
            RAISERROR('Validation errors found [%d] - check [%s].[%s_errors]', 11, 1, @count, @temp_schema, @temp_name)
            RETURN 2
        END

        --+ Only drop if truly empty
        SET @sql = 'SELECT @o_count = COUNT(*) FROM ' + @err_table
        EXEC meta.debug @@PROCID, @sql
        EXEC sp_executesql @sql, N'@o_count INT OUT', @o_count = @count OUT

        IF @count = 0 
        BEGIN
            --+ Drop the error(empty) table
            SET @sql = 'DROP TABLE ' + @err_table
            EXEC meta.debug @@PROCID, @sql
            EXEC sp_executesql @sql
        END
    END

    --| BEGIN controlled transaction
    --+ From here we take over error handling in order to log failed attempts
    BEGIN TRANSACTION

    BEGIN TRY
        --| Get the stored procedure call for moving data(temp --> stag)
        EXEC meta.debug @@PROCID, 'Prepare SQL for mapping temp table to stag'
        --| Replace available parameters in quotes in the dynamic query (temp2stag)
        --|  @delivery_id
        SET @temp2stag = REPLACE(@temp2stag, '@delivery_id', CAST(@delivery_id AS NVARCHAR))
        EXEC meta.debug @@PROCID, @temp2stag
        EXEC sp_executesql @temp2stag, N'@o_sql NVARCHAR(MAX) OUT', @o_sql = @sql OUT

        EXEC meta.debug @@PROCID, @sql

        IF LEN(@sql) = 0 RAISERROR('Temp->Stag procedure [%s] returned empty SQL', 11, 1, @temp2stag)
        
        --| Execute the SQL insert into stag statement
        EXEC sp_executesql @sql

        --+ Prepare cleanup of temp statement(TRUNCATE)
        EXEC meta.debug @@PROCID, 'Truncate temp table'
        SET @sql = 'TRUNCATE TABLE [' + @temp_schema + '].[' + @temp_name + ']'

        -- | Execute the cleanup of temp table
        EXEC sp_executesql @sql


    END TRY
    --| ERROR handling
    BEGIN CATCH
        --| Log in audit and rollback transaction
        IF @@trancount > 0 ROLLBACK TRANSACTION
        EXEC meta.operation_add @audit_id, 3, @@PROCID, NULL
        EXEC meta.debug @@PROCID, 'Validating delivery failed'
        --| Return error code
        RETURN 10
    END CATCH
    
    --| SUCCESS handling
    EXEC meta.debug @@PROCID, 'DONE'
        --| COMMIT controlled transaction
    COMMIT TRANSACTION
        --| Return success
    RETURN
    --| END
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[generic_big2temp] --|
--| ==========================================================================================
--| Description: Wrap the meta.generic_file2temp by providing the destination path of the big
--|              output file - load the meta data as normal.This way the big files becomes
--|              agreement specific and not an exception in the batch script controlling it.
--|              The call to this procedure is tied into the agreement using it and the path
--|              is extracted from the meta.agreement.file2temp column by the batch script.
(
    @destination NVARCHAR(250),  --| The hardcoded(in agreement spec) destination of file
  @delivery_id  BIGINT,         --| Pass-through argument to generic_file2temp
    @path NVARCHAR(250)   --| Pass-through argument to generic_file2temp
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    --| Execute wrapped call to generic_file2temp
    EXEC meta.debug @@PROCID, 'Wrap the generic_file2temp call'
    EXEC meta.generic_file2temp @delivery_id, @path
    RETURN
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[generic_link2temp] --|
--| ==========================================================================================
--| Description: Load data from source db_link into temp table
--| Arguments:             
(
    @delivery_id BIGINT,
    @db_link NVARCHAR(250)
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @count INT
    DECLARE @agreement_id  BIGINT
    DECLARE @schema NVARCHAR(50)
    DECLARE @table         NVARCHAR(100)

    --| Lookup the essential arguments from the delivery
    SELECT @agreement_id = agreement_id
      FROM meta.delivery
     WHERE id = @delivery_id

    --| Lookup the type details from the delivery_id via the agreement
    EXEC meta.debug @@PROCID, 'Lookup temp details meta data via agreement'

    DECLARE rec CURSOR FOR
    SELECT table_schema, table_name, mapping, column_name
      FROM meta.column_mapping_v
     WHERE agreement_id = @agreement_id
       AND table_schema = 'temp'
     ORDER BY ordinal_position

    --+ Open cursor
    OPEN rec

    --| Loop over temp_column and stag_column mappings and prepare lists for insert statement
    DECLARE @sql        NVARCHAR(MAX)
    DECLARE @msg NVARCHAR(500)
    DECLARE @s_column   NVARCHAR(MAX)
    DECLARE @s_columns  NVARCHAR(MAX)
    DECLARE @d_column   NVARCHAR(MAX)
    DECLARE @d_columns  NVARCHAR(MAX)
    SET @s_columns = CAST('' AS NVARCHAR(MAX))
    SET @d_columns = CAST('' AS NVARCHAR(MAX))

    -- + Prepare(daft MS SQL) loop
    FETCH NEXT FROM rec INTO @schema, @table, @s_column, @d_column

    EXEC meta.debug @@PROCID, 'Generate SQL for transferring data'

    --| Generate insert into temp statement:
    --| INSERT INTO[temp table] (..) SELECT(..) FROM[db link]
  SET @sql = CAST('INSERT INTO [' + @schema + '].[' + @table + '] (' AS NVARCHAR(MAX))

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @msg = '  [' + @s_column + '] --> [' + @d_column + ']'
        EXEC meta.debug @@PROCID, @msg
        SET @s_columns = @s_columns + @s_column
        SET @d_columns = @d_columns + @d_column

        -- + Repeat(daft MS SQL) fetch
        FETCH NEXT FROM rec INTO @schema, @table, @s_column, @d_column
        IF @@FETCH_STATUS = 0
        BEGIN
            SET @s_columns = @s_columns + CAST(',' AS NVARCHAR(MAX))
            SET @d_columns = @d_columns + CAST(',' AS NVARCHAR(MAX))
        END
    END
    CLOSE rec
    DEALLOCATE rec

    --+ Finish the SQL statement
    SET @sql = @sql + @d_columns
             + CAST(') SELECT ' AS NVARCHAR(MAX))
             + @s_columns
             + CAST('  FROM ' + @db_link AS NVARCHAR(MAX))
    EXEC meta.debug @@PROCID, @sql

    --| Execute SQL statement in transaction
    BEGIN TRY
        EXEC sp_executesql @sql
        SET @count = @@ROWCOUNT
        EXEC meta.debug @@PROCID, 'DONE'
    END TRY
    BEGIN CATCH
        EXEC meta.debug @@PROCID, 'Error retrieving rows from link'
    END CATCH

    --| Update the delivery meta data
    EXEC meta.debug @@PROCID, 'Update meta.delivery with rowcount'
    EXEC meta.debug @@PROCID, @count
    UPDATE meta.delivery
       SET size = @count
     WHERE id = @delivery_id


    RETURN
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[generic_stag2repo] --|
--| ==========================================================================================
--| Description: Generic method for generating SQL for moving data from stag to repo based
--|              on the columns in the meta.column_mapping_V view. The custom methods
--|              will need to implement the same stub
--| Arguments:
(
    @delivery_id BIGINT,              --| ID of delivery to move data for
    @sql NVARCHAR(MAX) OUTPUT --| Generated SQL string for doing the move
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    --| Lookup the agreement
    EXEC meta.debug @@PROCID, 'Lookup agreement_id from delivery_id'
    DECLARE @agreement_id    BIGINT
    SELECT @agreement_id = agreement_id
      FROM meta.delivery
     WHERE id = @delivery_id

    --+ Get the stag and repo table names
    --+ NOTE: Repo table(may depend on frequency agreement attribute)
    DECLARE @stag_name    NVARCHAR(100)
    DECLARE @repo_name    NVARCHAR(100)

    --+ Stag table
    SELECT @stag_name = table_name
      FROM meta.agreement_stage_table_v
     WHERE agreement_id = @agreement_id
       AND table_schema = 'stag'

    -- | Select the mapping of columns from stag to repo (identical data types)
    --+ NOTE: dw_row_id is auto populated by IDENTITY, so exclude
    EXEC meta.debug @@PROCID, 'Prepare SQL for mapping stag table to repo'
    DECLARE rec CURSOR FOR
    SELECT mapping, column_name, table_name
      FROM meta.column_mapping_v
     WHERE agreement_id = @agreement_id
       AND table_schema = 'repo'
       AND column_name <> '[dw_row_id]'
     ORDER BY ordinal_position

    --+ Open cursor
    OPEN rec

    --| Loop over temp_column and stag_column mappings and prepare lists for insert statement
    DECLARE @msg           NVARCHAR(4000)
    DECLARE @stag_column   NVARCHAR(MAX)
    DECLARE @stag_columns  NVARCHAR(MAX)
    DECLARE @repo_column   NVARCHAR(MAX)
    DECLARE @repo_columns  NVARCHAR(MAX)
    SET @stag_columns = CAST('' AS NVARCHAR(MAX))
    SET @repo_columns = CAST('' AS NVARCHAR(MAX))

    -- + Prepare(daft MS SQL) loop
    FETCH NEXT FROM rec INTO @stag_column, @repo_column, @repo_name

    --| Generate insert into repo statement:
    --| INSERT INTO[repo table] (..) SELECT(..) FROM[stag table]
  SET @sql = CAST('INSERT INTO [repo].[' + @repo_name + '] (' AS NVARCHAR(MAX))

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @msg = '  [' + @stag_column + '] --> [' + @stag_column + ']'
        EXEC meta.debug @@PROCID, @msg
        SET @stag_columns = @stag_columns + @stag_column
        SET @repo_columns = @repo_columns + @repo_column

        -- + Repeat(daft MS SQL) fetch
        FETCH NEXT FROM rec INTO @stag_column, @repo_column, @repo_name
        IF @@FETCH_STATUS = 0
        BEGIN
            SET @stag_columns = @stag_columns + CAST(',' AS NVARCHAR(MAX))
            SET @repo_columns = @repo_columns + CAST(',' AS NVARCHAR(MAX))
        END
    END
    CLOSE rec
    DEALLOCATE rec
    
    --| Finish and return SQL statement
    SET @sql = @sql
             + @repo_columns
             + CAST(') SELECT ' AS NVARCHAR(MAX))
             + @stag_columns
             + CAST(' FROM [stag].[' + @stag_name + ']' AS NVARCHAR(MAX))

    EXEC meta.debug @@PROCID, 'DONE'

    --| Return success
    RETURN
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[generic_temp2stag] --|
--| ==========================================================================================
--| Description: Generic method for generating SQL for moving data from temp to stag based
--|              on the columns in the meta.column_mapping_v view. The custom methods
--|              will need to implement the same stub
--| Arguments:
(
    @delivery_id BIGINT,              --| ID of delivery to move data for
    @sql NVARCHAR(MAX) OUTPUT --| Generated SQL string for doing the move
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    --| Lookup the agreement
    EXEC meta.debug @@PROCID, 'Lookup agreement_id from delivery_id'
    DECLARE @agreement_id    BIGINT
    SELECT @agreement_id = agreement_id
      FROM meta.delivery
     WHERE id = @delivery_id

    --| Lookup the tablename and file separator from agreement type
    DECLARE @separator NVARCHAR(10)
    DECLARE @nvarchar_max_load  NVARCHAR(1000)
    DECLARE @table              NVARCHAR(128)

    SELECT @table = t.table_name,
           @nvarchar_max_load = u.value,
           @separator = y.fieldterminator
      FROM meta.agreement_stage_table_v t,
           meta.agreement a,
           meta.[type] y,
           meta.agreement_attribute_v u
     WHERE a.id = @agreement_id
       AND a.id = t.agreement_id
       AND a.id = u.agreement_id
       AND y.id = a.type_id
       AND t.table_schema   = 'stag'
       AND u.attribute_name = 'NVARCHAR_MAX_LOAD'

    -- | Select the mapping of columns from temp (all in NVARCHAR) to stag(real data types)
    --| using the mapping precedence order outlined below
    EXEC meta.debug @@PROCID, 'Prepare SQL for mapping temp table to stag'
    DECLARE rec CURSOR FOR
    SELECT CASE WHEN column_name = '[dw_delivery_id]' THEN CAST(@delivery_id AS NVARCHAR) ELSE mapping END, column_name
      FROM meta.column_mapping_v
     WHERE agreement_id = @agreement_id
       AND table_schema = 'stag'
     ORDER BY ordinal_position

    --+ Open cursor
    OPEN rec

    --| Loop over temp_column and stag_column mappings and prepare lists for insert statement
    DECLARE @msg           NVARCHAR(4000)
    DECLARE @in_list       NVARCHAR(MAX)
    DECLARE @temp_column   NVARCHAR(MAX)
    DECLARE @stag_column   NVARCHAR(MAX)
    DECLARE @temp_columns  NVARCHAR(MAX)
    DECLARE @stag_columns  NVARCHAR(MAX)
    DECLARE @position      INT
    SET @temp_columns = CAST('' AS NVARCHAR(MAX))
    SET @stag_columns = CAST('' AS NVARCHAR(MAX))

    -- + Prepare(daft MS SQL) loop
    FETCH NEXT FROM rec INTO @temp_column, @stag_column

    --| Generate insert into stag statement:
    --| INSERT INTO[stag table] (..) SELECT(..) FROM[temp table]
  SET @sql = CAST('INSERT INTO [stag].[' + @table + '] (' AS NVARCHAR(MAX))
    SET @position = 1
    SET @in_list = ''


    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @msg = '  [' + @temp_column + '] --> [' + @stag_column + ']'
        EXEC meta.debug @@PROCID, @msg
        SET @temp_columns = @temp_columns
                          + CASE WHEN @nvarchar_max_load = 'NO' THEN @temp_column
                                 ELSE CAST(REPLACE(@temp_column, @stag_column, '[' + CAST(@position AS NVARCHAR) + ']') AS NVARCHAR(MAX))
                            END
        SET @stag_columns = @stag_columns + @stag_column
        SET @in_list  = @in_list + '[' + CAST(@position AS NVARCHAR(MAX)) + ']'

        --+ Repeat(daft MS SQL) fetch
       FETCH NEXT FROM rec INTO @temp_column, @stag_column
       IF @@FETCH_STATUS = 0 
        BEGIN
            SET @temp_columns = @temp_columns + CAST(',' AS NVARCHAR(MAX))
            SET @stag_columns = @stag_columns + CAST(',' AS NVARCHAR(MAX))
            SET @in_list = @in_list + CAST(',' AS NVARCHAR(MAX))
        END
        SET @position = @position + 1
    END
    CLOSE rec
    DEALLOCATE rec


    DECLARE @source NVARCHAR(MAX)
    --| Handle source table depending on type of data(attribute NVARCHAR_MAX_LOAD)
    IF @nvarchar_max_load = 'NO'
    BEGIN
        --| NO  => Standard select from temp table
        EXEC meta.debug @@PROCID, 'Standard source select'
        SET @source = CAST('[temp].[' + @table + ']' AS NVARCHAR(MAX))
    END
    ELSE
    BEGIN
        --| YES => Special select first splitting using separator and re-grouping into
        --|        table using pivot
        EXEC meta.debug @@PROCID, 'Special source select (NVARCHAR_MAX_LOAD) using CROSS JOIN with split function and PIVOT due to MS SQL 8060 char limit'
        SET @source = CAST('(' AS NVARCHAR(MAX))
                    + CAST('     SELECT a.rowid, b.val, b.pos ' AS NVARCHAR(MAX))
                    + CAST('       FROM (SELECT *, ROW_NUMBER() OVER (ORDER BY data) AS rowid FROM [temp].[' + @table + ']) a ' AS NVARCHAR(MAX))
                    + CAST('            CROSS APPLY meta.split(a.data, ''' + @separator + ''') b) s' AS NVARCHAR(MAX))
                    + CAST(' PIVOT' AS NVARCHAR(MAX))
                    + CAST(' (MAX(s.val) FOR pos IN (' + @in_list + ')) AS p' AS NVARCHAR(MAX))
    END

    EXEC meta.debug @@PROCID, @source

    --| Finish and return SQL statement
    SET @sql = @sql
             + @stag_columns
             + CAST(') SELECT ' AS NVARCHAR(MAX))
             + @temp_columns
             + CAST(' FROM ' + @source AS NVARCHAR(MAX))

    EXEC meta.debug @@PROCID, 'DONE'

    --| Return success
    RETURN
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[get_data] --|
--| ==========================================================================================
--| Description: Return the dataset related to the delivery agreement matching the date/time,
--|              i.e.delivered as the latest delivery BEFORE the @delivery_date provided.
--|              Defaults to current date/time.If @delivery_id is provided, any date/time
--|              constraints are overridden.
--| Arguments:
(
    @username NVARCHAR(250), --| Username of requestor
@name                  NVARCHAR(250), --| Name of agreement
@external_id           BIGINT,        --| ID of external data item(e.g. in AAC)
    @delivery_date NVARCHAR(25),  --| Date string (YYYY-MM-DD[HH24:MI:SS]) of latest
                                          --| delivery up until
    @delivery_id           BIGINT         --| ID of delivery - blank/NULL => latest based on 
                                          --| @delivery_date
)
AS 
SET NOCOUNT ON
SET ANSI_WARNINGS OFF
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @table_schema NVARCHAR(50)
    DECLARE @table_name   NVARCHAR(100)
    DECLARE @agreement_id BIGINT
    DECLARE @sql NVARCHAR(MAX)
    DECLARE @date         DATETIME
    DECLARE @user_id BIGINT

    --| Setup the date for latest delivery
    SET @date = COALESCE(CONVERT(DATETIME, @delivery_date, 120), GETDATE())

    -- | Collect meta data
    --+ Get the agreement_id based on name
    SELECT @agreement_id = id
      FROM meta.agreement
     WHERE name = @name

    -- | Check user permissions
    SET @user_id = meta.user_access(@username, @agreement_id, 'VIEW')
    IF COALESCE(@user_id, 0) = 0 
    BEGIN
        --+ Lookup the user(without VIEW permissions) in order to log retrieval attempt
       SELECT @user_id = id
         FROM meta.[user]
        WHERE username = @username

        --+ Insert the failed link in status error
        INSERT INTO meta.[link]
               (external_id, dw_delivery_id, user_id, status_id)
        VALUES(@external_id, @delivery_id, @user_id, 2)


        RAISERROR('User [%s] does not have VIEW permission on agreement [%I64d]', 11, 1, @username, @agreement_id)
        RETURN 2
    END

    --+ TODO: ERROR-HANDLING

    --| Get the MAX_AGE_DAYS attribute for limiting the retrieval back in time
    DECLARE @max_age_days INT
    DECLARE @max_age_days_c NVARCHAR(50)
    SELECT @max_age_days_c = value
      FROM meta.agreement_attribute_v
     WHERE agreement_id = @agreement_id
       AND attribute_name = 'MAX_AGE_DAYS'

    -- + Set default 7
    SET @max_age_days = 7
    -- + Override with actual value if valid numeric
    IF meta.check_numeric(@max_age_days_c, 12, 0) = 0 SET @max_age_days = CAST(@max_age_days_c AS INT)
    EXEC meta.debug @@PROCID, @max_age_days
    
    --| Get MAX delivery id with[@date - @max_age_days <= createdtm <= @date] if no specific 
    --| delivery id is provided
    IF COALESCE(@delivery_id, 0) = 0
        SELECT @delivery_id = MAX(id)
          FROM meta.delivery
         WHERE agreement_id = @agreement_id
           AND status_date BETWEEN @date - @max_age_days AND @date

    EXEC meta.debug @@PROCID, @agreement_id
    EXEC meta.debug @@PROCID, @delivery_id
    
    --+ Get repo table name
    SELECT @table_schema = table_schema,
           @table_name   = table_name
      FROM meta.agreement_stage_table_v
     WHERE agreement_id = @agreement_id
       AND table_schema = 'repo'

    -- + TODO: ERROR-HANDLING

    --+ Get the columns for the repo table
    DECLARE rec CURSOR FOR
    SELECT column_name,
           data_type,
           character_maximum_length,
           numeric_precision,
           numeric_scale
      FROM meta.column_mapping_v
     WHERE table_schema = @table_schema
       AND table_name = @table_name
     ORDER BY ordinal_position

    --+ Open cursor
    OPEN rec

    --+ Prepare (daft MS SQL) variables
    DECLARE @column_name NVARCHAR(128)
    DECLARE @data_type                 NVARCHAR(128)
    DECLARE @character_maximum_length  INT
    DECLARE @numeric_precision TINYINT
    DECLARE @numeric_scale             INT
    DECLARE @col NVARCHAR(500)

    SET @sql = CAST('SELECT ' AS NVARCHAR(MAX))

    -- + Prepare(daft MS SQL) loop
    FETCH NEXT FROM rec
    INTO @column_name, @data_type, @character_maximum_length, @numeric_precision, @numeric_scale

    --| Loop over columns in repo table for delivery
    EXEC meta.debug @@PROCID, 'Loop over list of columns'
    WHILE @@FETCH_STATUS = 0
    BEGIN
        --| MAP: 
        SET @col =
            CASE
                --| NVARCHAR(MAX) => NVARCHAR(4000) due to GUI/AAC cannot handle MAX
                WHEN @data_type = 'nvarchar' AND @character_maximum_length = -1 THEN 'CAST(' + @column_name + ' AS NVARCHAR(MAX)) ' + @column_name
                --| <other types> => - No mapping -
                ELSE @column_name
            END

        --+ Repeat(daft MS SQL) fetch
       FETCH NEXT FROM rec
       INTO @column_name, @data_type, @character_maximum_length, @numeric_precision, @numeric_scale

       EXEC meta.debug @@PROCID, @col
       SET @sql = @sql + CAST(@col AS NVARCHAR(MAX))
        IF @@FETCH_STATUS = 0 SET @sql = @sql + CAST(',' AS NVARCHAR(MAX))
    END

    EXEC meta.debug @@PROCID, 'Close and deallocate cursor'
    CLOSE rec
    DEALLOCATE rec

    
    --| Insert the link
    INSERT INTO meta.[link]
           (external_id, dw_delivery_id, user_id, status_id)
    VALUES (@external_id, @delivery_id, @user_id, 1)

    --| Finish and execute SQL statement outputting delivery table
    SET @sql = @sql + CAST(' FROM [' + @table_schema + '].[' + @table_name + '] '
                    + 'WHERE dw_delivery_id = ' + CAST(@delivery_id AS NVARCHAR) AS NVARCHAR(MAX))
                    + CAST(' ORDER BY dw_row_id ASC' AS NVARCHAR(MAX))


    EXEC meta.debug @@PROCID, 'Execute query to return proper dataset'
    EXEC meta.debug @@PROCID, @sql
    EXEC sp_executesql @sql
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[get_error_detail] --|
--| ==========================================================================================
--| Description: Return the details of error lines of data set breaking a validation rule.
--|              Tries to deduce the columns from what is in the rule definition
--| Arguments:
(
    @username NVARCHAR(50),   --| Username of requestor(VIEW)
    @delivery_id BIGINT,         --| ID of delivery
@rule_id               BIGINT          --| ID of rule to retrieve error data from
)
AS 
SET NOCOUNT ON
SET ANSI_WARNINGS OFF
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @agreement_id BIGINT
    DECLARE @table_name   NVARCHAR(250)
    DECLARE @rule_text    NVARCHAR(4000)
    DECLARE @sql          NVARCHAR(2000)

    --| Collect meta data for delivery - tablename and agreement_id
    SELECT @table_name   = '[' + t.table_schema + '].[' + t.table_name + '_errors]',
           @agreement_id = d.agreement_id,
           @rule_text    = r.rule_text
      FROM meta.delivery d,
           meta.agreement_stage_table_v t,
           meta.agreement_rule r
     WHERE t.agreement_id = d.agreement_id
       AND r.agreement_id = d.agreement_id
       AND t.table_schema = 'temp'
       AND d.id      = @delivery_id
       AND r.rule_id = @rule_id

    -- | Check user permissions
    IF meta.user_access(@username, @agreement_id, 'VIEW') = 0 
    BEGIN
        RAISERROR('User [%s] does not have VIEW permission on agreement [%I64d]', 11, 1, @username, @agreement_id)
        RETURN 2
    END

    --| Deduce the relevant columns from what matches the rule text
    DECLARE @column AS NVARCHAR(128)
    DECLARE rec CURSOR FOR
    SELECT column_name
      FROM meta.column_mapping_v
     WHERE agreement_id = @agreement_id
       AND table_schema = 'temp'
       AND UPPER(@rule_text) LIKE UPPER('%' + REPLACE(REPLACE(column_name, ']', ''), '[', '') + '%')
     ORDER BY ordinal_position

    --+ Open cursor
    OPEN rec

    --+ Prepare(daft MS SQL) loop
   FETCH NEXT FROM rec INTO @column

    --| Generate select statement
    SET @sql = 'SELECT rule_id'

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @sql = @sql + ',' + @column
        FETCH NEXT FROM rec INTO @column
    END
    CLOSE rec
    DEALLOCATE rec
    
    --| Finish and execute SQL statement
    SET @sql = @sql 
             + ' FROM ' + @table_name 
             + ' WHERE rule_id     = ' + CAST(@rule_id AS NVARCHAR)
             + '   AND delivery_id = ' + CAST(@delivery_id AS NVARCHAR)

    EXEC meta.debug @@PROCID, @sql
    EXEC sp_executesql @sql
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[get_error_summary] --|
--| ==========================================================================================
--| Description: Return the summary of errors from a delivery
--| Arguments:
(
    @username NVARCHAR(50),  --| Username of requestor(VIEW)
    @delivery_id BIGINT         --| ID of delivery
)
AS 
SET NOCOUNT ON
SET ANSI_WARNINGS OFF
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @agreement_id BIGINT
    DECLARE @table_name   NVARCHAR(250)
    DECLARE @sql          NVARCHAR(2000)

    --| Collect meta data
    SELECT @table_name   = '[' + t.table_schema + '].[' + t.table_name + '_errors]',
           @agreement_id = d.agreement_id
      FROM meta.delivery d,
           meta.agreement_stage_table_v t
     WHERE t.agreement_id = d.agreement_id
       AND t.table_schema = 'temp'
       AND d.id = @delivery_id

    -- | Check user permissions
    IF meta.user_access(@username, @agreement_id, 'VIEW') = 0 
    BEGIN
        RAISERROR('User [%s] does not have VIEW permission on agreement [%I64d]', 11, 1, @username, @agreement_id)
        RETURN 2
    END
        
    --| Return the error results
    SET @sql = 'SELECT r.rule_id, r.rule_text, COUNT(*) AS rule_count'
             + '  FROM meta.agreement_rule r, '
             + @table_name + '     t '
             + ' WHERE r.agreement_id = ' + CAST(@agreement_id AS NVARCHAR)
             + '   AND t.rule_id      = r.rule_id '
             + '   AND t.delivery_id  = ' + CAST(@delivery_id AS NVARCHAR)
             + ' GROUP BY r.rule_id, r.rule_text'
             + ' ORDER BY r.rule_id'

    EXEC meta.debug @@PROCID, @sql
    EXEC sp_executesql @sql
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[group_add] --|
--| ==========================================================================================
--| Description: Create (or update) group meta data. If a group with same name already exists
--|              an update is issued.
--| Arguments:
(
    @name NVARCHAR(50),        --| Name
@description   NVARCHAR(1000)       --| Description
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @exists BIGINT

    --| Check if user_group entry already exists
    EXEC meta.debug @@PROCID, 'Check if entry already exists'
    SELECT @exists = 1
      FROM meta.[group]
     WHERE name = @name

    IF @exists IS NULL
    BEGIN
        --| Insert new entry if not existing
        INSERT INTO meta.[group]
               (name, description)
        VALUES(@name, @description)


        EXEC meta.debug @@PROCID, 'Group entry inserted'
    END ELSE BEGIN
        --| Otherwise update
        UPDATE meta.[group]
           SET description = @description
         WHERE name = @name
        EXEC meta.debug @@PROCID, 'Group entry updated'
    END

    EXEC meta.debug @@PROCID, 'DONE'
    --| Return success
    RETURN
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[group_agreement_delete] --|
--| ==========================================================================================
--| Description: Delete an access for at group to an agreement
--| Arguments:
(
    @group_id BIGINT,        --| ID of the group
    @agreement_id BIGINT,        --| ID of the agreement
    @access_id BIGINT         --| ID of the access
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @exists BIGINT

    --| Check if group_agreement entry exists
    EXEC meta.debug @@PROCID, 'Check if entry exists'
    SELECT @exists = 1
      FROM meta.group_agreement
     WHERE group_id = @group_id
       AND agreement_id = @agreement_id
       AND access_id = @access_id

    IF @exists IS NOT NULL
    BEGIN
        --| Delete if existing
        DELETE FROM meta.group_agreement
         WHERE group_id     = @group_id
           AND agreement_id = @agreement_id
           AND access_id = @access_id

        EXEC meta.debug @@PROCID, 'group_agreement entry deleted'
    END

    EXEC meta.debug @@PROCID, 'DONE'
    --| Return success
    RETURN
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[log] --|
--| ==========================================================================================
--| Description: Log user access to a GUI page
--| Arguments:
(
    @username NVARCHAR(50),  --| Username of requestor
@path                  NVARCHAR(250), --| Script path
    @query NVARCHAR(1000) --| Parameters
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    --| Lookup userid from username
    DECLARE @user_id BIGINT
    SET @user_id = COALESCE((SELECT TOP 1 id FROM meta.[user] WHERE username = @username), 0)

    --| Log the entry
    INSERT INTO meta.usage_log
           (user_id, path, query)
    VALUES(@user_id, @path, @query)
END
--| ==========================================================================================
;
CREATE PROCEDURE[meta].[template_file2temp] AS SELECT 1
;
CREATE
PROCEDURE[meta].[type_map_add] --|
--| ==========================================================================================
--| Description: Add a customized type map for a particular agreement table for moving data
--|              from temp to stag
--| Arguments:
(
    @agreement_id BIGINT,        --| ID of agreement to which the rule applies
    @column_name NVARCHAR(50),  --| Name of column to which the type rule applies
@mapping           NVARCHAR(4000) --| Mapping SQL statement
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @count INT
    DECLARE @msg    NVARCHAR(4000)
    DECLARE @table  NVARCHAR(200)

    --| Look up the init table from agreement_id(which match the temp table)
    SELECT @table = '[' + table_schema + '].[' + table_name + ']'
      FROM meta.agreement_stage_table_v
     WHERE agreement_id = @agreement_id
       AND stage_id = 0

    IF @table IS NULL
    BEGIN
        RAISERROR ('Agreement [%I64d] does not exist', 11, 1, @agreement_id)
        RETURN 2
    END

    --| Look up the column name in meta data/system view
    SELECT @count = COUNT(*)
      FROM meta.column_mapping_v
     WHERE agreement_id = @agreement_id
       AND table_schema = 'init'
       AND column_name = '[' + @column_name + ']'

    IF @count = 0
    BEGIN
        RAISERROR ('Invalid column [%s] for agreement [%I64d] table', 11, 1, @column_name, @agreement_id)
        RETURN 1
    END

    SET @msg = 'Column [' + @column_name + '] -> [' + @mapping + ']'
    EXEC meta.debug @@PROCID, @msg

    --| Check the mapping rule against the table definition
    DECLARE @mapping_check  NVARCHAR(4000)
    SET @mapping_check = REPLACE(@mapping, '{column}', @column_name)
    SET @msg = 'SELECT TOP 1 ' + @mapping_check + ' FROM ' + @table
    BEGIN TRY
        EXEC sp_executesql @msg
    END TRY
    BEGIN CATCH
        SET @msg = 'Type map [' + @mapping_check + '] error [' +  CAST(ERROR_NUMBER() AS NVARCHAR) + '] [' + ERROR_MESSAGE() + ']'
        EXEC meta.debug @@PROCID, @msg
        RETURN 3
    END CATCH

    --| Determine update or insert to meta.type_rule table
    SELECT @count = COUNT(*)
      FROM meta.type_map
     WHERE agreement_id = @agreement_id
       AND column_name = @column_name

    IF @count = 0
        INSERT INTO meta.type_map
               (agreement_id, column_name, mapping)
        VALUES (@agreement_id, @column_name, @mapping)
    ELSE
        UPDATE meta.type_map
           SET mapping = @mapping
         WHERE agreement_id = @agreement_id
           AND column_name = @column_name

    EXEC meta.debug @@PROCID, 'DONE'

    --| Return success
    RETURN
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[user_add] --|
--| ==========================================================================================
--| Description: Create (or update) user meta data. If a user with same username already
--|              exists an update is issued.
--| Arguments:
(
    @username NVARCHAR(50),        --| Username
@realname      NVARCHAR(100),       --| Realname
@description   NVARCHAR(1000)       --| Description
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @exists BIGINT

    --| Check if user_group entry already exists
    EXEC meta.debug @@PROCID, 'Check if entry already exists'
    SELECT @exists = 1
      FROM meta.[user]
     WHERE username = @username

    IF @exists IS NULL
    BEGIN
        --| Insert new entry if not existing
        INSERT INTO meta.[user]
               (username, realname, description)
        VALUES(@username, @realname, @description)


        EXEC meta.debug @@PROCID, 'User entry inserted'
    END ELSE BEGIN
        --| Otherwise update meta data
        UPDATE meta.[user]
           SET realname    = @realname,
               description = @description
         WHERE username = @username
        EXEC meta.debug @@PROCID, 'User entry updated'
    END

    EXEC meta.debug @@PROCID, 'DONE'
    --| Return success
    RETURN
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[user_group_add] --|
--| ==========================================================================================
--| Description: Add a user/group membership - checking for doublets
--| Arguments:
(
    @user_id BIGINT,        --| ID of the user
    @group_id BIGINT         --| ID of group
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @exists BIGINT

    --| Check if user_group entry already exists
    EXEC meta.debug @@PROCID, 'Check if entry already exists'
    SELECT @exists = 1
      FROM meta.user_group
     WHERE user_id  = @user_id
       AND group_id = @group_id

    IF @exists IS NULL
    BEGIN
        --| Insert new entry if not existing
        INSERT INTO meta.user_group
               (user_id, group_id)
        VALUES(@user_id, @group_id)

        EXEC meta.debug @@PROCID, 'user_group entry inserted'
    END

    EXEC meta.debug @@PROCID, 'DONE'
    --| Return success
    RETURN
END
--| ==========================================================================================
;
CREATE
PROCEDURE[meta].[user_group_delete] --|
--| ==========================================================================================
--| Description: Delete a user/group membership
--| Arguments:
(
    @user_id BIGINT,        --| ID of the user
    @group_id BIGINT         --| ID of group
)
AS 
--| ------------------------------------------------------------------------------------------
BEGIN
    DECLARE @exists BIGINT

    --| Check if user_group entry already exists
    EXEC meta.debug @@PROCID, 'Check if entry exists'
    SELECT @exists = 1
      FROM meta.user_group
     WHERE user_id  = @user_id
       AND group_id = @group_id

    IF @exists IS NOT NULL
    BEGIN
        --| Insert new entry if not existing
        DELETE FROM meta.user_group
         WHERE user_id  = @user_id
           AND group_id = @group_id

        EXEC meta.debug @@PROCID, 'user_group entry deleted'
    END

    EXEC meta.debug @@PROCID, 'DONE'
    --| Return success
    RETURN
END
--| ==========================================================================================
;

--| ==========================================================================================
--| Create indexes
CREATE UNIQUE INDEX ux_group_agreement_gid_aid_cid ON meta.group_agreement (group_id, agreement_id, access_id)
;
CREATE UNIQUE INDEX ux_stage_id_name ON meta.stage (id, name)
;
CREATE UNIQUE INDEX ux_delivery_id_aid_uid ON meta.delivery (id, agreement_id, user_id)
;
CREATE UNIQUE INDEX ux_access_id_name ON meta.access (id, name)
;
CREATE UNIQUE INDEX ux_group_id_name ON meta.[group] (id, name)
;
CREATE UNIQUE INDEX ux_id_name_schema ON meta.[table] (id, name, [schema])
;
CREATE INDEX ix_audit_id_sid_did_tid ON meta.audit (id, stage_id, delivery_id, table_id)
;
CREATE UNIQUE INDEX ux_type_map_id_aid_column_name ON meta.type_map (id, agreement_id, column_name)
;
CREATE INDEX ix_type_map_id_aid_data_type ON meta.type_map (id, agreement_id, data_type)
;
CREATE INDEX ix_type_map_aid_column_name_data_type ON meta.type_map (agreement_id, data_type, column_name)
;
--| ==========================================================================================

--| Populate the [meta].[access] table
--+ Consider using SET IDENTITY_INSERT meta.access ON/OFF

--+ Truncate the table 
DELETE FROM [meta].[access]

--+ Initialize the identity to 0 => next value is 1
DBCC CHECKIDENT('[meta].[access]', RESEED, 0)

--+ Insert the static values referred to in the code
INSERT INTO [meta].[access] (name, description)
SELECT 'UPLOAD',  'Allow uploading data to agreement'  UNION ALL
SELECT 'VIEW',    'Allow read access to the data'      UNION ALL
SELECT 'APPROVE', 'Allow approval of staged data'      UNION ALL
SELECT 'DELETE',  'Allow deletion of data'

--| Populate the [meta].[attribute] table
--+ Consider using SET IDENTITY_INSERT meta.status ON/OFF

--+ Truncate the table 
DELETE FROM [meta].[attribute]

--+ Initialize the identity to 0 => next value is 1
DBCC CHECKIDENT('[meta].[attribute]', RESEED, 0)

--+ Insert the static values referred to in the code
INSERT INTO [meta].[attribute] (name, description, default_value, options)
SELECT 'NVARCHAR_MAX_LOAD',      'Load data using single data NVARCHAR(MAX) column due to 8060 character limit in SQL Server data loads. Validation rules cannot be applied for this type of agreements.', 'NO', 'NO,YES' UNION ALL
SELECT 'ALLOW_DELIVERY_REPLACE', 'Allow existing deliveries to be replaced with a new one - filenames may be hardcoded in external systems',                                                               'NO', 'NO,YES' UNION ALL
SELECT 'AUTO_TRUNCATE_TEMP',     'The temp table is automatically truncated when a new delivery is added to allow progress in case a previous failed delivery is blocking',                                'YES','NO,YES' UNION ALL
SELECT 'MAX_AGE_DAYS',           'Number of days back a delivery is fetched in get_data call when specifying a date',                                                                                      '180','1,2,3,4,5,6,7,8,9,10,11,12,13,14,30,90,180,365,3650'



--| Populate the [meta].[group] table
--+ Consider using SET IDENTITY_INSERT meta.status ON/OFF

--+ Truncate the table 
DELETE FROM [meta].[group]

--+ Initialize the identity to 0 => next value is 1
DBCC CHECKIDENT('[meta].[group]', RESEED, 1)

--+ Insert the static values referred to in the code
INSERT INTO [meta].[group] (name, description)
SELECT 'ADMIN',  'Overall admin of the system'  UNION ALL
SELECT 'READERS','General read access'




--| Populate the [meta].[status] table
--+ Consider using SET IDENTITY_INSERT meta.status ON/OFF

--+ Truncate the table 
DELETE FROM [meta].[status]

--+ Initialize the identity to 0 => next value is 1
DBCC CHECKIDENT('[meta].[status]', RESEED, 1)

--+ Insert the static values referred to in the code
INSERT INTO [meta].[status] (description)
SELECT 'OK - Success'                UNION ALL
SELECT 'WARN - Warnings were raised' UNION ALL
SELECT 'ERROR - Errors occurred'     UNION ALL
SELECT 'CRITICAL - System critical errors occurred'




--| Populate the [meta].[type_map] table

--+ Truncate the table 
DELETE FROM [meta].[type_map]

--+ Initialize the identity to 0 => next value is 1
DBCC CHECKIDENT('[meta].[type_map]', RESEED, 0)

--+ Insert the static values referred to in the code
INSERT INTO meta.type_map (data_type, mapping, agreement_id, column_name) 
--+ Generic types
SELECT 'INT',      NULL, NULL, NULL UNION ALL
SELECT 'NVARCHAR', NULL, NULL, NULL UNION ALL
SELECT 'VARCHAR',  NULL, NULL, NULL UNION ALL
SELECT 'NCHAR',    NULL, NULL, NULL UNION ALL
SELECT 'CHAR',     NULL, NULL, NULL UNION ALL
SELECT 'DATE',     NULL, NULL, NULL UNION ALL
SELECT 'DECIMAL',  'CAST(ROUND(REPLACE({column},'','',''.''),{scale}) AS DECIMAL({precision},{scale}))', NULL, NULL UNION ALL
SELECT 'NUMERIC',  'CAST(ROUND(REPLACE({column},'','',''.''),{scale}) AS NUMERIC({precision},{scale}))', NULL, NULL UNION ALL
SELECT 'DATETIME', 'CONVERT(datetime, {column}, 103)', NULL, NULL UNION ALL
--+ Generic columns
SELECT NULL,       'CAST({column} AS BIGINT)',         NULL, 'id'





--| Populate the [meta].[user] table
--+ Consider using SET IDENTITY_INSERT meta.user ON/OFF

--+ Truncate the table 
DELETE FROM [meta].[user]

--+ Initialize the identity to 0 => next value is 1
DBCC CHECKIDENT('[meta].[user]', RESEED, 1)

--| Populate the [meta].[stage] table
--+ Consider using SET IDENTITY_INSERT meta.stage ON/OFF

--+ Truncate the table 
DELETE FROM [meta].[stage]

--+ Initialize the identity to 0 => next value is 0 (init)
DBCC CHECKIDENT('[meta].[stage]', RESEED, 0)

--+ Insert the static values referred to in the code
INSERT INTO [meta].[stage] (name, description)
SELECT 'init', 'Initial area for agreement and table definition - linked to the agreement table_id' UNION ALL
SELECT 'temp', 'Load area for input files to enter the database into error tolerant tables' UNION ALL
SELECT 'stag', 'Staging area where temp load tables are copied and endowed with audig information and row keys' UNION ALL
SELECT 'repo', 'Repository area where consolidated data is copied after all validation rules have been applied and accepted'

--| Populate the [meta].[type] table

--+ Truncate the table 
DELETE FROM [meta].[type]

--+ Initialize the identity to 0 => next value is 1
DBCC CHECKIDENT('[meta].[type]', RESEED, 0)

--+ Insert the static values referred to in the code
INSERT INTO [meta].[type]
           ([name]
           ,[batchsize]
           ,[check_constraints]
           ,[codepage]
           ,[datafiletype]
           ,[fieldterminator]
           ,[firstrow]
           ,[fire_triggers]
           ,[format_file]
           ,[keepidentity]
           ,[keepnulls]
           ,[kilobytes_per_batch]
           ,[lastrow]
           ,[maxerrors]
           ,[order]
           ,[rows_per_batch]
           ,[rowterminator]
           ,[tablock]
           ,[errorfile])
SELECT 'DEFAULT_CSV',        NULL, NULL, NULL, 'WIDECHAR', ';', 1, NULL, NULL, NULL, NULL, NULL, NULL, 1000, NULL, NULL, '\n', NULL, '{datafile}.error' UNION ALL
SELECT 'DEFAULT_CSV_HEADER', NULL, NULL, NULL, 'WIDECHAR', ';', 2, NULL, NULL, NULL, NULL, NULL, NULL, 1000, NULL, NULL, '\n', NULL, '{datafile}.error' UNION ALL
SELECT 'EXTERNAL',           NULL, NULL, NULL, 'WIDECHAR', ';', 1, NULL, NULL, NULL, NULL, NULL, NULL, 0,    NULL, NULL, '\n', NULL, '{datafile}.error' UNION ALL
SELECT 'COMMA_CSV',          NULL, NULL, NULL, 'WIDECHAR', ',', 1, NULL, NULL, NULL, NULL, NULL, NULL, 1000, NULL, NULL, '\n', NULL, '{datafile}.error' UNION ALL
SELECT 'COMMA_CSV_HEADER',   NULL, NULL, NULL, 'WIDECHAR', ',', 2, NULL, NULL, NULL, NULL, NULL, NULL, 1000, NULL, NULL, '\n', NULL, '{datafile}.error' UNION ALL
SELECT 'MARS_LINK',          NULL, NULL, NULL, 'ORACLE',   ',', 1, NULL, NULL, NULL, NULL, NULL, NULL, 0,    NULL, NULL, '',   NULL, ''                 UNION ALL
SELECT 'NLPNO_LINK',         NULL, NULL, NULL, 'MSSQL',    ',', 1, NULL, NULL, NULL, NULL, NULL, NULL, 0,    NULL, NULL, '',   NULL, ''                 UNION ALL
SELECT 'COMMA_CSV_HEADER_C', NULL, NULL, NULL, 'CHAR',     ',', 2, NULL, NULL, NULL, NULL, NULL, NULL, 1000, NULL, NULL, '\n', NULL, '{datafile}.error' UNION ALL
SELECT 'ANALYSIS_CSV',       NULL, NULL, NULL, 'WIDECHAR', ';', 2, NULL, NULL, NULL, NULL, NULL,100000, 0,    NULL, NULL, '\n', NULL, '{datafile}.error' UNION ALL
SELECT 'COMMA_CSV_HEADER_ACP',NULL, NULL, 'ACP', 'WIDECHAR', ',', 2, NULL, NULL, NULL, NULL, NULL, NULL, 1000, NULL, NULL, '\n', NULL, '{datafile}.error'
;
-- Add initial system user
EXEC meta.user_add 'system', 'System User', 'Owner of all agreements'
;
EXEC meta.user_group_add 1, 1
;

-- ----------------------------------------------------------------------------------------------------------------------------------
-- +migrate Down
-- ----------------------------------------------------------------------------------------------------------------------------------
PRINT 'N/A'
;
