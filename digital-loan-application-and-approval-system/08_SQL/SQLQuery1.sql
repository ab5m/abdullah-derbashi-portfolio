/*
   Digital Loan Application and Approval System - SQL Server setup
   Portfolio case study with simulated data only.

   Before running: update @CsvPath only if your CSV file is stored elsewhere.
   Run this complete script in SQL Server Management Studio.
*/

IF DB_ID('DigitalLoanDB') IS NULL
    CREATE DATABASE DigitalLoanDB;
GO

USE DigitalLoanDB;
GO

/* Rebuild only the tables created for this portfolio project. */
DROP VIEW IF EXISTS dbo.vw_LoanApplicationPowerBI;
DROP TABLE IF EXISTS dbo.FactLoanApplications;
DROP TABLE IF EXISTS dbo.DimDecisionReason;
DROP TABLE IF EXISTS dbo.DimTerm;
DROP TABLE IF EXISTS dbo.DimEmploymentType;
DROP TABLE IF EXISTS dbo.DimStatus;
DROP TABLE IF EXISTS dbo.DimDate;
DROP TABLE IF EXISTS dbo.stg_LoanApplicationsRaw;
GO

/* 1. Staging table: imports the source CSV exactly as received. */
CREATE TABLE dbo.stg_LoanApplicationsRaw (
    Application_ID                  nvarchar(50)  NULL,
    Customer_ID                     nvarchar(50)  NULL,
    Submitted_Date                  nvarchar(50)  NULL,
    Requested_Amount_JOD            nvarchar(50)  NULL,
    Term_Months                     nvarchar(20)  NULL,
    Employment_Type                 nvarchar(100) NULL,
    Current_Status                  nvarchar(100) NULL,
    Turnaround_Days                 nvarchar(20)  NULL,
    Current_or_Decision_Reason      nvarchar(250) NULL
);
GO

/*
  2. Import the CSV.
  If SQL Server cannot access a user-profile path, copy the CSV to a folder
  readable by the SQL Server service and update the path below.
*/
DECLARE @CsvPath nvarchar(1000) =
    'C:\Users\user\OneDrive\Desktop\Digital_Loan_Application_and_Approval_System_Organized\08_SQL\CSV_Import\Loan_Applications_Clean.csv';

DECLARE @BulkSql nvarchar(max) = N'
BULK INSERT dbo.stg_LoanApplicationsRaw
FROM ''' + REPLACE(@CsvPath, '''', '''''') + N'''
WITH (
    FORMAT = ''CSV'',
    FIRSTROW = 2,
    FIELDQUOTE = ''"'',
    FIELDTERMINATOR = '','',
    ROWTERMINATOR = ''0x0a'',
    TABLOCK,
    CODEPAGE = ''65001''
);';
EXEC sys.sp_executesql @BulkSql;
GO

/* 3. Data quality review: investigate these before refreshing the Power BI model. */
SELECT
    COUNT(*) AS ImportedRows,
    SUM(CASE WHEN NULLIF(TRIM(Application_ID), '') IS NULL THEN 1 ELSE 0 END) AS MissingApplicationID,
    SUM(CASE WHEN TRY_CONVERT(date, TRIM(Submitted_Date), 23) IS NULL THEN 1 ELSE 0 END) AS InvalidSubmittedDate,
    SUM(CASE WHEN TRY_CONVERT(decimal(12,2), TRIM(Requested_Amount_JOD)) IS NULL
              OR TRY_CONVERT(decimal(12,2), TRIM(Requested_Amount_JOD)) <= 0 THEN 1 ELSE 0 END) AS InvalidRequestedAmount,
    SUM(CASE WHEN TRY_CONVERT(int, TRIM(Term_Months)) IS NULL THEN 1 ELSE 0 END) AS InvalidTerm,
    SUM(CASE WHEN TRY_CONVERT(int, TRIM(Turnaround_Days)) IS NULL
              OR TRY_CONVERT(int, TRIM(Turnaround_Days)) < 0 THEN 1 ELSE 0 END) AS InvalidTurnaroundDays
FROM dbo.stg_LoanApplicationsRaw;
GO

/* 4. Dimension tables. */
CREATE TABLE dbo.DimDate (
    DateKey          int          NOT NULL PRIMARY KEY,
    FullDate         date         NOT NULL UNIQUE,
    CalendarYear     smallint     NOT NULL,
    CalendarMonthNo  tinyint      NOT NULL,
    CalendarMonth    nvarchar(20) NOT NULL,
    YearMonth        char(7)      NOT NULL
);

CREATE TABLE dbo.DimStatus (
    StatusKey        int IDENTITY(1,1) NOT NULL PRIMARY KEY,
    StatusName       nvarchar(100)     NOT NULL UNIQUE,
    StatusCategory   nvarchar(30)      NOT NULL
);

CREATE TABLE dbo.DimEmploymentType (
    EmploymentTypeKey int IDENTITY(1,1) NOT NULL PRIMARY KEY,
    EmploymentType    nvarchar(100)     NOT NULL UNIQUE
);

CREATE TABLE dbo.DimTerm (
    TermKey           int IDENTITY(1,1) NOT NULL PRIMARY KEY,
    TermMonths        int               NOT NULL UNIQUE,
    TermLabel         nvarchar(30)      NOT NULL
);

CREATE TABLE dbo.DimDecisionReason (
    DecisionReasonKey int IDENTITY(1,1) NOT NULL PRIMARY KEY,
    DecisionReason    nvarchar(250)     NOT NULL UNIQUE,
    ReasonCategory    nvarchar(50)      NOT NULL
);
GO

/* 5. Fact table with cleaned values and foreign keys. */
CREATE TABLE dbo.FactLoanApplications (
    LoanApplicationKey  int IDENTITY(1,1) NOT NULL PRIMARY KEY,
    ApplicationID       nvarchar(50)      NOT NULL UNIQUE,
    CustomerID          nvarchar(50)      NOT NULL,
    SubmittedDateKey    int               NOT NULL,
    StatusKey           int               NOT NULL,
    EmploymentTypeKey   int               NOT NULL,
    TermKey             int               NOT NULL,
    DecisionReasonKey   int               NULL,
    RequestedAmountJOD  decimal(12,2)     NOT NULL,
    TurnaroundDays      int               NOT NULL,
    CONSTRAINT FK_FactLoanApplications_Date FOREIGN KEY (SubmittedDateKey) REFERENCES dbo.DimDate(DateKey),
    CONSTRAINT FK_FactLoanApplications_Status FOREIGN KEY (StatusKey) REFERENCES dbo.DimStatus(StatusKey),
    CONSTRAINT FK_FactLoanApplications_Employment FOREIGN KEY (EmploymentTypeKey) REFERENCES dbo.DimEmploymentType(EmploymentTypeKey),
    CONSTRAINT FK_FactLoanApplications_Term FOREIGN KEY (TermKey) REFERENCES dbo.DimTerm(TermKey),
    CONSTRAINT FK_FactLoanApplications_Reason FOREIGN KEY (DecisionReasonKey) REFERENCES dbo.DimDecisionReason(DecisionReasonKey)
);
GO

/* 6. Create a clean in-memory dataset and reject invalid or duplicate records. */
;WITH Cleaned AS (
    SELECT
        TRIM(Application_ID) AS ApplicationID,
        COALESCE(NULLIF(TRIM(Customer_ID), ''), 'Unknown Customer') AS CustomerID,
        TRY_CONVERT(date, TRIM(Submitted_Date), 23) AS SubmittedDate,
        TRY_CONVERT(decimal(12,2), TRIM(Requested_Amount_JOD)) AS RequestedAmountJOD,
        TRY_CONVERT(int, TRIM(Term_Months)) AS TermMonths,
        COALESCE(NULLIF(TRIM(Employment_Type), ''), 'Not Recorded') AS EmploymentType,
        CASE
            WHEN TRIM(Current_Status) IN ('Approved','Declined','Under Review','More Information Required') THEN TRIM(Current_Status)
            ELSE 'Unknown'
        END AS StatusName,
        TRY_CONVERT(int, TRIM(Turnaround_Days)) AS TurnaroundDays,
        NULLIF(TRIM(Current_or_Decision_Reason), '') AS DecisionReason,
        ROW_NUMBER() OVER (PARTITION BY TRIM(Application_ID) ORDER BY (SELECT 1)) AS DuplicateRank
    FROM dbo.stg_LoanApplicationsRaw
)
SELECT * INTO #CleanLoanApplications
FROM Cleaned
WHERE ApplicationID IS NOT NULL
  AND SubmittedDate IS NOT NULL
  AND RequestedAmountJOD > 0
  AND TermMonths > 0
  AND TurnaroundDays >= 0
  AND DuplicateRank = 1;

/* 7. Populate the dimensions from clean data. */
DECLARE @MinDate date = (SELECT MIN(SubmittedDate) FROM #CleanLoanApplications);
DECLARE @MaxDate date = (SELECT MAX(SubmittedDate) FROM #CleanLoanApplications);

;WITH Dates AS (
    SELECT @MinDate AS FullDate
    UNION ALL
    SELECT DATEADD(day, 1, FullDate) FROM Dates WHERE FullDate < @MaxDate
)
INSERT INTO dbo.DimDate (DateKey, FullDate, CalendarYear, CalendarMonthNo, CalendarMonth, YearMonth)
SELECT CONVERT(int, CONVERT(char(8), FullDate, 112)), FullDate, YEAR(FullDate), MONTH(FullDate), DATENAME(month, FullDate), CONVERT(char(7), FullDate, 120)
FROM Dates
OPTION (MAXRECURSION 0);

INSERT INTO dbo.DimStatus (StatusName, StatusCategory)
SELECT StatusName,
       CASE WHEN StatusName IN ('Approved','Declined') THEN 'Final Decision'
            WHEN StatusName = 'Under Review' THEN 'In Progress'
            WHEN StatusName = 'More Information Required' THEN 'Pending Applicant'
            ELSE 'Unknown' END
FROM #CleanLoanApplications
GROUP BY StatusName;

INSERT INTO dbo.DimEmploymentType (EmploymentType)
SELECT EmploymentType FROM #CleanLoanApplications GROUP BY EmploymentType;

INSERT INTO dbo.DimTerm (TermMonths, TermLabel)
SELECT TermMonths, CONCAT(TermMonths, ' months') FROM #CleanLoanApplications GROUP BY TermMonths;

INSERT INTO dbo.DimDecisionReason (DecisionReason, ReasonCategory)
SELECT DecisionReason,
       CASE WHEN StatusName = 'Approved' THEN 'Approval Reason'
            WHEN StatusName = 'Declined' THEN 'Decline Reason'
            WHEN StatusName = 'More Information Required' THEN 'Missing Information'
            ELSE 'Review Note' END
FROM #CleanLoanApplications
WHERE DecisionReason IS NOT NULL
GROUP BY DecisionReason, StatusName;

/* 8. Populate the fact table with valid normalized keys. */
INSERT INTO dbo.FactLoanApplications (
    ApplicationID, CustomerID, SubmittedDateKey, StatusKey, EmploymentTypeKey,
    TermKey, DecisionReasonKey, RequestedAmountJOD, TurnaroundDays
)
SELECT c.ApplicationID, c.CustomerID,
       CONVERT(int, CONVERT(char(8), c.SubmittedDate, 112)), s.StatusKey, e.EmploymentTypeKey,
       t.TermKey, r.DecisionReasonKey, c.RequestedAmountJOD, c.TurnaroundDays
FROM #CleanLoanApplications c
JOIN dbo.DimStatus s ON s.StatusName = c.StatusName
JOIN dbo.DimEmploymentType e ON e.EmploymentType = c.EmploymentType
JOIN dbo.DimTerm t ON t.TermMonths = c.TermMonths
LEFT JOIN dbo.DimDecisionReason r ON r.DecisionReason = c.DecisionReason;
GO

/* 9. Power BI view: import this view plus dimensions to build the model. */
CREATE OR ALTER VIEW dbo.vw_LoanApplicationPowerBI
AS
SELECT
    f.LoanApplicationKey, f.ApplicationID, f.CustomerID,
    d.FullDate AS SubmittedDate, d.CalendarYear, d.CalendarMonthNo, d.CalendarMonth, d.YearMonth,
    s.StatusName, s.StatusCategory,
    e.EmploymentType,
    t.TermMonths, t.TermLabel,
    r.DecisionReason, r.ReasonCategory,
    f.RequestedAmountJOD, f.TurnaroundDays,
    CASE WHEN f.StatusKey IN (SELECT StatusKey FROM dbo.DimStatus WHERE StatusName = 'Approved') THEN 1 ELSE 0 END AS IsApproved,
    CASE WHEN f.StatusKey IN (SELECT StatusKey FROM dbo.DimStatus WHERE StatusName = 'Declined') THEN 1 ELSE 0 END AS IsDeclined,
    CASE WHEN f.StatusKey IN (SELECT StatusKey FROM dbo.DimStatus WHERE StatusName = 'Under Review')
              AND f.TurnaroundDays > 7 THEN 1 ELSE 0 END AS IsAgingException
FROM dbo.FactLoanApplications f
JOIN dbo.DimDate d ON d.DateKey = f.SubmittedDateKey
JOIN dbo.DimStatus s ON s.StatusKey = f.StatusKey
JOIN dbo.DimEmploymentType e ON e.EmploymentTypeKey = f.EmploymentTypeKey
JOIN dbo.DimTerm t ON t.TermKey = f.TermKey
LEFT JOIN dbo.DimDecisionReason r ON r.DecisionReasonKey = f.DecisionReasonKey;
GO

/* 10. Final validation. */
SELECT 'Imported raw rows' AS CheckName, COUNT(*) AS Result FROM dbo.stg_LoanApplicationsRaw
UNION ALL SELECT 'Clean fact rows', COUNT(*) FROM dbo.FactLoanApplications
UNION ALL SELECT 'Rejected raw rows', (SELECT COUNT(*) FROM dbo.stg_LoanApplicationsRaw) - COUNT(*) FROM dbo.FactLoanApplications;

SELECT * FROM dbo.vw_LoanApplicationPowerBI ORDER BY SubmittedDate, ApplicationID;
GO