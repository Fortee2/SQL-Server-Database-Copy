# SQL Server Database Copy
SQL and Powershell scripts for exporting a database's structure and data 

## About
Most development is maintaining and enhancing existing systems.  Often times these systems do not have a way to recreate the database structure, but we need these structures to setup local development, testing, and QA environments.   Often times we use backup files and then end up writing script to obfuscate or remove sensitive data.

The purpose of this project is to simplify the process of recreating a SQL Server database structure or being able to script out sections of a database.

## What’s Here?
There are two files that make up this project.  

The first is [Schema.sql](https://github.com/Fortee2/SQL-Serer-Database-Copy/tree/master/ExtractDB/Schema.sql) in the ExtractDB folder.  This script extracts the schema information from your source database using the SQL Server system table and generates the necessary create statements.  

The second file is a Powershell script, [CopyDatabase.ps1](https://github.com/Fortee2/SQL-Serer-Database-Copy/tree/master/Powershell/CopyDatabase.ps1), that executes Schema.sql against the source database and take the output and applies it to a destination database.   The CopyDatabase script also includes calls to the Bulk Copy tool, BCP, to transfer data after the table structure has been created.

## Version 2019.08.10
* Fixed - Adds brackets around column names when generating table create statements.
* Adds Foreign Key Constraints.
* Adds support User Defined Table Types.
* Orders Functions, Procedures, and Views by create date to attempt to create parent objects before dependent objects.
* Increased max characters in powershell script to 150,000 characters to accommodate large scripts.

# Prerequisites
If you are using the powershell script to create a database copy you will need:
* The sqlserver Powershell module installed.   You can find out more about it [here](https://docs.microsoft.com/en-us/sql/powershell/download-sql-server-ps-module?view=sql-server-2017).
* SQL Bulk Copy Tool (BCP) installed on the machine running the Powershell script.  You can find out more [here](https://docs.microsoft.com/en-us/sql/tools/bcp-utility?view=sql-server-2017)

## Assumptions
* The source and target databases are SQL Server 2017.   This script has not been tested againist an older version of SQL Server.
* The scripts does not create any empty database but expect a target already exists.
