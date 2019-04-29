
-- +migrate Up
ALTER PROCEDURE[meta].[agreement_rule_add] --|
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
    /*SET @msg = 'SELECT TOP 1 1 FROM ' + @table + ' WHERE ' + @rule_text
    BEGIN TRY
        EXEC sp_executesql @msg
    END TRY
    BEGIN CATCH
        SET @msg = 'Validation [' + @rule_text + '] error [' + CAST(ERROR_NUMBER() AS NVARCHAR) + '] [' + ERROR_MESSAGE() + ']'
        EXEC meta.debug @@PROCID, @msg
        RETURN 3
    END CATCH*/

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

-- +migrate Down
ALTER PROCEDURE[meta].[agreement_rule_add] --|
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
