-- Reference copy of the schema (applied by scripts/grant_sql_access.py in Azure,
-- and by app/db.py in local docker compose).
IF OBJECT_ID(N'dbo.tasks', N'U') IS NULL
CREATE TABLE dbo.tasks (
  id INT IDENTITY(1,1) PRIMARY KEY,
  title NVARCHAR(200) NOT NULL,
  done BIT NOT NULL DEFAULT 0,
  created_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
