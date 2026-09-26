USE DigitalLoanDB;
GO

/*
   Digital Loan Application and Approval System
   Portfolio case study using simulated data only.
   Import Loan_Applications_Clean.csv from the CSV_Import folder
   into dbo.LoanApplications before running these queries.
*/

/* 1. Executive KPIs */
SELECT
    COUNT(*) AS TotalApplications,
    SUM(CASE WHEN Current_Status = 'Approved' THEN 1 ELSE 0 END) AS ApprovedApplications,
    SUM(CASE WHEN Current_Status = 'Declined' THEN 1 ELSE 0 END) AS DeclinedApplications,
    SUM(CASE WHEN Current_Status = 'Under Review' THEN 1 ELSE 0 END) AS UnderReviewApplications,
    SUM(CASE WHEN Current_Status = 'More Information Required' THEN 1 ELSE 0 END) AS MoreInformationRequired,
    CAST(SUM(Requested_Amount_JOD) AS decimal(18,2)) AS TotalRequestedAmountJOD,
    CAST(AVG(CAST(Turnaround_Days AS decimal(10,2))) AS decimal(10,2)) AS AverageTurnaroundDays
FROM dbo.LoanApplications;
GO

/* 2. Application status distribution */
SELECT
    Current_Status,
    COUNT(*) AS ApplicationCount,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS decimal(5,2)) AS ApplicationPercentage,
    CAST(SUM(Requested_Amount_JOD) AS decimal(18,2)) AS RequestedAmountJOD,
    CAST(AVG(CAST(Turnaround_Days AS decimal(10,2))) AS decimal(10,2)) AS AverageTurnaroundDays
FROM dbo.LoanApplications
GROUP BY Current_Status
ORDER BY ApplicationCount DESC;
GO

/* 3. Decision outcome and decision reason analysis */
SELECT
    Current_Status AS DecisionOutcome,
    COALESCE(NULLIF(TRIM(Current_or_Decision_Reason), ''), 'Not recorded') AS DecisionReason,
    COUNT(*) AS ApplicationCount,
    CAST(100.0 * COUNT(*) /
         SUM(COUNT(*)) OVER (PARTITION BY Current_Status) AS decimal(5,2)) AS PercentageWithinOutcome
FROM dbo.LoanApplications
WHERE Current_Status IN ('Approved', 'Declined')
GROUP BY Current_Status, COALESCE(NULLIF(TRIM(Current_or_Decision_Reason), ''), 'Not recorded')
ORDER BY DecisionOutcome, ApplicationCount DESC;
GO

/* 4. Requested amount by employment type */
SELECT
    Employment_Type,
    COUNT(*) AS ApplicationCount,
    CAST(AVG(Requested_Amount_JOD) AS decimal(18,2)) AS AverageRequestedAmountJOD,
    CAST(SUM(Requested_Amount_JOD) AS decimal(18,2)) AS TotalRequestedAmountJOD,
    CAST(AVG(CAST(Turnaround_Days AS decimal(10,2))) AS decimal(10,2)) AS AverageTurnaroundDays
FROM dbo.LoanApplications
GROUP BY Employment_Type
ORDER BY TotalRequestedAmountJOD DESC;
GO

/* 5. Approval rate by employment type */
SELECT
    Employment_Type,
    COUNT(*) AS TotalApplications,
    SUM(CASE WHEN Current_Status = 'Approved' THEN 1 ELSE 0 END) AS ApprovedApplications,
    CAST(100.0 * SUM(CASE WHEN Current_Status = 'Approved' THEN 1 ELSE 0 END)
         / NULLIF(COUNT(*), 0) AS decimal(5,2)) AS ApprovalRatePct
FROM dbo.LoanApplications
GROUP BY Employment_Type
ORDER BY ApprovalRatePct DESC;
GO

/* 6. Application distribution by requested amount band */
SELECT
    CASE
        WHEN Requested_Amount_JOD < 3000 THEN 'Below 3,000 JOD'
        WHEN Requested_Amount_JOD < 6000 THEN '3,000 to 5,999 JOD'
        WHEN Requested_Amount_JOD < 10000 THEN '6,000 to 9,999 JOD'
        ELSE '10,000 JOD and above'
    END AS RequestedAmountBand,
    COUNT(*) AS ApplicationCount,
    CAST(AVG(CAST(Turnaround_Days AS decimal(10,2))) AS decimal(10,2)) AS AverageTurnaroundDays
FROM dbo.LoanApplications
GROUP BY CASE
        WHEN Requested_Amount_JOD < 3000 THEN 'Below 3,000 JOD'
        WHEN Requested_Amount_JOD < 6000 THEN '3,000 to 5,999 JOD'
        WHEN Requested_Amount_JOD < 10000 THEN '6,000 to 9,999 JOD'
        ELSE '10,000 JOD and above'
    END
ORDER BY ApplicationCount DESC;
GO

/* 7. Term analysis */
SELECT
    Term_Months,
    COUNT(*) AS ApplicationCount,
    CAST(AVG(Requested_Amount_JOD) AS decimal(18,2)) AS AverageRequestedAmountJOD,
    CAST(100.0 * SUM(CASE WHEN Current_Status = 'Approved' THEN 1 ELSE 0 END)
         / NULLIF(COUNT(*), 0) AS decimal(5,2)) AS ApprovalRatePct
FROM dbo.LoanApplications
GROUP BY Term_Months
ORDER BY Term_Months;
GO

/* 8. Queue aging exceptions */
SELECT
    Application_ID,
    Customer_ID,
    Submitted_Date,
    Requested_Amount_JOD,
    Employment_Type,
    Current_Status,
    Turnaround_Days,
    Current_or_Decision_Reason
FROM dbo.LoanApplications
WHERE (Current_Status = 'Under Review' AND Turnaround_Days > 7)
   OR Current_Status = 'More Information Required'
ORDER BY Turnaround_Days DESC, Submitted_Date;
GO

/* 9. Monthly application volume and decision outcomes */
SELECT
    DATEFROMPARTS(YEAR(Submitted_Date), MONTH(Submitted_Date), 1) AS ApplicationMonth,
    COUNT(*) AS TotalApplications,
    SUM(CASE WHEN Current_Status = 'Approved' THEN 1 ELSE 0 END) AS ApprovedApplications,
    SUM(CASE WHEN Current_Status = 'Declined' THEN 1 ELSE 0 END) AS DeclinedApplications,
    CAST(AVG(CAST(Turnaround_Days AS decimal(10,2))) AS decimal(10,2)) AS AverageTurnaroundDays
FROM dbo.LoanApplications
GROUP BY YEAR(Submitted_Date), MONTH(Submitted_Date)
ORDER BY ApplicationMonth;
GO

/* 10. Monthly volume with month-over-month change */
WITH MonthlyApplications AS (
    SELECT DATEFROMPARTS(YEAR(Submitted_Date), MONTH(Submitted_Date), 1) AS ApplicationMonth,
           COUNT(*) AS ApplicationCount
    FROM dbo.LoanApplications
    GROUP BY YEAR(Submitted_Date), MONTH(Submitted_Date)
), Comparison AS (
    SELECT ApplicationMonth, ApplicationCount,
           LAG(ApplicationCount) OVER (ORDER BY ApplicationMonth) AS PreviousMonthApplications
    FROM MonthlyApplications
)
SELECT
    ApplicationMonth,
    ApplicationCount,
    PreviousMonthApplications,
    ApplicationCount - PreviousMonthApplications AS ApplicationChange,
    CAST(100.0 * (ApplicationCount - PreviousMonthApplications)
         / NULLIF(PreviousMonthApplications, 0) AS decimal(8,2)) AS ApplicationChangePct
FROM Comparison
ORDER BY ApplicationMonth;
GO
